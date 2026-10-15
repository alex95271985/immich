import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_viewer.page.dart';
import 'package:immich_mobile/presentation/widgets/images/thumbnail_tile.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/fixed/row.dart';
import 'package:immich_mobile/presentation/widgets/timeline/header.widget.dart';
import 'package:immich_mobile/presentation/widgets/timeline/segment.model.dart';
import 'package:immich_mobile/presentation/widgets/timeline/segment_builder.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.state.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline_drag_region.dart';
import 'package:immich_mobile/providers/asset_viewer/is_motion_video_playing.provider.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/infrastructure/current_album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/timeline/multiselect.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/device_profile.dart';

class FixedSegment extends Segment {
  final double tileHeight;
  final int columnCount;
  final double mainAxisExtend;

  const FixedSegment({
    required super.firstIndex,
    required super.lastIndex,
    required super.startOffset,
    required super.endOffset,
    required super.firstAssetIndex,
    required super.bucket,
    required this.tileHeight,
    required this.columnCount,
    required super.headerExtent,
    required super.spacing,
    required super.header,
  }) : assert(tileHeight != 0),
       mainAxisExtend = tileHeight + spacing;

  @override
  double indexToLayoutOffset(int index) {
    final relativeIndex = index - gridIndex;
    return relativeIndex < 0 ? startOffset : gridOffset + (mainAxisExtend * relativeIndex);
  }

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    final adjustedOffset = scrollOffset - gridOffset;
    if (!adjustedOffset.isFinite || adjustedOffset < 0) {
      return firstIndex;
    }
    return gridIndex + (adjustedOffset / mainAxisExtend).floor();
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    final adjustedOffset = scrollOffset - gridOffset;
    if (!adjustedOffset.isFinite || adjustedOffset < 0) {
      return firstIndex;
    }
    return gridIndex + (adjustedOffset / mainAxisExtend).ceil() - 1;
  }

  @override
  Widget builder(BuildContext context, int index) {
    final rowIndexInSegment = index - (firstIndex + 1);
    final assetIndex = rowIndexInSegment * columnCount;
    final assetCount = bucket.assetCount;
    final numberOfAssets = math.min(columnCount, assetCount - assetIndex);

    if (index == firstIndex) {
      return TimelineHeader(bucket: bucket, header: header, height: headerExtent, assetOffset: firstAssetIndex);
    }

    return _FixedSegmentRow(
      assetIndex: firstAssetIndex + assetIndex,
      assetCount: numberOfAssets,
      tileHeight: tileHeight,
      spacing: spacing,
      columnCount: columnCount,
    );
  }
}

class _FixedSegmentRow extends ConsumerWidget {
  final int assetIndex;
  final int assetCount;
  final double tileHeight;
  final double spacing;
  final int columnCount;

  const _FixedSegmentRow({
    required this.assetIndex,
    required this.assetCount,
    required this.tileHeight,
    required this.spacing,
    required this.columnCount,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timelineService = ref.watch(timelineServiceProvider);
    final isDynamicLayout = columnCount <= (context.isMobile ? 2 : 3);

    if (DeviceProfile.isTV) {
      _prefetchAhead(timelineService);
    }

    if (timelineService.hasRange(assetIndex, assetCount)) {
      return _buildAssetRow(
        context,
        timelineService.getAssets(assetIndex, assetCount),
        timelineService,
        isDynamicLayout,
      );
    }

    // Purposefully created outside of the FutureBuilder so it's created only once
    late final assets = timelineService.loadAssets(assetIndex, assetCount);
    return _DeferredRowLoader(
      key: ValueKey(assetIndex),
      placeholder: _buildPlaceholder,
      builder: (context) => FutureBuilder<List<BaseAsset>>(
        future: assets,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildPlaceholder(context);
          }
          return _buildAssetRow(context, snapshot.requireData, timelineService, isDynamicLayout);
        },
      ),
    );
  }

  /// TV: keep the asset buffer ahead of the focus frontier so that rows entering
  /// the cache extent resolve immediately instead of flashing placeholders.
  /// A single `loadAssets` call fills a whole batch, covering many rows ahead.
  void _prefetchAhead(TimelineService timelineService) {
    const rowsAhead = 2;
    final index = assetIndex + rowsAhead * columnCount;
    if (index >= timelineService.totalAssets || timelineService.hasRange(index, columnCount)) {
      return;
    }

    unawaited(timelineService.loadAssets(index, columnCount));
  }

  Widget _buildPlaceholder(BuildContext context) {
    return SegmentBuilder.buildPlaceholder(context, assetCount, size: Size.square(tileHeight), spacing: spacing);
  }

  Widget _buildAssetRow(
    BuildContext context,
    List<BaseAsset> assets,
    TimelineService timelineService,
    bool isDynamicLayout,
  ) {
    final widths = List.filled(assets.length, tileHeight);

    if (isDynamicLayout) {
      final aspectRatios = assets.map((e) => (e.width ?? 1) / (e.height ?? 1)).toList();
      final meanAspectRatio = aspectRatios.sum / assets.length;

      // 1: mean width
      // 0.5: width < mean - threshold
      // 1.5: width > mean + threshold
      final arConfiguration = aspectRatios.map((e) {
        if (e - meanAspectRatio > 0.3) {
          return 1.5;
        }
        if (e - meanAspectRatio < -0.3) {
          return 0.5;
        }
        return 1.0;
      });

      // Normalize to get width distribution
      final sum = arConfiguration.sum;

      int index = 0;
      for (final ratio in arConfiguration) {
        // Distribute the available width proportionally based on aspect ratio configuration
        widths[index++] = ((ratio * assets.length) / sum) * tileHeight;
      }
    }

    final children = [
      for (int i = 0; i < assets.length; i++)
        TimelineAssetIndexWrapper(
          assetIndex: assetIndex + i,
          segmentIndex: 0, // For simplicity, using 0 for now
          child: _AssetTileWidget(
            key: ValueKey(Object.hash(assets[i].heroTag, assetIndex + i, timelineService.hashCode)),
            asset: assets[i],
            assetIndex: assetIndex + i,
            size: Size(widths[i], tileHeight),
          ),
        ),
    ];

    return TimelineDragRegion(
      child: TimelineRow(
        height: tileHeight,
        widths: widths,
        spacing: spacing,
        textDirection: Directionality.of(context),
        children: children,
      ),
    );
  }
}

/// Lock to displaying placeholders while the timeline is quickly scrolling
/// Automatically stops watching the deferred loading flag once the row has started loading, preventing ever rebuilding the view and losing state
class _DeferredRowLoader extends ConsumerStatefulWidget {
  final WidgetBuilder placeholder;
  final WidgetBuilder builder;

  const _DeferredRowLoader({super.key, required this.placeholder, required this.builder});

  @override
  ConsumerState<_DeferredRowLoader> createState() => _DeferredRowLoaderState();
}

class _DeferredRowLoaderState extends ConsumerState<_DeferredRowLoader> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    // TV: key-driven scrolling must not be treated as a fast fling, rows always load
    final deferLoading =
        !DeviceProfile.isTV && ref.watch(timelineStateProvider.select((state) => state.recommendDeferredLoading));
    if (!_isLoading && deferLoading) {
      return widget.placeholder(context);
    }

    _isLoading = true;
    return widget.builder(context);
  }
}

class _AssetTileWidget extends ConsumerStatefulWidget {
  final BaseAsset asset;
  final int assetIndex;
  final Size size;

  const _AssetTileWidget({super.key, required this.asset, required this.assetIndex, required this.size});

  @override
  ConsumerState<_AssetTileWidget> createState() => _AssetTileWidgetState();
}

class _AssetTileWidgetState extends ConsumerState<_AssetTileWidget> {
  bool _focused = false;

  Future<void> _handleOnTap(int assetIndex, BaseAsset asset, int? heroOffset, Size remoteSize) async {
    final multiSelectState = ref.read(multiSelectProvider);

    if (multiSelectState.forceEnable || multiSelectState.isEnabled) {
      ref.read(multiSelectProvider.notifier).toggleAssetSelection(asset);
    } else {
      await ref.read(timelineServiceProvider).loadAssets(assetIndex, 1);
      if (!mounted) {
        return;
      }

      ref.read(isPlayingMotionVideoProvider.notifier).playing = false;
      AssetViewer.setAsset(ref, asset, thumbnailSize: remoteSize);
      unawaited(
        context.pushRoute(
          AssetViewerRoute(
            initialIndex: assetIndex,
            timelineService: ref.read(timelineServiceProvider),
            heroOffset: heroOffset,
            currentAlbum: ref.read(currentRemoteAlbumProvider),
          ),
        ),
      );
    }
  }

  void _handleOnLongPress(BaseAsset asset) {
    final multiSelectState = ref.read(multiSelectProvider);
    if (multiSelectState.isEnabled || multiSelectState.forceEnable) {
      return;
    }

    ref.read(hapticFeedbackProvider.notifier).heavyImpact();
    ref.read(multiSelectProvider.notifier).toggleAssetSelection(asset);
  }

  bool _getLockSelectionStatus() {
    final lockSelectionAssets = ref.read(multiSelectProvider.select((state) => state.lockedSelectionAssets));

    if (lockSelectionAssets.isEmpty) {
      return false;
    }

    // Iterate with `==` instead of `Set.contains` because `RemoteAsset.hashCode`
    // includes `localId` while `==` does not — so the same server asset can
    // hash to a different bucket when its `localId` differs (e.g., album-fetched
    // copy has localId=null, merged-timeline copy has it populated).
    return lockSelectionAssets.any((a) => a == widget.asset);
  }

  void _setFocused(bool value) {
    if (_focused != value) {
      setState(() => _focused = value);
    }
  }

  /// TV: scale the tile up and draw a border around the focused one
  Widget _buildFocusHighlight(BuildContext context, Widget child) {
    return AnimatedScale(
      scale: _focused ? 1.06 : 1.0,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        foregroundDecoration: _focused
            ? BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 3))
            : null,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final remoteSize = widget.size * MediaQuery.devicePixelRatioOf(context);

    final heroOffset = TabsRouterScope.of(context)?.controller.activeIndex ?? 0;

    final lockSelection = _getLockSelectionStatus();
    final showStorageIndicator = ref.watch(timelineArgsProvider.select((args) => args.showStorageIndicator));
    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);
    final showStackIndicator = ref.watch(timelineServiceProvider).origin != TimelineOrigin.trash;

    final tile = GestureDetector(
      onTap: () => lockSelection ? null : _handleOnTap(widget.assetIndex, widget.asset, heroOffset, remoteSize),
      onLongPress: () => lockSelection || isReadonlyModeEnabled ? null : _handleOnLongPress(widget.asset),
      child: ThumbnailTile(
        widget.asset,
        remoteSize: remoteSize,
        lockSelection: lockSelection,
        showStorageIndicator: showStorageIndicator,
        showStackIndicator: showStackIndicator,
        heroOffset: heroOffset,
      ),
    );

    // TV only: make the tile traversable by a D-pad. Touch devices keep the
    // plain tile so the timeline does not pay for the extra widget layers.
    if (!DeviceProfile.isTV) {
      return RepaintBoundary(child: tile);
    }

    return RepaintBoundary(
      child: FocusableActionDetector(
        // D-pad center / enter opens the asset, same as a tap
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) => _handleOnTap(widget.assetIndex, widget.asset, heroOffset, remoteSize),
          ),
        },
        onShowFocusHighlight: _setFocused,
        child: _buildFocusHighlight(context, tile),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/bottom_bar.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';

class ViewerBottomAppBar extends ConsumerWidget {
  const ViewerBottomAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showingControls = ref.watch(assetViewerProvider.select((s) => s.showingControls));
    final double opacity =
        ref.watch(assetViewerProvider.select((s) => s.backgroundOpacity)) * (showingControls ? 1 : 0);

    return ExcludeFocus(
      // IgnorePointer only blocks pointer events, not focus: exclude the
      // hidden overlay from focus traversal as well (TV remote support)
      excluding: opacity < 1.0,
      child: IgnorePointer(
        ignoring: opacity < 1.0,
        child: AnimatedOpacity(opacity: opacity, duration: Durations.short2, child: const ViewerBottomBar()),
      ),
    );
  }
}

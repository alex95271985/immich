import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/extensions/platform_extensions.dart';

/// Device profile for form-factor specific behavior (TV vs touch).
///
/// TV detection combines two signals, either being sufficient:
/// - the device declares the `android.software.leanback` system feature
///   (reported by Android TV / Google TV and most TV boxes)
/// - the Android `UiModeManager` reports a television UI mode (checked via a
///   small MethodChannel, since device_info_plus does not expose it)
///
/// Initialize once in `main()` before `runApp`; consumers then use the
/// synchronous [isTV] getter.
class DeviceProfile {
  DeviceProfile._();

  static const MethodChannel _channel = MethodChannel('immich/mobile/device_profile');

  static bool _isTV = false;
  static bool _initialized = false;

  /// Whether the app is running on an Android TV / set-top box.
  static bool get isTV => _initialized && _isTV;

  static Future<void> init() async {
    if (_initialized) {
      return;
    }

    if (!CurrentPlatform.isAndroid) {
      _initialized = true;
      return;
    }

    try {
      final info = await DeviceInfoPlugin().androidInfo;
      if (info.systemFeatures.contains('android.software.leanback')) {
        _isTV = true;
      } else {
        _isTV = await _channel.invokeMethod<bool>('isTelevision') ?? false;
      }
    } catch (_) {
      // Detection failures safely fall back to non-TV behavior
      _isTV = false;
    } finally {
      _initialized = true;
    }
  }
}

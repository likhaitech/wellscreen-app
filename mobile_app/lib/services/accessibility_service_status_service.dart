import 'package:flutter/services.dart';

class AccessibilityServiceStatusService {
  static const MethodChannel _channel = MethodChannel(
    'com.wellscreen.app/accessibility_service',
  );

  Future<bool> isAccessibilityServiceEnabled() async {
    try {
      final enabled = await _channel.invokeMethod<bool>(
        'isAccessibilityServiceEnabled',
      );
      return enabled ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openAccessibilitySettings() async {
    await _channel.invokeMethod('openAccessibilitySettings');
  }
}

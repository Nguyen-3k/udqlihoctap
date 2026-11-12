/// Cầu nối Browser Notification API (stub cho Android/Desktop/Unit Test).
class WebNotificationBridge {
  static bool get isSupported => false;

  static String get permissionState => 'unsupported';

  static Future<bool> requestPermission() async => false;

  static bool showNotification({
    required String title,
    required String body,
    String? tag,
  }) => false;
}

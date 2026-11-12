import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Cầu nối trực tiếp tới Browser Notification API trên nền tảng Web.
/// Chỉ hoạt động trong lúc người dùng đang mở tab trình duyệt và đã cấp quyền Notification.
class WebNotificationBridge {
  static bool get isSupported {
    try {
      return web.window.hasProperty('Notification'.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  static String get permissionState {
    if (!isSupported) return 'unsupported';
    try {
      return web.Notification.permission;
    } catch (_) {
      return 'unsupported';
    }
  }

  static Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      final current = permissionState;
      if (current == 'granted') return true;
      if (current == 'denied') return false;
      final res = await web.Notification.requestPermission().toDart;
      return res.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  static bool showNotification({
    required String title,
    required String body,
    String? tag,
  }) {
    if (!isSupported || permissionState != 'granted') {
      return false;
    }
    try {
      web.Notification(
        title,
        web.NotificationOptions(body: body, tag: tag ?? 'exampilot'),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}

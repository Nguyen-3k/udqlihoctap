import 'package:web/web.dart' as web;

/// Lưu trữ bền vững trạng thái Alarm State Machine trên Web Preview qua `window.localStorage`.
class WebAlarmStorage {
  static const String _storageKey = 'exampilot_web_alarms_v1';

  static String? loadRawJson() {
    try {
      return web.window.localStorage.getItem(_storageKey);
    } catch (_) {
      return null;
    }
  }

  static void saveRawJson(String rawJson) {
    try {
      web.window.localStorage.setItem(_storageKey, rawJson);
    } catch (_) {}
  }

  static void clear() {
    try {
      web.window.localStorage.removeItem(_storageKey);
    } catch (_) {}
  }
}

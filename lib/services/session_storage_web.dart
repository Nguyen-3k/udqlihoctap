import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;
import '../models/study_session.dart';
import 'session_storage_codec.dart';

/// Lưu trữ bền vững danh sách `StudySession` trên Web (`window.localStorage`)
/// sử dụng namespace riêng, hoàn toàn độc lập với `WebStreakStorage` và không phụ thuộc SQLite.
class WebSessionStorage {
  static const String storageKey = SessionStorageCodec.sessionsStorageKey;

  /// Đọc danh sách toàn bộ `StudySession` từ `window.localStorage`.
  static List<StudySession> loadSessions() {
    try {
      final raw = web.window.localStorage.getItem(storageKey);
      return SessionStorageCodec.parseSessionsJson(raw);
    } catch (_) {
      return [];
    }
  }

  /// Lưu danh sách `StudySession` vào `window.localStorage` dưới key riêng.
  static void saveSessions(List<StudySession> sessions) {
    try {
      web.window.localStorage.setItem(
        storageKey,
        SessionStorageCodec.encodeSessionsJson(sessions),
      );
    } catch (e) {
      debugPrint('Lỗi ghi WebSessionStorage vào localStorage: $e');
    }
  }

  /// Tìm một phiên học theo ID.
  static StudySession? loadSessionById(String id) {
    for (final s in loadSessions()) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Tạo mới một phiên học (ném lỗi nếu trùng ID).
  static void createSession(StudySession session) {
    final current = loadSessions();
    if (current.any((s) => s.id == session.id)) {
      throw StateError('Phiên học với id "${session.id}" đã tồn tại.');
    }
    current.add(session);
    saveSessions(current);
  }

  /// Cập nhật một phiên học đã tồn tại (ném lỗi nếu không tìm thấy).
  static void updateSession(StudySession session) {
    final current = loadSessions();
    final idx = current.indexWhere((s) => s.id == session.id);
    if (idx == -1) {
      throw StateError(
        'Không tìm thấy phiên học với id "${session.id}" để cập nhật.',
      );
    }
    current[idx] = session;
    saveSessions(current);
  }

  /// Xóa một phiên học theo ID.
  static void deleteSession(String id) {
    final current = loadSessions();
    current.removeWhere((s) => s.id == id);
    saveSessions(current);
  }

  /// Xóa sạch dữ liệu phiên học (chỉ xóa key của `WebSessionStorage`).
  static void clearSessions() {
    try {
      web.window.localStorage.removeItem(storageKey);
    } catch (_) {}
  }

  @visibleForTesting
  static void setRawStorageValueForTesting(String key, String value) {
    try {
      web.window.localStorage.setItem(key, value);
    } catch (_) {}
  }

  @visibleForTesting
  static String? getRawStorageValueForTesting(String key) {
    try {
      return web.window.localStorage.getItem(key);
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static void resetAllSimulatedStorageForTesting() {
    clearSessions();
  }
}

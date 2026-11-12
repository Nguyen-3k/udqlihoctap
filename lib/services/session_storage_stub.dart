import 'package:flutter/foundation.dart';
import '../models/study_session.dart';
import 'session_storage_codec.dart';

/// Lưu trữ danh sách `StudySession` độc lập trên bộ nhớ giả lập localStorage
/// cho các nền tảng non-Web (Android/Desktop/Unit Test), hoàn toàn tách biệt khỏi `WebStreakStorage`.
class WebSessionStorage {
  static const String storageKey = SessionStorageCodec.sessionsStorageKey;

  /// Bộ nhớ khóa-giá trị nội bộ mô phỏng chính xác cơ chế tuần tự hóa JSON của trình duyệt.
  static final Map<String, String> _simulatedLocalStorage = {};

  /// Đọc danh sách toàn bộ `StudySession` (đã sắp xếp ổn định, an toàn với JSON lỗi).
  static List<StudySession> loadSessions() {
    final raw = _simulatedLocalStorage[storageKey];
    return SessionStorageCodec.parseSessionsJson(raw);
  }

  /// Lưu đè toàn bộ danh sách `StudySession` vào khóa riêng biệt.
  static void saveSessions(List<StudySession> sessions) {
    _simulatedLocalStorage[storageKey] = SessionStorageCodec.encodeSessionsJson(
      sessions,
    );
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

  /// Xóa sạch dữ liệu phiên học (chỉ chạm vào key của `WebSessionStorage`).
  static void clearSessions() {
    _simulatedLocalStorage.remove(storageKey);
  }

  @visibleForTesting
  static void setRawStorageValueForTesting(String key, String value) {
    _simulatedLocalStorage[key] = value;
  }

  @visibleForTesting
  static String? getRawStorageValueForTesting(String key) {
    return _simulatedLocalStorage[key];
  }

  @visibleForTesting
  static void resetAllSimulatedStorageForTesting() {
    _simulatedLocalStorage.clear();
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/study_session.dart';

/// Tiện ích dùng chung cho cả Web (`localStorage`) và Stub để tuần tự hóa / giải mã
/// danh sách `StudySession` đồng nhất, an toàn với JSON hỏng và có thứ tự ổn định.
class SessionStorageCodec {
  /// Namespace riêng biệt tuyệt đối khỏi các khóa của `WebStreakStorage`.
  static const String sessionsStorageKey = 'exampilot_web_study_sessions_v1';

  /// Sắp xếp ổn định: mới nhất trước (`startedAt DESC`), cùng mốc thời gian xếp theo `id ASC`.
  static List<StudySession> sortDeterministic(List<StudySession> sessions) {
    final sorted = List<StudySession>.from(sessions);
    sorted.sort((a, b) {
      final timeCmp = b.startedAt.compareTo(a.startedAt);
      if (timeCmp != 0) return timeCmp;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  /// Giải mã an toàn chuỗi JSON từ localStorage; trả về danh sách rỗng nếu JSON hỏng.
  static List<StudySession> parseSessionsJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return [];

      final parsed = <StudySession>[];
      for (final item in decoded) {
        if (item is Map) {
          try {
            parsed.add(StudySession.fromMap(Map<String, dynamic>.from(item)));
          } catch (e) {
            debugPrint('Bỏ qua bản ghi StudySession hỏng trong WebStorage: $e');
          }
        }
      }
      return sortDeterministic(parsed);
    } catch (e) {
      debugPrint('Lỗi giải mã JSON WebSessionStorage: $e');
      return [];
    }
  }

  /// Mã hóa danh sách `StudySession` sang JSON chuẩn UTC.
  static String encodeSessionsJson(List<StudySession> sessions) {
    final sorted = sortDeterministic(sessions);
    return jsonEncode(sorted.map((s) => s.toMap()).toList());
  }
}

import 'dart:convert';
import 'package:web/web.dart' as web;
import '../models/class_schedule.dart';
import '../models/class_schedule_occurrence.dart';
import '../models/study_activity.dart';
import '../models/user_profile.dart';

/// Triển khai lưu trữ danh sách ngày học tập và hoạt động trên Web (Chrome) sử dụng window.localStorage.
class WebStreakStorage {
  static const String _storageKey = 'exampilot_web_active_dates';
  static const String _activitiesStorageKey = 'exampilot_web_activities';
  static const String _profileStorageKey = 'exampilot_web_profile';

  /// Đọc danh sách các ngày học đã lưu từ localStorage của trình duyệt.
  static Set<String> loadActiveDates() {
    try {
      final raw = web.window.localStorage.getItem(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map((e) => e.toString().trim())
              .where((d) => d.isNotEmpty)
              .toSet();
        }
      }
    } catch (_) {}
    return {};
  }

  /// Lưu danh sách các ngày học (định dạng YYYY-MM-DD) vào localStorage của trình duyệt.
  static void saveActiveDates(Set<String> dates) {
    try {
      final list = dates.toList()..sort();
      web.window.localStorage.setItem(_storageKey, jsonEncode(list));
    } catch (_) {}
  }

  /// Đọc danh sách hoạt động học tập chi tiết từ localStorage.
  static List<StudyActivity> loadActivities() {
    try {
      final raw = web.window.localStorage.getItem(_activitiesStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map(
                (item) => StudyActivity.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  /// Lưu danh sách hoạt động học tập chi tiết vào localStorage.
  static void saveActivities(List<StudyActivity> activities) {
    try {
      final list = activities.map((a) => a.toMap()).toList();
      web.window.localStorage.setItem(_activitiesStorageKey, jsonEncode(list));
    } catch (_) {}
  }

  /// Đọc thông tin hồ sơ cá nhân và cài đặt từ localStorage.
  static UserProfile? loadProfile() {
    try {
      final raw = web.window.localStorage.getItem(_profileStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return UserProfile.fromMap(decoded);
        } else if (decoded is Map) {
          return UserProfile.fromMap(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {}
    return null;
  }

  /// Lưu thông tin hồ sơ cá nhân và cài đặt vào localStorage.
  static void saveProfile(UserProfile profile) {
    try {
      web.window.localStorage.setItem(
        _profileStorageKey,
        jsonEncode(profile.toMap()),
      );
    } catch (_) {}
  }

  /// Xóa thông tin hồ sơ cá nhân khỏi localStorage.
  static void clearProfile() {
    try {
      web.window.localStorage.removeItem(_profileStorageKey);
    } catch (_) {}
  }

  /// Xóa danh sách ngày học và hoạt động học tập (giữ nguyên hồ sơ cá nhân).
  static void clearStudyActivitiesAndDates() {
    try {
      web.window.localStorage.removeItem(_storageKey);
      web.window.localStorage.removeItem(_activitiesStorageKey);
    } catch (_) {}
  }

  /// Xóa dữ liệu ngày học và hoạt động (phục vụ kiểm thử).
  static void clearActiveDates() {
    try {
      web.window.localStorage.removeItem(_storageKey);
      web.window.localStorage.removeItem(_activitiesStorageKey);
    } catch (_) {}
  }
}

/// Triển khai lưu trữ lịch học trên Web sử dụng localStorage.
class WebScheduleStorage {
  static const String _scheduleStorageKey = 'exampilot_web_schedules';

  static List<ClassSchedule> loadSchedules() {
    try {
      final raw = web.window.localStorage.getItem(_scheduleStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map(
                (item) => ClassSchedule.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static void saveSchedules(List<ClassSchedule> schedules) {
    try {
      final list = schedules.map((s) => s.toMap()).toList();
      web.window.localStorage.setItem(_scheduleStorageKey, jsonEncode(list));
    } catch (_) {}
  }

  static void clearSchedules() {
    try {
      web.window.localStorage.removeItem(_scheduleStorageKey);
    } catch (_) {}
  }
}

/// Triển khai lưu trữ buổi học theo ngày (occurrences) trên Web sử dụng localStorage.
class WebOccurrenceStorage {
  static const String _occurrenceStorageKey = 'exampilot_web_occurrences';

  static List<ClassScheduleOccurrence> loadOccurrences() {
    try {
      final raw = web.window.localStorage.getItem(_occurrenceStorageKey);
      if (raw != null && raw.isNotEmpty) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is List) {
          return decoded
              .map(
                (item) => ClassScheduleOccurrence.fromMap(
                  Map<String, dynamic>.from(item as Map),
                ),
              )
              .toList();
        }
      }
    } catch (_) {}
    return [];
  }

  static void saveOccurrences(List<ClassScheduleOccurrence> occurrences) {
    try {
      final list = occurrences.map((o) => o.toMap()).toList();
      web.window.localStorage.setItem(_occurrenceStorageKey, jsonEncode(list));
    } catch (_) {}
  }

  static void clearOccurrences() {
    try {
      web.window.localStorage.removeItem(_occurrenceStorageKey);
    } catch (_) {}
  }
}

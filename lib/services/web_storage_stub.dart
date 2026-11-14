import '../models/class_schedule.dart';
import '../models/class_schedule_occurrence.dart';
import '../models/study_activity.dart';
import '../models/user_profile.dart';

/// Triển khai lưu trữ dự phòng khi không chạy trên Web (Android, iOS, Desktop, Unit Test).
class WebStreakStorage {
  static Set<String> _inMemoryStorage = {};
  static List<StudyActivity> _inMemoryActivities = [];
  static UserProfile? _inMemoryProfile;

  /// Đọc danh sách ngày học đã lưu.
  static Set<String> loadActiveDates() {
    return Set<String>.from(_inMemoryStorage);
  }

  /// Lưu danh sách ngày học.
  static void saveActiveDates(Set<String> dates) {
    _inMemoryStorage = Set<String>.from(dates);
  }

  /// Đọc danh sách hoạt động học tập đã lưu.
  static List<StudyActivity> loadActivities() {
    return List<StudyActivity>.from(_inMemoryActivities);
  }

  /// Lưu danh sách hoạt động học tập.
  static void saveActivities(List<StudyActivity> activities) {
    _inMemoryActivities = List<StudyActivity>.from(activities);
  }

  /// Đọc thông tin hồ sơ cá nhân và cài đặt đã lưu.
  static UserProfile? loadProfile() {
    return _inMemoryProfile;
  }

  /// Lưu thông tin hồ sơ cá nhân và cài đặt.
  static void saveProfile(UserProfile profile) {
    _inMemoryProfile = profile;
  }

  /// Xóa thông tin hồ sơ cá nhân đã lưu.
  static void clearProfile() {
    _inMemoryProfile = null;
  }

  /// Xóa danh sách ngày học và hoạt động học tập (giữ nguyên hồ sơ cá nhân).
  static void clearStudyActivitiesAndDates() {
    _inMemoryStorage.clear();
    _inMemoryActivities.clear();
  }

  /// Xóa dữ liệu ngày học và hoạt động (phục vụ kiểm thử).
  static void clearActiveDates() {
    _inMemoryStorage.clear();
    _inMemoryActivities.clear();
  }
}

/// Triển khai lưu trữ lịch học dự phòng khi không chạy trên Web.
class WebScheduleStorage {
  static List<ClassSchedule> _inMemorySchedules = [];

  static List<ClassSchedule> loadSchedules() {
    return List<ClassSchedule>.from(_inMemorySchedules);
  }

  static void saveSchedules(List<ClassSchedule> schedules) {
    _inMemorySchedules = List<ClassSchedule>.from(schedules);
  }

  static void clearSchedules() {
    _inMemorySchedules.clear();
  }
}

/// Triển khai lưu trữ buổi học theo ngày (occurrences) dự phòng khi không chạy trên Web.
class WebOccurrenceStorage {
  static List<ClassScheduleOccurrence> _inMemoryOccurrences = [];

  static List<ClassScheduleOccurrence> loadOccurrences() {
    return List<ClassScheduleOccurrence>.from(_inMemoryOccurrences);
  }

  static void saveOccurrences(List<ClassScheduleOccurrence> occurrences) {
    _inMemoryOccurrences = List<ClassScheduleOccurrence>.from(occurrences);
  }

  static void clearOccurrences() {
    _inMemoryOccurrences.clear();
  }
}

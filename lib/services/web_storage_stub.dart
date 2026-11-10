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

  /// Xóa dữ liệu (phục vụ kiểm thử).
  static void clearActiveDates() {
    _inMemoryStorage.clear();
    _inMemoryActivities.clear();
    _inMemoryProfile = null;
  }
}

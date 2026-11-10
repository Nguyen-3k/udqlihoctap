import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/user_profile.dart';
import '../services/web_storage.dart';

/// Repository quản lý lưu trữ Hồ sơ cá nhân, Mục tiêu học tập và Cài đặt.
/// - Trên Android / SQLite: Lưu bền vững trong bảng `user_profile`.
/// - Trên Web Preview / In-memory: Lưu bền vững trong `localStorage` qua `WebStreakStorage`.
class ProfileRepository {
  final DatabaseHelper? _dbHelper;
  final bool isWebPreview;
  UserProfile? _cachedProfile;

  ProfileRepository({DatabaseHelper? dbHelper, bool useWebPreview = false})
    : _dbHelper = dbHelper ?? DatabaseHelper.instance,
      isWebPreview = useWebPreview || kIsWeb;

  /// Đảm bảo bảng `user_profile` đã tồn tại trong SQLite (kể cả trong các mock in-memory database test).
  Future<void> _ensureTableExists(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${DatabaseHelper.tableProfile} (
        ${DatabaseHelper.columnProfileId} TEXT PRIMARY KEY,
        ${DatabaseHelper.columnProfileName} TEXT NOT NULL DEFAULT '',
        ${DatabaseHelper.columnProfileUniversity} TEXT NOT NULL DEFAULT '',
        ${DatabaseHelper.columnProfileMajor} TEXT NOT NULL DEFAULT '',
        ${DatabaseHelper.columnProfileAcademicYear} TEXT NOT NULL DEFAULT '',
        ${DatabaseHelper.columnProfileAvatarId} TEXT NOT NULL DEFAULT 'school',
        ${DatabaseHelper.columnProfileTargetHours} REAL NOT NULL DEFAULT 10.0,
        ${DatabaseHelper.columnProfileTargetTasks} INTEGER NOT NULL DEFAULT 5,
        ${DatabaseHelper.columnProfileThemeMode} TEXT NOT NULL DEFAULT 'system',
        ${DatabaseHelper.columnProfileReminderEnabled} INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Đọc hồ sơ cá nhân hiện tại.
  /// Nếu chưa thiết lập, trả về UserProfile() với các trường rỗng (không tạo thông tin giả).
  Future<UserProfile> getProfile() async {
    if (isWebPreview) {
      final saved = WebStreakStorage.loadProfile();
      _cachedProfile = saved ?? const UserProfile();
      return _cachedProfile!;
    }

    try {
      final db = await _dbHelper!.database;
      if (!db.isOpen) {
        _cachedProfile = const UserProfile();
        return _cachedProfile!;
      }
      await _ensureTableExists(db);

      final List<Map<String, dynamic>> maps = await db.query(
        DatabaseHelper.tableProfile,
        where: '${DatabaseHelper.columnProfileId} = ?',
        whereArgs: [UserProfile.defaultId],
      );

      if (maps.isNotEmpty) {
        _cachedProfile = UserProfile.fromMap(maps.first);
        return _cachedProfile!;
      }
    } catch (e) {
      debugPrint('Lỗi đọc UserProfile từ SQLite: $e');
    }

    // Nếu chưa có dữ liệu trong SQLite, trả về trạng thái rỗng chưa cấu hình
    _cachedProfile = const UserProfile();
    return _cachedProfile!;
  }

  /// Lưu thông tin hồ sơ cá nhân và cài đặt.
  Future<void> saveProfile(UserProfile profile) async {
    _cachedProfile = profile;

    if (isWebPreview) {
      WebStreakStorage.saveProfile(profile);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      if (!db.isOpen) return;
      await _ensureTableExists(db);

      await db.insert(
        DatabaseHelper.tableProfile,
        profile.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      debugPrint('Lỗi lưu UserProfile vào SQLite: $e');
      rethrow;
    }
  }

  /// Cập nhật mục tiêu học tập hàng tuần (giờ và số công việc).
  Future<UserProfile> updateWeeklyGoals({
    required double hours,
    required int tasks,
  }) async {
    final current = await getProfile();
    final updated = current.copyWith(
      weeklyTargetHours: hours,
      weeklyTargetTasks: tasks,
    );
    await saveProfile(updated);
    return updated;
  }

  /// Cập nhật chế độ giao diện sáng / tối / hệ thống.
  Future<UserProfile> updateThemeMode(String mode) async {
    final current = await getProfile();
    final updated = current.copyWith(themeMode: mode);
    await saveProfile(updated);
    return updated;
  }

  /// Bật hoặc tắt thông báo nhắc nhở học tập.
  Future<UserProfile> updateReminderEnabled(bool enabled) async {
    final current = await getProfile();
    final updated = current.copyWith(reminderEnabled: enabled);
    await saveProfile(updated);
    return updated;
  }

  /// Đặt lại hồ sơ cá nhân về trạng thái chưa thiết lập.
  Future<void> resetProfile() async {
    _cachedProfile = const UserProfile();

    if (isWebPreview) {
      WebStreakStorage.clearProfile();
      return;
    }

    try {
      final db = await _dbHelper!.database;
      if (!db.isOpen) return;
      await _ensureTableExists(db);
      await db.delete(
        DatabaseHelper.tableProfile,
        where: '${DatabaseHelper.columnProfileId} = ?',
        whereArgs: [UserProfile.defaultId],
      );
    } catch (e) {
      debugPrint('Lỗi đặt lại UserProfile trong SQLite: $e');
      rethrow;
    }
  }
}

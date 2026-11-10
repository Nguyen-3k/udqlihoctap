import 'package:flutter/material.dart';

/// Đại diện cho biểu tượng avatar được hỗ trợ sẵn trong ExamPilot.
class AvatarPreset {
  final String id;
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;

  const AvatarPreset({
    required this.id,
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  static const List<AvatarPreset> presets = [
    AvatarPreset(
      id: 'school',
      label: 'Sinh viên',
      icon: Icons.school_rounded,
      backgroundColor: Color(0xFFEEF2FF),
      foregroundColor: Color(0xFF3B5BDB),
    ),
    AvatarPreset(
      id: 'laptop',
      label: 'Công nghệ',
      icon: Icons.laptop_chromebook_rounded,
      backgroundColor: Color(0xFFE0F2FE),
      foregroundColor: Color(0xFF0284C7),
    ),
    AvatarPreset(
      id: 'book',
      label: 'Mọt sách',
      icon: Icons.menu_book_rounded,
      backgroundColor: Color(0xFFDCFCE7),
      foregroundColor: Color(0xFF16A34A),
    ),
    AvatarPreset(
      id: 'psychology',
      label: 'Tư duy',
      icon: Icons.psychology_rounded,
      backgroundColor: Color(0xFFF3E8FF),
      foregroundColor: Color(0xFF9333EA),
    ),
    AvatarPreset(
      id: 'science',
      label: 'Nghiên cứu',
      icon: Icons.science_rounded,
      backgroundColor: Color(0xFFFFFBEB),
      foregroundColor: Color(0xFFD97706),
    ),
    AvatarPreset(
      id: 'palette',
      label: 'Sáng tạo',
      icon: Icons.palette_rounded,
      backgroundColor: Color(0xFFFFE4E6),
      foregroundColor: Color(0xFFE11D48),
    ),
    AvatarPreset(
      id: 'workspace',
      label: 'Chuyên gia',
      icon: Icons.workspace_premium_rounded,
      backgroundColor: Color(0xFFFEF3C7),
      foregroundColor: Color(0xFFB45309),
    ),
    AvatarPreset(
      id: 'person',
      label: 'Cá nhân',
      icon: Icons.person_rounded,
      backgroundColor: Color(0xFFF1F5F9),
      foregroundColor: Color(0xFF475569),
    ),
  ];

  static AvatarPreset getById(String id) {
    return presets.firstWhere((p) => p.id == id, orElse: () => presets.first);
  }
}

/// Mô hình lưu trữ Hồ sơ cá nhân, Mục tiêu học tập và Cài đặt của sinh viên.
/// Thiết kế chạy offline, không có backend và không có đăng nhập.
class UserProfile {
  static const String defaultId = 'primary_profile';

  final String id;
  final String name; // Tên hiển thị (để trống nếu chưa thiết lập)
  final String university; // Trường đại học
  final String major; // Ngành học
  final String academicYear; // Khóa học hoặc năm học (tùy chọn)
  final String avatarId; // Mã avatar được chọn
  final double weeklyTargetHours; // Mục tiêu thời lượng học tuần (giờ)
  final int weeklyTargetTasks; // Mục tiêu số công việc hoàn thành tuần
  final String themeMode; // 'system', 'light', 'dark'
  final bool reminderEnabled; // Trạng thái bật/tắt nhắc học

  const UserProfile({
    this.id = defaultId,
    this.name = '',
    this.university = '',
    this.major = '',
    this.academicYear = '',
    this.avatarId = 'school',
    this.weeklyTargetHours = 10.0,
    this.weeklyTargetTasks = 5,
    this.themeMode = 'system',
    this.reminderEnabled = false,
  });

  /// Kiểm tra xem người dùng đã thiết lập thông tin cá nhân hay chưa.
  bool get isConfigured => name.trim().isNotEmpty;

  /// Lấy avatar preset tương ứng.
  AvatarPreset get avatar => AvatarPreset.getById(avatarId);

  /// Chuyển đổi themeMode chuỗi sang ThemeMode của Flutter.
  ThemeMode get flutterThemeMode {
    switch (themeMode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  UserProfile copyWith({
    String? id,
    String? name,
    String? university,
    String? major,
    String? academicYear,
    String? avatarId,
    double? weeklyTargetHours,
    int? weeklyTargetTasks,
    String? themeMode,
    bool? reminderEnabled,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      university: university ?? this.university,
      major: major ?? this.major,
      academicYear: academicYear ?? this.academicYear,
      avatarId: avatarId ?? this.avatarId,
      weeklyTargetHours: weeklyTargetHours ?? this.weeklyTargetHours,
      weeklyTargetTasks: weeklyTargetTasks ?? this.weeklyTargetTasks,
      themeMode: themeMode ?? this.themeMode,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'university': university,
      'major': major,
      'academic_year': academicYear,
      'avatar_id': avatarId,
      'weekly_target_hours': weeklyTargetHours,
      'weekly_target_tasks': weeklyTargetTasks,
      'theme_mode': themeMode,
      'reminder_enabled': reminderEnabled ? 1 : 0,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id']?.toString() ?? defaultId,
      name: map['name']?.toString() ?? '',
      university: map['university']?.toString() ?? '',
      major: map['major']?.toString() ?? '',
      academicYear: map['academic_year']?.toString() ?? '',
      avatarId: map['avatar_id']?.toString() ?? 'school',
      weeklyTargetHours: (map['weekly_target_hours'] is num)
          ? (map['weekly_target_hours'] as num).toDouble()
          : (double.tryParse(
                  map['weekly_target_hours']?.toString() ?? '10.0',
                ) ??
                10.0),
      weeklyTargetTasks: (map['weekly_target_tasks'] is int)
          ? map['weekly_target_tasks'] as int
          : (int.tryParse(map['weekly_target_tasks']?.toString() ?? '5') ?? 5),
      themeMode: map['theme_mode']?.toString() ?? 'system',
      reminderEnabled:
          map['reminder_enabled'] == 1 || map['reminder_enabled'] == true,
    );
  }

  /// Khởi tạo trạng thái mặc định chưa thiết lập hồ sơ.
  static const UserProfile empty = UserProfile();
}

/// Tiến độ thực hiện mục tiêu học tập tuần này.
/// Được tính toán từ các hoạt động học tập thực tế (`study_activities`).
class WeeklyGoalProgress {
  final double targetHours;
  final int targetTasks;
  final double actualHours;
  final int actualTasks;

  const WeeklyGoalProgress({
    required this.targetHours,
    required this.targetTasks,
    required this.actualHours,
    required this.actualTasks,
  });

  /// Số giờ còn thiếu để đạt mục tiêu (tối thiểu 0).
  double get remainingHours =>
      (targetHours - actualHours).clamp(0.0, double.infinity);

  /// Số công việc còn thiếu để đạt mục tiêu (tối thiểu 0).
  int get remainingTasks => (targetTasks - actualTasks).clamp(0, 999999);

  /// Tỷ lệ phần trăm thời lượng đã đạt (0.0 -> 1.0).
  double get hoursRate =>
      targetHours <= 0 ? 0.0 : (actualHours / targetHours).clamp(0.0, 1.0);

  /// Tỷ lệ phần trăm số công việc đã đạt (0.0 -> 1.0).
  double get tasksRate =>
      targetTasks <= 0 ? 0.0 : (actualTasks / targetTasks).clamp(0.0, 1.0);

  /// Đã đạt mục tiêu thời lượng.
  bool get isHoursAchieved => targetHours > 0 && actualHours >= targetHours;

  /// Đã đạt mục tiêu số công việc.
  bool get isTasksAchieved => targetTasks > 0 && actualTasks >= targetTasks;

  /// Đã hoàn thành xuất sắc cả 2 mục tiêu.
  bool get isAllAchieved => isHoursAchieved && isTasksAchieved;
}

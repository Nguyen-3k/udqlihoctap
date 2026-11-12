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

  static const String defaultAlarmSoundId = 'alarm_dawn';
  static const String defaultBreakSoundId = 'break_windchime';
  static const int defaultPreReminderMinutes = 10;
  static const String defaultBreakPresetId = 'pomodoro_25_5';
  static const int defaultCustomStudyMinutes = 25;
  static const int defaultCustomBreakMinutes = 5;
  static const int defaultDailyStudyLimitMinutes = 240;

  static const Set<String> validAlarmSoundIds = {
    'alarm_dawn',
    'alarm_school_bell',
    'alarm_energetic',
    'none',
  };
  static const Set<String> validBreakSoundIds = {
    'break_windchime',
    'break_waterdrop',
    'break_marimba',
    'none',
  };
  static const Set<String> validBreakPresetIds = {
    'pomodoro_25_5',
    'deep_50_10',
    'long_90_15',
    'custom',
  };
  static const Set<String> validThemeModes = {'system', 'light', 'dark'};

  final String id;
  final String name; // Tên hiển thị (để trống nếu chưa thiết lập)
  final String university; // Trường đại học
  final String major; // Ngành học
  final String academicYear; // Khóa học hoặc năm học (tùy chọn)
  final String avatarId; // Mã avatar được chọn
  final double weeklyTargetHours; // Mục tiêu thời lượng học tuần (giờ)
  final int weeklyTargetTasks; // Mục tiêu số công việc hoàn thành tuần
  final String themeMode; // 'system', 'light', 'dark'
  final bool reminderEnabled; // Trạng thái bật/tắt thông báo tổng

  // Cấu hình Âm thanh, Thông báo, Chu kỳ nghỉ & Giới hạn lập lịch G9.0 (Schema v7)
  final String alarmSoundId;
  final String breakSoundId;
  final int preReminderMinutes;
  final String breakPresetId;
  final int customStudyMinutes;
  final int customBreakMinutes;
  final bool autoBreakReminder;
  final bool notifyPreStudy;
  final bool notifyAlarmOnTime;
  final bool notifySessionStart;
  final bool notifyBreakStart;
  final bool notifyBreakEnd;

  /// Giới hạn học tham khảo mỗi ngày dành riêng cho Smart Rescheduling G9.0.
  /// KHÔNG dùng để giới hạn hoặc tự dừng Study Timer.
  final int dailyStudyLimitMinutes;

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
    this.alarmSoundId = defaultAlarmSoundId,
    this.breakSoundId = defaultBreakSoundId,
    this.preReminderMinutes = defaultPreReminderMinutes,
    this.breakPresetId = defaultBreakPresetId,
    this.customStudyMinutes = defaultCustomStudyMinutes,
    this.customBreakMinutes = defaultCustomBreakMinutes,
    this.autoBreakReminder = true,
    this.notifyPreStudy = true,
    this.notifyAlarmOnTime = true,
    this.notifySessionStart = true,
    this.notifyBreakStart = true,
    this.notifyBreakEnd = true,
    this.dailyStudyLimitMinutes = defaultDailyStudyLimitMinutes,
  });

  /// Kiểm tra xem người dùng đã thiết lập thông tin cá nhân hay chưa.
  bool get isConfigured => name.trim().isNotEmpty;

  /// Lấy avatar preset tương ứng.
  AvatarPreset get avatar => AvatarPreset.getById(avatarId);

  /// Kiểm tra tính hợp lệ các giá trị cấu hình trước khi lưu trữ.
  void validate() {
    if (weeklyTargetHours.isNaN ||
        weeklyTargetHours.isInfinite ||
        weeklyTargetHours < 0 ||
        weeklyTargetHours > 168) {
      throw ArgumentError.value(
        weeklyTargetHours,
        'weeklyTargetHours',
        'Mục tiêu giờ học tuần phải nằm trong khoảng 0 đến 168 giờ.',
      );
    }
    if (weeklyTargetTasks < 0 || weeklyTargetTasks > 500) {
      throw ArgumentError.value(
        weeklyTargetTasks,
        'weeklyTargetTasks',
        'Mục tiêu số công việc tuần phải nằm trong khoảng 0 đến 500.',
      );
    }
    if (!validThemeModes.contains(themeMode)) {
      throw ArgumentError.value(
        themeMode,
        'themeMode',
        'Chế độ giao diện không hợp lệ: $themeMode',
      );
    }
    if (!validAlarmSoundIds.contains(alarmSoundId)) {
      throw ArgumentError.value(
        alarmSoundId,
        'alarmSoundId',
        'Âm thanh báo thức không hợp lệ: $alarmSoundId',
      );
    }
    if (!validBreakSoundIds.contains(breakSoundId)) {
      throw ArgumentError.value(
        breakSoundId,
        'breakSoundId',
        'Âm thanh nhắc nghỉ không hợp lệ: $breakSoundId',
      );
    }
    if (preReminderMinutes < 0 || preReminderMinutes > 120) {
      throw ArgumentError.value(
        preReminderMinutes,
        'preReminderMinutes',
        'Thời gian nhắc trước phải nằm trong khoảng 0 đến 120 phút.',
      );
    }
    if (!validBreakPresetIds.contains(breakPresetId)) {
      throw ArgumentError.value(
        breakPresetId,
        'breakPresetId',
        'Preset chu kỳ nghỉ không hợp lệ: $breakPresetId',
      );
    }
    if (customStudyMinutes < 1 || customStudyMinutes > 180) {
      throw ArgumentError.value(
        customStudyMinutes,
        'customStudyMinutes',
        'Thời lượng học tùy chỉnh phải nằm trong khoảng 1 đến 180 phút.',
      );
    }
    if (customBreakMinutes < 1 || customBreakMinutes > 60) {
      throw ArgumentError.value(
        customBreakMinutes,
        'customBreakMinutes',
        'Thời lượng nghỉ tùy chỉnh phải nằm trong khoảng 1 đến 60 phút.',
      );
    }
    if (dailyStudyLimitMinutes < 15 || dailyStudyLimitMinutes > 1440) {
      throw ArgumentError.value(
        dailyStudyLimitMinutes,
        'dailyStudyLimitMinutes',
        'Giới hạn học tham khảo mỗi ngày phải nằm trong khoảng 15 đến 1440 phút.',
      );
    }
  }

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
    String? alarmSoundId,
    String? breakSoundId,
    int? preReminderMinutes,
    String? breakPresetId,
    int? customStudyMinutes,
    int? customBreakMinutes,
    bool? autoBreakReminder,
    bool? notifyPreStudy,
    bool? notifyAlarmOnTime,
    bool? notifySessionStart,
    bool? notifyBreakStart,
    bool? notifyBreakEnd,
    int? dailyStudyLimitMinutes,
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
      alarmSoundId: alarmSoundId ?? this.alarmSoundId,
      breakSoundId: breakSoundId ?? this.breakSoundId,
      preReminderMinutes: preReminderMinutes ?? this.preReminderMinutes,
      breakPresetId: breakPresetId ?? this.breakPresetId,
      customStudyMinutes: customStudyMinutes ?? this.customStudyMinutes,
      customBreakMinutes: customBreakMinutes ?? this.customBreakMinutes,
      autoBreakReminder: autoBreakReminder ?? this.autoBreakReminder,
      notifyPreStudy: notifyPreStudy ?? this.notifyPreStudy,
      notifyAlarmOnTime: notifyAlarmOnTime ?? this.notifyAlarmOnTime,
      notifySessionStart: notifySessionStart ?? this.notifySessionStart,
      notifyBreakStart: notifyBreakStart ?? this.notifyBreakStart,
      notifyBreakEnd: notifyBreakEnd ?? this.notifyBreakEnd,
      dailyStudyLimitMinutes:
          dailyStudyLimitMinutes ?? this.dailyStudyLimitMinutes,
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
      'alarm_sound_id': alarmSoundId,
      'break_sound_id': breakSoundId,
      'pre_reminder_minutes': preReminderMinutes,
      'break_preset_id': breakPresetId,
      'custom_study_minutes': customStudyMinutes,
      'custom_break_minutes': customBreakMinutes,
      'auto_break_reminder': autoBreakReminder ? 1 : 0,
      'notify_pre_study': notifyPreStudy ? 1 : 0,
      'notify_alarm_on_time': notifyAlarmOnTime ? 1 : 0,
      'notify_session_start': notifySessionStart ? 1 : 0,
      'notify_break_start': notifyBreakStart ? 1 : 0,
      'notify_break_end': notifyBreakEnd ? 1 : 0,
      'daily_study_limit_minutes': dailyStudyLimitMinutes,
    };
  }

  static int _parseInt(dynamic raw, int fallback) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw != null) return int.tryParse(raw.toString()) ?? fallback;
    return fallback;
  }

  static bool _parseBool(dynamic raw, bool fallback) {
    if (raw == null) return fallback;
    if (raw is bool) return raw;
    if (raw is num) return raw.toInt() == 1;
    final text = raw.toString().toLowerCase().trim();
    if (text == '1' || text == 'true') return true;
    if (text == '0' || text == 'false') return false;
    return fallback;
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final rawAlarm = map['alarm_sound_id']?.toString();
    final rawBreak = map['break_sound_id']?.toString();
    final rawPreset = map['break_preset_id']?.toString();

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
      weeklyTargetTasks: _parseInt(map['weekly_target_tasks'], 5),
      themeMode: map['theme_mode']?.toString() ?? 'system',
      reminderEnabled: _parseBool(map['reminder_enabled'], false),
      alarmSoundId: (rawAlarm != null && validAlarmSoundIds.contains(rawAlarm))
          ? rawAlarm
          : defaultAlarmSoundId,
      breakSoundId: (rawBreak != null && validBreakSoundIds.contains(rawBreak))
          ? rawBreak
          : defaultBreakSoundId,
      preReminderMinutes: _parseInt(
        map['pre_reminder_minutes'],
        defaultPreReminderMinutes,
      ).clamp(0, 120),
      breakPresetId:
          (rawPreset != null && validBreakPresetIds.contains(rawPreset))
          ? rawPreset
          : defaultBreakPresetId,
      customStudyMinutes: _parseInt(
        map['custom_study_minutes'],
        defaultCustomStudyMinutes,
      ).clamp(1, 180),
      customBreakMinutes: _parseInt(
        map['custom_break_minutes'],
        defaultCustomBreakMinutes,
      ).clamp(1, 60),
      autoBreakReminder: _parseBool(map['auto_break_reminder'], true),
      notifyPreStudy: _parseBool(map['notify_pre_study'], true),
      notifyAlarmOnTime: _parseBool(map['notify_alarm_on_time'], true),
      notifySessionStart: _parseBool(map['notify_session_start'], true),
      notifyBreakStart: _parseBool(map['notify_break_start'], true),
      notifyBreakEnd: _parseBool(map['notify_break_end'], true),
      dailyStudyLimitMinutes: _parseInt(
        map['daily_study_limit_minutes'],
        defaultDailyStudyLimitMinutes,
      ).clamp(15, 1440),
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

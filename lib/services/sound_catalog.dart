import '../models/user_profile.dart';

/// Nhóm âm thanh hỗ trợ trong ExamPilot.
enum SoundGroup { alarm, breakReminder }

/// Mô tả một lựa chọn âm thanh được lưu trong `UserProfile`.
class SoundOption {
  final String id;
  final String label;
  final SoundGroup group;
  final String description;
  final String? assetPath;

  const SoundOption({
    required this.id,
    required this.label,
    required this.group,
    required this.description,
    this.assetPath,
  });

  bool get isSilent => id == 'none';
  bool get hasBundledAsset => assetPath != null && assetPath!.isNotEmpty;
}

/// Danh mục âm thanh hợp lệ khớp hoàn toàn với Schema v7 (`UserProfile`).
/// Theo xác nhận hiện tại (A1), khi chưa nhúng bộ 6 tệp audio tùy chỉnh riêng vào
/// `assets/audio/` và `res/raw/`, các lựa chọn có âm đều dùng âm thanh hệ thống mặc định
/// (trên Web phát âm mẫu Web Audio API) và hiển thị trung thực trên giao diện.
class SoundCatalog {
  const SoundCatalog._();

  static const List<SoundOption> alarmOptions = [
    SoundOption(
      id: 'alarm_dawn',
      label: 'Rạng đông',
      group: SoundGroup.alarm,
      description:
          'Hiện dùng âm báo thức mặc định của hệ thống (chưa có tệp riêng).',
    ),
    SoundOption(
      id: 'alarm_school_bell',
      label: 'Chuông trường học',
      group: SoundGroup.alarm,
      description:
          'Hiện dùng âm báo thức mặc định của hệ thống (chưa có tệp riêng).',
    ),
    SoundOption(
      id: 'alarm_energetic',
      label: 'Nhịp điệu sôi động',
      group: SoundGroup.alarm,
      description:
          'Hiện dùng âm báo thức mặc định của hệ thống (chưa có tệp riêng).',
    ),
    SoundOption(
      id: 'none',
      label: 'Im lặng',
      group: SoundGroup.alarm,
      description: 'Chỉ hiển thị thông báo/rung, không phát âm thanh báo thức.',
    ),
  ];

  static const List<SoundOption> breakOptions = [
    SoundOption(
      id: 'break_windchime',
      label: 'Tiếng chuông gió',
      group: SoundGroup.breakReminder,
      description:
          'Hiện dùng âm thông báo mặc định của hệ thống (chưa có tệp riêng).',
    ),
    SoundOption(
      id: 'break_waterdrop',
      label: 'Giọt nước',
      group: SoundGroup.breakReminder,
      description:
          'Hiện dùng âm thông báo mặc định của hệ thống (chưa có tệp riêng).',
    ),
    SoundOption(
      id: 'break_marimba',
      label: 'Thư giãn',
      group: SoundGroup.breakReminder,
      description:
          'Hiện dùng âm thông báo mặc định của hệ thống (chưa có tệp riêng).',
    ),
    SoundOption(
      id: 'none',
      label: 'Im lặng',
      group: SoundGroup.breakReminder,
      description:
          'Chỉ hiển thị thông báo trực quan khi bắt đầu/kết thúc nghỉ.',
    ),
  ];

  static bool get hasAnyCustomBundledAssets =>
      alarmOptions.any((o) => o.hasBundledAsset) ||
      breakOptions.any((o) => o.hasBundledAsset);

  static SoundOption alarmById(String soundId) {
    final normalized = UserProfile.validAlarmSoundIds.contains(soundId)
        ? soundId
        : UserProfile.defaultAlarmSoundId;
    return alarmOptions.firstWhere(
      (o) => o.id == normalized,
      orElse: () => alarmOptions.first,
    );
  }

  static SoundOption breakById(String soundId) {
    final normalized = UserProfile.validBreakSoundIds.contains(soundId)
        ? soundId
        : UserProfile.defaultBreakSoundId;
    return breakOptions.firstWhere(
      (o) => o.id == normalized,
      orElse: () => breakOptions.first,
    );
  }
}

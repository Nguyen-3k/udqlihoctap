import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'user_profile.dart';

/// Phân loại các sự kiện thông báo và báo thức trong ExamPilot Phase 4.
enum AppNotificationType {
  preStudy('pre_study'),
  alarmOnTime('alarm_on_time'),
  sessionStart('session_start'),
  sessionOngoing('session_ongoing'),
  sessionCompleted('session_completed'),
  breakStart('break_start'),
  breakEnd('break_end');

  final String wireValue;
  const AppNotificationType(this.wireValue);
}

/// Sinh ID thông báo và báo thức tất định (31-bit dương, ổn định giữa các lần chạy),
/// bảo đảm hủy lịch cũ chính xác và tuyệt đối tránh tạo bản ghi trùng lặp.
class NotificationIds {
  const NotificationIds._();

  static int stablePositiveInt(String seed) {
    var hash = 0x811c9dc5;
    for (final unit in seed.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    if (hash == 0) return 100001;
    return hash;
  }

  static int preStudyForSlot(String slotId) =>
      stablePositiveInt('pre_study:$slotId');

  static int alarmForSlot(String slotId) => stablePositiveInt('alarm:$slotId');

  static int sessionStart(String sessionId) =>
      stablePositiveInt('session_start:$sessionId');

  static int sessionOngoing(String sessionId) => sessionStart(sessionId);

  static int sessionCompleted(String sessionId) =>
      stablePositiveInt('session_completed:$sessionId');

  static int breakStart(String sessionId, int breakIndex) =>
      stablePositiveInt('break_start:$sessionId:$breakIndex');

  static int breakEnd(String sessionId, int breakIndex) =>
      stablePositiveInt('break_end:$sessionId:$breakIndex');
}

/// Định nghĩa metadata cho một Android Notification Channel cố định.
class NotificationChannelSpec {
  final String id;
  final String name;
  final String description;
  final Importance importance;
  final bool playSound;
  final bool enableVibration;
  final AudioAttributesUsage audioAttributesUsage;

  const NotificationChannelSpec({
    required this.id,
    required this.name,
    required this.description,
    required this.importance,
    this.playSound = true,
    this.enableVibration = true,
    this.audioAttributesUsage = AudioAttributesUsage.notification,
  });

  AndroidNotificationChannel toAndroidChannel() {
    return AndroidNotificationChannel(
      id,
      name,
      description: description,
      importance: importance,
      playSound: playSound,
      enableVibration: enableVibration,
      audioAttributesUsage: audioAttributesUsage,
    );
  }
}

/// Bộ Notification Channel hữu hạn cố định (khớp kiến trúc G8.8.2 mục 8.2):
/// - Không tạo channel ngẫu nhiên.
/// - Không xóa channel cũ khi người dùng đổi tùy chọn âm thanh để tránh mất thông báo chờ
///   và bảo toàn thiết lập DND/rung của người dùng trên Android.
class NotificationChannelRegistry {
  const NotificationChannelRegistry._();

  static const String preStudyChannelId = 'exampilot_pre_study_v1';
  static const String sessionStartChannelId = 'exampilot_session_status_v1';
  static const String sessionCompletionChannelId =
      'exampilot_session_completion_v1';

  static const NotificationChannelSpec preStudyChannel =
      NotificationChannelSpec(
        id: preStudyChannelId,
        name: 'Nhắc trước giờ học',
        description:
            'Thông báo nhắc nhở trước thời điểm bắt đầu buổi học theo lịch.',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

  static const NotificationChannelSpec
  sessionStartChannel = NotificationChannelSpec(
    id: sessionStartChannelId,
    name: 'Phiên học đang chạy',
    description:
        'Thông báo trạng thái phiên học và thời gian học thực tế trên Study Timer.',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
  );

  static const NotificationChannelSpec sessionCompletionChannel =
      NotificationChannelSpec(
        id: sessionCompletionChannelId,
        name: 'Hoàn thành phiên học',
        description:
            'Thông báo chúc mừng khi hoàn thành phiên học trên Study Timer.',
        importance: Importance.defaultImportance,
        playSound: true,
        enableVibration: true,
      );

  static final List<NotificationChannelSpec> fixedAlarmChannels = [
    for (final soundId in UserProfile.validAlarmSoundIds)
      NotificationChannelSpec(
        id: alarmChannelIdFor(soundId),
        name: soundId == 'none'
            ? 'Báo thức học tập (Im lặng)'
            : 'Báo thức học tập (${_alarmChannelLabel(soundId)})',
        description: 'Kênh thông báo báo thức khi đến giờ học.',
        importance: Importance.max,
        playSound: soundId != 'none',
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
  ];

  static final List<NotificationChannelSpec> fixedBreakChannels = [
    for (final soundId in UserProfile.validBreakSoundIds)
      NotificationChannelSpec(
        id: breakChannelIdFor(soundId),
        name: soundId == 'none'
            ? 'Nhắc nghỉ giải lao (Im lặng)'
            : 'Nhắc nghỉ giải lao (${_breakChannelLabel(soundId)})',
        description: 'Thông báo bắt đầu và hết thời gian nghỉ giải lao.',
        importance: Importance.high,
        playSound: soundId != 'none',
        enableVibration: true,
        audioAttributesUsage: AudioAttributesUsage.notification,
      ),
  ];

  static List<NotificationChannelSpec> get allFixedChannels => [
    preStudyChannel,
    sessionStartChannel,
    sessionCompletionChannel,
    ...fixedAlarmChannels,
    ...fixedBreakChannels,
  ];

  static String alarmChannelIdFor(String soundId) {
    final normalized = UserProfile.validAlarmSoundIds.contains(soundId)
        ? soundId
        : UserProfile.defaultAlarmSoundId;
    return 'exampilot_${normalized}_v1';
  }

  static String breakChannelIdFor(String soundId) {
    final normalized = UserProfile.validBreakSoundIds.contains(soundId)
        ? soundId
        : UserProfile.defaultBreakSoundId;
    return 'exampilot_${normalized}_v1';
  }

  static NotificationChannelSpec resolveFor(
    AppNotificationType type,
    UserProfile profile,
  ) {
    switch (type) {
      case AppNotificationType.preStudy:
        return preStudyChannel;
      case AppNotificationType.sessionStart:
      case AppNotificationType.sessionOngoing:
        return sessionStartChannel;
      case AppNotificationType.sessionCompleted:
        return sessionCompletionChannel;
      case AppNotificationType.alarmOnTime:
        final targetId = alarmChannelIdFor(profile.alarmSoundId);
        return fixedAlarmChannels.firstWhere(
          (c) => c.id == targetId,
          orElse: () => fixedAlarmChannels.first,
        );
      case AppNotificationType.breakStart:
      case AppNotificationType.breakEnd:
        final targetId = breakChannelIdFor(profile.breakSoundId);
        return fixedBreakChannels.firstWhere(
          (c) => c.id == targetId,
          orElse: () => fixedBreakChannels.first,
        );
    }
  }

  static String _alarmChannelLabel(String soundId) {
    switch (soundId) {
      case 'alarm_dawn':
        return 'Rạng đông';
      case 'alarm_school_bell':
        return 'Chuông trường học';
      case 'alarm_energetic':
        return 'Nhịp điệu sôi động';
      default:
        return 'Mặc định';
    }
  }

  static String _breakChannelLabel(String soundId) {
    switch (soundId) {
      case 'break_windchime':
        return 'Tiếng chuông gió';
      case 'break_waterdrop':
        return 'Giọt nước';
      case 'break_marimba':
        return 'Thư giãn';
      default:
        return 'Mặc định';
    }
  }
}

import 'package:flutter/foundation.dart';

/// Các trạng thái chuẩn của Alarm State Machine (G8.8.1 – D2):
/// Scheduled -> Ringing -> (Snoozed -> Ringing) | Dismissed | Started | Cancelled.
/// Không cho phép tự ý thêm trạng thái ngoài đặc tả.
enum AlarmStatus {
  scheduled('scheduled'),
  ringing('ringing'),
  snoozed('snoozed'),
  dismissed('dismissed'),
  started('started'),
  cancelled('cancelled');

  final String wireValue;
  const AlarmStatus(this.wireValue);

  static AlarmStatus fromWire(String? raw) {
    switch (raw?.trim()) {
      case 'scheduled':
        return AlarmStatus.scheduled;
      case 'ringing':
        return AlarmStatus.ringing;
      case 'snoozed':
        return AlarmStatus.snoozed;
      case 'dismissed':
        return AlarmStatus.dismissed;
      case 'started':
        return AlarmStatus.started;
      case 'cancelled':
        return AlarmStatus.cancelled;
      default:
        return AlarmStatus.cancelled;
    }
  }
}

/// Dữ liệu đầu vào chuẩn hóa cho một buổi học dự kiến có giờ bắt đầu hợp lệ.
/// Đây là hợp đồng giao tiếp cho Smart Timetable (G9.0); KHÔNG được dùng Task.deadline
/// hay StudyTimer plannedMinutes để tạo đối tượng này.
@immutable
class ScheduledStudySlot {
  final String id;
  final String? subjectId;
  final String subjectName;
  final String? taskId;
  final String? taskTitle;
  final DateTime startAtUtc;
  final bool isCancelled;
  final bool isCompleted;

  ScheduledStudySlot({
    required this.id,
    this.subjectId,
    required this.subjectName,
    this.taskId,
    this.taskTitle,
    required DateTime startAtUtc,
    this.isCancelled = false,
    this.isCompleted = false,
  }) : startAtUtc = startAtUtc.toUtc();

  bool get isSchedulable => !isCancelled && !isCompleted;
}

/// Bản ghi bền vững của một báo thức gắn với Alarm State Machine.
@immutable
class AlarmRecord {
  static const int maxSnoozeCount = 1;
  static const Duration defaultSnoozeDuration = Duration(minutes: 5);

  final String alarmKey;
  final int alarmId;
  final String? scheduledSessionId;
  final String? subjectId;
  final String title;
  final String? taskTitle;
  final String soundId;
  final AlarmStatus status;
  final int snoozeCount;
  final DateTime scheduledAtUtc;
  final DateTime? snoozedUntilUtc;
  final DateTime updatedAtUtc;
  final DateTime? acknowledgedAtUtc;

  AlarmRecord({
    required this.alarmKey,
    required this.alarmId,
    this.scheduledSessionId,
    this.subjectId,
    required this.title,
    this.taskTitle,
    required this.soundId,
    required this.status,
    this.snoozeCount = 0,
    required DateTime scheduledAtUtc,
    DateTime? snoozedUntilUtc,
    required DateTime updatedAtUtc,
    DateTime? acknowledgedAtUtc,
  }) : scheduledAtUtc = scheduledAtUtc.toUtc(),
       snoozedUntilUtc = snoozedUntilUtc?.toUtc(),
       updatedAtUtc = updatedAtUtc.toUtc(),
       acknowledgedAtUtc = acknowledgedAtUtc?.toUtc();

  bool get isPendingTrigger =>
      status == AlarmStatus.scheduled || status == AlarmStatus.snoozed;

  bool get isRinging => status == AlarmStatus.ringing;

  bool get isTerminal =>
      status == AlarmStatus.dismissed ||
      status == AlarmStatus.started ||
      status == AlarmStatus.cancelled;

  bool get canSnooze =>
      status == AlarmStatus.ringing && snoozeCount < maxSnoozeCount;

  DateTime get effectiveTriggerAtUtc =>
      (status == AlarmStatus.snoozed && snoozedUntilUtc != null)
      ? snoozedUntilUtc!
      : scheduledAtUtc;

  AlarmRecord copyWith({
    String? alarmKey,
    int? alarmId,
    String? scheduledSessionId,
    String? subjectId,
    String? title,
    String? taskTitle,
    String? soundId,
    AlarmStatus? status,
    int? snoozeCount,
    DateTime? scheduledAtUtc,
    DateTime? snoozedUntilUtc,
    bool clearSnoozedUntil = false,
    DateTime? updatedAtUtc,
    DateTime? acknowledgedAtUtc,
  }) {
    return AlarmRecord(
      alarmKey: alarmKey ?? this.alarmKey,
      alarmId: alarmId ?? this.alarmId,
      scheduledSessionId: scheduledSessionId ?? this.scheduledSessionId,
      subjectId: subjectId ?? this.subjectId,
      title: title ?? this.title,
      taskTitle: taskTitle ?? this.taskTitle,
      soundId: soundId ?? this.soundId,
      status: status ?? this.status,
      snoozeCount: snoozeCount ?? this.snoozeCount,
      scheduledAtUtc: scheduledAtUtc ?? this.scheduledAtUtc,
      snoozedUntilUtc: clearSnoozedUntil
          ? null
          : (snoozedUntilUtc ?? this.snoozedUntilUtc),
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      acknowledgedAtUtc: acknowledgedAtUtc ?? this.acknowledgedAtUtc,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'alarmKey': alarmKey,
      'alarmId': alarmId,
      'scheduledSessionId': scheduledSessionId,
      'subjectId': subjectId,
      'title': title,
      'taskTitle': taskTitle,
      'soundId': soundId,
      'status': status.wireValue,
      'snoozeCount': snoozeCount,
      'scheduledAtUtc': scheduledAtUtc.toUtc().toIso8601String(),
      'snoozedUntilUtc': snoozedUntilUtc?.toUtc().toIso8601String(),
      'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
      'acknowledgedAtUtc': acknowledgedAtUtc?.toUtc().toIso8601String(),
    };
  }

  Map<String, dynamic> toNativeMap() {
    return {
      'alarmKey': alarmKey,
      'alarmId': alarmId,
      'title': title,
      'taskTitle': taskTitle,
      'soundId': soundId,
      'status': status.wireValue,
      'snoozeCount': snoozeCount,
      'scheduledAtMillis': scheduledAtUtc.millisecondsSinceEpoch,
      'snoozedUntilMillis': snoozedUntilUtc?.millisecondsSinceEpoch,
      'updatedAtMillis': updatedAtUtc.millisecondsSinceEpoch,
      'acknowledgedAtMillis': acknowledgedAtUtc?.millisecondsSinceEpoch,
    };
  }

  factory AlarmRecord.fromMap(Map<String, dynamic> map) {
    final scheduledRaw = map['scheduledAtUtc']?.toString();
    final snoozedRaw = map['snoozedUntilUtc']?.toString();
    final updatedRaw = map['updatedAtUtc']?.toString();
    final ackRaw = map['acknowledgedAtUtc']?.toString();

    return AlarmRecord(
      alarmKey: map['alarmKey']?.toString() ?? '',
      alarmId: (map['alarmId'] as num?)?.toInt() ?? 100001,
      scheduledSessionId: map['scheduledSessionId']?.toString(),
      subjectId: map['subjectId']?.toString(),
      title: map['title']?.toString() ?? 'Đến giờ học tập',
      taskTitle: map['taskTitle']?.toString(),
      soundId: map['soundId']?.toString() ?? 'alarm_dawn',
      status: AlarmStatus.fromWire(map['status']?.toString()),
      snoozeCount: (map['snoozeCount'] as num?)?.toInt() ?? 0,
      scheduledAtUtc: scheduledRaw != null
          ? (DateTime.tryParse(scheduledRaw)?.toUtc() ??
                DateTime.fromMillisecondsSinceEpoch(0, isUtc: true))
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      snoozedUntilUtc: snoozedRaw != null
          ? DateTime.tryParse(snoozedRaw)?.toUtc()
          : null,
      updatedAtUtc: updatedRaw != null
          ? (DateTime.tryParse(updatedRaw)?.toUtc() ?? DateTime.now().toUtc())
          : DateTime.now().toUtc(),
      acknowledgedAtUtc: ackRaw != null
          ? DateTime.tryParse(ackRaw)?.toUtc()
          : null,
    );
  }

  factory AlarmRecord.fromNativeMap(
    Map<dynamic, dynamic> map, {
    AlarmRecord? fallback,
  }) {
    final scheduledMillis = (map['scheduledAtMillis'] as num?)?.toInt();
    final snoozedMillis = (map['snoozedUntilMillis'] as num?)?.toInt();
    final updatedMillis = (map['updatedAtMillis'] as num?)?.toInt();
    final ackMillis = (map['acknowledgedAtMillis'] as num?)?.toInt();

    return AlarmRecord(
      alarmKey: map['alarmKey']?.toString() ?? fallback?.alarmKey ?? '',
      alarmId: (map['alarmId'] as num?)?.toInt() ?? fallback?.alarmId ?? 100001,
      scheduledSessionId: fallback?.scheduledSessionId,
      subjectId: fallback?.subjectId,
      title: map['title']?.toString() ?? fallback?.title ?? 'Đến giờ học tập',
      taskTitle: map['taskTitle']?.toString() ?? fallback?.taskTitle,
      soundId: map['soundId']?.toString() ?? fallback?.soundId ?? 'alarm_dawn',
      status: AlarmStatus.fromWire(map['status']?.toString()),
      snoozeCount:
          (map['snoozeCount'] as num?)?.toInt() ?? fallback?.snoozeCount ?? 0,
      scheduledAtUtc: scheduledMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(scheduledMillis, isUtc: true)
          : (fallback?.scheduledAtUtc ?? DateTime.now().toUtc()),
      snoozedUntilUtc: snoozedMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(snoozedMillis, isUtc: true)
          : null,
      updatedAtUtc: updatedMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(updatedMillis, isUtc: true)
          : DateTime.now().toUtc(),
      acknowledgedAtUtc: ackMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(ackMillis, isUtc: true)
          : fallback?.acknowledgedAtUtc,
    );
  }
}

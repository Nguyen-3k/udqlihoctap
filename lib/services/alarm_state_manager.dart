import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/alarm_state.dart';
import '../models/notification_type.dart';
import '../models/study_task.dart';
import 'alarm_service.dart';
import 'alarm_store.dart';
import 'audio_playback_gateway.dart';
import 'study_timer_engine.dart';

/// Quản lý tập trung Alarm State Machine theo kiến trúc G8.8.1 (Quyết định D2):
/// - `Scheduled -> Ringing -> Snoozed -> Ringing | Dismissed | Started | Cancelled`
/// - Tuyệt đối KHÔNG tự động timeout tắt báo thức khi đang `Ringing`.
/// - Giới hạn tối đa 1 lần Snooze (+5 phút) trên mỗi báo thức gốc.
/// - Chống trùng ID và lưu bền vững qua tiến trình bị hủy / khởi động lại.
class AlarmStateManager extends ChangeNotifier {
  final AlarmStore store;
  final AlarmPlatformBridge platformBridge;
  final AudioPlaybackGateway audioGateway;
  final TimerClock clock;

  final Map<String, AlarmRecord> _alarms = {};
  final ValueChanged<AlarmRecord>? onStartStudyRequested;
  bool _initialized = false;
  bool _disposed = false;

  AlarmStateManager({
    required this.store,
    required this.platformBridge,
    required this.audioGateway,
    TimerClock? clock,
    this.onStartStudyRequested,
  }) : clock = clock ?? SystemTimerClock() {
    platformBridge.attachListeners(
      onNativeAlarmUpdated: _handleNativeAlarmUpdated,
      onNativeLaunchStartRequested: (alarmKey) {
        if (alarmKey != null && _alarms.containsKey(alarmKey)) {
          onStartStudyRequested?.call(_alarms[alarmKey]!);
        }
      },
    );
  }

  List<AlarmRecord> get allAlarms => List.unmodifiable(_alarms.values);

  List<AlarmRecord> get pendingAlarms =>
      List.unmodifiable(_alarms.values.where((a) => a.isPendingTrigger));

  AlarmRecord? get activeRingingAlarm {
    for (final alarm in _alarms.values) {
      if (alarm.isRinging) return alarm;
    }
    return null;
  }

  AlarmRecord? getByKey(String alarmKey) => _alarms[alarmKey];

  bool get hasRingingAlarm => activeRingingAlarm != null;

  static String buildSlotAlarmKey(String slotId) => 'slot:$slotId';
  static String buildTaskAlarmKey(String taskId) => 'task_deadline:$taskId';

  /// Khởi tạo và phục hồi trạng thái báo thức đã lưu khi mở ứng dụng.
  Future<void> restoreOnAppStart() async {
    if (_disposed) return;
    final stored = await store.loadAll();
    _alarms
      ..clear()
      ..addEntries(stored.map((r) => MapEntry(r.alarmKey, r)));

    // Đồng bộ trạng thái mới hơn từ tầng Android native (nếu service hoặc notification action
    // đã đổi trạng thái trong lúc Flutter chưa chạy).
    final nativeRecords = await platformBridge.getStoredNativeAlarms();
    for (final native in nativeRecords) {
      final local = _alarms[native.alarmKey];
      if (local == null || !native.updatedAtUtc.isBefore(local.updatedAtUtc)) {
        _alarms[native.alarmKey] = AlarmRecord.fromNativeMap(
          native.toNativeMap(),
          fallback: local,
        );
      }
    }

    await store.saveAll(_alarms.values.toList());

    // Đảm bảo nếu có báo thức đang Ringing trên native/sau reboot nhưng audio web/app đang tắt,
    // UI + âm thanh giữ đúng trạng thái chưa xác nhận, tuyệt đối không tự Dismiss!
    final ringing = activeRingingAlarm;
    if (ringing != null && !platformBridge.supportsBackgroundAlarm) {
      await audioGateway.startAlarmLoop(ringing.soundId);
    }

    final pendingLaunch = await platformBridge.consumePendingLaunchAction();
    if (pendingLaunch != null && pendingLaunch.action == 'start') {
      final target = pendingLaunch.alarmKey != null
          ? _alarms[pendingLaunch.alarmKey]
          : null;
      if (target != null) {
        onStartStudyRequested?.call(target);
      }
    }

    _initialized = true;
    _notifySafely();
  }

  /// Lên lịch hoặc cập nhật một báo thức học tập từ nguồn lịch thật (trả về true nếu dùng Exact Alarm).
  Future<bool> scheduleForSlot({
    required ScheduledStudySlot slot,
    required String soundId,
  }) async {
    if (!_initialized) {
      await restoreOnAppStart();
    }
    final nowUtc = clock.nowUtc();
    if (!slot.isSchedulable || !slot.startAtUtc.isAfter(nowUtc)) {
      return false;
    }

    final key = buildSlotAlarmKey(slot.id);
    final existing = _alarms[key];
    // Nếu đang có báo thức cũ trùng slot hoặc chưa kết thúc, hủy lịch OS cũ trước để chống trùng.
    if (existing != null && existing.isPendingTrigger) {
      await platformBridge.cancelAlarm(existing);
    }

    final alarmId = existing?.alarmId ?? NotificationIds.alarmForSlot(slot.id);
    final record = AlarmRecord(
      alarmKey: key,
      alarmId: alarmId,
      scheduledSessionId: slot.id,
      subjectId: slot.subjectId,
      title: slot.subjectName,
      taskTitle: slot.taskTitle,
      soundId: soundId,
      status: AlarmStatus.scheduled,
      snoozeCount: 0,
      scheduledAtUtc: slot.startAtUtc,
      updatedAtUtc: nowUtc,
    );

    _alarms[key] = record;
    await store.saveAll(_alarms.values.toList());
    debugPrint(
      '[ExamPilotAlarm] 1b. Flutter: AlarmStateManager.scheduleForSlot record=$key, alarmId=$alarmId, triggerAt=${record.effectiveTriggerAtUtc}',
    );
    final exact = await platformBridge.scheduleAlarm(record);
    debugPrint(
      '[ExamPilotAlarm] 1d. Flutter: AlarmStateManager.scheduleForSlot bridge returned exact=$exact',
    );
    _notifySafely();
    return exact;
  }

  /// Lên lịch báo thức cho hạn chót (deadline) của một StudyTask (Phase 4.3).
  Future<bool> scheduleForTaskDeadline({
    required StudyTask task,
    required String soundId,
  }) async {
    if (!_initialized) {
      await restoreOnAppStart();
    }
    final nowUtc = clock.nowUtc();
    final deadline = task.deadline;
    if (deadline == null || task.isCompleted || !task.reminderEnabled) {
      return false;
    }

    final triggerAtUtc = deadline
        .toUtc()
        .subtract(Duration(minutes: task.reminderMinutes));
    if (!triggerAtUtc.isAfter(nowUtc)) {
      return false;
    }

    final key = buildTaskAlarmKey(task.id);
    final existing = _alarms[key];
    if (existing != null && existing.isPendingTrigger) {
      await platformBridge.cancelAlarm(existing);
    }

    final alarmId =
        existing?.alarmId ?? NotificationIds.alarmForTaskDeadline(task.id);
    final reminderSuffix = task.reminderMinutes > 0
        ? 'Còn ${task.reminderMinutes} phút tới hạn hoàn thành: ${task.title}'
        : 'Đến hạn hoàn thành công việc: ${task.title}';

    final record = AlarmRecord(
      alarmKey: key,
      alarmId: alarmId,
      scheduledSessionId: null,
      subjectId: task.subjectId,
      title: 'Hạn chót: ${task.title}',
      taskTitle: '${task.subject} • $reminderSuffix',
      soundId: soundId,
      status: AlarmStatus.scheduled,
      snoozeCount: 0,
      scheduledAtUtc: triggerAtUtc,
      updatedAtUtc: nowUtc,
    );

    _alarms[key] = record;
    await store.saveAll(_alarms.values.toList());
    debugPrint(
      '[ExamPilotAlarm] 1b-task. Flutter: AlarmStateManager.scheduleForTaskDeadline record=$key, triggerAt=${record.effectiveTriggerAtUtc}',
    );
    final exact = await platformBridge.scheduleAlarm(record);
    _notifySafely();
    return exact;
  }

  /// Hủy báo thức hạn chót của một công việc (khi hoàn thành, xóa hoặc đổi hạn)
  Future<void> cancelTaskDeadlineAlarm(String taskId) async {
    final key = buildTaskAlarmKey(taskId);
    await cancelAlarm(key);
  }

  /// Kích hoạt báo thức chuyển sang trạng thái `Ringing` (từ Scheduled hoặc Snoozed).
  /// Không có timeout tự động tắt theo Quyết định D2.
  Future<AlarmRecord?> triggerAlarmRinging(String alarmKey) async {
    final existing = _alarms[alarmKey];
    if (existing == null) return null;
    if (existing.isTerminal) {
      throw StateError(
        'Không thể reo báo thức đã kết thúc (${existing.status.wireValue}).',
      );
    }
    if (existing.status == AlarmStatus.ringing) {
      return existing;
    }

    final ringing = existing.copyWith(
      status: AlarmStatus.ringing,
      updatedAtUtc: clock.nowUtc(),
    );
    _alarms[alarmKey] = ringing;
    await store.saveAll(_alarms.values.toList());
    await platformBridge.syncAlarmRecord(ringing);

    if (platformBridge.supportsBackgroundAlarm) {
      await platformBridge.startRingingForeground(ringing);
    } else {
      await audioGateway.startAlarmLoop(ringing.soundId);
    }

    _notifySafely();
    return ringing;
  }

  /// Nhắc lại báo thức (Snooze 5 phút). Chỉ cho phép đúng 1 lần khi đang Ringing và `snoozeCount == 0`.
  Future<AlarmRecord> snoozeAlarm(
    String alarmKey, {
    Duration duration = AlarmRecord.defaultSnoozeDuration,
  }) async {
    final existing = _alarms[alarmKey];
    if (existing == null) {
      throw StateError('Không tìm thấy báo thức: $alarmKey');
    }
    if (existing.status != AlarmStatus.ringing) {
      throw StateError('Chỉ có thể Nhắc lại khi báo thức đang reo.');
    }
    if (!existing.canSnooze) {
      throw StateError('Báo thức này đã sử dụng hết 1 lần Nhắc lại.');
    }

    final nowUtc = clock.nowUtc();
    final snoozedUntil = nowUtc.add(duration);
    final updated = existing.copyWith(
      status: AlarmStatus.snoozed,
      snoozeCount: existing.snoozeCount + 1,
      snoozedUntilUtc: snoozedUntil,
      updatedAtUtc: nowUtc,
    );

    await _stopActiveAudioAndService();
    _alarms[alarmKey] = updated;
    await store.saveAll(_alarms.values.toList());
    // Đảm bảo chỉ tồn tại 1 lịch Snooze mới gắn đúng alarmId ban đầu (chống trùng).
    await platformBridge.scheduleAlarm(updated);
    _notifySafely();
    return updated;
  }

  /// Tắt báo thức tường minh (`Dismissed`) — dừng toàn bộ âm thanh và dịch vụ liên quan.
  Future<AlarmRecord> dismissAlarm(String alarmKey) async {
    final existing = _alarms[alarmKey];
    if (existing == null) {
      throw StateError('Không tìm thấy báo thức: $alarmKey');
    }
    final nowUtc = clock.nowUtc();
    final updated = existing.copyWith(
      status: AlarmStatus.dismissed,
      acknowledgedAtUtc: nowUtc,
      updatedAtUtc: nowUtc,
      clearSnoozedUntil: true,
    );

    await _stopActiveAudioAndService();
    await platformBridge.cancelAlarm(updated);
    _alarms[alarmKey] = updated;
    await store.saveAll(_alarms.values.toList());
    await platformBridge.syncAlarmRecord(updated);
    _notifySafely();
    return updated;
  }

  /// Người dùng bấm [Vào học ngay] từ báo thức (`Started`): dừng chuông và phát callback điều hướng,
  /// không tự ý đếm giờ thay StudyTimerEngine nếu người dùng chưa bấm bắt đầu phiên.
  Future<AlarmRecord> startFromAlarm(String alarmKey) async {
    final existing = _alarms[alarmKey];
    if (existing == null) {
      throw StateError('Không tìm thấy báo thức: $alarmKey');
    }
    if (existing.status != AlarmStatus.ringing &&
        existing.status != AlarmStatus.snoozed &&
        existing.status != AlarmStatus.scheduled) {
      throw StateError('Báo thức đã ở trạng thái kết thúc.');
    }

    final nowUtc = clock.nowUtc();
    final updated = existing.copyWith(
      status: AlarmStatus.started,
      acknowledgedAtUtc: nowUtc,
      updatedAtUtc: nowUtc,
      clearSnoozedUntil: true,
    );

    await _stopActiveAudioAndService();
    await platformBridge.cancelAlarm(updated);
    _alarms[alarmKey] = updated;
    await store.saveAll(_alarms.values.toList());
    await platformBridge.syncAlarmRecord(updated);
    _notifySafely();
    onStartStudyRequested?.call(updated);
    return updated;
  }

  /// Hủy một báo thức đang chờ (`Cancelled`) khi lịch thay đổi hoặc bị xóa.
  Future<void> cancelAlarm(String alarmKey) async {
    final existing = _alarms[alarmKey];
    if (existing == null || existing.isTerminal) return;

    final wasRinging = existing.isRinging;
    final updated = existing.copyWith(
      status: AlarmStatus.cancelled,
      updatedAtUtc: clock.nowUtc(),
      clearSnoozedUntil: true,
    );

    if (wasRinging) {
      await _stopActiveAudioAndService();
    }
    await platformBridge.cancelAlarm(updated);
    _alarms[alarmKey] = updated;
    await store.saveAll(_alarms.values.toList());
    await platformBridge.syncAlarmRecord(updated);
    _notifySafely();
  }

  /// Hủy toàn bộ báo thức đang chờ/đang reo (khi tắt công tắc thông báo tổng hoặc Reset/Restore).
  Future<void> cancelAllActiveAlarms() async {
    final nowUtc = clock.nowUtc();
    var changed = false;
    for (final entry in _alarms.entries.toList()) {
      final current = entry.value;
      if (!current.isTerminal) {
        _alarms[entry.key] = current.copyWith(
          status: AlarmStatus.cancelled,
          updatedAtUtc: nowUtc,
          clearSnoozedUntil: true,
        );
        changed = true;
      }
    }
    await _stopActiveAudioAndService();
    await platformBridge.cancelAllAlarms();
    if (changed) {
      await store.saveAll(_alarms.values.toList());
      _notifySafely();
    }
  }

  void _handleNativeAlarmUpdated(AlarmRecord updatedNative) {
    final merged = AlarmRecord.fromNativeMap(
      updatedNative.toNativeMap(),
      fallback: _alarms[updatedNative.alarmKey],
    );
    _alarms[merged.alarmKey] = merged;
    unawaited(store.saveAll(_alarms.values.toList()));
    if (!merged.isRinging && !platformBridge.supportsBackgroundAlarm) {
      unawaited(audioGateway.stopAlarmLoop());
    } else if (merged.isRinging && !platformBridge.supportsBackgroundAlarm) {
      unawaited(audioGateway.startAlarmLoop(merged.soundId));
    }
    _notifySafely();
  }

  Future<void> _stopActiveAudioAndService() async {
    await audioGateway.stopAlarmLoop();
    await platformBridge.stopRingingForeground();
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    platformBridge.dispose();
    super.dispose();
  }
}

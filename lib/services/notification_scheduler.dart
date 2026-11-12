import '../models/alarm_state.dart';
import '../models/notification_type.dart';
import '../models/user_profile.dart';
import 'alarm_state_manager.dart';
import 'notification_permission_service.dart';
import 'notification_service.dart';
import 'study_timer_engine.dart';

/// Báo cáo kết quả một chu kỳ đồng bộ lập lịch thông báo & báo thức.
class ScheduleSyncReport {
  final int preStudyScheduledCount;
  final int alarmsScheduledCount;
  final int cancelledCount;
  final bool allUsedExactAlarms;
  final bool hasValidScheduleSource;

  const ScheduleSyncReport({
    this.preStudyScheduledCount = 0,
    this.alarmsScheduledCount = 0,
    this.cancelledCount = 0,
    this.allUsedExactAlarms = false,
    this.hasValidScheduleSource = false,
  });
}

/// Điều phối lên lịch, cập nhật lại và hủy thông báo nhắc trước / báo thức đúng giờ
/// theo đúng hợp đồng dữ liệu `ScheduledStudySlot`.
///
/// Tuyệt đối KHÔNG dùng `StudyTask.deadline` hay `plannedStudyMinutes` của Timer
/// làm thời điểm lập lịch và KHÔNG tự tạo lịch học giả.
class NotificationScheduler {
  final NotificationService notificationService;
  final AlarmStateManager alarmStateManager;
  final TimerClock clock;

  final Set<String> _scheduledPreStudySlotIds = {};

  NotificationScheduler({
    required this.notificationService,
    required this.alarmStateManager,
    TimerClock? clock,
  }) : clock = clock ?? SystemTimerClock();

  Set<String> get trackedPreStudySlotIds =>
      Set.unmodifiable(_scheduledPreStudySlotIds);

  /// Đồng bộ toàn bộ thông báo nhắc trước và báo thức cho danh sách buổi học hợp lệ.
  Future<ScheduleSyncReport> syncScheduledSlots({
    required List<ScheduledStudySlot> slots,
    required UserProfile profile,
    required NotificationPermissionStatus permissionStatus,
  }) async {
    if (!profile.reminderEnabled) {
      final cancelled = await cancelAllScheduledRemindersAndAlarms();
      return ScheduleSyncReport(
        cancelledCount: cancelled,
        hasValidScheduleSource: slots.isNotEmpty,
      );
    }

    final nowUtc = clock.nowUtc();
    final validSlots = slots
        .where((s) => s.isSchedulable && s.startAtUtc.isAfter(nowUtc))
        .toList();

    // Khử trùng theo slot.id (giữ bản mới nhất nếu danh sách truyền vào bị trùng)
    final uniqueSlots = <String, ScheduledStudySlot>{};
    for (final slot in validSlots) {
      uniqueSlots[slot.id] = slot;
    }

    int cancelledCount = 0;

    // 1. Hủy các thông báo nhắc trước không còn nằm trong danh sách hợp lệ hoặc đã tắt công tắc
    for (final oldSlotId in _scheduledPreStudySlotIds.toList()) {
      final keepSlot =
          profile.notifyPreStudy &&
          profile.preReminderMinutes > 0 &&
          uniqueSlots.containsKey(oldSlotId);
      if (!keepSlot) {
        await notificationService.cancel(
          NotificationIds.preStudyForSlot(oldSlotId),
        );
        _scheduledPreStudySlotIds.remove(oldSlotId);
        cancelledCount++;
      }
    }

    // 2. Hủy các báo thức pending không còn trong danh sách hợp lệ hoặc khi tắt notifyAlarmOnTime
    for (final alarm in alarmStateManager.pendingAlarms.toList()) {
      final slotId = alarm.scheduledSessionId;
      final keepAlarm =
          profile.notifyAlarmOnTime &&
          slotId != null &&
          uniqueSlots.containsKey(slotId);
      if (!keepAlarm) {
        await alarmStateManager.cancelAlarm(alarm.alarmKey);
        cancelledCount++;
      }
    }

    int preStudyCount = 0;
    int alarmCount = 0;
    bool allExact = true;

    for (final slot in uniqueSlots.values) {
      // A. Nhắc trước giờ học
      if (profile.notifyPreStudy && profile.preReminderMinutes > 0) {
        final preAtUtc = slot.startAtUtc.subtract(
          Duration(minutes: profile.preReminderMinutes),
        );
        final notifId = NotificationIds.preStudyForSlot(slot.id);
        await notificationService.cancel(notifId);

        if (preAtUtc.isAfter(nowUtc)) {
          final body = slot.taskTitle != null && slot.taskTitle!.isNotEmpty
              ? 'Còn ${profile.preReminderMinutes} phút tới giờ học ${slot.subjectName}: ${slot.taskTitle}'
              : 'Còn ${profile.preReminderMinutes} phút tới giờ học ${slot.subjectName}';
          final res = await notificationService.scheduleAt(
            id: notifId,
            scheduledAtUtc: preAtUtc,
            type: AppNotificationType.preStudy,
            profile: profile,
            title: 'Sắp đến giờ học ${slot.subjectName}',
            body: body,
            payload: 'pre_study:${slot.id}',
            allowExact: permissionStatus.exactAlarmsGranted,
          );
          if (res.succeeded) {
            _scheduledPreStudySlotIds.add(slot.id);
            preStudyCount++;
          }
        } else {
          _scheduledPreStudySlotIds.remove(slot.id);
        }
      }

      // B. Báo thức đúng giờ
      if (profile.notifyAlarmOnTime) {
        final existingAlarm = alarmStateManager.getByKey(
          AlarmStateManager.buildSlotAlarmKey(slot.id),
        );
        // Không ghi đè nếu báo thức gốc đang reo hoặc đang trong trạng thái Snoozed cùng slot
        if (existingAlarm == null ||
            existingAlarm.status != AlarmStatus.snoozed &&
                existingAlarm.status != AlarmStatus.ringing) {
          final exact = await alarmStateManager.scheduleForSlot(
            slot: slot,
            soundId: profile.alarmSoundId,
          );
          if (!exact) allExact = false;
          alarmCount++;
        } else if (existingAlarm.status == AlarmStatus.snoozed) {
          alarmCount++;
        }
      }
    }

    return ScheduleSyncReport(
      preStudyScheduledCount: preStudyCount,
      alarmsScheduledCount: alarmCount,
      cancelledCount: cancelledCount,
      allUsedExactAlarms: alarmCount > 0
          ? allExact
          : permissionStatus.exactAlarmsGranted,
      hasValidScheduleSource: uniqueSlots.isNotEmpty,
    );
  }

  /// Hủy lịch thông báo & báo thức của riêng một buổi học đã bị hủy/đổi.
  Future<void> cancelForSlot(String slotId) async {
    await notificationService.cancel(NotificationIds.preStudyForSlot(slotId));
    _scheduledPreStudySlotIds.remove(slotId);
    await alarmStateManager.cancelAlarm(
      AlarmStateManager.buildSlotAlarmKey(slotId),
    );
  }

  /// Hủy toàn bộ thông báo chờ và báo thức đang hoạt động (khi tắt công tắc tổng hoặc khôi phục/reset).
  Future<int> cancelAllScheduledRemindersAndAlarms() async {
    var count = _scheduledPreStudySlotIds.length;
    for (final slotId in _scheduledPreStudySlotIds.toList()) {
      await notificationService.cancel(NotificationIds.preStudyForSlot(slotId));
    }
    _scheduledPreStudySlotIds.clear();

    final pendingCount =
        alarmStateManager.pendingAlarms.length +
        (alarmStateManager.hasRingingAlarm ? 1 : 0);
    count += pendingCount;
    await alarmStateManager.cancelAllActiveAlarms();
    await notificationService.cancelAll();
    return count;
  }
}

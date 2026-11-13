import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/alarm_state.dart';
import '../models/notification_type.dart';
import '../models/study_session.dart';
import '../models/user_profile.dart';
import '../widgets/study_timer_formatters.dart';
import 'alarm_service.dart';
import 'alarm_state_manager.dart';
import 'alarm_store.dart';
import 'audio_playback_gateway.dart';
import 'notification_permission_service.dart';
import 'notification_scheduler.dart';
import 'notification_service.dart';
import 'sound_catalog.dart';
import 'study_session_platform_bridge.dart';
import 'study_timer_engine.dart';

/// Điều phối tập trung giữa Notification, Alarm State Machine, Audio Preview,
/// Quyền hệ thống, StudyTimerEngine và Android Foreground Service (Phase 4.1).
///
/// Đảm bảo:
/// - Lỗi quyền hoặc lỗi plugin Notification không bao giờ làm gián đoạn StudyTimerEngine.
/// - Notification không bao giờ cộng thêm hoặc thay đổi `verifiedStudySeconds`.
/// - Thông báo phiên học ongoing duy trì đúng một ID ổn định, không thể vuốt tắt khi đang học,
///   đồng bộ theo nhịp Heartbeat 15 giây và dừng sạch khi hoàn thành/hủy phiên.
/// - Thông báo hoàn thành phiên được gửi duy nhất 1 lần với thời lượng thực tế đã xác nhận.
class StudyNotificationCoordinator extends ChangeNotifier {
  final NotificationService notificationService;
  final NotificationPermissionService permissionService;
  final AudioPlaybackGateway audioGateway;
  final AlarmStateManager alarmStateManager;
  late final NotificationScheduler scheduler;
  final StudySessionPlatformBridge sessionBridge;
  final TimerClock clock;
  final List<ScheduledStudySlot> Function()? scheduleSlotsProvider;
  final bool ownsAudioGateway;
  final bool ownsAlarmStateManager;

  StudyTimerEngine? _boundEngine;
  UserProfile _profile;
  NotificationPermissionStatus _permissionStatus =
      const NotificationPermissionStatus.unknown();
  ScheduleSyncReport _lastSyncReport = const ScheduleSyncReport();

  bool _initialized = false;
  bool _disposed = false;

  // Theo dõi các sự kiện Study Timer đã thông báo để tránh lặp thông báo
  String? _activeTrackSessionId;
  StudySessionStatus? _lastObservedTimerStatus;
  int _breakIndex = 0;
  int? _pendingScheduledBreakEndNotifId;
  bool _notifiedBreakStartForCurrentStretch = false;
  bool _notifiedBreakEndForCurrentStretch = false;
  final Set<String> _completedNotifiedSessionIds = <String>{};

  StudyNotificationCoordinator({
    required UserProfile initialProfile,
    NotificationService? notificationService,
    NotificationPermissionService? permissionService,
    AudioPlaybackGateway? audioGateway,
    AlarmStateManager? alarmStateManager,
    NotificationScheduler? scheduler,
    AlarmStore? alarmStore,
    AlarmPlatformBridge? alarmPlatformBridge,
    StudySessionPlatformBridge? sessionBridge,
    TimerClock? clock,
    List<ScheduledStudySlot> Function()? scheduleSlotsProvider,
    ValueChanged<AlarmRecord>? onAlarmStartStudyRequested,
  }) : this._build(
         initialProfile: initialProfile,
         notificationService:
             notificationService ?? PlatformNotificationService(),
         permissionService:
             permissionService ?? PlatformNotificationPermissionService(),
         audioGateway: audioGateway ?? PlatformAudioPlaybackGateway(),
         ownsAudioGateway: audioGateway == null,
         alarmStateManager: alarmStateManager,
         ownsAlarmStateManager: alarmStateManager == null,
         scheduler: scheduler,
         alarmStore: alarmStore,
         alarmPlatformBridge: alarmPlatformBridge,
         sessionBridge: sessionBridge ?? NativeStudySessionBridge(),
         clock: clock ?? SystemTimerClock(),
         scheduleSlotsProvider: scheduleSlotsProvider,
         onAlarmStartStudyRequested: onAlarmStartStudyRequested,
       );

  StudyNotificationCoordinator._build({
    required UserProfile initialProfile,
    required this.notificationService,
    required this.permissionService,
    required this.audioGateway,
    required this.ownsAudioGateway,
    required AlarmStateManager? alarmStateManager,
    required this.ownsAlarmStateManager,
    required NotificationScheduler? scheduler,
    required AlarmStore? alarmStore,
    required AlarmPlatformBridge? alarmPlatformBridge,
    required this.sessionBridge,
    required this.clock,
    required this.scheduleSlotsProvider,
    required ValueChanged<AlarmRecord>? onAlarmStartStudyRequested,
  }) : _profile = initialProfile,
       alarmStateManager =
           alarmStateManager ??
           AlarmStateManager(
             store: alarmStore ?? LocalAlarmStore(),
             platformBridge: alarmPlatformBridge ?? PlatformAlarmBridge(),
             audioGateway: audioGateway,
             clock: clock,
             onStartStudyRequested: onAlarmStartStudyRequested,
           ) {
    this.scheduler =
        scheduler ??
        NotificationScheduler(
          notificationService: notificationService,
          alarmStateManager: this.alarmStateManager,
          clock: clock,
        );
    this.alarmStateManager.addListener(_onDependencyChanged);
    audioGateway.addListener(_onDependencyChanged);
  }

  /// Tạo coordinator chuẩn với các phụ thuộc chia sẻ đúng một thể hiện.
  factory StudyNotificationCoordinator.createDefault({
    required UserProfile initialProfile,
    TimerClock? clock,
    List<ScheduledStudySlot> Function()? scheduleSlotsProvider,
    ValueChanged<AlarmRecord>? onAlarmStartStudyRequested,
  }) {
    return StudyNotificationCoordinator(
      initialProfile: initialProfile,
      clock: clock,
      scheduleSlotsProvider: scheduleSlotsProvider,
      onAlarmStartStudyRequested: onAlarmStartStudyRequested,
    );
  }

  /// Lên lịch thử nghiệm một báo thức thực tế sau một khoảng thời gian (mặc định 10s)
  /// để người dùng và kiểm thử viên kiểm chứng tức thì trên thiết bị thật:
  /// Flutter -> MethodChannel -> AlarmManager (Exact) -> BroadcastReceiver -> ForegroundService -> Looping Audio & Vibration.
  Future<bool> scheduleTestAlarm({
    Duration duration = const Duration(seconds: 10),
    String? title,
  }) async {
    final targetUtc = clock.nowUtc().add(duration);
    final testSlot = ScheduledStudySlot(
      id: 'test_alarm_${targetUtc.millisecondsSinceEpoch}',
      subjectName: title ?? 'Báo thức thử nghiệm ExamPilot',
      taskTitle: 'Đang kiểm tra chuông báo thức (${duration.inSeconds}s)',
      startAtUtc: targetUtc,
    );
    final chosenSoundId = _profile.alarmSoundId;
    return alarmStateManager.scheduleForSlot(
      slot: testSlot,
      soundId: chosenSoundId,
    );
  }

  UserProfile get profile => _profile;
  NotificationPermissionStatus get permissionStatus => _permissionStatus;
  ScheduleSyncReport get lastSyncReport => _lastSyncReport;
  bool get isInitialized => _initialized;
  Set<String> get completedNotifiedSessionIds =>
      Set.unmodifiable(_completedNotifiedSessionIds);

  AlarmRecord? get activeRingingAlarm => alarmStateManager.activeRingingAlarm;
  bool get supportsBackgroundAlarm =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize({
    void Function(String? payload, String? actionId)? onNotificationTap,
  }) async {
    if (_initialized || _disposed) return;
    _initialized = true;
    await notificationService.initialize(onResponse: onNotificationTap);
    await alarmStateManager.restoreOnAppStart();
    await refreshPermissions();
    await syncSchedules();
  }

  void bindTimerEngine(StudyTimerEngine engine) {
    if (identical(_boundEngine, engine)) return;
    unbindTimerEngine();
    _boundEngine = engine;
    _captureTimerBaseline(engine);
    engine.addListener(_handleTimerStateChanged);
    engine.uiTickListenable.addListener(_handleTimerTickForBreakEnd);
  }

  void unbindTimerEngine() {
    final old = _boundEngine;
    if (old == null) return;
    old.removeListener(_handleTimerStateChanged);
    old.uiTickListenable.removeListener(_handleTimerTickForBreakEnd);
    _boundEngine = null;
  }

  void _captureTimerBaseline(StudyTimerEngine engine) {
    final session = engine.activeSession;
    _activeTrackSessionId = session?.id;
    _lastObservedTimerStatus = engine.currentStatus;
    _breakIndex = 0;
    _notifiedBreakStartForCurrentStretch = engine.isInBreak;
    _notifiedBreakEndForCurrentStretch =
        engine.isInBreak && engine.hasReachedPlannedBreakDuration;
  }

  Future<NotificationPermissionStatus> refreshPermissions() async {
    _permissionStatus = await permissionService.checkStatus();
    _notifySafely();
    return _permissionStatus;
  }

  Future<bool> requestNotificationPermission() async {
    final granted = await permissionService.requestNotificationPermission();
    await refreshPermissions();
    await syncSchedules();
    return granted;
  }

  Future<bool> requestExactAlarmPermission() async {
    final granted = await permissionService.requestExactAlarmPermission();
    await refreshPermissions();
    await syncSchedules();
    return granted;
  }

  Future<bool> openSystemNotificationSettings() async {
    return permissionService.openSystemNotificationSettings();
  }

  /// Cập nhật cài đặt từ UserProfile:
  /// - Tắt công tắc tổng -> hủy các nhắc nhở chờ & dừng báo thức đang chạy, bảo toàn Task/Subject/Session.
  /// - Bật công tắc tổng -> kiểm tra/xin quyền hệ thống và đồng bộ lịch hợp lệ.
  Future<void> applyProfile(
    UserProfile nextProfile, {
    bool promptPermissionIfEnabling = true,
  }) async {
    final wasEnabled = _profile.reminderEnabled;
    _profile = nextProfile;

    if (!nextProfile.reminderEnabled || !nextProfile.notifySessionStart) {
      final active = _boundEngine?.activeSession;
      if (active != null) {
        unawaited(sessionBridge.stopOngoingSession().catchError((_) {}));
        await notificationService.cancel(
          NotificationIds.sessionOngoing(active.id),
        );
      }
    }

    if (!nextProfile.reminderEnabled) {
      await _cancelScheduledBreakEndNotification();
      _lastSyncReport = await scheduler.syncScheduledSlots(
        slots: const [],
        profile: nextProfile,
        permissionStatus: _permissionStatus,
      );
      _notifySafely();
      return;
    }

    if (!wasEnabled && promptPermissionIfEnabling) {
      await permissionService.requestNotificationPermission();
    }
    await refreshPermissions();
    await syncSchedules();
  }

  /// Đồng bộ lại sau khi Restore Backup hoặc Reset dữ liệu:
  /// Hủy lịch cũ để chống trùng và chỉ lên lịch lại nguồn lịch tương lai hợp lệ.
  Future<void> syncAfterRestoreOrReset(UserProfile restoredProfile) async {
    _profile = restoredProfile;
    unawaited(sessionBridge.stopOngoingSession().catchError((_) {}));
    final active = _boundEngine?.activeSession;
    if (active != null) {
      await notificationService.cancel(
        NotificationIds.sessionOngoing(active.id),
      );
    }
    await _cancelScheduledBreakEndNotification();
    await scheduler.cancelAllScheduledRemindersAndAlarms();
    await refreshPermissions();
    await syncSchedules();
  }

  Future<ScheduleSyncReport> syncSchedules([
    List<ScheduledStudySlot>? explicitSlots,
  ]) async {
    final slots =
        explicitSlots ??
        scheduleSlotsProvider?.call() ??
        const <ScheduledStudySlot>[];
    _lastSyncReport = await scheduler.syncScheduledSlots(
      slots: slots,
      profile: _profile,
      permissionStatus: _permissionStatus,
    );
    _notifySafely();
    return _lastSyncReport;
  }

  void _handleTimerStateChanged() {
    final engine = _boundEngine;
    if (engine == null || _disposed) return;
    unawaited(_processTimerTransitionSafely(engine));
  }

  Future<void> _processTimerTransitionSafely(StudyTimerEngine engine) async {
    try {
      final session = engine.activeSession;
      final ended = engine.lastEndedSession;
      final status = engine.currentStatus;

      // 1. Khi kết thúc hoặc hủy phiên -> dừng foreground service, xóa thông báo ongoing
      if (session == null && ended != null) {
        unawaited(sessionBridge.stopOngoingSession().catchError((_) {}));
        await notificationService.cancel(
          NotificationIds.sessionOngoing(ended.id),
        );
        await notificationService.cancel(
          NotificationIds.sessionStart(ended.id),
        );
        await _cancelScheduledBreakEndNotification();

        // Gửi thông báo chúc mừng đúng một lần khi Completed (không gửi khi Cancelled)
        if (ended.status == StudySessionStatus.completed &&
            !_completedNotifiedSessionIds.contains(ended.id)) {
          _completedNotifiedSessionIds.add(ended.id);

          if (_profile.reminderEnabled) {
            final hasName =
                _profile.isConfigured && _profile.name.trim().isNotEmpty;
            final title = hasName
                ? 'Chúc mừng ${_profile.name.trim()}! Bạn đã hoàn thành phiên học.'
                : 'Chúc mừng! Bạn đã hoàn thành phiên học.';
            final taskSuffix =
                (ended.taskTitleSnapshot != null &&
                    ended.taskTitleSnapshot!.trim().isNotEmpty)
                ? ' (${ended.taskTitleSnapshot!.trim()})'
                : '';
            final durationStr = formatVietnameseDurationSummary(
              ended.verifiedStudySeconds,
            );
            final body =
                'Bạn đã học ${ended.subjectNameSnapshot}$taskSuffix trong $durationStr. Hãy tiếp tục duy trì thói quen học tập nhé!';

            await notificationService.showImmediate(
              id: NotificationIds.sessionCompleted(ended.id),
              type: AppNotificationType.sessionCompleted,
              profile: _profile,
              title: title,
              body: body,
              payload: 'timer_completed:${ended.id}',
              ongoing: false,
            );
          }
        }

        _activeTrackSessionId = null;
        _lastObservedTimerStatus = status;
        _notifiedBreakStartForCurrentStretch = false;
        _notifiedBreakEndForCurrentStretch = false;
        return;
      }

      if (session == null) return;

      // 2. Nếu trạng thái là InterruptedPending -> dừng ongoing, không gửi chúc mừng
      if (status == StudySessionStatus.interruptedPending) {
        unawaited(sessionBridge.stopOngoingSession().catchError((_) {}));
        await notificationService.cancel(
          NotificationIds.sessionOngoing(session.id),
        );
        await notificationService.cancel(
          NotificationIds.sessionStart(session.id),
        );
        await _cancelScheduledBreakEndNotification();
        _lastObservedTimerStatus = status;
        return;
      }

      // 3. Theo dõi phiên học mới
      if (session.id != _activeTrackSessionId) {
        _activeTrackSessionId = session.id;
        _breakIndex = 0;
        _notifiedBreakStartForCurrentStretch = false;
        _notifiedBreakEndForCurrentStretch = false;
      }

      final taskPart =
          (session.taskTitleSnapshot != null &&
              session.taskTitleSnapshot!.trim().isNotEmpty)
          ? ' (${session.taskTitleSnapshot!.trim()})'
          : '';

      // 4. Trạng thái A & D: Đang học (Running)
      if (status == StudySessionStatus.running) {
        if (_profile.reminderEnabled && _profile.notifySessionStart) {
          final elapsed = engine.getCurrentElapsedSeconds();
          final durationStr = formatNotificationDuration(elapsed);
          final title = 'ExamPilot · Đang học';
          final body =
              'Môn học: ${session.subjectNameSnapshot}$taskPart\nThời gian: $durationStr';

          await _dispatchOngoingNotification(
            session: session,
            title: title,
            body: body,
          );
        }
      }
      // 5. Trạng thái B: Đang nghỉ (InBreak)
      else if (status == StudySessionStatus.inBreak) {
        final activeBreak = engine.getCurrentActiveBreakSeconds();
        final durationStr = formatNotificationDuration(activeBreak);
        final title = 'ExamPilot · Đang nghỉ';
        final body =
            'Môn học: ${session.subjectNameSnapshot}$taskPart\nThời gian nghỉ: $durationStr';

        if (_profile.reminderEnabled && _profile.notifySessionStart) {
          await _dispatchOngoingNotification(
            session: session,
            title: title,
            body: body,
          );
        }

        if (_lastObservedTimerStatus != StudySessionStatus.inBreak) {
          _breakIndex++;
          _notifiedBreakStartForCurrentStretch = false;
          _notifiedBreakEndForCurrentStretch = false;

          if (_profile.reminderEnabled &&
              _profile.notifyBreakStart &&
              !_notifiedBreakStartForCurrentStretch) {
            _notifiedBreakStartForCurrentStretch = true;
            final plannedBreak = session.plannedBreakMinutes;
            final breakBody = plannedBreak > 0
                ? 'Nghỉ giải lao dự kiến $plannedBreak phút cho môn ${session.subjectNameSnapshot}.'
                : 'Đang nghỉ giải lao môn ${session.subjectNameSnapshot}.';
            await notificationService.showImmediate(
              id: NotificationIds.breakStart(session.id, _breakIndex),
              type: AppNotificationType.breakStart,
              profile: _profile,
              title: 'Bắt đầu giờ nghỉ',
              body: breakBody,
              payload: 'timer_break:${session.id}',
            );
          }

          if (_profile.reminderEnabled &&
              _profile.notifyBreakEnd &&
              session.plannedBreakMinutes > 0) {
            final breakEndNotifId = NotificationIds.breakEnd(
              session.id,
              _breakIndex,
            );
            _pendingScheduledBreakEndNotifId = breakEndNotifId;
            final targetAtUtc = clock.nowUtc().add(
              Duration(minutes: session.plannedBreakMinutes),
            );
            await notificationService.scheduleAt(
              id: breakEndNotifId,
              scheduledAtUtc: targetAtUtc,
              type: AppNotificationType.breakEnd,
              profile: _profile,
              title: 'Hết thời gian nghỉ dự kiến',
              body:
                  'Đã hết ${session.plannedBreakMinutes} phút nghỉ cho môn ${session.subjectNameSnapshot}. Bạn có thể tiếp tục học.',
              payload: 'timer_break_end:${session.id}',
              allowExact: _permissionStatus.exactAlarmsGranted,
            );
          }
        }
      }
      // 6. Trạng thái C: Tạm dừng (Paused)
      else if (status == StudySessionStatus.paused) {
        if (_lastObservedTimerStatus == StudySessionStatus.inBreak) {
          await _cancelScheduledBreakEndNotification();
        }

        if (_profile.reminderEnabled && _profile.notifySessionStart) {
          final elapsed = engine.getCurrentElapsedSeconds();
          final durationStr = formatNotificationDuration(elapsed);
          final title = 'ExamPilot · Đã tạm dừng';
          final body =
              'Môn học: ${session.subjectNameSnapshot}$taskPart\nThời gian học: $durationStr';

          await _dispatchOngoingNotification(
            session: session,
            title: title,
            body: body,
          );
        }
      }

      // Thoát khỏi InBreak (quay lại học hoặc tạm dừng) -> hủy lịch nhắc kết thúc nghỉ
      if (status != StudySessionStatus.inBreak &&
          _lastObservedTimerStatus == StudySessionStatus.inBreak) {
        await _cancelScheduledBreakEndNotification();
        _notifiedBreakStartForCurrentStretch = false;
        _notifiedBreakEndForCurrentStretch = false;
      }

      _lastObservedTimerStatus = status;
    } catch (e) {
      // Cô lập hoàn toàn lỗi notification khỏi StudyTimerEngine
      debugPrint('Lỗi xử lý thông báo sự kiện Study Timer (đã bỏ qua): $e');
    }
  }

  Future<void> _dispatchOngoingNotification({
    required StudySession session,
    required String title,
    required String body,
  }) async {
    final notifId = NotificationIds.sessionOngoing(session.id);
    await notificationService.showImmediate(
      id: notifId,
      type: AppNotificationType.sessionStart,
      profile: _profile,
      title: title,
      body: body,
      payload: 'timer:${session.id}',
      ongoing: true,
    );
    unawaited(
      sessionBridge
          .startOrUpdateOngoingSession(
            sessionId: session.id,
            notificationId: notifId,
            title: title,
            content: body,
          )
          .catchError((_) {}),
    );
  }

  void _handleTimerTickForBreakEnd() {
    final engine = _boundEngine;
    if (engine == null || _disposed) return;
    if (!engine.isInBreak || _notifiedBreakEndForCurrentStretch) return;
    if (!engine.hasReachedPlannedBreakDuration) return;

    _notifiedBreakEndForCurrentStretch = true;
    unawaited(_dispatchBreakReachedAlert(engine));
  }

  Future<void> _dispatchBreakReachedAlert(StudyTimerEngine engine) async {
    try {
      final session = engine.activeSession;
      if (session == null ||
          !_profile.reminderEnabled ||
          !_profile.notifyBreakEnd) {
        return;
      }
      final breakEndNotifId = NotificationIds.breakEnd(session.id, _breakIndex);
      if (_pendingScheduledBreakEndNotifId == breakEndNotifId) {
        _pendingScheduledBreakEndNotifId = null;
      }
      await notificationService.cancel(breakEndNotifId);
      await notificationService.showImmediate(
        id: breakEndNotifId,
        type: AppNotificationType.breakEnd,
        profile: _profile,
        title: 'Hết thời gian nghỉ dự kiến',
        body:
            'Đã đủ ${session.plannedBreakMinutes} phút nghỉ (${session.subjectNameSnapshot}). Nhấn để quay lại tiếp tục học.',
        payload: 'timer_break_end:${session.id}',
      );
      await audioGateway.playOneShotCue(
        _profile.breakSoundId,
        group: SoundGroup.breakReminder,
      );
    } catch (e) {
      debugPrint('Lỗi thông báo hết giờ nghỉ (đã bỏ qua): $e');
    }
  }

  Future<void> _cancelScheduledBreakEndNotification() async {
    final id = _pendingScheduledBreakEndNotifId;
    _pendingScheduledBreakEndNotifId = null;
    if (id != null) {
      await notificationService.cancel(id);
    }
  }

  void _onDependencyChanged() {
    _notifySafely();
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unbindTimerEngine();
    alarmStateManager.removeListener(_onDependencyChanged);
    audioGateway.removeListener(_onDependencyChanged);
    unawaited(sessionBridge.stopOngoingSession());
    if (ownsAlarmStateManager) {
      alarmStateManager.dispose();
    }
    if (ownsAudioGateway) {
      audioGateway.dispose();
    }
    super.dispose();
  }
}

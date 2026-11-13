import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/alarm_state.dart';
import 'package:exampilot/models/notification_type.dart';
import 'package:exampilot/models/study_session.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/user_profile.dart';
import 'package:exampilot/repositories/profile_repository.dart';
import 'package:exampilot/repositories/session_repository.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/screens/app_shell.dart';
import 'package:exampilot/screens/profile_screen.dart';
import 'package:exampilot/services/alarm_service.dart';
import 'package:exampilot/services/alarm_state_manager.dart';
import 'package:exampilot/services/alarm_store.dart';
import 'package:exampilot/services/audio_playback_gateway.dart';
import 'package:exampilot/services/backup_service.dart';
import 'package:exampilot/services/notification_permission_service.dart';
import 'package:exampilot/services/notification_scheduler.dart';
import 'package:exampilot/services/notification_service.dart';
import 'package:exampilot/services/session_storage.dart';
import 'package:exampilot/services/sound_catalog.dart';
import 'package:exampilot/services/study_notification_coordinator.dart';
import 'package:exampilot/services/study_timer_engine.dart';
import 'package:exampilot/services/web_storage.dart';
import 'package:exampilot/widgets/active_alarm_banner.dart';
import 'package:exampilot/widgets/notification_settings_section.dart';

class _FakeNotificationRecord {
  final int id;
  final AppNotificationType type;
  final String title;
  final String body;
  final String? payload;
  final DateTime? scheduledAtUtc;
  final bool usedExact;
  final bool ongoing;

  const _FakeNotificationRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.payload,
    this.scheduledAtUtc,
    this.usedExact = false,
    this.ongoing = false,
  });
}

class _FakeNotificationService implements NotificationService {
  bool throwOnDispatch = false;
  final List<_FakeNotificationRecord> immediateLogs = [];
  final Map<int, _FakeNotificationRecord> scheduled = {};
  final List<int> cancelledIds = [];
  int cancelAllCount = 0;

  @override
  Future<void> initialize({
    void Function(String? payload, String? actionId)? onResponse,
  }) async {}

  @override
  Future<NotificationDispatchResult> showImmediate({
    required int id,
    required AppNotificationType type,
    required UserProfile profile,
    required String title,
    required String body,
    String? payload,
    bool ongoing = false,
  }) async {
    if (throwOnDispatch) {
      throw StateError('Simulated notification plugin failure');
    }
    immediateLogs.add(
      _FakeNotificationRecord(
        id: id,
        type: type,
        title: title,
        body: body,
        payload: payload,
        ongoing: ongoing,
      ),
    );
    return NotificationDispatchResult.ok;
  }

  @override
  Future<NotificationDispatchResult> scheduleAt({
    required int id,
    required DateTime scheduledAtUtc,
    required AppNotificationType type,
    required UserProfile profile,
    required String title,
    required String body,
    String? payload,
    bool allowExact = true,
  }) async {
    if (throwOnDispatch) {
      throw StateError('Simulated notification schedule failure');
    }
    scheduled[id] = _FakeNotificationRecord(
      id: id,
      type: type,
      title: title,
      body: body,
      payload: payload,
      scheduledAtUtc: scheduledAtUtc.toUtc(),
      usedExact: allowExact,
    );
    return NotificationDispatchResult(
      succeeded: true,
      usedExactSchedule: allowExact,
    );
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
    scheduled.clear();
  }

  @override
  Future<List<int>> getPendingNotificationIds() async =>
      scheduled.keys.toList();
}

class _FakePermissionService implements NotificationPermissionService {
  NotificationPermissionStatus status;
  bool grantNotificationOnRequest = true;
  bool grantExactAlarmOnRequest = true;
  int requestNotificationCalls = 0;
  int requestExactAlarmCalls = 0;
  int openSettingsCalls = 0;

  _FakePermissionService({NotificationPermissionStatus? initialStatus})
    : status =
          initialStatus ??
          const NotificationPermissionStatus(
            notificationsGranted: true,
            exactAlarmsGranted: true,
          );

  @override
  Future<NotificationPermissionStatus> checkStatus() async => status;

  @override
  Future<bool> requestNotificationPermission() async {
    requestNotificationCalls++;
    status = NotificationPermissionStatus(
      notificationsGranted: grantNotificationOnRequest,
      exactAlarmsGranted: status.exactAlarmsGranted,
      isWebPlatform: status.isWebPlatform,
      webPermissionState: grantNotificationOnRequest ? 'granted' : 'denied',
    );
    return grantNotificationOnRequest;
  }

  @override
  Future<bool> requestExactAlarmPermission() async {
    requestExactAlarmCalls++;
    status = NotificationPermissionStatus(
      notificationsGranted: status.notificationsGranted,
      exactAlarmsGranted: grantExactAlarmOnRequest,
      isWebPlatform: status.isWebPlatform,
      webPermissionState: status.webPermissionState,
    );
    return grantExactAlarmOnRequest;
  }

  @override
  Future<bool> openSystemNotificationSettings() async {
    openSettingsCalls++;
    return true;
  }
}

class _FakeAlarmPlatformBridge implements AlarmPlatformBridge {
  @override
  bool supportsBackgroundAlarm = true;
  bool exactPermissionGranted = true;
  final Map<String, AlarmRecord> osScheduled = {};
  List<AlarmRecord> storedNativeOnBoot = [];
  ({String action, String? alarmKey})? pendingLaunch;
  int startForegroundCalls = 0;
  int stopForegroundCalls = 0;
  int cancelAllCalls = 0;

  ValueChanged<AlarmRecord>? _onUpdate;
  ValueChanged<String?>? _onLaunchStart;

  _FakeAlarmPlatformBridge();

  @override
  void attachListeners({
    required ValueChanged<AlarmRecord> onNativeAlarmUpdated,
    required ValueChanged<String?> onNativeLaunchStartRequested,
  }) {
    _onUpdate = onNativeAlarmUpdated;
    _onLaunchStart = onNativeLaunchStartRequested;
  }

  void simulateNativeUpdate(AlarmRecord record) {
    _onUpdate?.call(record);
  }

  void simulateNativeLaunchStart(String? key) {
    _onLaunchStart?.call(key);
  }

  @override
  Future<bool> scheduleAlarm(AlarmRecord record) async {
    osScheduled[record.alarmKey] = record;
    return supportsBackgroundAlarm && exactPermissionGranted;
  }

  @override
  Future<void> startRingingForeground(AlarmRecord record) async {
    startForegroundCalls++;
  }

  @override
  Future<void> stopRingingForeground() async {
    stopForegroundCalls++;
  }

  @override
  Future<void> syncAlarmRecord(AlarmRecord record) async {
    if (record.isTerminal) {
      osScheduled.remove(record.alarmKey);
    }
  }

  @override
  Future<void> cancelAlarm(AlarmRecord record) async {
    osScheduled.remove(record.alarmKey);
  }

  @override
  Future<void> cancelAllAlarms() async {
    cancelAllCalls++;
    osScheduled.clear();
  }

  @override
  Future<List<AlarmRecord>> getStoredNativeAlarms() async => storedNativeOnBoot;

  @override
  Future<({String action, String? alarmKey})?>
  consumePendingLaunchAction() async {
    final p = pendingLaunch;
    pendingLaunch = null;
    return p;
  }

  @override
  void dispose() {}
}

class _FakeAudioGateway extends AudioPlaybackGateway {
  String? _currentPreview;
  SoundGroup? _currentGroup;
  bool _isAlarmLoopPlaying = false;
  String? _activeAlarmSoundId;
  int activeStreamCount = 0;
  int maxObservedConcurrentPlays = 0;
  final List<String> playHistory = [];
  final List<String> cueHistory = [];
  int stopPreviewCalls = 0;
  int stopAlarmLoopCalls = 0;

  @override
  String? get currentPreviewSoundId => _currentPreview;

  @override
  SoundGroup? get currentPreviewGroup => _currentGroup;

  @override
  bool get isPreviewPlaying => _currentPreview != null;

  @override
  bool get isAlarmLoopPlaying => _isAlarmLoopPlaying;

  @override
  String? get activeAlarmSoundId => _activeAlarmSoundId;

  @override
  Future<void> playPreview(String soundId, {required SoundGroup group}) async {
    await stopPreview();
    if (soundId == 'none') return;
    _currentPreview = soundId;
    _currentGroup = group;
    activeStreamCount++;
    if (activeStreamCount > maxObservedConcurrentPlays) {
      maxObservedConcurrentPlays = activeStreamCount;
    }
    playHistory.add(soundId);
    notifyListeners();
  }

  @override
  Future<void> stopPreview() async {
    stopPreviewCalls++;
    final had = _currentPreview != null;
    if (had && activeStreamCount > 0) {
      activeStreamCount--;
    }
    _currentPreview = null;
    _currentGroup = null;
    if (had) notifyListeners();
  }

  @override
  Future<void> playOneShotCue(
    String soundId, {
    required SoundGroup group,
  }) async {
    if (soundId == 'none') return;
    cueHistory.add(soundId);
  }

  @override
  Future<void> startAlarmLoop(String soundId) async {
    await stopPreview();
    _isAlarmLoopPlaying = soundId != 'none';
    _activeAlarmSoundId = soundId;
    notifyListeners();
  }

  @override
  Future<void> stopAlarmLoop() async {
    stopAlarmLoopCalls++;
    final had = _isAlarmLoopPlaying || _activeAlarmSoundId != null;
    _isAlarmLoopPlaying = false;
    _activeAlarmSoundId = null;
    if (had) notifyListeners();
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late FakeTimerClock clock;
  late _FakeNotificationService notifService;
  late _FakePermissionService permService;
  late _FakeAlarmPlatformBridge alarmBridge;
  late _FakeAudioGateway audioGateway;
  late LocalAlarmStore alarmStore;

  setUp(() {
    WebSessionStorage.resetAllSimulatedStorageForTesting();
    WebStreakStorage.clearProfile();
    WebStreakStorage.clearStudyActivitiesAndDates();
    clock = FakeTimerClock(DateTime.utc(2026, 11, 12, 8, 0));
    notifService = _FakeNotificationService();
    permService = _FakePermissionService();
    alarmBridge = _FakeAlarmPlatformBridge();
    audioGateway = _FakeAudioGateway();
    alarmStore = LocalAlarmStore(useMemoryOnly: true);
  });

  StudyNotificationCoordinator buildCoordinator({
    UserProfile initialProfile = const UserProfile(),
    List<ScheduledStudySlot> Function()? scheduleSlotsProvider,
    ValueChanged<AlarmRecord>? onAlarmStartStudyRequested,
  }) {
    final alarmMgr = AlarmStateManager(
      store: alarmStore,
      platformBridge: alarmBridge,
      audioGateway: audioGateway,
      clock: clock,
      onStartStudyRequested: onAlarmStartStudyRequested,
    );
    final scheduler = NotificationScheduler(
      notificationService: notifService,
      alarmStateManager: alarmMgr,
      clock: clock,
    );
    return StudyNotificationCoordinator(
      initialProfile: initialProfile,
      notificationService: notifService,
      permissionService: permService,
      audioGateway: audioGateway,
      alarmStateManager: alarmMgr,
      scheduler: scheduler,
      clock: clock,
      scheduleSlotsProvider: scheduleSlotsProvider,
      onAlarmStartStudyRequested: onAlarmStartStudyRequested,
    );
  }

  group('Nhóm A - Notification Settings & Persistence', () {
    test(
      'Bật/tắt tổng, từng loại, nhắc trước, âm thanh; lưu đọc SQLite và bảo toàn qua Backup/Restore',
      () async {
        final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
        await db.execute('''
          CREATE TABLE ${DatabaseHelper.tableSubjects} (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            description TEXT DEFAULT '',
            icon_code INTEGER DEFAULT 0,
            color_value INTEGER DEFAULT 0
          )
        ''');
        await db.execute('''
          CREATE TABLE ${DatabaseHelper.tableTasks} (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            subject_id TEXT NOT NULL,
            subject TEXT NOT NULL,
            deadline TEXT,
            estimated_minutes INTEGER DEFAULT 30,
            actual_minutes INTEGER,
            priority INTEGER DEFAULT 1,
            status INTEGER DEFAULT 0,
            notes TEXT DEFAULT '',
            understanding_level INTEGER DEFAULT 0,
            review_notes TEXT DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE ${DatabaseHelper.tableActivities} (
            id TEXT PRIMARY KEY,
            activity_date TEXT NOT NULL,
            task_id TEXT,
            completed_at TEXT NOT NULL,
            actual_minutes INTEGER DEFAULT 0,
            subject_id TEXT
          )
        ''');
        await DatabaseHelper.createProfileTable(db);
        await DatabaseHelper.createClassSchedulesTable(db);
        DatabaseHelper.instance.setDatabaseForTesting(db);

        final profileRepo = ProfileRepository(
          dbHelper: DatabaseHelper.instance,
        );
        final taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);
        final subjectRepo = SubjectRepository(
          dbHelper: DatabaseHelper.instance,
        );
        final backupService = BackupService(
          taskRepository: taskRepo,
          subjectRepository: subjectRepo,
          profileRepository: profileRepo,
          dbHelper: DatabaseHelper.instance,
        );

        final updated = await profileRepo.updateStudyPreferences(
          alarmSoundId: 'alarm_energetic',
          breakSoundId: 'break_waterdrop',
          preReminderMinutes: 30,
          notifyPreStudy: true,
          notifyAlarmOnTime: false,
          notifySessionStart: true,
          notifyBreakStart: false,
          notifyBreakEnd: true,
        );
        final enabledProfile = await profileRepo
            .saveProfile(updated.copyWith(reminderEnabled: true))
            .then((_) => profileRepo.getProfile());

        expect(enabledProfile.reminderEnabled, isTrue);
        expect(enabledProfile.alarmSoundId, 'alarm_energetic');
        expect(enabledProfile.breakSoundId, 'break_waterdrop');
        expect(enabledProfile.preReminderMinutes, 30);
        expect(enabledProfile.notifyAlarmOnTime, isFalse);
        expect(enabledProfile.notifyBreakStart, isFalse);

        final backup = await backupService.createBackupData();
        await profileRepo.resetProfile();
        final afterReset = await profileRepo.getProfile();
        expect(afterReset.reminderEnabled, isFalse);

        await backupService.restoreBackup(backup);
        final restored = await profileRepo.getProfile();
        expect(restored.reminderEnabled, isTrue);
        expect(restored.alarmSoundId, 'alarm_energetic');
        expect(restored.breakSoundId, 'break_waterdrop');
        expect(restored.preReminderMinutes, 30);
        expect(restored.notifyPreStudy, isTrue);
        expect(restored.notifyAlarmOnTime, isFalse);
        expect(restored.notifySessionStart, isTrue);
        expect(restored.notifyBreakStart, isFalse);
        expect(restored.notifyBreakEnd, isTrue);

        // Kiểm tra sau Restore coordinator dọn lịch cũ và không tự kích hoạt báo thức trùng
        final coord = buildCoordinator(initialProfile: restored);
        await coord.syncAfterRestoreOrReset(restored);
        expect(coord.alarmStateManager.pendingAlarms, isEmpty);
        expect(notifService.cancelAllCount, greaterThanOrEqualTo(1));

        coord.dispose();
        await db.close();
      },
    );

    testWidgets(
      'UI NotificationSettingsSection đổi tổng, từng loại, nhắc trước và báo rõ khi bị từ chối quyền',
      (tester) async {
        UserProfile current = const UserProfile(reminderEnabled: false);
        permService.status = const NotificationPermissionStatus(
          notificationsGranted: false,
          exactAlarmsGranted: false,
        );
        permService.grantNotificationOnRequest = false;

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) => Scaffold(
                body: SingleChildScrollView(
                  child: NotificationSettingsSection(
                    profile: current,
                    initiallyExpanded: true,
                    permissionStatus: permService.status,
                    audioGateway: audioGateway,
                    onUpdateReminderEnabled: (val) => setState(
                      () => current = current.copyWith(reminderEnabled: val),
                    ),
                    onUpdateNotificationPrefs:
                        ({
                          alarmSoundId,
                          breakSoundId,
                          preReminderMinutes,
                          notifyPreStudy,
                          notifyAlarmOnTime,
                          notifySessionStart,
                          notifyBreakStart,
                          notifyBreakEnd,
                        }) {
                          setState(() {
                            current = current.copyWith(
                              alarmSoundId: alarmSoundId,
                              breakSoundId: breakSoundId,
                              preReminderMinutes: preReminderMinutes,
                              notifyPreStudy: notifyPreStudy,
                              notifyAlarmOnTime: notifyAlarmOnTime,
                              notifySessionStart: notifySessionStart,
                              notifyBreakStart: notifyBreakStart,
                              notifyBreakEnd: notifyBreakEnd,
                            );
                          });
                        },
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('reminder_switch')));
        await tester.pumpAndSettle();
        expect(current.reminderEnabled, isTrue);
        // Dù user bật switch, khi chưa cấp quyền hệ thống vẫn phải cảnh báo rõ ràng
        expect(find.textContaining('CHƯA cấp quyền thông báo'), findsOneWidget);
        expect(find.text('Chưa cấp quyền thông báo'), findsOneWidget);

        // Đổi thời gian nhắc trước 15 phút
        await tester.ensureVisible(
          find.byKey(const ValueKey('pre_reminder_15')),
        );
        await tester.tap(find.byKey(const ValueKey('pre_reminder_15')));
        await tester.pumpAndSettle();
        expect(current.preReminderMinutes, 15);

        // Tắt từng công tắc con
        await tester.ensureVisible(
          find.byKey(const ValueKey('switch_notify_break_end')),
        );
        await tester.tap(find.byKey(const ValueKey('switch_notify_break_end')));
        await tester.pumpAndSettle();
        expect(current.notifyBreakEnd, isFalse);
      },
    );
  });

  group('Nhóm B - Notification Scheduling', () {
    test(
      'Lên lịch hợp lệ, cập nhật chống trùng, hủy lịch, không dùng Task.deadline hay nguồn thiếu',
      () async {
        final coordinator = buildCoordinator(
          initialProfile: const UserProfile(
            reminderEnabled: true,
            preReminderMinutes: 10,
            notifyPreStudy: true,
            notifyAlarmOnTime: true,
          ),
        );
        await coordinator.initialize();

        // 1. Khi không có nguồn ScheduledStudySlot (dù Task có deadline gần) -> 0 lịch
        final taskOnlyWithDeadline = StudyTask(
          id: 't1',
          title: 'Nộp bài tập',
          subjectId: 's1',
          subject: 'Toán',
          deadline: clock.nowUtc().add(const Duration(minutes: 20)),
          estimatedMinutes: 60,
        );
        expect(taskOnlyWithDeadline.deadline, isNotNull);
        final emptyReport = await coordinator.syncSchedules(const []);
        expect(emptyReport.preStudyScheduledCount, 0);
        expect(emptyReport.alarmsScheduledCount, 0);
        expect(notifService.scheduled, isEmpty);

        // 2. Có nguồn lịch học hợp lệ + có bản ghi bị hủy & bản ghi trùng ID
        final slot1 = ScheduledStudySlot(
          id: 'sched_1',
          subjectId: 'subj_math',
          subjectName: 'Toán cao cấp',
          taskId: 't1',
          taskTitle: 'Ôn đạo hàm',
          startAtUtc: clock.nowUtc().add(const Duration(hours: 2)),
        );
        final slotCancelled = ScheduledStudySlot(
          id: 'sched_cancelled',
          subjectId: 'subj_db',
          subjectName: 'CSDL',
          startAtUtc: clock.nowUtc().add(const Duration(hours: 3)),
          isCancelled: true,
        );

        final report1 = await coordinator.syncSchedules([
          slot1,
          slot1, // Trùng slot id -> khử trùng còn 1
          slotCancelled,
        ]);
        expect(report1.preStudyScheduledCount, 1);
        expect(report1.alarmsScheduledCount, 1);
        expect(notifService.scheduled.length, 1);
        expect(alarmBridge.osScheduled.length, 1);
        expect(
          notifService
              .scheduled[NotificationIds.preStudyForSlot('sched_1')]!
              .scheduledAtUtc,
          slot1.startAtUtc.subtract(const Duration(minutes: 10)),
        );

        // 3. Lên lịch lại giờ mới -> không tạo lịch trùng thứ 2
        final slot1Moved = ScheduledStudySlot(
          id: 'sched_1',
          subjectId: 'subj_math',
          subjectName: 'Toán cao cấp',
          startAtUtc: clock.nowUtc().add(const Duration(hours: 4)),
        );
        await coordinator.syncSchedules([slot1Moved]);
        expect(notifService.scheduled.length, 1);
        expect(coordinator.alarmStateManager.allAlarms.length, 1);
        expect(
          coordinator.alarmStateManager.pendingAlarms.single.scheduledAtUtc,
          slot1Moved.startAtUtc,
        );

        // 4. Hủy riêng slot -> hủy cả pre-study & alarm
        await coordinator.scheduler.cancelForSlot('sched_1');
        expect(notifService.scheduled, isEmpty);
        expect(coordinator.alarmStateManager.pendingAlarms, isEmpty);

        // 5. Lên lại rồi tắt công tắc tổng -> hủy toàn bộ lịch chờ
        await coordinator.syncSchedules([slot1Moved]);
        expect(coordinator.alarmStateManager.pendingAlarms.length, 1);
        await coordinator.applyProfile(
          const UserProfile(reminderEnabled: false),
        );
        expect(notifService.scheduled, isEmpty);
        expect(coordinator.alarmStateManager.pendingAlarms, isEmpty);

        coordinator.dispose();
      },
    );
  });

  group('Nhóm C - Alarm State Machine', () {
    test(
      'Đủ vòng đời Scheduled -> Ringing -> Snoozed -> Ringing -> Dismissed/Started/Cancelled, không timeout, snooze tối đa 1 lần',
      () async {
        AlarmRecord? launchedAlarm;
        final coordinator = buildCoordinator(
          initialProfile: const UserProfile(reminderEnabled: true),
          onAlarmStartStudyRequested: (r) => launchedAlarm = r,
        );
        await coordinator.initialize();

        final slot = ScheduledStudySlot(
          id: 'slot_fsm',
          subjectId: 'subj_math',
          subjectName: 'Giải tích',
          taskTitle: 'Bài tập giới hạn',
          startAtUtc: clock.nowUtc().add(const Duration(minutes: 30)),
        );
        await coordinator.alarmStateManager.scheduleForSlot(
          slot: slot,
          soundId: 'alarm_dawn',
        );
        final key = AlarmStateManager.buildSlotAlarmKey('slot_fsm');
        expect(
          coordinator.alarmStateManager.getByKey(key)!.status,
          AlarmStatus.scheduled,
        );

        // Scheduled -> Ringing
        clock.advance(const Duration(minutes: 30));
        await coordinator.alarmStateManager.triggerAlarmRinging(key);
        expect(
          coordinator.alarmStateManager.getByKey(key)!.status,
          AlarmStatus.ringing,
        );
        expect(alarmBridge.startForegroundCalls, 1);

        // Không có timeout tự động tắt dù để trôi qua nhiều giờ
        clock.advance(const Duration(hours: 3));
        expect(
          coordinator.alarmStateManager.getByKey(key)!.status,
          AlarmStatus.ringing,
        );

        // Ringing -> Snoozed (lần 1 hợp lệ)
        final snoozed = await coordinator.alarmStateManager.snoozeAlarm(key);
        expect(snoozed.status, AlarmStatus.snoozed);
        expect(snoozed.snoozeCount, 1);
        expect(snoozed.canSnooze, isFalse);
        expect(alarmBridge.stopForegroundCalls, greaterThanOrEqualTo(1));
        expect(audioGateway.stopAlarmLoopCalls, greaterThanOrEqualTo(1));

        // Snoozed -> Ringing
        clock.advance(const Duration(minutes: 5));
        final reRinging = await coordinator.alarmStateManager
            .triggerAlarmRinging(key);
        expect(reRinging!.status, AlarmStatus.ringing);
        expect(reRinging.canSnooze, isFalse);

        // Không cho phép Snooze quá 1 lần
        await expectLater(
          () => coordinator.alarmStateManager.snoozeAlarm(key),
          throwsStateError,
        );

        // Ringing -> Dismissed
        final dismissed = await coordinator.alarmStateManager.dismissAlarm(key);
        expect(dismissed.status, AlarmStatus.dismissed);
        expect(coordinator.alarmStateManager.hasRingingAlarm, isFalse);

        // Kiểm tra Ringing -> Started không tự chạy Timer trước khi user thao tác
        final slot2 = ScheduledStudySlot(
          id: 'slot_start',
          subjectId: 'subj_db',
          subjectName: 'CSDL',
          startAtUtc: clock.nowUtc().add(const Duration(minutes: 10)),
        );
        await coordinator.alarmStateManager.scheduleForSlot(
          slot: slot2,
          soundId: 'alarm_dawn',
        );
        final key2 = AlarmStateManager.buildSlotAlarmKey('slot_start');
        await coordinator.alarmStateManager.triggerAlarmRinging(key2);
        await coordinator.alarmStateManager.startFromAlarm(key2);
        expect(
          coordinator.alarmStateManager.getByKey(key2)!.status,
          AlarmStatus.started,
        );
        expect(launchedAlarm?.scheduledSessionId, 'slot_start');

        // Scheduled -> Cancelled
        final slot3 = ScheduledStudySlot(
          id: 'slot_cancel',
          subjectId: 'subj_db',
          subjectName: 'Mạng máy tính',
          startAtUtc: clock.nowUtc().add(const Duration(minutes: 20)),
        );
        await coordinator.alarmStateManager.scheduleForSlot(
          slot: slot3,
          soundId: 'alarm_dawn',
        );
        final key3 = AlarmStateManager.buildSlotAlarmKey('slot_cancel');
        await coordinator.alarmStateManager.cancelAlarm(key3);
        expect(
          coordinator.alarmStateManager.getByKey(key3)!.status,
          AlarmStatus.cancelled,
        );

        coordinator.dispose();
      },
    );

    testWidgets(
      'ActiveAlarmBanner ẩn nút Nhắc lại sau 1 lần Snooze và dừng chuông khi Tắt',
      (tester) async {
        final coordinator = buildCoordinator();
        await coordinator.initialize();
        final slot = ScheduledStudySlot(
          id: 'slot_ui',
          subjectId: 'subj_1',
          subjectName: 'Toán rời rạc',
          startAtUtc: clock.nowUtc().add(const Duration(minutes: 5)),
        );
        await coordinator.alarmStateManager.scheduleForSlot(
          slot: slot,
          soundId: 'alarm_dawn',
        );
        final key = AlarmStateManager.buildSlotAlarmKey('slot_ui');
        await coordinator.alarmStateManager.triggerAlarmRinging(key);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ActiveAlarmBanner(
                alarmStateManager: coordinator.alarmStateManager,
              ),
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey('active_alarm_banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('active_alarm_snooze_button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('active_alarm_snooze_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('active_alarm_banner')), findsNothing);

        await coordinator.alarmStateManager.triggerAlarmRinging(key);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('active_alarm_banner')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('active_alarm_snooze_button')),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const ValueKey('active_alarm_dismiss_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('active_alarm_banner')), findsNothing);
        expect(
          coordinator.alarmStateManager.getByKey(key)!.status,
          AlarmStatus.dismissed,
        );

        coordinator.dispose();
      },
    );
  });

  group('Nhóm D - Audio Selection, Preview & Cleanup', () {
    testWidgets(
      'Chọn từng âm thanh, nghe thử, chuyển âm dừng âm trước, chỉ 1 âm đồng thời và đóng màn hình dừng audio',
      (tester) async {
        UserProfile profile = const UserProfile(reminderEnabled: true);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => StatefulBuilder(
                          builder: (ctx, setState) => Scaffold(
                            appBar: AppBar(title: const Text('Hồ sơ')),
                            body: ProfileScreen(
                              profile: profile,
                              activities: const [],
                              audioGateway: audioGateway,
                              permissionStatus: permService.status,
                              onUpdateProfile: (_) {},
                              onUpdateGoals: (h, t) {},
                              onUpdateThemeMode: (_) {},
                              onUpdateReminderEnabled: (_) {},
                              onUpdateNotificationPrefs:
                                  ({
                                    alarmSoundId,
                                    breakSoundId,
                                    preReminderMinutes,
                                    notifyPreStudy,
                                    notifyAlarmOnTime,
                                    notifySessionStart,
                                    notifyBreakStart,
                                    notifyBreakEnd,
                                  }) {
                                    setState(() {
                                      profile = profile.copyWith(
                                        alarmSoundId: alarmSoundId,
                                        breakSoundId: breakSoundId,
                                      );
                                    });
                                  },
                              onResetStudyData: () async {},
                              onResetProfile: () async {},
                              onResetSampleData: () async {},
                              onResetAllData: () async {},
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('OpenProfile'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('OpenProfile'));
        await tester.pumpAndSettle();

        Future<void> scrollAndTap(String key) async {
          final finder = find.byKey(ValueKey(key));
          if (finder.evaluate().isEmpty) {
            await tester.scrollUntilVisible(
              finder,
              200,
              scrollable: find.byType(Scrollable).first,
            );
          }
          await tester.ensureVisible(finder);
          await tester.pumpAndSettle();
          await tester.tap(finder);
          await tester.pumpAndSettle();
        }

        // Cuộn tới nút mở rộng mục chi tiết thông báo & âm thanh trong ListView
        await scrollAndTap('notification_details_toggle');

        // Chọn & nghe thử alarm_school_bell
        await scrollAndTap('alarm_sound_option_alarm_school_bell');
        expect(profile.alarmSoundId, 'alarm_school_bell');

        await scrollAndTap('sound_preview_btn_alarm_school_bell');
        expect(audioGateway.isPreviewPlaying, isTrue);
        expect(audioGateway.currentPreviewSoundId, 'alarm_school_bell');
        expect(audioGateway.activeStreamCount, 1);

        // Phát sang break_waterdrop -> phải tự dừng alarm_school_bell trước (maxConcurrent == 1)
        await scrollAndTap('sound_preview_btn_break_waterdrop');
        expect(audioGateway.currentPreviewSoundId, 'break_waterdrop');
        expect(audioGateway.maxObservedConcurrentPlays, 1);

        // Bấm Dừng ngay trên sound_stop_btn_break_waterdrop
        await scrollAndTap('sound_stop_btn_break_waterdrop');
        expect(audioGateway.isPreviewPlaying, isFalse);

        // Cuộn ngược lên nghe thử alarm_dawn rồi đóng màn hình -> audio phải dừng sạch khi thoát
        final dawnFinder = find.byKey(
          const ValueKey('sound_preview_btn_alarm_dawn'),
        );
        if (dawnFinder.evaluate().isEmpty) {
          await tester.scrollUntilVisible(
            dawnFinder,
            -200,
            scrollable: find.byType(Scrollable).first,
          );
        }
        await tester.ensureVisible(dawnFinder);
        await tester.pumpAndSettle();
        await tester.tap(dawnFinder);
        await tester.pumpAndSettle();
        expect(audioGateway.isPreviewPlaying, isTrue);

        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(audioGateway.isPreviewPlaying, isFalse);
        expect(audioGateway.activeStreamCount, 0);
      },
    );
  });

  group('Nhóm E - Study Timer Integration', () {
    testWidgets(
      'Start session, Start break, Break reached, Complete, Cancel; Timer không bị ảnh hưởng nếu từ chối quyền hoặc plugin lỗi',
      (tester) async {
        final sessionRepo = SessionRepository(useWebPreview: true);
        final engine = StudyTimerEngine(
          repository: sessionRepo,
          clock: clock,
          autoStartHeartbeat: false,
          autoStartUiTicker: true,
        );
        final coordinator = buildCoordinator(
          initialProfile: const UserProfile(
            reminderEnabled: true,
            notifySessionStart: true,
            notifyBreakStart: true,
            notifyBreakEnd: true,
            breakSoundId: 'break_windchime',
          ),
        );
        await coordinator.initialize();
        coordinator.bindTimerEngine(engine);

        const subject = Subject(
          id: 'subj_math',
          name: 'Toán cao cấp',
          description: '',
        );

        // 1. Start session -> gửi 1 thông báo bắt đầu phiên
        await engine.startSession(
          subject: subject,
          plannedStudyMinutes: 25,
          plannedBreakMinutes: 5,
        );
        await tester.pump();
        expect(
          notifService.immediateLogs
              .where((e) => e.type == AppNotificationType.sessionStart)
              .length,
          1,
        );

        // 2. Học 10p -> Start break -> thông báo bắt đầu nghỉ + hẹn mốc hết nghỉ 5p
        clock.advance(const Duration(minutes: 10));
        await engine.startBreak();
        await tester.pump();
        expect(
          notifService.immediateLogs
              .where((e) => e.type == AppNotificationType.breakStart)
              .length,
          1,
        );
        expect(notifService.scheduled.length, 1);

        // 3. Đến mốc 5p nghỉ dự kiến -> kích hoạt nhịp 1s thật -> báo kết thúc nghỉ 1 lần + cue âm thanh
        clock.advance(const Duration(minutes: 5));
        await tester.pump(const Duration(seconds: 1));
        await tester.pump();
        expect(engine.isInBreak, isTrue);
        expect(engine.activeSession!.verifiedStudySeconds, 600);
        expect(
          notifService.immediateLogs
              .where((e) => e.type == AppNotificationType.breakEnd)
              .length,
          1,
        );
        expect(audioGateway.cueHistory, ['break_windchime']);
        expect(notifService.scheduled, isEmpty);

        // 4. Tiếp tục học 5p -> mở nghỉ lần 2 và kết thúc sớm / Complete -> không tạo báo thức mới
        await engine.endBreak();
        clock.advance(const Duration(minutes: 5));
        await engine.startBreak();
        await tester.pump();
        await engine.completeSession();
        await tester.pump();
        expect(notifService.scheduled, isEmpty);
        expect(coordinator.alarmStateManager.pendingAlarms, isEmpty);
        expect(engine.lastEndedSession!.verifiedStudySeconds, 900);

        // 5. Khi quyền bị từ chối & plugin throw lỗi -> Start, Break, Cancel của Timer vẫn chạy đúng
        permService.status = const NotificationPermissionStatus(
          notificationsGranted: false,
          exactAlarmsGranted: false,
        );
        notifService.throwOnDispatch = true;

        await engine.startSession(subject: subject);
        clock.advance(const Duration(minutes: 3));
        await engine.startBreak();
        await engine.cancelSession();
        await tester.pump();
        expect(engine.lastEndedSession!.status, StudySessionStatus.cancelled);

        coordinator.dispose();
        engine.dispose();
      },
    );
  });

  group('Nhóm F - Platform (Android & Web Limits)', () {
    test(
      'Xử lý quyền Android (Exact granted/denied), phục hồi sau kill process, và giới hạn Web',
      () async {
        // 1. Android không cấp Exact Alarm -> vẫn xếp lịch an toàn (fallback non-exact) và báo false
        alarmBridge.supportsBackgroundAlarm = true;
        alarmBridge.exactPermissionGranted = false;
        permService.status = const NotificationPermissionStatus(
          notificationsGranted: true,
          exactAlarmsGranted: false,
        );

        final coordinator = buildCoordinator(
          initialProfile: const UserProfile(reminderEnabled: true),
        );
        await coordinator.initialize();

        final slot = ScheduledStudySlot(
          id: 'slot_fallback',
          subjectId: 's1',
          subjectName: 'Lý thuyết đồ thị',
          startAtUtc: clock.nowUtc().add(const Duration(hours: 1)),
        );
        final report = await coordinator.syncSchedules([slot]);
        expect(report.alarmsScheduledCount, 1);
        expect(report.allUsedExactAlarms, isFalse);

        // 2. Giả lập process kill trong lúc native AlarmForegroundService đã chuyển sang Ringing
        final nativeRinging = AlarmRecord(
          alarmKey: AlarmStateManager.buildSlotAlarmKey('slot_fallback'),
          alarmId: NotificationIds.alarmForSlot('slot_fallback'),
          subjectId: 's1',
          title: 'Lý thuyết đồ thị',
          soundId: 'alarm_dawn',
          status: AlarmStatus.ringing,
          scheduledAtUtc: slot.startAtUtc,
          updatedAtUtc: clock.nowUtc().add(const Duration(hours: 1)),
        );
        alarmBridge.storedNativeOnBoot = [nativeRinging];

        final rebornCoordinator = buildCoordinator(
          initialProfile: const UserProfile(reminderEnabled: true),
        );
        await rebornCoordinator.initialize();
        expect(
          rebornCoordinator.activeRingingAlarm?.alarmKey,
          nativeRinging.alarmKey,
        );
        expect(rebornCoordinator.activeRingingAlarm?.isRinging, isTrue);

        coordinator.dispose();
        rebornCoordinator.dispose();
      },
    );

    testWidgets(
      'Trên Web với quyền bị từ chối hiển thị rõ trạng thái bị chặn và giới hạn chạy nền',
      (tester) async {
        permService.status = const NotificationPermissionStatus(
          notificationsGranted: false,
          exactAlarmsGranted: false,
          isWebPlatform: true,
          webPermissionState: 'denied',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NotificationSettingsSection(
                profile: const UserProfile(reminderEnabled: true),
                permissionStatus: permService.status,
                onUpdateReminderEnabled: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.textContaining('đang bị chặn trong cài đặt trang web'),
          findsOneWidget,
        );
        expect(
          find.textContaining('không bảo đảm đánh thức nền như Android'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'AppShell chuyển tab từ Cá nhân sang tab khác tự động dừng âm thanh đang nghe thử',
      (tester) async {
        final coordinator = buildCoordinator(
          initialProfile: const UserProfile(reminderEnabled: true),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: AppShell(
              taskRepository: TaskRepository(useWebPreview: true),
              subjectRepository: SubjectRepository(useWebPreview: true),
              profileRepository: ProfileRepository(useWebPreview: true),
              sessionRepository: SessionRepository(useWebPreview: true),
              notificationCoordinator: coordinator,
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cá nhân'));
        await tester.pumpAndSettle();

        await audioGateway.playPreview('alarm_dawn', group: SoundGroup.alarm);
        expect(audioGateway.isPreviewPlaying, isTrue);

        await tester.tap(find.text('Tổng quan'));
        await tester.pumpAndSettle();
        expect(audioGateway.isPreviewPlaying, isFalse);

        coordinator.dispose();
      },
    );
  });
}

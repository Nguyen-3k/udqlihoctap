import 'package:exampilot/models/alarm_state.dart';
import 'package:exampilot/models/user_profile.dart';
import 'package:exampilot/services/alarm_service.dart';
import 'package:exampilot/services/alarm_state_manager.dart';
import 'package:exampilot/services/alarm_store.dart';
import 'package:exampilot/services/audio_playback_gateway.dart';
import 'package:exampilot/services/notification_permission_service.dart';
import 'package:exampilot/services/notification_service.dart';
import 'package:exampilot/services/sound_catalog.dart';
import 'package:exampilot/services/study_notification_coordinator.dart';
import 'package:exampilot/services/study_timer_engine.dart';
import 'package:exampilot/widgets/notification_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockPlatformBridge implements AlarmPlatformBridge {
  final List<AlarmRecord> scheduled = [];
  final List<AlarmRecord> cancelled = [];
  bool exactAlarmSupported = true;

  @override
  bool get supportsBackgroundAlarm => true;

  @override
  void attachListeners({
    required ValueChanged<AlarmRecord> onNativeAlarmUpdated,
    required ValueChanged<String?> onNativeLaunchStartRequested,
  }) {}

  @override
  Future<bool> scheduleAlarm(AlarmRecord record) async {
    scheduled.add(record);
    return exactAlarmSupported;
  }

  @override
  Future<void> cancelAlarm(AlarmRecord record) async {
    cancelled.add(record);
  }

  @override
  Future<void> cancelAllAlarms() async {}

  @override
  Future<({String action, String? alarmKey})?> consumePendingLaunchAction() async => null;

  @override
  void dispose() {}

  @override
  Future<List<AlarmRecord>> getStoredNativeAlarms() async => const [];

  @override
  Future<void> startRingingForeground(AlarmRecord record) async {}

  @override
  Future<void> stopRingingForeground() async {}

  @override
  Future<void> syncAlarmRecord(AlarmRecord record) async {}
}

class _MockAudioGateway extends ChangeNotifier implements AudioPlaybackGateway {
  @override
  String? get activeAlarmSoundId => null;
  @override
  SoundGroup? get currentPreviewGroup => null;
  @override
  String? get currentPreviewSoundId => null;
  @override
  bool get isAlarmLoopPlaying => false;
  @override
  bool get isPreviewPlaying => false;

  @override
  Future<void> playOneShotCue(String soundId, {required SoundGroup group}) async {}
  @override
  Future<void> playPreview(String soundId, {required SoundGroup group}) async {}
  @override
  Future<void> startAlarmLoop(String soundId) async {}
  @override
  Future<void> stopAlarmLoop() async {}
  @override
  Future<void> stopPreview() async {}
}

class _MockNotificationService implements NotificationService {
  final List<int> cancelledIds = [];

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> cancelAll() async {}
  @override
  Future<void> initialize({void Function(String? payload, String? actionId)? onResponse}) async {}
  @override
  Future<List<int>> getPendingNotificationIds() async => const [];
  @override
  Future<NotificationDispatchResult> showImmediate({
    required int id,
    required dynamic type,
    required UserProfile profile,
    required String title,
    required String body,
    String? payload,
    bool ongoing = false,
  }) async => NotificationDispatchResult.ok;

  @override
  Future<NotificationDispatchResult> scheduleAt({
    required int id,
    required DateTime scheduledAtUtc,
    required dynamic type,
    required UserProfile profile,
    required String title,
    required String body,
    String? payload,
    bool allowExact = true,
  }) async {
    return const NotificationDispatchResult(succeeded: true, usedExactSchedule: true);
  }
}

class _FixedClock implements TimerClock {
  final DateTime fixedUtc;
  _FixedClock(this.fixedUtc);
  @override
  DateTime nowUtc() => fixedUtc;
  @override
  DateTime nowLocal() => fixedUtc.toLocal();
  @override
  bool get hasMonotonicClock => false;
  @override
  Duration get monotonicElapsed => Duration.zero;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Phase 4.2.1 – Android Alarm Audit & Fix Verification', () {
    test('1. AlarmRecord native map serialization retains all critical alarm metadata', () {
      final scheduledUtc = DateTime.utc(2026, 11, 13, 15, 30, 0);
      final snoozedUtc = DateTime.utc(2026, 11, 13, 15, 35, 0);
      final updatedUtc = DateTime.utc(2026, 11, 13, 15, 30, 5);
      final ackUtc = DateTime.utc(2026, 11, 13, 15, 30, 10);

      final record = AlarmRecord(
        alarmKey: 'slot:slot_test_100',
        alarmId: 900123,
        scheduledSessionId: 'slot_test_100',
        subjectId: 'sub_math',
        title: 'Giải tích nâng cao',
        taskTitle: 'Luyện tập vi phân',
        soundId: 'alarm_school_bell',
        status: AlarmStatus.snoozed,
        snoozeCount: 1,
        scheduledAtUtc: scheduledUtc,
        snoozedUntilUtc: snoozedUtc,
        updatedAtUtc: updatedUtc,
        acknowledgedAtUtc: ackUtc,
      );

      final map = record.toNativeMap();

      expect(map['alarmKey'], equals('slot:slot_test_100'));
      expect(map['alarmId'], equals(900123));
      expect(map['title'], equals('Giải tích nâng cao'));
      expect(map['taskTitle'], equals('Luyện tập vi phân'));
      expect(map['soundId'], equals('alarm_school_bell'));
      expect(map['status'], equals('snoozed'));
      expect(map['snoozeCount'], equals(1));
      expect(map['scheduledAtMillis'], equals(scheduledUtc.millisecondsSinceEpoch));
      expect(map['snoozedUntilMillis'], equals(snoozedUtc.millisecondsSinceEpoch));
      expect(map['updatedAtMillis'], equals(updatedUtc.millisecondsSinceEpoch));
      expect(map['acknowledgedAtMillis'], equals(ackUtc.millisecondsSinceEpoch));

      // Reconstruct from native map
      final reconstructed = AlarmRecord.fromNativeMap(map, fallback: record);
      expect(reconstructed.alarmKey, equals(record.alarmKey));
      expect(reconstructed.alarmId, equals(record.alarmId));
      expect(reconstructed.title, equals(record.title));
      expect(reconstructed.taskTitle, equals(record.taskTitle));
      expect(reconstructed.soundId, equals(record.soundId));
      expect(reconstructed.status, equals(AlarmStatus.snoozed));
      expect(reconstructed.snoozeCount, equals(1));
      expect(reconstructed.scheduledAtUtc, equals(scheduledUtc));
      expect(reconstructed.snoozedUntilUtc, equals(snoozedUtc));
      expect(reconstructed.effectiveTriggerAtUtc, equals(snoozedUtc));
    });

    test('2. StudyNotificationCoordinator.scheduleTestAlarm schedules exact slot +10s', () async {
      final nowUtc = DateTime.utc(2026, 11, 13, 8, 0, 0);
      final clock = _FixedClock(nowUtc);
      final bridge = _MockPlatformBridge();
      final store = LocalAlarmStore(useMemoryOnly: true);
      final audioGateway = _MockAudioGateway();
      final alarmManager = AlarmStateManager(
        store: store,
        platformBridge: bridge,
        audioGateway: audioGateway,
        clock: clock,
      );

      final coordinator = StudyNotificationCoordinator(
        initialProfile: const UserProfile(
          notifyAlarmOnTime: true,
          alarmSoundId: 'alarm_school_bell',
        ),
        notificationService: _MockNotificationService(),
        alarmStateManager: alarmManager,
        clock: clock,
      );

      final exact = await coordinator.scheduleTestAlarm(
        duration: const Duration(seconds: 10),
      );

      expect(exact, isTrue);
      expect(bridge.scheduled.length, equals(1));
      final testAlarm = bridge.scheduled.first;
      expect(testAlarm.alarmKey, startsWith('slot:test_alarm_'));
      expect(testAlarm.title, equals('Báo thức thử nghiệm ExamPilot'));
      expect(testAlarm.soundId, equals('alarm_school_bell'));
      expect(testAlarm.scheduledAtUtc, equals(nowUtc.add(const Duration(seconds: 10))));

      alarmManager.dispose();
      coordinator.dispose();
    });

    test('3. StudyNotificationCoordinator.createDefault accepts scheduleSlotsProvider and syncs', () async {
      final nowUtc = DateTime.utc(2026, 11, 13, 8, 0, 0);
      final clock = _FixedClock(nowUtc);
      final slot = ScheduledStudySlot(
        id: 'slot_real_1',
        subjectName: 'Vật lý hạt nhân',
        taskTitle: 'Thí nghiệm tán xạ',
        startAtUtc: nowUtc.add(const Duration(hours: 1)),
      );

      final coordinator = StudyNotificationCoordinator.createDefault(
        initialProfile: const UserProfile(
          reminderEnabled: true,
          notifyAlarmOnTime: true,
          notifyPreStudy: true,
          alarmSoundId: 'alarm_dawn',
        ),
        clock: clock,
        scheduleSlotsProvider: () => [slot],
      );

      final report = await coordinator.syncSchedules();
      expect(report.alarmsScheduledCount, equals(1));
      expect(coordinator.alarmStateManager.pendingAlarms.length, equals(1));
      expect(coordinator.alarmStateManager.pendingAlarms.first.title, equals('Vật lý hạt nhân'));

      coordinator.dispose();
    });

    testWidgets('4. NotificationSettingsSection displays Test Alarm button & triggers callback', (tester) async {
      bool testAlarmCalled = false;
      bool exactAlarmReqCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationSettingsSection(
                profile: const UserProfile(
                  reminderEnabled: true,
                  notifyAlarmOnTime: true,
                ),
                initiallyExpanded: true,
                permissionStatus: const NotificationPermissionStatus(
                  notificationsGranted: true,
                  exactAlarmsGranted: true,
                ),
                onUpdateReminderEnabled: (_) {},
                onScheduleTestAlarm: () async {
                  testAlarmCalled = true;
                  return true;
                },
                onRequestExactAlarmPermission: () async {
                  exactAlarmReqCalled = true;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const ValueKey('test_alarm_10s_button'));
      await tester.ensureVisible(buttonFinder);
      await tester.pumpAndSettle();

      expect(find.text('Kiểm tra Báo thức trên Thiết bị'), findsOneWidget);
      expect(buttonFinder, findsOneWidget);
      expect(find.textContaining('Quyền Báo thức chính xác (Exact Alarm): Đã cấp'), findsOneWidget);

      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(testAlarmCalled, isTrue);
      expect(find.textContaining('Đã lên lịch báo thức thử nghiệm sau 10 giây (Exact Alarm)!'), findsOneWidget);
      expect(exactAlarmReqCalled, isFalse);
    });

    testWidgets('5. NotificationSettingsSection displays warning & grant button when Exact Alarm denied', (tester) async {
      bool exactAlarmReqCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationSettingsSection(
                profile: const UserProfile(
                  reminderEnabled: true,
                  notifyAlarmOnTime: true,
                ),
                initiallyExpanded: true,
                permissionStatus: const NotificationPermissionStatus(
                  notificationsGranted: true,
                  exactAlarmsGranted: false,
                ),
                onUpdateReminderEnabled: (_) {},
                onRequestExactAlarmPermission: () async {
                  exactAlarmReqCalled = true;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final grantBtnFinder = find.text('Cấp quyền');
      await tester.ensureVisible(grantBtnFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('Chưa cấp quyền Exact Alarm'), findsOneWidget);
      expect(grantBtnFinder, findsOneWidget);

      await tester.tap(grantBtnFinder);
      await tester.pumpAndSettle();

      expect(exactAlarmReqCalled, isTrue);
    });

    testWidgets('6. NotificationSettingsSection displays warning SnackBar when scheduleTestAlarm falls back to inexact', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationSettingsSection(
                profile: const UserProfile(
                  reminderEnabled: true,
                  notifyAlarmOnTime: true,
                ),
                initiallyExpanded: true,
                permissionStatus: const NotificationPermissionStatus(
                  notificationsGranted: true,
                  exactAlarmsGranted: false,
                ),
                onUpdateReminderEnabled: (_) {},
                onScheduleTestAlarm: () async {
                  return false; // Inexact fallback
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final buttonFinder = find.byKey(const ValueKey('test_alarm_10s_button'));
      await tester.ensureVisible(buttonFinder);
      await tester.pumpAndSettle();

      await tester.tap(buttonFinder);
      await tester.pumpAndSettle();

      expect(find.textContaining('Cảnh báo: Báo thức đặt ở chế độ không chính xác (Doze Fallback)'), findsOneWidget);
    });
  });
}

import 'package:flutter_test/flutter_test.dart';

import 'package:exampilot/models/notification_type.dart';
import 'package:exampilot/models/study_session.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/user_profile.dart';
import 'package:exampilot/repositories/session_repository.dart';
import 'package:exampilot/services/notification_permission_service.dart';
import 'package:exampilot/services/notification_service.dart';
import 'package:exampilot/services/session_storage.dart';
import 'package:exampilot/services/study_notification_coordinator.dart';
import 'package:exampilot/services/study_session_platform_bridge.dart';
import 'package:exampilot/services/study_timer_engine.dart';
import 'package:exampilot/widgets/study_timer_formatters.dart';

class _FakeNotificationRecord {
  final int id;
  final AppNotificationType type;
  final String title;
  final String body;
  final String? payload;
  final bool ongoing;

  const _FakeNotificationRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.payload,
    this.ongoing = false,
  });
}

class _TestNotificationService implements NotificationService {
  bool throwOnDispatch = false;
  final List<_FakeNotificationRecord> immediateLogs = [];
  final List<int> cancelledIds = [];

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
      throw StateError('Simulated notification failure');
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
    return const NotificationDispatchResult(succeeded: true);
  }

  int cancelAllCount = 0;

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCount++;
  }

  @override
  Future<List<int>> getPendingNotificationIds() async => const [];
}

class _TestPermissionService implements NotificationPermissionService {
  NotificationPermissionStatus status = const NotificationPermissionStatus(
    notificationsGranted: true,
    exactAlarmsGranted: true,
  );

  @override
  Future<NotificationPermissionStatus> checkStatus() async => status;

  @override
  Future<bool> requestNotificationPermission() async =>
      status.notificationsGranted;

  @override
  Future<bool> requestExactAlarmPermission() async => status.exactAlarmsGranted;

  @override
  Future<bool> openSystemNotificationSettings() async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SessionRepository sessionRepo;
  late FakeTimerClock clock;
  late StudyTimerEngine engine;
  late _TestNotificationService notifService;
  late _TestPermissionService permService;
  late FakeStudySessionBridge sessionBridge;
  late StudyNotificationCoordinator coordinator;

  const testSubject = Subject(
    id: 'subj_mobile',
    name: 'Lập trình di động',
    description: 'Flutter & Android',
  );

  const testProfile = UserProfile(
    name: 'An',
    reminderEnabled: true,
    notifySessionStart: true,
    notifyBreakStart: true,
    notifyBreakEnd: true,
  );

  setUp(() async {
    WebSessionStorage.resetAllSimulatedStorageForTesting();
    sessionRepo = SessionRepository(useWebPreview: true);
    clock = FakeTimerClock(DateTime.utc(2026, 11, 13, 8, 0, 0));
    engine = StudyTimerEngine(
      repository: sessionRepo,
      clock: clock,
      autoStartHeartbeat: true,
      autoStartUiTicker: true,
      bindLifecycleObserver: false,
    );

    notifService = _TestNotificationService();
    permService = _TestPermissionService();
    sessionBridge = FakeStudySessionBridge();

    coordinator = StudyNotificationCoordinator(
      initialProfile: testProfile,
      notificationService: notifService,
      permissionService: permService,
      sessionBridge: sessionBridge,
      clock: clock,
    );
    await coordinator.initialize();
    coordinator.bindTimerEngine(engine);
  });

  tearDown(() async {
    coordinator.dispose();
    engine.dispose();
  });

  group('Nhóm A - Start & Stable Ongoing Notification', () {
    test(
      'Bắt đầu phiên tạo ongoing notification với ID ổn định và setOngoing(true)',
      () async {
        final session = await engine.startSession(
          subject: testSubject,
          plannedStudyMinutes: 25,
          plannedBreakMinutes: 5,
        );
        expect(session.id, isNotEmpty);

        final ongoingNotifs = notifService.immediateLogs
            .where((n) => n.id == NotificationIds.sessionOngoing(session.id))
            .toList();

        expect(ongoingNotifs, isNotEmpty);
        final latest = ongoingNotifs.last;
        expect(latest.ongoing, isTrue);
        expect(latest.title, 'ExamPilot · Đang học');
        expect(latest.body, contains('Môn học: Lập trình di động'));
        expect(latest.body, contains('Thời gian: 00:00:00'));

        // Kiểm tra native service bridge đã nhận lệnh startOrUpdate
        expect(sessionBridge.calls, isNotEmpty);
        final bridgeCall = sessionBridge.calls.first;
        expect(bridgeCall['action'], 'startOrUpdate');
        expect(bridgeCall['sessionId'], session.id);
        expect(bridgeCall['title'], 'ExamPilot · Đang học');
        expect(bridgeCall['content'], contains('Thời gian: 00:00:00'));
      },
    );

    test(
      'Không tạo ID notification mới trùng lặp qua các nhịp heartbeat',
      () async {
        final session = await engine.startSession(
          subject: testSubject,
          plannedStudyMinutes: 25,
        );

        final stableId = NotificationIds.sessionOngoing(session.id);

        // Nhịp heartbeat 1 (sau 15s)
        clock.advance(const Duration(seconds: 15));
        await engine.heartbeat();

        // Nhịp heartbeat 2 (sau 30s)
        clock.advance(const Duration(seconds: 15));
        await engine.heartbeat();

        final ongoingNotifs = notifService.immediateLogs
            .where((n) => n.id == stableId)
            .toList();

        // Cùng 1 ID notification được cập nhật tiến trình
        expect(ongoingNotifs.length, greaterThanOrEqualTo(2));
        for (final n in ongoingNotifs) {
          expect(n.id, stableId);
          expect(n.ongoing, isTrue);
        }

        // Không có ID notification ngẫu nhiên nào khác được tạo cho session này
        final uniqueIds = notifService.immediateLogs.map((e) => e.id).toSet();
        expect(uniqueIds, {stableId});
      },
    );
  });

  group('Nhóm B - Pause & Resume', () {
    test(
      'Pause cập nhật tiêu đề thành Đã tạm dừng và thời gian học đóng băng',
      () async {
        final session = await engine.startSession(
          subject: testSubject,
          plannedStudyMinutes: 25,
        );
        expect(session.id, isNotEmpty);

        // Học 10 phút (600 giây)
        clock.advance(const Duration(minutes: 10));
        await engine.heartbeat();

        // Tạm dừng
        await engine.pauseSession();

        final pauseNotifs = notifService.immediateLogs
            .where((n) => n.title == 'ExamPilot · Đã tạm dừng')
            .toList();
        expect(pauseNotifs, isNotEmpty);
        final pauseNotif = pauseNotifs.last;
        expect(pauseNotif.ongoing, isTrue);
        expect(pauseNotif.body, contains('Thời gian học: 00:10:00'));

        // Khi Pause, trôi thêm 5 phút thời gian vật lý -> thời gian học vẫn đóng băng ở 00:10:00
        clock.advance(const Duration(minutes: 5));
        expect(engine.getCurrentElapsedSeconds(), 600);
        expect(
          formatNotificationDuration(engine.getCurrentElapsedSeconds()),
          '00:10:00',
        );
      },
    );

    test(
      'Resume cập nhật lại cùng notification thành Đang học và tiếp tục đếm',
      () async {
        final session = await engine.startSession(
          subject: testSubject,
          plannedStudyMinutes: 25,
        );

        clock.advance(const Duration(minutes: 10));
        await engine.pauseSession();

        // Tiếp tục học
        await engine.resumeSession();

        final resumedNotifs = notifService.immediateLogs
            .where((n) => n.id == NotificationIds.sessionOngoing(session.id))
            .toList();
        final latest = resumedNotifs.last;
        expect(latest.title, 'ExamPilot · Đang học');
        expect(latest.body, contains('Thời gian: 00:10:00'));
        expect(latest.ongoing, isTrue);
      },
    );
  });

  group('Nhóm C - Break States', () {
    test(
      'Chuyển sang InBreak: Notification hiển thị thời gian nghỉ riêng biệt',
      () async {
        final session = await engine.startSession(
          subject: testSubject,
          plannedStudyMinutes: 25,
          plannedBreakMinutes: 5,
        );
        expect(session.id, isNotEmpty);

        clock.advance(const Duration(minutes: 10));
        await engine.startBreak();

        final breakNotifs = notifService.immediateLogs
            .where((n) => n.title == 'ExamPilot · Đang nghỉ')
            .toList();
        expect(breakNotifs, isNotEmpty);
        final breakNotif = breakNotifs.last;
        expect(breakNotif.ongoing, isTrue);
        expect(breakNotif.body, contains('Thời gian nghỉ: 00:00:00'));

        // Nghỉ 3 phút
        clock.advance(const Duration(minutes: 3));
        await engine.heartbeat();

        final updatedBreak = notifService.immediateLogs
            .where((n) => n.title == 'ExamPilot · Đang nghỉ')
            .toList();
        expect(updatedBreak.last.body, contains('Thời gian nghỉ: 00:03:00'));
        // Thời gian học thực tế không bị nhầm lẫn với thời gian nghỉ
        expect(engine.getCurrentElapsedSeconds(), 600);
      },
    );

    test(
      'Kết thúc nghỉ (endBreak) khôi phục lại notification Đang học',
      () async {
        final session = await engine.startSession(
          subject: testSubject,
          plannedStudyMinutes: 25,
          plannedBreakMinutes: 5,
        );
        expect(session.id, isNotEmpty);

        clock.advance(const Duration(minutes: 10));
        await engine.startBreak();
        clock.advance(const Duration(minutes: 3));

        // Quay lại học
        await engine.endBreak();

        final runningNotifs = notifService.immediateLogs
            .where((n) => n.id == NotificationIds.sessionOngoing(session.id))
            .toList();
        final latest = runningNotifs.last;
        expect(latest.title, 'ExamPilot · Đang học');
        expect(latest.body, contains('Thời gian: 00:10:00'));
        expect(latest.ongoing, isTrue);
      },
    );
  });

  group('Nhóm D - Complete Session & Congratulation Alert', () {
    test(
      'Complete xóa ongoing notification và gửi notification chúc mừng đúng một lần',
      () async {
        final session = await engine.startSession(
          subject: testSubject,
          taskTitleSnapshot: 'Bài tập tuần 5',
          plannedStudyMinutes: 25,
        );

        // Học 20 phút (1200 giây)
        clock.advance(const Duration(minutes: 20));
        await engine.heartbeat();

        // Hoàn thành phiên
        await engine.completeSession();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final ongoingId = NotificationIds.sessionOngoing(session.id);
        final completionId = NotificationIds.sessionCompleted(session.id);

        // Ongoing notification đã bị hủy
        expect(notifService.cancelledIds, contains(ongoingId));

        // Foreground service native đã nhận lệnh dừng
        expect(sessionBridge.isStopped, isTrue);

        // Thông báo chúc mừng được gửi duy nhất 1 lần
        final completionNotifs = notifService.immediateLogs
            .where((n) => n.id == completionId)
            .toList();
        expect(completionNotifs.length, 1);

        final congrat = completionNotifs.first;
        expect(congrat.ongoing, isFalse);
        expect(congrat.type, AppNotificationType.sessionCompleted);
        expect(congrat.title, 'Chúc mừng An! Bạn đã hoàn thành phiên học.');
        expect(congrat.body, contains('Lập trình di động (Bài tập tuần 5)'));
        expect(congrat.body, contains('20 phút'));
        expect(coordinator.completedNotifiedSessionIds, contains(session.id));

        // Lần heartbeat sau không gửi trùng
        await engine.heartbeat();
        final duplicateCheck = notifService.immediateLogs
            .where((n) => n.id == completionId)
            .toList();
        expect(duplicateCheck.length, 1);
      },
    );

    test(
      'Thời lượng trong thông báo chúc mừng lấy từ verified study time, không tính break',
      () async {
        await engine.startSession(
          subject: testSubject,
          plannedStudyMinutes: 50,
          plannedBreakMinutes: 10,
        );

        // Học 15 phút (900s)
        clock.advance(const Duration(minutes: 15));
        await engine.heartbeat();

        // Nghỉ 10 phút (600s)
        await engine.startBreak();
        clock.advance(const Duration(minutes: 10));

        // Học thêm 15 phút (900s) -> tổng học = 30 phút (1800s)
        await engine.endBreak();
        clock.advance(const Duration(minutes: 15));
        await engine.completeSession();
        await Future<void>.delayed(Duration.zero);

        final lastEnded = engine.lastEndedSession!;
        expect(lastEnded.verifiedStudySeconds, 1800);
        expect(lastEnded.accumulatedBreakSeconds, 600);

        final congrat = notifService.immediateLogs.firstWhere(
          (n) => n.type == AppNotificationType.sessionCompleted,
        );
        // Thời lượng chúc mừng ghi đúng 30 phút học thực tế, không cộng 10 phút nghỉ
        expect(congrat.body, contains('30 phút'));
        expect(congrat.body, isNot(contains('40 phút')));
      },
    );
  });

  group('Nhóm E - Cancel & Recovery Boundary Handling', () {
    test(
      'Hủy phiên (Cancel) hủy ongoing notification và KHÔNG gửi chúc mừng',
      () async {
        final session = await engine.startSession(
          subject: testSubject,
          plannedStudyMinutes: 25,
        );

        clock.advance(const Duration(minutes: 5));
        await engine.cancelSession();

        // Ongoing notification bị hủy
        expect(
          notifService.cancelledIds,
          contains(NotificationIds.sessionOngoing(session.id)),
        );
        expect(sessionBridge.isStopped, isTrue);

        // Tuyệt đối không gửi notification chúc mừng
        final congratList = notifService.immediateLogs
            .where((n) => n.type == AppNotificationType.sessionCompleted)
            .toList();
        expect(congratList, isEmpty);
        expect(coordinator.completedNotifiedSessionIds, isEmpty);
      },
    );

    test(
      'InterruptedPending dừng ongoing notification và không gửi chúc mừng',
      () async {
        // Giả lập phiên bị gián đoạn cần phục hồi
        final pendingSession = StudySession(
          id: 'interrupted_1',
          subjectNameSnapshot: 'Hệ điều hành',
          startedAt: clock.nowUtc().subtract(const Duration(minutes: 40)),
          plannedStudyMinutes: 30,
          plannedBreakMinutes: 5,
          verifiedStudySeconds: 600,
          status: StudySessionStatus.interruptedPending,
          studyDate: '2026-11-13',
          lastHeartbeatAt: clock.nowUtc().subtract(const Duration(minutes: 30)),
          lastStateChangedAt: clock.nowUtc().subtract(
            const Duration(minutes: 30),
          ),
        );
        await sessionRepo.createSession(pendingSession);

        // Khôi phục trạng thái
        await engine.restoreSessionState();
        expect(engine.currentStatus, StudySessionStatus.interruptedPending);

        // Khi pending xác nhận: không có ongoing notification và không có chúc mừng
        expect(
          notifService.immediateLogs.where(
            (n) => n.type == AppNotificationType.sessionCompleted,
          ),
          isEmpty,
        );
        expect(sessionBridge.isStopped, isTrue);
      },
    );
  });

  group('Nhóm F - Permissions, Bridge Errors & Robustness', () {
    test(
      'Khi từ chối quyền thông báo hoặc plugin lỗi: StudyTimerEngine vẫn hoạt động bình thường',
      () async {
        permService.status = const NotificationPermissionStatus(
          notificationsGranted: false,
          exactAlarmsGranted: false,
        );
        notifService.throwOnDispatch = true;

        final session = await engine.startSession(
          subject: testSubject,
          plannedStudyMinutes: 25,
        );
        expect(session.status, StudySessionStatus.running);

        clock.advance(const Duration(minutes: 5));
        await engine.pauseSession();
        expect(engine.currentStatus, StudySessionStatus.paused);

        await engine.resumeSession();
        expect(engine.currentStatus, StudySessionStatus.running);

        await engine.completeSession();
        await Future<void>.delayed(Duration.zero);
        expect(engine.activeSession, isNull);
        expect(engine.lastEndedSession!.status, StudySessionStatus.completed);
        expect(engine.lastEndedSession!.verifiedStudySeconds, 300);
      },
    );

    test(
      'Tắt thông báo trong Profile dừng ngay ongoing notification và native service',
      () async {
        final session = await engine.startSession(
          subject: testSubject,
          plannedStudyMinutes: 25,
        );

        // Tắt nhắc nhở trong Profile
        await coordinator.applyProfile(
          const UserProfile(reminderEnabled: false),
        );

        expect(
          notifService.cancelledIds,
          contains(NotificationIds.sessionOngoing(session.id)),
        );
        expect(sessionBridge.isStopped, isTrue);
      },
    );
  });
}

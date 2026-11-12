import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/study_session.dart';
import 'package:exampilot/models/study_streak.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/models/user_profile.dart';
import 'package:exampilot/repositories/profile_repository.dart';
import 'package:exampilot/repositories/session_repository.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/screens/app_shell.dart';
import 'package:exampilot/services/session_storage.dart';
import 'package:exampilot/services/study_timer_engine.dart';
import 'package:exampilot/services/web_storage.dart';
import 'package:exampilot/widgets/weekly_goal_summary_card.dart';

/// Repository giả lập lỗi ghi xuống storage tạm thời để kiểm thử retry & rollback.
class _FlakySessionRepository extends SessionRepository {
  bool failNextUpdate = false;
  bool failNextCreate = false;
  int updateCallCount = 0;

  _FlakySessionRepository({super.dbHelper});

  @override
  Future<StudySession> createSession(StudySession session) async {
    if (failNextCreate) {
      failNextCreate = false;
      throw Exception('Simulated create storage failure');
    }
    return super.createSession(session);
  }

  @override
  Future<void> updateSession(StudySession session) async {
    updateCallCount++;
    if (failNextUpdate) {
      failNextUpdate = false;
      throw Exception('Simulated transient SQLite lock');
    }
    return super.updateSession(session);
  }
}

Future<Database> _openCleanV7Db(Directory tempDir, String fileName) async {
  return databaseFactoryFfi.openDatabase(
    p.join(tempDir.path, fileName),
    options: OpenDatabaseOptions(
      version: DatabaseHelper.databaseVersion,
      onConfigure: DatabaseHelper.configureDatabase,
      onCreate: (db, version) async {
        await DatabaseHelper.instance.createForTesting(db, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await DatabaseHelper.instance.upgradeForTesting(
          db,
          oldVersion,
          newVersion,
        );
      },
    ),
  );
}

StudySession _completedSession({
  required String id,
  required String studyDate,
  required int verifiedStudySeconds,
  int accumulatedBreakSeconds = 0,
  String? scheduledSessionId,
}) {
  final parsed = StudyStreak.parseDateKey(studyDate);
  final startUtc = DateTime.utc(parsed.year, parsed.month, parsed.day, 8, 0);
  return StudySession(
    id: id,
    subjectId: 'subj_math',
    subjectNameSnapshot: 'Toán cao cấp',
    startedAt: startUtc,
    endedAt: startUtc.add(Duration(seconds: verifiedStudySeconds)),
    lastHeartbeatAt: startUtc.add(Duration(seconds: verifiedStudySeconds)),
    lastStateChangedAt: startUtc,
    studyDate: studyDate,
    verifiedStudySeconds: verifiedStudySeconds,
    accumulatedBreakSeconds: accumulatedBreakSeconds,
    status: StudySessionStatus.completed,
    scheduledSessionId: scheduledSessionId,
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  Database? openTestDb;
  late SessionRepository sessionRepo;
  late SubjectRepository subjectRepo;
  late TaskRepository taskRepo;
  late FakeTimerClock clock;

  const subjectMath = Subject(
    id: 'subj_math',
    name: 'Giải tích 1',
    description: 'Giới hạn và Tích phân',
    color: Color(0xFF3B5BDB),
  );

  StudyTask sampleTask() => StudyTask(
    id: 'task_math_1',
    title: 'Giải 20 bài tập Tích phân',
    subjectId: 'subj_math',
    subject: 'Giải tích 1',
    deadline: DateTime(2026, 11, 20),
    estimatedMinutes: 45,
  );

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('exampilot_phase2_');
    WebSessionStorage.resetAllSimulatedStorageForTesting();
    WebStreakStorage.clearProfile();
    WebStreakStorage.clearStudyActivitiesAndDates();
    DatabaseHelper.instance.setDatabaseForTesting(null);

    openTestDb = await _openCleanV7Db(tempDir, 'phase2_timer.db');
    DatabaseHelper.instance.setDatabaseForTesting(openTestDb);

    subjectRepo = SubjectRepository(dbHelper: DatabaseHelper.instance);
    taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);
    sessionRepo = SessionRepository(dbHelper: DatabaseHelper.instance);

    await subjectRepo.insertSubject(subjectMath);
    await taskRepo.insertTask(sampleTask());

    clock = FakeTimerClock(
      DateTime.utc(2026, 11, 12, 2, 0, 0), // 09:00:00 tại UTC+7
      initialLocalOffset: const Duration(hours: 7),
    );
  });

  tearDown(() async {
    DatabaseHelper.instance.setDatabaseForTesting(null);
    if (openTestDb != null && openTestDb!.isOpen) {
      await openTestDb!.close();
    }
    openTestDb = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  StudyTimerEngine makeEngine({
    SessionRepository? repo,
    FakeTimerClock? customClock,
    bool autoStartHeartbeat = false,
    Duration heartbeatInterval = const Duration(seconds: 15),
    Future<void> Function()? onSessionsChanged,
  }) {
    return StudyTimerEngine(
      repository: repo ?? sessionRepo,
      clock: customClock ?? clock,
      autoStartHeartbeat: autoStartHeartbeat,
      heartbeatInterval: heartbeatInterval,
      onSessionsChanged: onSessionsChanged,
    );
  }

  group('Nhóm A - Timer State Machine', () {
    test(
      '1. Bắt đầu phiên theo môn học lưu snapshot và giữ ổn định khi đổi tên môn',
      () async {
        final engine = makeEngine();
        addTearDown(engine.dispose);

        final session = await engine.startSession(
          subject: subjectMath,
          sessionMode: StudySessionMode.pomodoro25_5,
          plannedStudyMinutes: 25,
          plannedBreakMinutes: 5,
        );

        expect(engine.isRunning, isTrue);
        expect(engine.currentStatus, StudySessionStatus.running);
        expect(session.subjectId, 'subj_math');
        expect(session.subjectNameSnapshot, 'Giải tích 1');
        expect(
          session.subjectColorSnapshot,
          const Color(0xFF3B5BDB).toARGB32(),
        );
        expect(session.taskId, isNull);
        expect(session.taskTitleSnapshot, isNull);
        expect(session.studyDate, '2026-11-12');
        expect(session.verifiedStudySeconds, 0);

        // Đổi tên môn học không được làm thay đổi snapshot lịch sử phiên
        await subjectRepo.updateSubject(
          const Subject(
            id: 'subj_math',
            name: 'Giải tích nâng cao',
            description: 'Mới',
          ),
        );
        final persisted = await sessionRepo.getSessionById(session.id);
        expect(persisted!.subjectNameSnapshot, 'Giải tích 1');
      },
    );

    test(
      '2. Bắt đầu phiên theo công việc (kèm hoặc không kèm scheduledSessionId)',
      () async {
        final engine = makeEngine();
        addTearDown(engine.dispose);

        final session = await engine.startSession(
          task: sampleTask(),
          subject: subjectMath,
          notes: 'Học ngoài lịch AI đề xuất',
        );

        expect(session.taskId, 'task_math_1');
        expect(session.taskTitleSnapshot, 'Giải 20 bài tập Tích phân');
        expect(session.subjectId, 'subj_math');
        expect(session.subjectNameSnapshot, 'Giải tích 1');
        expect(session.scheduledSessionId, isNull);
        expect(session.notes, 'Học ngoài lịch AI đề xuất');
      },
    );

    test(
      '3. Không cho phép tồn tại hai phiên hoạt động đồng thời (Running/Paused/InBreak/InterruptedPending)',
      () async {
        final engine = makeEngine();
        addTearDown(engine.dispose);

        await engine.startSession(subject: subjectMath);
        await expectLater(
          engine.startSession(subject: subjectMath),
          throwsStateError,
        );

        await engine.pauseSession();
        await expectLater(
          engine.startSession(subject: subjectMath),
          throwsStateError,
        );

        await engine.resumeSession();
        await engine.startBreak();
        await expectLater(
          engine.startSession(subject: subjectMath),
          throwsStateError,
        );

        // Cả engine mới khởi tạo từ cùng storage chưa khôi phục cũng không được mở phiên thứ 2
        final secondEngine = makeEngine();
        addTearDown(secondEngine.dispose);
        await expectLater(
          secondEngine.startSession(subject: subjectMath),
          throwsStateError,
        );

        await secondEngine.restoreSessionState();
        await expectLater(
          secondEngine.startSession(subject: subjectMath),
          throwsStateError,
        );
      },
    );

    test(
      '4. Pause -> Resume -> Running và đặt lại mốc pha chính xác',
      () async {
        final engine = makeEngine();
        addTearDown(engine.dispose);

        await engine.startSession(subject: subjectMath);
        clock.advance(const Duration(seconds: 40));

        final paused = await engine.pauseSession();
        expect(paused.status, StudySessionStatus.paused);
        expect(paused.verifiedStudySeconds, 40);
        expect(engine.isPaused, isTrue);

        clock.advance(const Duration(minutes: 10));
        expect(engine.getCurrentElapsedSeconds(), 40);

        final resumed = await engine.resumeSession();
        expect(resumed.status, StudySessionStatus.running);
        expect(resumed.verifiedStudySeconds, 40);

        clock.advance(const Duration(seconds: 25));
        expect(engine.getCurrentElapsedSeconds(), 65);
      },
    );

    test(
      '5. Start Break -> End Break không tự ép nghỉ/dừng khi vượt planned minutes',
      () async {
        final engine = makeEngine();
        addTearDown(engine.dispose);

        await engine.startSession(
          subject: subjectMath,
          sessionMode: StudySessionMode.pomodoro25_5,
          plannedStudyMinutes: 25,
          plannedBreakMinutes: 5,
        );

        // Học vượt mốc dự kiến 25 phút tới 30 phút vẫn tiếp tục Running bình thường
        clock.advance(const Duration(minutes: 30));
        expect(engine.isRunning, isTrue);
        expect(engine.hasReachedPlannedStudyDuration, isTrue);
        expect(engine.getCurrentElapsedSeconds(), 1800);

        final inBreak = await engine.startBreak();
        expect(inBreak.status, StudySessionStatus.inBreak);
        expect(inBreak.verifiedStudySeconds, 1800);
        expect(engine.isInBreak, isTrue);

        // Nghỉ 7 phút (> 5 phút dự kiến) vẫn giữ nguyên giờ học 1800s
        clock.advance(const Duration(minutes: 7));
        expect(engine.getCurrentElapsedSeconds(), 1800);
        expect(engine.getCurrentBreakSeconds(), 420);

        final resumed = await engine.endBreak();
        expect(resumed.status, StudySessionStatus.running);
        expect(resumed.verifiedStudySeconds, 1800);
        expect(resumed.accumulatedBreakSeconds, 420);
      },
    );

    test('6. Complete hợp lệ từ Running, Paused và InBreak', () async {
      final engine = makeEngine();
      addTearDown(engine.dispose);

      // Case 1: Complete từ Running
      await engine.startSession(subject: subjectMath);
      clock.advance(const Duration(minutes: 15));
      final doneFromRun = await engine.completeSession();
      expect(doneFromRun.status, StudySessionStatus.completed);
      expect(doneFromRun.verifiedStudySeconds, 900);
      expect(doneFromRun.endedAt, isNotNull);
      expect(engine.isIdle, isTrue);

      // Case 2: Complete từ Paused
      await engine.startSession(subject: subjectMath);
      clock.advance(const Duration(seconds: 100));
      await engine.pauseSession();
      clock.advance(const Duration(minutes: 5));
      final doneFromPause = await engine.completeSession();
      expect(doneFromPause.status, StudySessionStatus.completed);
      expect(doneFromPause.verifiedStudySeconds, 100);

      // Case 3: Complete từ InBreak chốt phần nghỉ vào break chứ không cộng vào giờ học
      await engine.startSession(subject: subjectMath);
      clock.advance(const Duration(seconds: 200));
      await engine.startBreak();
      clock.advance(const Duration(seconds: 90));
      final doneFromBreak = await engine.completeSession();
      expect(doneFromBreak.status, StudySessionStatus.completed);
      expect(doneFromBreak.verifiedStudySeconds, 200);
      expect(doneFromBreak.accumulatedBreakSeconds, 90);
    });

    test(
      '7. Cancel hợp lệ từ Running, Paused, InBreak và giữ lịch sử cũ',
      () async {
        final engine = makeEngine();
        addTearDown(engine.dispose);

        await engine.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 20));
        final cancelled = await engine.cancelSession();
        expect(cancelled.status, StudySessionStatus.cancelled);
        expect(cancelled.endedAt, isNotNull);
        expect(engine.isIdle, isTrue);

        final persisted = await sessionRepo.getSessionById(cancelled.id);
        expect(persisted, isNotNull);
        expect(persisted!.status, StudySessionStatus.cancelled);
      },
    );

    test('8. Từ chối mọi chuyển trạng thái không hợp lệ', () async {
      final engine = makeEngine();
      addTearDown(engine.dispose);

      // Từ Idle
      await expectLater(engine.pauseSession(), throwsStateError);
      await expectLater(engine.resumeSession(), throwsStateError);
      await expectLater(engine.startBreak(), throwsStateError);
      await expectLater(engine.endBreak(), throwsStateError);
      await expectLater(engine.completeSession(), throwsStateError);
      await expectLater(engine.cancelSession(), throwsStateError);

      // Từ Running
      await engine.startSession(subject: subjectMath);
      await expectLater(engine.resumeSession(), throwsStateError);
      await expectLater(engine.endBreak(), throwsStateError);

      // Từ Paused
      await engine.pauseSession();
      await expectLater(engine.pauseSession(), throwsStateError);
      await expectLater(engine.startBreak(), throwsStateError);
      await expectLater(engine.endBreak(), throwsStateError);

      // Từ InBreak
      await engine.resumeSession();
      await engine.startBreak();
      await expectLater(engine.pauseSession(), throwsStateError);
      await expectLater(engine.resumeSession(), throwsStateError);
      await expectLater(engine.startBreak(), throwsStateError);
    });

    test(
      '9. Không hoàn thành hoặc hủy phiên hai lần (kể cả khi bấm liên tiếp đồng thời)',
      () async {
        final engine = makeEngine();
        addTearDown(engine.dispose);

        await engine.startSession(subject: subjectMath);
        clock.advance(const Duration(seconds: 60));

        // Bấm completeSession đồng thời 2 lần -> chỉ lần đầu thành công, lần sau throws StateError
        final first = engine.completeSession();
        final second = engine.completeSession();
        final done = await first;
        expect(done.status, StudySessionStatus.completed);
        await expectLater(second, throwsStateError);

        // Hủy sau khi đã hoàn thành -> throws StateError
        await expectLater(engine.cancelSession(), throwsStateError);

        // Tạo phiên mới và hủy -> không thể hủy hay hoàn thành lại
        await engine.startSession(subject: subjectMath);
        await engine.cancelSession();
        await expectLater(engine.cancelSession(), throwsStateError);
        await expectLater(engine.completeSession(), throwsStateError);
      },
    );
  });

  group('Nhóm B - Time Calculation & Single Checkpoint Anchor', () {
    test('1-3. Tính chính xác elapsed ở Running, Paused và InBreak', () async {
      final engine = makeEngine();
      addTearDown(engine.dispose);

      await engine.startSession(subject: subjectMath);
      clock.advance(const Duration(seconds: 12));
      expect(engine.getCurrentElapsedSeconds(), 12);
      expect(engine.getCurrentBreakSeconds(), 0);

      await engine.pauseSession();
      clock.advance(const Duration(minutes: 4));
      expect(engine.getCurrentElapsedSeconds(), 12);
      expect(engine.getCurrentBreakSeconds(), 0);

      await engine.resumeSession();
      clock.advance(const Duration(seconds: 18));
      expect(engine.getCurrentElapsedSeconds(), 30);

      await engine.startBreak();
      clock.advance(const Duration(seconds: 45));
      expect(engine.getCurrentElapsedSeconds(), 30);
      expect(engine.getCurrentBreakSeconds(), 45);
    });

    test(
      '4-5. Heartbeat cộng đúng, bảo toàn phần lẻ mili-giây và không cộng trùng (chứng minh G8.8.2)',
      () async {
        final engine = makeEngine();
        addTearDown(engine.dispose);

        // T = 0.000s
        final s0 = await engine.startSession(subject: subjectMath);
        expect(s0.verifiedStudySeconds, 0);

        // T = 10.500s -> hiển thị 10s
        clock.advance(const Duration(seconds: 10, milliseconds: 500));
        expect(engine.getCurrentElapsedSeconds(), 10);

        // T = 15.400s (Heartbeat 1): chốt 15s, giữ phần lẻ .400s bằng anchor 15.000s
        clock.advance(const Duration(seconds: 4, milliseconds: 900));
        final hb1 = await engine.heartbeat();
        expect(hb1!.verifiedStudySeconds, 15);
        expect(
          hb1.lastHeartbeatAt,
          s0.startedAt.add(const Duration(seconds: 15)),
        );

        // T = 20.200s -> hiển thị đúng 20s (không cộng trùng thành 35s!)
        clock.advance(const Duration(seconds: 4, milliseconds: 800));
        expect(engine.getCurrentElapsedSeconds(), 20);

        // T = 30.600s (Heartbeat 2): nhờ giữ .400s từ lần trước, tổng chốt đạt chuẩn 30s
        clock.advance(const Duration(seconds: 10, milliseconds: 400));
        final hb2 = await engine.heartbeat();
        expect(hb2!.verifiedStudySeconds, 30);
        expect(
          hb2.lastHeartbeatAt,
          s0.startedAt.add(const Duration(seconds: 30)),
        );
        expect(engine.getCurrentElapsedSeconds(), 30);

        // T = 35.000s (Pause)
        clock.advance(const Duration(seconds: 4, milliseconds: 400));
        final paused = await engine.pauseSession();
        expect(paused.verifiedStudySeconds, 35);
      },
    );

    test('6-7. Heartbeat không tăng giờ học khi Paused hoặc InBreak', () async {
      final engine = makeEngine();
      addTearDown(engine.dispose);

      await engine.startSession(subject: subjectMath);
      clock.advance(const Duration(seconds: 50));
      await engine.pauseSession();

      clock.advance(const Duration(minutes: 3));
      final hbPause = await engine.heartbeat();
      expect(hbPause!.verifiedStudySeconds, 50);
      expect(hbPause.accumulatedBreakSeconds, 0);

      await engine.resumeSession();
      await engine.startBreak();
      clock.advance(const Duration(seconds: 35));
      final hbBreak = await engine.heartbeat();
      expect(hbBreak!.verifiedStudySeconds, 50);
      expect(hbBreak.accumulatedBreakSeconds, 35);
    });

    test(
      '8-9. Pause & Complete chốt chính xác và không tính thời gian nghỉ vào giờ học',
      () async {
        final engine = makeEngine();
        addTearDown(engine.dispose);

        await engine.startSession(subject: subjectMath);
        clock.advance(const Duration(seconds: 600));
        await engine.startBreak();
        clock.advance(const Duration(seconds: 900)); // Nghỉ 15 phút
        await engine.endBreak();
        clock.advance(const Duration(seconds: 120)); // Học thêm 2 phút
        final done = await engine.completeSession();

        expect(done.verifiedStudySeconds, 720);
        expect(done.accumulatedBreakSeconds, 900);

        // Streak yêu cầu >= 900s học thực tế -> không cộng 900s nghỉ nên chưa đạt Streak
        final streak = StudyStreak.fromSessions([done], now: clock.nowLocal());
        expect(streak.currentStreak, 0);
      },
    );
  });

  group('Nhóm C - Persistence, Heartbeat Loop & Lifecycle', () {
    test(
      '1-4. Lưu bền vững Running/Paused/InBreak và khôi phục an toàn khi tạo lại Engine',
      () async {
        final engine1 = makeEngine();
        final s = await engine1.startSession(subject: subjectMath);
        clock.advance(const Duration(seconds: 90));
        await engine1.heartbeat();

        final storedRun = await sessionRepo.getSessionById(s.id);
        expect(storedRun!.status, StudySessionStatus.running);
        expect(storedRun.verifiedStudySeconds, 90);

        clock.advance(const Duration(seconds: 30));
        await engine1.pauseSession();
        final storedPause = await sessionRepo.getSessionById(s.id);
        expect(storedPause!.status, StudySessionStatus.paused);
        expect(storedPause.verifiedStudySeconds, 120);

        await engine1.resumeSession();
        await engine1.startBreak();
        clock.advance(const Duration(seconds: 40));
        await engine1.heartbeat();
        final storedBreak = await sessionRepo.getSessionById(s.id);
        expect(storedBreak!.status, StudySessionStatus.inBreak);
        expect(storedBreak.accumulatedBreakSeconds, 40);
        engine1.dispose();

        // Giả lập app bị kill và mở lại sau 5 phút
        clock.advance(const Duration(minutes: 5));
        final engine2 = makeEngine();
        addTearDown(engine2.dispose);
        final recovery = await engine2.restoreSessionState();

        expect(recovery, isNotNull);
        expect(engine2.hasPendingRecovery, isTrue);
        expect(recovery!.interruptedFromStatus, StudySessionStatus.inBreak);
        expect(recovery.verifiedStudySeconds, 120);
        expect(recovery.verifiedBreakSeconds, 40);
      },
    );

    test('5. Không bao giờ tạo hai heartbeat loop song song', () async {
      final engine = makeEngine(
        autoStartHeartbeat: true,
        heartbeatInterval: const Duration(seconds: 15),
      );
      addTearDown(engine.dispose);

      expect(engine.activeHeartbeatTimerCount, 0);
      await engine.startSession(subject: subjectMath);
      expect(engine.activeHeartbeatTimerCount, 1);

      await engine.pauseSession();
      expect(engine.activeHeartbeatTimerCount, 0);

      await engine.resumeSession();
      expect(engine.activeHeartbeatTimerCount, 1);

      await engine.startBreak();
      expect(engine.activeHeartbeatTimerCount, 1);

      await engine.handleLifecycleChange(AppLifecycleState.paused);
      expect(engine.activeHeartbeatTimerCount, 0);

      await engine.handleLifecycleChange(AppLifecycleState.resumed);
      expect(engine.activeHeartbeatTimerCount, 1);

      await engine.completeSession();
      expect(engine.activeHeartbeatTimerCount, 0);
    });

    test(
      '6. Xử lý lỗi lưu storage an toàn khi Heartbeat/Complete và retry không mất/trùng thời gian',
      () async {
        final flakyRepo = _FlakySessionRepository(
          dbHelper: DatabaseHelper.instance,
        );
        final engine = makeEngine(repo: flakyRepo);
        addTearDown(engine.dispose);

        await engine.startSession(subject: subjectMath);
        clock.advance(const Duration(seconds: 15));

        // Giả lập DB lỗi tạm thời ở lần heartbeat 1
        flakyRepo.failNextUpdate = true;
        await expectLater(engine.heartbeat(), throwsException);
        expect(engine.lastSyncError, isNotNull);
        // Bộ nhớ KHÔNG cập nhật sai verifiedStudySeconds khi DB chưa lưu
        expect(engine.activeSession!.verifiedStudySeconds, 0);
        expect(engine.getCurrentElapsedSeconds(), 15);

        // Thêm 10s nữa và retry thành công -> chốt đúng 25s (không mất 15s cũ, không cộng trùng)
        clock.advance(const Duration(seconds: 10));
        final recoveredHb = await engine.heartbeat();
        expect(engine.lastSyncError, isNull);
        expect(recoveredHb!.verifiedStudySeconds, 25);

        // Giả lập lỗi khi Pause -> trạng thái vẫn là Running để user thử lại
        clock.advance(const Duration(seconds: 5));
        flakyRepo.failNextUpdate = true;
        await expectLater(engine.pauseSession(), throwsException);
        expect(engine.isRunning, isTrue);

        final retriedPause = await engine.pauseSession();
        expect(retriedPause.status, StudySessionStatus.paused);
        expect(retriedPause.verifiedStudySeconds, 30);
      },
    );

    test(
      '7. Lifecycle paused/resumed chốt checkpoint khi ngắn hạn (<8h) và chuyển Recovery nếu >8h',
      () async {
        final engine = makeEngine(autoStartHeartbeat: true);
        addTearDown(engine.dispose);

        await engine.startSession(subject: subjectMath);
        clock.advance(const Duration(seconds: 20));

        // Chuyển background 5 phút rồi quay lại -> tiến trình sống không tạo phiên mới và đồng bộ 320s
        await engine.handleLifecycleChange(AppLifecycleState.paused);
        clock.advance(const Duration(minutes: 5));
        await engine.handleLifecycleChange(AppLifecycleState.resumed);
        expect(engine.isRunning, isTrue);
        expect(engine.getCurrentElapsedSeconds(), 320);

        // Chuyển background hơn 8 giờ rồi quay lại -> chuyển Recovery bắt buộc
        await engine.handleLifecycleChange(AppLifecycleState.paused);
        clock.advance(const Duration(hours: 9));
        await engine.handleLifecycleChange(AppLifecycleState.resumed);
        expect(engine.hasPendingRecovery, isTrue);
        expect(engine.recoveryContext!.isStaleOver8Hours, isTrue);
        expect(engine.recoveryContext!.verifiedStudySeconds, 320);
      },
    );
  });

  group('Nhóm D - Interrupted Session Recovery', () {
    test(
      '1-3. Phục hồi đúng cho Running, Paused và InBreak bị gián đoạn',
      () async {
        // Running bị ngắt sau 10 phút học + 20 phút đóng app -> unverifiedGap = 1200s
        final engRun = makeEngine();
        await engRun.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 10));
        await engRun.heartbeat();
        engRun.dispose();

        clock.advance(const Duration(minutes: 20));
        final recEngRun = makeEngine();
        final ctxRun = await recEngRun.restoreSessionState();
        expect(ctxRun!.interruptedFromStatus, StudySessionStatus.running);
        expect(ctxRun.verifiedStudySeconds, 600);
        expect(ctxRun.unverifiedGapSeconds, 1200);
        await recEngRun.recoverInterruptedSession(
          action: StudyRecoveryAction.cancel,
        );
        recEngRun.dispose();

        // Paused bị ngắt -> unverifiedStudyGap == 0
        final engPause = makeEngine();
        await engPause.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 5));
        await engPause.pauseSession();
        engPause.dispose();

        clock.advance(const Duration(minutes: 30));
        final recEngPause = makeEngine();
        final ctxPause = await recEngPause.restoreSessionState();
        expect(ctxPause!.interruptedFromStatus, StudySessionStatus.paused);
        expect(ctxPause.verifiedStudySeconds, 300);
        expect(ctxPause.unverifiedGapSeconds, 0);
        await recEngPause.recoverInterruptedSession(
          action: StudyRecoveryAction.cancel,
        );
        recEngPause.dispose();

        // InBreak bị ngắt -> giữ giờ học + break đã chốt, unverifiedGapSeconds == 0 đối với giờ học
        final engBreak = makeEngine();
        await engBreak.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 15));
        await engBreak.startBreak();
        clock.advance(const Duration(minutes: 3));
        await engBreak.heartbeat();
        engBreak.dispose();

        clock.advance(const Duration(minutes: 25));
        final recEngBreak = makeEngine();
        final ctxBreak = await recEngBreak.restoreSessionState();
        expect(ctxBreak!.interruptedFromStatus, StudySessionStatus.inBreak);
        expect(ctxBreak.verifiedStudySeconds, 900);
        expect(ctxBreak.verifiedBreakSeconds, 180);
        expect(ctxBreak.unverifiedGapSeconds, 0);
        await recEngBreak.recoverInterruptedSession(
          action: StudyRecoveryAction.cancel,
        );
        recEngBreak.dispose();
      },
    );

    test(
      '4. Lựa chọn A (Tiếp tục học) giữ verified và bỏ hoàn toàn khoảng gián đoạn',
      () async {
        final engine1 = makeEngine();
        await engine1.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 12));
        await engine1.heartbeat();
        engine1.dispose();

        // Đóng app 40 phút
        clock.advance(const Duration(minutes: 40));
        final engine2 = makeEngine();
        addTearDown(engine2.dispose);
        await engine2.restoreSessionState();

        final continued = await engine2.recoverInterruptedSession(
          action: StudyRecoveryAction.continueStudying,
        );
        expect(continued.status, StudySessionStatus.running);
        expect(continued.verifiedStudySeconds, 720);
        expect(engine2.getCurrentElapsedSeconds(), 720);

        // Học tiếp 3 phút => 15 phút (900s), hoàn toàn bỏ qua 40 phút gián đoạn
        clock.advance(const Duration(minutes: 3));
        final done = await engine2.completeSession();
        expect(done.verifiedStudySeconds, 900);
      },
    );

    test(
      '5. Lựa chọn B (Kết thúc & Xác nhận) giới hạn chặt trong biên hợp lệ, cấm vượt gap',
      () async {
        final engine1 = makeEngine();
        await engine1.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 10));
        await engine1.heartbeat();
        engine1.dispose();

        // Đóng app 15 phút (900s gap)
        clock.advance(const Duration(minutes: 15));
        final engine2 = makeEngine();
        addTearDown(engine2.dispose);
        final ctx = await engine2.restoreSessionState();
        expect(ctx!.verifiedStudySeconds, 600);
        expect(ctx.maxConfirmableExtraSeconds, 900);

        // Cố gắng xác nhận vượt quá khoảng gián đoạn có thể xảy ra -> ném ArgumentError
        await expectLater(
          engine2.recoverInterruptedSession(
            action: StudyRecoveryAction.completeAndConfirm,
            confirmedExtraSeconds: 901,
          ),
          throwsArgumentError,
        );
        await expectLater(
          engine2.recoverInterruptedSession(
            action: StudyRecoveryAction.completeAndConfirm,
            confirmedExtraSeconds: -1,
          ),
          throwsArgumentError,
        );

        // Xác nhận thêm đúng 5 phút (300s) hợp lệ -> Tổng 900s
        final confirmed = await engine2.recoverInterruptedSession(
          action: StudyRecoveryAction.completeAndConfirm,
          confirmedExtraSeconds: 300,
        );
        expect(confirmed.status, StudySessionStatus.completed);
        expect(confirmed.verifiedStudySeconds, 900);
        expect(engine2.isIdle, isTrue);
      },
    );

    test(
      '6-7. Lựa chọn C (Hủy phiên) và không tự ghi nhận trước khi xác nhận qua nhiều lần mở app',
      () async {
        final engine1 = makeEngine();
        await engine1.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 20));
        await engine1.heartbeat();
        engine1.dispose();

        // Mở lại lần 1 sau 15 phút
        clock.advance(const Duration(minutes: 15));
        final engine2 = makeEngine();
        await engine2.restoreSessionState();
        expect(
          engine2.activeSession!.status,
          StudySessionStatus.interruptedPending,
        );
        expect(engine2.activeSession!.verifiedStudySeconds, 1200);
        engine2.dispose();

        // Không chọn gì mà tắt rồi mở lại lần 2 sau 10 phút nữa -> vẫn bảo toàn anchor cũ (25 phút gap)
        clock.advance(const Duration(minutes: 10));
        final engine3 = makeEngine();
        addTearDown(engine3.dispose);
        final ctx3 = await engine3.restoreSessionState();
        expect(ctx3!.verifiedStudySeconds, 1200);
        expect(ctx3.unverifiedGapSeconds, 1500);

        final cancelled = await engine3.recoverInterruptedSession(
          action: StudyRecoveryAction.cancel,
        );
        expect(cancelled.status, StudySessionStatus.cancelled);
        expect(engine3.isIdle, isTrue);
      },
    );

    test(
      '8. Phiên cũ hơn 8 giờ cảnh báo stale và giới hạn mức xác nhận an toàn',
      () async {
        final engine1 = makeEngine();
        await engine1.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 15));
        await engine1.heartbeat();
        engine1.dispose();

        // Quên 20 giờ sau mới mở app
        clock.advance(const Duration(hours: 20));
        final engine2 = makeEngine();
        addTearDown(engine2.dispose);
        final ctx = await engine2.restoreSessionState();

        expect(ctx!.isStaleOver8Hours, isTrue);
        expect(ctx.warningReason, isNotNull);
        expect(
          ctx.maxConfirmableExtraSeconds,
          StudyTimerEngine.maxConfirmableExtraCapSeconds,
        );
        expect(ctx.verifiedStudySeconds, 900);
      },
    );

    test(
      '9. Xử lý bản ghi SQLite hỏng và đồng hồ lùi khi mở lại không crash app',
      () async {
        // Chèn trực tiếp 1 bản ghi SQLite có timestamp started_at hỏng không parse được
        await openTestDb!.insert(DatabaseHelper.tableSessions, {
          DatabaseHelper.columnSessionId: 'corrupt_sess_1',
          DatabaseHelper.columnSessionSubjectId: 'subj_math',
          DatabaseHelper.columnSessionSubjectNameSnapshot: 'Giải tích 1',
          DatabaseHelper.columnSessionStartedAt: 'not-a-valid-utc-timestamp',
          DatabaseHelper.columnSessionEndedAt: null,
          DatabaseHelper.columnSessionLastHeartbeatAt: 'also-invalid',
          DatabaseHelper.columnSessionLastStateChangedAt: 'also-invalid',
          DatabaseHelper.columnSessionStudyDate: '2026-11-12',
          DatabaseHelper.columnSessionVerifiedStudySeconds: 300,
          DatabaseHelper.columnSessionAccumulatedBreakSeconds: 0,
          DatabaseHelper.columnSessionStatus: 'running',
          DatabaseHelper.columnSessionMode: 'stopwatch',
          DatabaseHelper.columnSessionPlannedStudyMinutes: 0,
          DatabaseHelper.columnSessionPlannedBreakMinutes: 0,
          DatabaseHelper.columnSessionNotes: '',
        });

        final engine = makeEngine();
        addTearDown(engine.dispose);
        final ctx = await engine.restoreSessionState();
        expect(ctx, isNull);

        final rows = await openTestDb!.query(
          DatabaseHelper.tableSessions,
          where: 'id = ?',
          whereArgs: ['corrupt_sess_1'],
        );
        expect(rows.single['status'], 'cancelled');
      },
    );
  });

  group('Nhóm E - Study Streak (G8.8.4), Weekly Goal & AppShell Sync', () {
    final nowWed = DateTime(2026, 11, 11, 15, 0);

    test(
      '1-4. Ngưỡng 900s, cộng dồn nhiều phiên cùng ngày và tối đa +1 Streak/ngày',
      () {
        // Đúng 900s (15 phút) -> đạt Streak
        final exact900 = StudyStreak.fromSessions([
          _completedSession(
            id: 's_exact',
            studyDate: '2026-11-11',
            verifiedStudySeconds: 900,
          ),
        ], now: nowWed);
        expect(exact900.currentStreak, 1);

        // 10 phút (600s) hoặc 899s -> chưa đạt
        final only600 = StudyStreak.fromSessions([
          _completedSession(
            id: 's_short',
            studyDate: '2026-11-11',
            verifiedStudySeconds: 600,
          ),
          _completedSession(
            id: 's_yesterday_899',
            studyDate: '2026-11-10',
            verifiedStudySeconds: 899,
          ),
        ], now: nowWed);
        expect(only600.currentStreak, 0);
        expect(only600.longestStreak, 0);

        // Hai phiên 10 phút cùng ngày -> 1200s >= 900s -> đạt 1 ngày
        final twoInDay = StudyStreak.fromSessions([
          _completedSession(
            id: 's_part1',
            studyDate: '2026-11-11',
            verifiedStudySeconds: 600,
          ),
          _completedSession(
            id: 's_part2',
            studyDate: '2026-11-11',
            verifiedStudySeconds: 600,
          ),
          _completedSession(
            id: 's_part3',
            studyDate: '2026-11-11',
            verifiedStudySeconds: 1800,
          ),
        ], now: nowWed);
        expect(twoInDay.currentStreak, 1);
        expect(twoInDay.activeDates, {'2026-11-11'});
      },
    );

    test(
      '5-7 & 9 & 12. Loại trừ Cancelled/Pending/Running/Break; tính học ngoài lịch & >240p',
      () {
        final startUtc = DateTime.utc(2026, 11, 11, 8, 0);
        final sessions = [
          StudySession(
            id: 'c_cancel',
            subjectNameSnapshot: 'Toán',
            startedAt: startUtc,
            endedAt: startUtc.add(const Duration(minutes: 30)),
            lastHeartbeatAt: startUtc,
            lastStateChangedAt: startUtc,
            studyDate: '2026-11-11',
            verifiedStudySeconds: 1800,
            status: StudySessionStatus.cancelled,
          ),
          StudySession(
            id: 'c_pending',
            subjectNameSnapshot: 'Toán',
            startedAt: startUtc,
            endedAt: null,
            lastHeartbeatAt: startUtc,
            lastStateChangedAt: startUtc,
            studyDate: '2026-11-11',
            verifiedStudySeconds: 1800,
            status: StudySessionStatus.interruptedPending,
          ),
          StudySession(
            id: 'c_run',
            subjectNameSnapshot: 'Toán',
            startedAt: startUtc,
            endedAt: null,
            lastHeartbeatAt: startUtc,
            lastStateChangedAt: startUtc,
            studyDate: '2026-11-11',
            verifiedStudySeconds: 1800,
            status: StudySessionStatus.running,
          ),
          // Hợp lệ 600s học + 1800s nghỉ -> không cộng break -> chưa đạt 900s
          _completedSession(
            id: 'c_break_only',
            studyDate: '2026-11-11',
            verifiedStudySeconds: 600,
            accumulatedBreakSeconds: 1800,
          ),
        ];

        expect(
          StudyStreak.fromSessions(sessions, now: nowWed).currentStreak,
          0,
        );
        expect(
          WeeklyGoalSummaryCard.calculateWeeklyTimerSeconds(
            sessions,
            now: nowWed,
          ),
          600, // Chỉ tính 600s từ phiên completed duy nhất
        );

        // Học ngoài lịch (`scheduledSessionId == null`) vượt 240 phút (= 300 phút = 18000s) vẫn tính đủ 100%
        final unscheduledHeavy = _completedSession(
          id: 'c_heavy_unsched',
          studyDate: '2026-11-11',
          verifiedStudySeconds: 18000,
          scheduledSessionId: null,
        );
        expect(
          StudyStreak.fromSessions([
            unscheduledHeavy,
          ], now: nowWed).currentStreak,
          1,
        );
        expect(
          WeeklyGoalSummaryCard.calculateWeeklyTimerSeconds([
            unscheduledHeavy,
          ], now: nowWed),
          18000,
        );
      },
    );

    testWidgets(
      '8, 10, 11. AppShell đồng bộ Study Streak và Weekly Goal ngay khi Timer hoàn thành, '
      'không cộng actualMinutes hay study_activities cũ',
      (tester) async {
        // Bật dữ liệu Web Preview cô lập với FakeTimerClock chạy tại đúng ngày local hôm nay
        WebStreakStorage.clearProfile();
        WebStreakStorage.clearStudyActivitiesAndDates();
        WebSessionStorage.resetAllSimulatedStorageForTesting();

        final webTaskRepo = TaskRepository(useWebPreview: true);
        final webSubjectRepo = SubjectRepository(useWebPreview: true);
        final webProfileRepo = ProfileRepository(useWebPreview: true);
        final webSessionRepo = SessionRepository(useWebPreview: true);

        await webProfileRepo.saveProfile(
          const UserProfile(weeklyTargetHours: 10, weeklyTargetTasks: 5),
        );

        // Ghi nhận hoàn thành task cũ kèm 120 phút actualMinutes thủ công
        await webTaskRepo.updateTaskStatus('task_1', TaskStatus.completed);
        await webTaskRepo.updateTaskAssessment('task_1', null, null, 120);

        final localToday = DateTime.now();
        final todayClock = FakeTimerClock(
          DateTime(
            localToday.year,
            localToday.month,
            localToday.day,
            10,
            0,
          ).toUtc(),
        );
        final engine = StudyTimerEngine(
          repository: webSessionRepo,
          clock: todayClock,
          autoStartHeartbeat: false,
        );
        addTearDown(engine.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: AppShell(
              taskRepository: webTaskRepo,
              subjectRepository: webSubjectRepo,
              profileRepository: webProfileRepo,
              sessionRepository: webSessionRepo,
              timerEngine: engine,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Mặc dù task_1 đã completed với 120 phút nhập tay & có study_activities cũ,
        // Study Streak MỚI và Weekly Goal vẫn bằng 0!
        expect(find.text('0 ngày liên tiếp'), findsOneWidget);
        expect(find.text('0 / 10 giờ'), findsOneWidget);
        expect(
          find.textContaining('Lịch sử 1 ngày theo quy tắc cũ'),
          findsOneWidget,
        );

        // Dùng Timer Engine học 30 phút (1800s) và hoàn thành phiên
        await engine.startSession(subject: subjectMath);
        todayClock.advance(const Duration(minutes: 30));
        await engine.completeSession();
        await tester.pumpAndSettle();

        // Weekly Goal và Study Streak đồng bộ tức thì mà không đếm 120p thủ công
        expect(find.text('1 ngày liên tiếp'), findsOneWidget);
        expect(find.text('0.5 / 10 giờ (30 phút)'), findsOneWidget);

        // Kiểm tra study_activities cũ vẫn được bảo toàn nguyên vẹn
        expect((await webTaskRepo.getAllActivities()).isNotEmpty, isTrue);
      },
    );
  });

  group('Nhóm F - Date Boundaries, Timezones & Clock Skew', () {
    test(
      '1-2. Phiên học qua 00:00 giữ nguyên studyDate ban đầu kể cả khi đổi múi giờ',
      () async {
        // Bắt đầu lúc 23:50:00 tối ngày 2026-11-11 tại UTC+7
        final crossMidnightClock = FakeTimerClock(
          DateTime.utc(2026, 11, 11, 16, 50, 0),
          initialLocalOffset: const Duration(hours: 7),
        );
        final engine = makeEngine(customClock: crossMidnightClock);
        addTearDown(engine.dispose);

        final s = await engine.startSession(subject: subjectMath);
        expect(s.studyDate, '2026-11-11');

        // Học liên tục 35 phút qua nửa đêm (sang 00:25 ngày 2026-11-12 tại UTC+7)
        // Đồng thời giả sử user đổi múi giờ sang +09:00 trong lúc học
        crossMidnightClock.setSimulatedLocalOffset(const Duration(hours: 9));
        crossMidnightClock.advance(const Duration(minutes: 35));
        final done = await engine.completeSession();

        // Toàn bộ 2100s vẫn dồn trọn vào 2026-11-11
        expect(done.studyDate, '2026-11-11');
        expect(done.verifiedStudySeconds, 2100);
      },
    );

    test(
      '3-5. Chuyển tháng, chuyển năm và năm nhuận bằng Pure Calendar-Day Stepping',
      () {
        // Chuyển tháng 31/01 -> 01/02 -> 02/02
        final monthCross = StudyStreak.fromActiveDates({
          '2026-01-30',
          '2026-01-31',
          '2026-02-01',
        }, now: DateTime(2026, 2, 1, 12));
        expect(monthCross.currentStreak, 3);

        // Chuyển năm 30/12/2025 -> 02/01/2026
        final yearCross = StudyStreak.fromActiveDates({
          '2025-12-30',
          '2025-12-31',
          '2026-01-01',
          '2026-01-02',
        }, now: DateTime(2026, 1, 2, 12));
        expect(yearCross.currentStreak, 4);
        expect(yearCross.longestStreak, 4);

        // Năm nhuận 2024: 28/02 -> 29/02 -> 01/03
        final leapStreak = StudyStreak.fromActiveDates({
          '2024-02-28',
          '2024-02-29',
          '2024-03-01',
        }, now: DateTime(2024, 3, 1, 12));
        expect(leapStreak.currentStreak, 3);

        // Năm không nhuận 2025: 28/02 -> 01/03 (chú ý 2025-02-29 không hợp lệ sẽ bị bỏ qua an toàn)
        final nonLeapStreak = StudyStreak.fromActiveDates({
          '2025-02-28',
          '2025-02-29',
          '2025-03-01',
        }, now: DateTime(2025, 3, 1, 12));
        expect(nonLeapStreak.currentStreak, 2);
        expect(nonLeapStreak.activeDates.contains('2025-02-29'), isFalse);
      },
    );

    test(
      '6. Timestamp ISO-8601 có UTC offset (+07:00) được chuẩn hóa UTC mà không sai studyDate',
      () {
        final decoded = StudySession.fromMap({
          'id': 'offset_s1',
          'subject_id': 'subj_math',
          'subject_name_snapshot': 'Giải tích 1',
          'started_at': '2026-11-11T23:40:00.000+07:00',
          'ended_at': '2026-11-12T00:05:00.000+07:00',
          'last_heartbeat_at': '2026-11-12T00:05:00.000+07:00',
          'last_state_changed_at': '2026-11-11T23:40:00.000+07:00',
          'study_date': '2026-11-11',
          'verified_study_seconds': 1500,
          'accumulated_break_seconds': 0,
          'status': 'completed',
          'session_mode': 'stopwatch',
          'planned_study_minutes': 0,
          'planned_break_minutes': 0,
          'notes': '',
        });

        expect(decoded.startedAt, DateTime.utc(2026, 11, 11, 16, 40));
        expect(decoded.endedAt, DateTime.utc(2026, 11, 11, 17, 5));
        expect(decoded.studyDate, '2026-11-11');
      },
    );

    test(
      '7. Đồng hồ hệ thống lùi không sinh thời gian âm và phát hiện bất thường lúc khôi phục',
      () async {
        final engine1 = makeEngine();
        await engine1.startSession(subject: subjectMath);
        clock.advance(const Duration(seconds: 300));
        await engine1.heartbeat();

        // Đột ngột chỉnh lùi đồng hồ 2 giờ khi đang Running
        clock.jumpWallClock(const Duration(hours: -2));
        expect(engine1.getCurrentElapsedSeconds(), 300);
        expect(engine1.clockAnomaly, StudyClockAnomaly.backward);
        engine1.dispose();

        // Khởi động lại khi đồng hồ vẫn lùi -> Recovery đánh dấu isClockMovedBackward
        final engine2 = makeEngine();
        addTearDown(engine2.dispose);
        final ctx = await engine2.restoreSessionState();
        expect(ctx!.isClockMovedBackward, isTrue);
        expect(ctx.unverifiedGapSeconds, 0);
        expect(ctx.verifiedStudySeconds, 300);

        // Chặn xác nhận thêm giây ảo khi clock đang lùi
        await expectLater(
          engine2.recoverInterruptedSession(
            action: StudyRecoveryAction.completeAndConfirm,
            confirmedExtraSeconds: 60,
          ),
          throwsArgumentError,
        );

        final done = await engine2.recoverInterruptedSession(
          action: StudyRecoveryAction.completeAndConfirm,
          confirmedExtraSeconds: 0,
        );
        expect(done.verifiedStudySeconds, 300);
      },
    );

    test(
      '8. Đồng hồ hệ thống nhảy tiến bất thường không được tự cộng thời gian chưa xác minh',
      () async {
        final engine = makeEngine();
        addTearDown(engine.dispose);

        await engine.startSession(subject: subjectMath);
        clock.advance(const Duration(seconds: 20)); // Học thật 20 giây

        // Chỉ chỉnh giờ hệ thống tiến +4 giờ (bộ đếm đơn điệu vẫn ở 20s)
        clock.jumpWallClock(const Duration(hours: 4));

        // Tuyệt đối KHÔNG trả về 14420 giây!
        expect(engine.getCurrentElapsedSeconds(), 20);
        expect(engine.clockAnomaly, StudyClockAnomaly.forwardJump);

        // Khi heartbeat phát hiện nhảy tiến bất thường -> giữ đúng 20s tin cậy và đưa vào Recovery
        final hb = await engine.heartbeat();
        expect(hb!.status, StudySessionStatus.interruptedPending);
        expect(hb.verifiedStudySeconds, 20);
        expect(engine.recoveryContext!.isClockJumpedForward, isTrue);
      },
    );
  });
}

import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/alarm_state.dart';
import 'package:exampilot/models/study_session.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/repositories/profile_repository.dart';
import 'package:exampilot/repositories/session_repository.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/screens/app_shell.dart';
import 'package:exampilot/services/alarm_service.dart';
import 'package:exampilot/services/alarm_state_manager.dart';
import 'package:exampilot/services/alarm_store.dart';
import 'package:exampilot/services/audio_playback_gateway.dart';
import 'package:exampilot/services/session_storage.dart';
import 'package:exampilot/services/sound_catalog.dart';
import 'package:exampilot/services/study_timer_engine.dart';
import 'package:exampilot/widgets/active_alarm_banner.dart';
import 'package:exampilot/widgets/task_card.dart';
import 'package:exampilot/widgets/task_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakeAudioGateway extends ChangeNotifier implements AudioPlaybackGateway {
  String? _previewSoundId;
  SoundGroup? _previewGroup;
  bool _alarmLoopPlaying = false;
  String? _activeAlarmSoundId;
  final List<String> playedLoops = [];

  @override
  String? get currentPreviewSoundId => _previewSoundId;
  @override
  SoundGroup? get currentPreviewGroup => _previewGroup;
  @override
  bool get isPreviewPlaying => _previewSoundId != null;
  @override
  bool get isAlarmLoopPlaying => _alarmLoopPlaying;
  @override
  String? get activeAlarmSoundId => _activeAlarmSoundId;

  @override
  Future<void> playPreview(String soundId, {required SoundGroup group}) async {
    _previewSoundId = soundId;
    _previewGroup = group;
    notifyListeners();
  }

  @override
  Future<void> stopPreview() async {
    _previewSoundId = null;
    _previewGroup = null;
    notifyListeners();
  }

  @override
  Future<void> playOneShotCue(
    String soundId, {
    required SoundGroup group,
  }) async {}

  @override
  Future<void> startAlarmLoop(String soundId) async {
    _alarmLoopPlaying = soundId != 'none';
    _activeAlarmSoundId = soundId;
    playedLoops.add(soundId);
    notifyListeners();
  }

  @override
  Future<void> stopAlarmLoop() async {
    _alarmLoopPlaying = false;
    _activeAlarmSoundId = null;
    notifyListeners();
  }
}

class _FakeAlarmBridge implements AlarmPlatformBridge {
  final Map<String, AlarmRecord> nativeStore = {};
  final List<AlarmRecord> scheduledCalls = [];
  final List<AlarmRecord> cancelledCalls = [];
  bool exactGranted = true;

  @override
  bool get supportsBackgroundAlarm => false;

  @override
  void attachListeners({
    required void Function(AlarmRecord record) onNativeAlarmUpdated,
    required void Function(String? alarmKey) onNativeLaunchStartRequested,
  }) {}

  Future<bool> canScheduleExactAlarms() async => exactGranted;

  @override
  Future<bool> scheduleAlarm(AlarmRecord record) async {
    scheduledCalls.add(record);
    nativeStore[record.alarmKey] = record;
    return exactGranted;
  }

  @override
  Future<void> cancelAlarm(AlarmRecord record) async {
    cancelledCalls.add(record);
    nativeStore.remove(record.alarmKey);
  }

  @override
  Future<void> cancelAllAlarms() async {
    nativeStore.clear();
  }

  @override
  Future<void> syncAlarmRecord(AlarmRecord record) async {
    nativeStore[record.alarmKey] = record;
  }

  @override
  Future<void> startRingingForeground(AlarmRecord record) async {
    nativeStore[record.alarmKey] = record;
  }

  @override
  Future<void> stopRingingForeground() async {}

  @override
  Future<List<AlarmRecord>> getStoredNativeAlarms() async =>
      nativeStore.values.toList();

  @override
  Future<({String action, String? alarmKey})?>
  consumePendingLaunchAction() async => null;

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Group B: Repository Query Verified Study Seconds For Task', () {
    Database? testDb;
    late SessionRepository sqliteRepo;
    late SessionRepository webRepo;

    setUp(() async {
      WebSessionStorage.resetAllSimulatedStorageForTesting();
      testDb = await openDatabase(
        inMemoryDatabasePath,
        version: 7,
        onConfigure: DatabaseHelper.configureDatabase,
        onCreate: (db, version) =>
            DatabaseHelper.instance.createForTesting(db, version),
      );
      DatabaseHelper.instance.setDatabaseForTesting(testDb);
      await testDb!.insert('subjects', {
        'id': 'subj_1',
        'name': 'Toán',
        'description': 'Môn toán',
        'icon_code': 0,
        'color_value': 0xFF2196F3,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await testDb!.insert('study_tasks', {
        'id': 'task_target',
        'title': 'Bài tập 1',
        'subject_id': 'subj_1',
        'subject': 'Toán',
        'deadline': '2026-11-20T10:00:00Z',
        'estimated_minutes': 60,
        'priority': 'medium',
        'status': 'todo',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await testDb!.insert('study_tasks', {
        'id': 'task_other',
        'title': 'Bài khác',
        'subject_id': 'subj_1',
        'subject': 'Toán',
        'deadline': '2026-11-20T10:00:00Z',
        'estimated_minutes': 60,
        'priority': 'medium',
        'status': 'todo',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await testDb!.insert('study_tasks', {
        'id': 'task_break',
        'title': 'Bài tập',
        'subject_id': 'subj_1',
        'subject': 'Toán',
        'deadline': '2026-11-20T10:00:00Z',
        'estimated_minutes': 60,
        'priority': 'medium',
        'status': 'todo',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      sqliteRepo = SessionRepository(dbHelper: DatabaseHelper.instance);
      webRepo = SessionRepository(useWebPreview: true);
    });

    tearDown(() async {
      DatabaseHelper.instance.setDatabaseForTesting(null);
      if (testDb != null && testDb!.isOpen) {
        await testDb!.close();
      }
    });

    test(
      'SQLite & Web: Trả về 0 khi không có phiên nào của công việc',
      () async {
        expect(await sqliteRepo.getVerifiedStudySecondsForTask('t_none'), 0);
        expect(await webRepo.getVerifiedStudySecondsForTask('t_none'), 0);
      },
    );

    test(
      'SQLite & Web: Chỉ cộng dồn các phiên completed, loại trừ running/paused/cancelled',
      () async {
        final now = DateTime.now().toUtc();
        final dateKey = '2026-11-13';

        final completed1 = StudySession(
          id: 's_comp_1',
          subjectId: 'subj_1',
          subjectNameSnapshot: 'Toán',
          taskId: 'task_target',
          taskTitleSnapshot: 'Bài tập 1',
          studyDate: dateKey,
          startedAt: now.subtract(const Duration(minutes: 30)),
          endedAt: now.subtract(const Duration(minutes: 20)),
          lastHeartbeatAt: now.subtract(const Duration(minutes: 20)),
          lastStateChangedAt: now.subtract(const Duration(minutes: 30)),
          verifiedStudySeconds: 400,
          status: StudySessionStatus.completed,
        );

        final completed2 = StudySession(
          id: 's_comp_2',
          subjectId: 'subj_1',
          subjectNameSnapshot: 'Toán',
          taskId: 'task_target',
          taskTitleSnapshot: 'Bài tập 1',
          studyDate: dateKey,
          startedAt: now.subtract(const Duration(minutes: 15)),
          endedAt: now.subtract(const Duration(minutes: 5)),
          lastHeartbeatAt: now.subtract(const Duration(minutes: 5)),
          lastStateChangedAt: now.subtract(const Duration(minutes: 15)),
          verifiedStudySeconds: 500,
          status: StudySessionStatus.completed,
        );

        final otherTask = StudySession(
          id: 's_other',
          subjectId: 'subj_1',
          subjectNameSnapshot: 'Toán',
          taskId: 'task_other',
          taskTitleSnapshot: 'Bài khác',
          studyDate: dateKey,
          startedAt: now.subtract(const Duration(minutes: 40)),
          endedAt: now.subtract(const Duration(minutes: 35)),
          lastHeartbeatAt: now.subtract(const Duration(minutes: 35)),
          lastStateChangedAt: now.subtract(const Duration(minutes: 40)),
          verifiedStudySeconds: 300,
          status: StudySessionStatus.completed,
        );

        final runningSession = StudySession(
          id: 's_running',
          subjectId: 'subj_1',
          subjectNameSnapshot: 'Toán',
          taskId: 'task_target',
          taskTitleSnapshot: 'Bài tập 1',
          studyDate: dateKey,
          startedAt: now.subtract(const Duration(minutes: 2)),
          lastHeartbeatAt: now,
          lastStateChangedAt: now.subtract(const Duration(minutes: 2)),
          verifiedStudySeconds: 120,
          status: StudySessionStatus.running,
        );

        final cancelledSession = StudySession(
          id: 's_cancelled',
          subjectId: 'subj_1',
          subjectNameSnapshot: 'Toán',
          taskId: 'task_target',
          taskTitleSnapshot: 'Bài tập 1',
          studyDate: dateKey,
          startedAt: now.subtract(const Duration(minutes: 60)),
          endedAt: now.subtract(const Duration(minutes: 55)),
          lastHeartbeatAt: now.subtract(const Duration(minutes: 55)),
          lastStateChangedAt: now.subtract(const Duration(minutes: 60)),
          verifiedStudySeconds: 300,
          status: StudySessionStatus.cancelled,
        );

        // Thêm vào SQLite
        await sqliteRepo.createSession(completed1);
        await sqliteRepo.createSession(completed2);
        await sqliteRepo.createSession(otherTask);
        await sqliteRepo.createSession(runningSession);
        await sqliteRepo.createSession(cancelledSession);

        // Thêm vào Web
        await webRepo.createSession(completed1);
        await webRepo.createSession(completed2);
        await webRepo.createSession(otherTask);
        await webRepo.createSession(runningSession);
        await webRepo.createSession(cancelledSession);

        // 400s + 500s = 900s (đủ 15 phút), không tính otherTask(300), running(120), cancelled(300)
        expect(
          await sqliteRepo.getVerifiedStudySecondsForTask('task_target'),
          900,
        );
        expect(
          await webRepo.getVerifiedStudySecondsForTask('task_target'),
          900,
        );
      },
    );

    test(
      'SQLite & Web: Không tính thời gian nghỉ (accumulatedBreakSeconds)',
      () async {
        final now = DateTime.now().toUtc();
        final sessionWithBreak = StudySession(
          id: 's_break',
          subjectId: 'subj_1',
          subjectNameSnapshot: 'Toán',
          taskId: 'task_break',
          taskTitleSnapshot: 'Bài tập',
          studyDate: '2026-11-13',
          startedAt: now.subtract(const Duration(minutes: 40)),
          endedAt: now,
          lastHeartbeatAt: now,
          lastStateChangedAt: now.subtract(const Duration(minutes: 40)),
          verifiedStudySeconds: 600, // 10 phút học
          accumulatedBreakSeconds: 1800, // 30 phút nghỉ
          status: StudySessionStatus.completed,
        );

        await sqliteRepo.createSession(sessionWithBreak);
        await webRepo.createSession(sessionWithBreak);

        // Chỉ tính đúng 600s, tuyệt đối loại trừ 1800s break
        expect(
          await sqliteRepo.getVerifiedStudySecondsForTask('task_break'),
          600,
        );
        expect(await webRepo.getVerifiedStudySecondsForTask('task_break'), 600);
      },
    );
  });

  group('Group B & C: TaskCard UI Rules', () {
    testWidgets(
      'TaskCard: Dưới 15 phút vô hiệu hóa Checkbox, hiển thị tiến độ và nút Bắt đầu học',
      (tester) async {
        final task = StudyTask(
          id: 'task_under15',
          title: 'Làm bài tập Hóa hữu cơ',
          subjectId: 'subj_chem',
          subject: 'Hóa học',
          deadline: DateTime.now().add(const Duration(days: 2)),
          status: TaskStatus.todo,
        );

        bool startStudyClicked = false;
        bool toggleClicked = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskCard(
                task: task,
                accumulatedStudySeconds: 480, // 8 phút
                onToggleComplete: (_) => toggleClicked = true,
                onTap: () {},
                onEdit: () {},
                onDelete: () {},
                onStartStudy: () => startStudyClicked = true,
              ),
            ),
          ),
        );

        // Kiểm tra nhãn và tiến độ
        expect(find.text('8/15 phút: chưa đủ điều kiện'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);

        // Nút Bắt đầu học
        final startStudyBtn = find.byKey(
          const ValueKey('task_card_start_study_button_task_under15'),
        );
        expect(startStudyBtn, findsOneWidget);
        await tester.tap(startStudyBtn);
        expect(startStudyClicked, isTrue);

        // Checkbox bị vô hiệu hóa (onChanged: null) -> tap không kích hoạt onToggleComplete
        final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
        expect(checkbox.onChanged, isNull);
        await tester.tap(find.byType(Checkbox));
        expect(toggleClicked, isFalse);
      },
    );

    testWidgets('TaskCard: Đạt 15 phút (900s) cho phép Checkbox hoàn thành', (
      tester,
    ) async {
      final task = StudyTask(
        id: 'task_eligible',
        title: 'Ôn tập Giải tích 1',
        subjectId: 'subj_math',
        subject: 'Toán học',
        deadline: DateTime.now().add(const Duration(days: 1)),
        status: TaskStatus.todo,
      );

      bool toggled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskCard(
              task: task,
              accumulatedStudySeconds: 900, // 15 phút
              onToggleComplete: (_) => toggled = true,
              onTap: () {},
              onEdit: () {},
              onDelete: () {},
            ),
          ),
        ),
      );

      expect(find.text('15/15 phút: đủ điều kiện'), findsOneWidget);
      final checkbox = tester.widget<Checkbox>(find.byType(Checkbox));
      expect(checkbox.onChanged, isNotNull);

      await tester.tap(find.byType(Checkbox));
      expect(toggled, isTrue);
    });

    testWidgets(
      'TaskCard: Công việc Quá hạn hiển thị nhãn và hai nút Học bù & Chuyển lịch',
      (tester) async {
        final overdueTask = StudyTask(
          id: 'task_overdue',
          title: 'Nộp báo cáo Thực tập',
          subjectId: 'subj_it',
          subject: 'Tin học',
          deadline: DateTime.now().subtract(const Duration(days: 2)), // Quá hạn
          status: TaskStatus.todo,
        );

        bool makeupClicked = false;
        bool rescheduleClicked = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskCard(
                task: overdueTask,
                accumulatedStudySeconds: 300,
                onToggleComplete: (_) {},
                onTap: () {},
                onEdit: () {},
                onDelete: () {},
                onStartStudy: () => makeupClicked = true,
                onReschedule: () => rescheduleClicked = true,
              ),
            ),
          ),
        );

        expect(find.text('Quá hạn'), findsOneWidget);

        final makeupBtn = find.byKey(
          const ValueKey('task_card_makeup_button_task_overdue'),
        );
        expect(makeupBtn, findsOneWidget);
        await tester.tap(makeupBtn);
        expect(makeupClicked, isTrue);

        final rescheduleBtn = find.byKey(
          const ValueKey('task_card_reschedule_button_task_overdue'),
        );
        expect(rescheduleBtn, findsOneWidget);
        await tester.tap(rescheduleBtn);
        expect(rescheduleClicked, isTrue);
      },
    );

    testWidgets(
      'TaskCard: Công việc đã hoàn thành KHÔNG hiển thị Học bù & Chuyển lịch',
      (tester) async {
        final completedOverdue = StudyTask(
          id: 'task_comp_past',
          title: 'Đã hoàn thành',
          subjectId: 'subj_it',
          subject: 'Tin học',
          deadline: DateTime.now().subtract(const Duration(days: 2)),
          status: TaskStatus.completed,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskCard(
                task: completedOverdue,
                accumulatedStudySeconds: 1200,
                onToggleComplete: (_) {},
                onTap: () {},
                onEdit: () {},
                onDelete: () {},
                onStartStudy: () {},
                onReschedule: () {},
              ),
            ),
          ),
        );

        expect(find.text('Quá hạn'), findsNothing);
        expect(find.text('Học bù'), findsNothing);
        expect(find.text('Chuyển lịch'), findsNothing);
      },
    );
  });

  group('Group B & C: TaskDetailSheet UI Rules', () {
    testWidgets(
      'TaskDetailSheet: Chưa đủ 15 phút vô hiệu hóa nút hoàn thành và hiển thị giải thích',
      (tester) async {
        final task = StudyTask(
          id: 'detail_task_under',
          title: 'Học ngữ pháp Tiếng Anh',
          subjectId: 'subj_en',
          subject: 'Tiếng Anh',
          deadline: DateTime.now().add(const Duration(days: 3)),
          status: TaskStatus.todo,
        );

        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        bool completeCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskDetailSheet(
                task: task,
                accumulatedStudySeconds: 420, // 7 phút
                onToggleComplete: () => completeCalled = true,
                onEdit: () {},
                onDelete: () {},
              ),
            ),
          ),
        );

        // Thẻ tiến độ 15 phút
        expect(
          find.byKey(const ValueKey('task_detail_study_time_progress_card')),
          findsOneWidget,
        );
        expect(find.text('7/15 phút: chưa đủ điều kiện'), findsOneWidget);
        expect(
          find.textContaining('tối thiểu 15 phút học thực tế'),
          findsOneWidget,
        );

        // Nút hoàn thành hiển thị 'Chưa đủ 15 phút' và bị disable
        final completeBtn = find.text('Chưa đủ 15 phút');
        expect(completeBtn, findsOneWidget);
        await tester.tap(completeBtn);
        expect(completeCalled, isFalse);
      },
    );

    testWidgets(
      'TaskDetailSheet: Quá hạn hiển thị Khối cảnh báo cùng nút Học bù',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final overdueTask = StudyTask(
          id: 'detail_overdue_1',
          title: 'Báo cáo môn Kiến trúc',
          subjectId: 'subj_arch',
          subject: 'Kiến trúc',
          deadline: DateTime.now().subtract(const Duration(days: 1)),
          status: TaskStatus.todo,
        );

        bool makeupTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskDetailSheet(
                task: overdueTask,
                accumulatedStudySeconds: 900,
                onToggleComplete: () {},
                onEdit: () {},
                onDelete: () {},
                onStartStudy: () => makeupTapped = true,
                onReschedule: () {},
              ),
            ),
          ),
        );

        expect(find.text('Công việc đã quá hạn hoàn thành'), findsOneWidget);

        final makeupBtn = find.byKey(
          const ValueKey('task_detail_makeup_button'),
        );
        expect(makeupBtn, findsOneWidget);
        await tester.tap(makeupBtn);
        expect(makeupTapped, isTrue);
      },
    );

    testWidgets(
      'TaskDetailSheet: Quá hạn hiển thị Khối cảnh báo cùng nút Chuyển lịch',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final overdueTask = StudyTask(
          id: 'detail_overdue_2',
          title: 'Báo cáo môn Kiến trúc',
          subjectId: 'subj_arch',
          subject: 'Kiến trúc',
          deadline: DateTime.now().subtract(const Duration(days: 1)),
          status: TaskStatus.todo,
        );

        bool rescheduleTapped = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskDetailSheet(
                task: overdueTask,
                accumulatedStudySeconds: 900,
                onToggleComplete: () {},
                onEdit: () {},
                onDelete: () {},
                onStartStudy: () {},
                onReschedule: () => rescheduleTapped = true,
              ),
            ),
          ),
        );

        expect(find.text('Công việc đã quá hạn hoàn thành'), findsOneWidget);

        final rescheduleBtn = find.byKey(
          const ValueKey('task_detail_reschedule_button'),
        );
        expect(rescheduleBtn, findsOneWidget);
        await tester.tap(rescheduleBtn);
        expect(rescheduleTapped, isTrue);
      },
    );
  });

  group('Group B & C: AppShell End-to-End Enforcement', () {
    testWidgets(
      'AppShell: Chặn hoàn thành khi < 15 phút và hiển thị thông báo lỗi',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final taskRepo = TaskRepository(useWebPreview: true);
        final subjectRepo = SubjectRepository(useWebPreview: true);
        final profileRepo = ProfileRepository(useWebPreview: true);
        final sessionRepo = SessionRepository(useWebPreview: true);

        final task = StudyTask(
          id: 'task_appshell_test',
          title: 'Lập trình ứng dụng Flutter',
          subjectId: 'subj_it',
          subject: 'Lập trình',
          deadline: DateTime.now().add(const Duration(days: 2)),
          status: TaskStatus.todo,
        );
        await taskRepo.insertTask(task);

        // Thêm phiên chỉ có 10 phút (600s) < 900s
        final shortSession = StudySession(
          id: 'sess_10m',
          subjectId: 'subj_it',
          subjectNameSnapshot: 'Lập trình',
          taskId: task.id,
          taskTitleSnapshot: task.title,
          studyDate: '2026-11-13',
          startedAt: DateTime.now().subtract(const Duration(minutes: 10)),
          endedAt: DateTime.now(),
          lastHeartbeatAt: DateTime.now(),
          lastStateChangedAt: DateTime.now().subtract(
            const Duration(minutes: 10),
          ),
          verifiedStudySeconds: 600,
          status: StudySessionStatus.completed,
        );
        await sessionRepo.createSession(shortSession);

        final shellEngine1 = StudyTimerEngine(
          repository: sessionRepo,
          bindLifecycleObserver: false,
        );
        addTearDown(shellEngine1.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: AppShell(
              taskRepository: taskRepo,
              subjectRepository: subjectRepo,
              profileRepository: profileRepo,
              sessionRepository: sessionRepo,
              timerEngine: shellEngine1,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Mở chi tiết công việc
        final taskCardFinder = find.text('Lập trình ứng dụng Flutter');
        expect(taskCardFinder, findsOneWidget);
        await tester.ensureVisible(taskCardFinder);
        await tester.tap(taskCardFinder);
        await tester.pumpAndSettle();

        // Nhấn nút hoàn thành trong sheet -> bị vô hiệu hóa
        final notEligibleBtn = find.text('Chưa đủ 15 phút');
        expect(notEligibleBtn, findsOneWidget);
        await tester.tap(notEligibleBtn);
        await tester.pumpAndSettle();

        // Kiểm tra task vẫn giữ nguyên trạng thái todo
        final allTasks = await taskRepo.getAllTasks();
        final current = allTasks.firstWhere((t) => t.id == task.id);
        expect(current.isCompleted, isFalse);
      },
    );

    testWidgets('AppShell: Cho phép hoàn thành khi phiên đạt đủ 15 phút', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final taskRepo = TaskRepository(useWebPreview: true);
      final subjectRepo = SubjectRepository(useWebPreview: true);
      final profileRepo = ProfileRepository(useWebPreview: true);
      final sessionRepo = SessionRepository(useWebPreview: true);

      final task = StudyTask(
        id: 'task_appshell_pass',
        title: 'Đọc giáo trình Mạng máy tính',
        subjectId: 'subj_net',
        subject: 'Mạng',
        deadline: DateTime.now().add(const Duration(days: 2)),
        status: TaskStatus.todo,
      );
      await taskRepo.insertTask(task);

      // Thêm phiên 15 phút (900s)
      final fullSession = StudySession(
        id: 'sess_15m',
        subjectId: 'subj_net',
        subjectNameSnapshot: 'Mạng',
        taskId: task.id,
        taskTitleSnapshot: task.title,
        studyDate: '2026-11-13',
        startedAt: DateTime.now().subtract(const Duration(minutes: 15)),
        endedAt: DateTime.now(),
        lastHeartbeatAt: DateTime.now(),
        lastStateChangedAt: DateTime.now().subtract(
          const Duration(minutes: 15),
        ),
        verifiedStudySeconds: 900,
        status: StudySessionStatus.completed,
      );
      await sessionRepo.createSession(fullSession);

      final shellEngine2 = StudyTimerEngine(
        repository: sessionRepo,
        bindLifecycleObserver: false,
      );
      addTearDown(shellEngine2.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AppShell(
            taskRepository: taskRepo,
            subjectRepository: subjectRepo,
            profileRepository: profileRepo,
            sessionRepository: sessionRepo,
            timerEngine: shellEngine2,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mở chi tiết công việc
      final taskCardFinder = find.text('Đọc giáo trình Mạng máy tính');
      expect(taskCardFinder, findsOneWidget);
      await tester.ensureVisible(taskCardFinder);
      await tester.tap(taskCardFinder);
      await tester.pumpAndSettle();

      // Nhấn nút Đã hoàn thành
      final completeBtn = find.text('Đã hoàn thành');
      expect(completeBtn, findsOneWidget);
      await tester.ensureVisible(completeBtn);
      await tester.tap(completeBtn);
      await tester.pumpAndSettle();

      // Kiểm tra task đã chuyển sang hoàn thành trong database
      final allTasks = await taskRepo.getAllTasks();
      final current = allTasks.firstWhere((t) => t.id == task.id);
      expect(current.isCompleted, isTrue);
    });
  });

  group('Group A: Alarm Robustness, Snooze Limitation & Persistent Ringing', () {
    late AlarmStore alarmStore;
    late _FakeAlarmBridge platformBridge;
    late _FakeAudioGateway audioGateway;
    late FakeTimerClock fakeClock;
    late AlarmStateManager alarmManager;

    setUp(() {
      alarmStore = LocalAlarmStore(useMemoryOnly: true);
      platformBridge = _FakeAlarmBridge();
      audioGateway = _FakeAudioGateway();
      fakeClock = FakeTimerClock(DateTime.utc(2026, 11, 13, 8, 0));
      alarmManager = AlarmStateManager(
        store: alarmStore,
        platformBridge: platformBridge,
        audioGateway: audioGateway,
        clock: fakeClock,
      );
    });

    tearDown(() {
      alarmManager.dispose();
    });

    test(
      'Alarm: Giới hạn tối đa 1 lần Snooze (+5 phút), lần 2 ném StateError',
      () async {
        final slot = ScheduledStudySlot(
          id: 'slot_math_alarm',
          subjectName: 'Toán cao cấp',
          startAtUtc: DateTime.utc(2026, 11, 13, 8, 30),
        );

        // Đặt lịch
        await alarmManager.scheduleForSlot(slot: slot, soundId: 'alarm_dawn');
        final key = AlarmStateManager.buildSlotAlarmKey(slot.id);

        // Reo chuông lần đầu
        fakeClock.advance(const Duration(minutes: 30));
        await alarmManager.triggerAlarmRinging(key);
        expect(alarmManager.hasRingingAlarm, isTrue);
        expect(alarmManager.activeRingingAlarm!.snoozeCount, 0);
        expect(alarmManager.activeRingingAlarm!.canSnooze, isTrue);

        // Snooze lần 1 (+5 phút)
        final snoozed = await alarmManager.snoozeAlarm(key);
        expect(snoozed.status, AlarmStatus.snoozed);
        expect(snoozed.snoozeCount, 1);
        expect(snoozed.canSnooze, isFalse);
        expect(
          snoozed.snoozedUntilUtc,
          fakeClock.nowUtc().add(const Duration(minutes: 5)),
        );

        // Reo lại sau 5 phút
        fakeClock.advance(const Duration(minutes: 5));
        await alarmManager.triggerAlarmRinging(key);
        expect(alarmManager.hasRingingAlarm, isTrue);
        expect(alarmManager.activeRingingAlarm!.snoozeCount, 1);
        expect(alarmManager.activeRingingAlarm!.canSnooze, isFalse);

        // Cố tình Snooze lần 2 -> ném StateError
        expect(
          () => alarmManager.snoozeAlarm(key),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('đã sử dụng hết 1 lần Nhắc lại'),
            ),
          ),
        );

        // Tắt báo thức (Dismiss) -> dừng sạch
        await alarmManager.dismissAlarm(key);
        expect(alarmManager.hasRingingAlarm, isFalse);
        expect(alarmManager.getByKey(key)!.status, AlarmStatus.dismissed);
      },
    );

    test(
      'Alarm: Chuông reo liên tục, không có auto-timeout, âm thanh "none" im lặng',
      () async {
        final slot = ScheduledStudySlot(
          id: 'slot_silent_alarm',
          subjectName: 'Tiếng Anh',
          startAtUtc: DateTime.utc(2026, 11, 13, 9, 0),
        );

        await alarmManager.scheduleForSlot(slot: slot, soundId: 'none');
        final key = AlarmStateManager.buildSlotAlarmKey(slot.id);

        fakeClock.advance(const Duration(hours: 1));
        await alarmManager.triggerAlarmRinging(key);

        // Âm thanh 'none' không phát âm thanh loop
        expect(audioGateway.isAlarmLoopPlaying, isFalse);
        expect(alarmManager.hasRingingAlarm, isTrue);

        // Thời gian trôi 30 phút mà người dùng không bấm Tắt -> vẫn Ringing (không timeout)
        fakeClock.advance(const Duration(minutes: 30));
        expect(alarmManager.hasRingingAlarm, isTrue);
        expect(alarmManager.activeRingingAlarm!.status, AlarmStatus.ringing);

        await alarmManager.dismissAlarm(key);
      },
    );

    testWidgets(
      'ActiveAlarmBanner: Hiển thị đầy đủ thông tin, ẩn nút Nhắc lại khi đã dùng hết 1 lần',
      (tester) async {
        final slot = ScheduledStudySlot(
          id: 'slot_banner_test',
          subjectName: 'Vật lý đại cương',
          taskTitle: 'Chương 2 Nhiệt động học',
          startAtUtc: DateTime.utc(2026, 11, 13, 10, 0),
        );

        await alarmManager.scheduleForSlot(
          slot: slot,
          soundId: 'alarm_school_bell',
        );
        final key = AlarmStateManager.buildSlotAlarmKey(slot.id);
        await alarmManager.triggerAlarmRinging(key);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ActiveAlarmBanner(alarmStateManager: alarmManager),
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey('active_alarm_banner')),
          findsOneWidget,
        );
        expect(find.text('Báo thức học tập: Vật lý đại cương'), findsOneWidget);
        expect(find.text('Chương 2 Nhiệt động học'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('active_alarm_snooze_button')),
          findsOneWidget,
        );

        // Nhấn Snooze
        await tester.tap(
          find.byKey(const ValueKey('active_alarm_snooze_button')),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('active_alarm_banner')), findsNothing);

        // Reo lại sau Snooze
        await alarmManager.triggerAlarmRinging(key);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('active_alarm_banner')),
          findsOneWidget,
        );

        // Nút Snooze đã bị ẩn vì đã dùng 1 lần
        expect(
          find.byKey(const ValueKey('active_alarm_snooze_button')),
          findsNothing,
        );
        expect(find.textContaining('đã dùng 1/1 lần Nhắc lại'), findsOneWidget);

        await alarmManager.dismissAlarm(key);
        await tester.pumpAndSettle();
      },
    );
  });
}

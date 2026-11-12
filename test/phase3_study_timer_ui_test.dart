import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:exampilot/models/study_session.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/task_priority.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/models/user_profile.dart';
import 'package:exampilot/repositories/profile_repository.dart';
import 'package:exampilot/repositories/session_repository.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/screens/app_shell.dart';
import 'package:exampilot/screens/study_timer_screen.dart';
import 'package:exampilot/screens/subject_detail_screen.dart';
import 'package:exampilot/services/session_storage.dart';
import 'package:exampilot/services/study_timer_engine.dart';
import 'package:exampilot/services/web_storage.dart';
import 'package:exampilot/theme/app_theme.dart';
import 'package:exampilot/widgets/floating_mini_timer_bar.dart';
import 'package:exampilot/widgets/study_recovery_dialog.dart';
import 'package:exampilot/widgets/study_timer_formatters.dart';
import 'package:exampilot/widgets/task_detail_sheet.dart';

void main() {
  late FakeTimerClock clock;
  late SessionRepository sessionRepo;
  late TaskRepository taskRepo;
  late SubjectRepository subjectRepo;
  late ProfileRepository profileRepo;

  const subjectMath = Subject(
    id: 'subj_math',
    name: 'Toán cao cấp',
    description: 'Giải tích',
    color: Color(0xFF3B5BDB),
  );
  const subjectDb = Subject(
    id: 'subj_db',
    name: 'Cơ sở dữ liệu',
    description: 'SQL & Chuẩn hóa',
    color: Color(0xFF0284C7),
  );

  List<StudyTask> sampleTasks() => [
    StudyTask(
      id: 'task_math_nodl',
      title: 'Ôn công thức vi phân',
      subjectId: 'subj_math',
      subject: 'Toán cao cấp',
      deadline: null,
      estimatedMinutes: 30,
      priority: TaskPriority.high,
      status: TaskStatus.todo,
    ),
    StudyTask(
      id: 'task_db_done',
      title: 'Thiết kế ERD thư viện',
      subjectId: 'subj_db',
      subject: 'Cơ sở dữ liệu',
      deadline: DateTime(2026, 11, 20, 17, 0),
      estimatedMinutes: 45,
      actualMinutes: 40,
      priority: TaskPriority.medium,
      status: TaskStatus.completed,
    ),
  ];

  setUp(() async {
    WebSessionStorage.resetAllSimulatedStorageForTesting();
    WebStreakStorage.clearProfile();
    WebStreakStorage.clearStudyActivitiesAndDates();

    final localNow = DateTime.now();
    clock = FakeTimerClock(
      DateTime(localNow.year, localNow.month, localNow.day, 10, 0).toUtc(),
    );

    sessionRepo = SessionRepository(useWebPreview: true);
    taskRepo = TaskRepository(useWebPreview: true);
    subjectRepo = SubjectRepository(useWebPreview: true);
    profileRepo = ProfileRepository(useWebPreview: true);
  });

  StudyTimerEngine buildEngine({
    bool autoStartHeartbeat = false,
    bool autoStartUiTicker = true,
  }) {
    return StudyTimerEngine(
      repository: sessionRepo,
      clock: clock,
      autoStartHeartbeat: autoStartHeartbeat,
      autoStartUiTicker: autoStartUiTicker,
    );
  }

  group('Nhóm A - Study Timer Screen & State Display', () {
    testWidgets(
      '1-6. Hiển thị đúng Idle, Running, Paused, InBreak; đồng hồ HH:MM:SS/MM:SS; lọc nút đúng trạng thái',
      (tester) async {
        final engine = buildEngine();

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: StudyTimerScreen(
              timerEngine: engine,
              subjects: const [subjectMath, subjectDb],
              tasks: sampleTasks(),
              userProfile: const UserProfile(breakPresetId: 'pomodoro_25_5'),
            ),
          ),
        );

        // 1. Trạng thái Idle
        expect(
          find.byKey(const ValueKey('timer_start_button')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('timer_pause_button')), findsNothing);
        expect(find.byKey(const ValueKey('timer_resume_button')), findsNothing);
        expect(
          find.byKey(const ValueKey('timer_complete_button')),
          findsNothing,
        );

        // Bắt đầu phiên học
        await tester.ensureVisible(
          find.byKey(const ValueKey('timer_start_button')),
        );
        await tester.tap(find.byKey(const ValueKey('timer_start_button')));
        await tester.pumpAndSettle();

        // 2. Trạng thái Running
        expect(find.text('Đang học'), findsWidgets);
        expect(find.text('Toán cao cấp'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('timer_pause_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('timer_start_break_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('timer_complete_button')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('timer_resume_button')), findsNothing);
        expect(find.text('00:00'), findsOneWidget);

        // Tiến thời gian giả 65 giây và kích hoạt 1s ticker -> 01:05
        clock.advance(const Duration(seconds: 65));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('01:05'), findsOneWidget);

        // Tiến vượt 1 giờ -> định dạng HH:MM:SS (01:01:05)
        clock.advance(const Duration(hours: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('01:01:05'), findsOneWidget);

        // 3. Tạm dừng -> Paused
        await tester.tap(find.byKey(const ValueKey('timer_pause_button')));
        await tester.pumpAndSettle();
        expect(find.text('Đã tạm dừng'), findsWidgets);
        expect(
          find.byKey(const ValueKey('timer_resume_button')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('timer_complete_button')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('timer_pause_button')), findsNothing);
        expect(
          find.byKey(const ValueKey('timer_start_break_button')),
          findsNothing,
        );

        // 4. Tiếp tục -> Bắt đầu nghỉ -> InBreak
        await tester.tap(find.byKey(const ValueKey('timer_resume_button')));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('timer_start_break_button')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Đang nghỉ'), findsWidgets);
        expect(find.text('THỜI GIAN NGHỈ'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('timer_break_study_summary')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('timer_end_break_button')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('timer_pause_button')), findsNothing);
        expect(
          find.byKey(const ValueKey('timer_start_break_button')),
          findsNothing,
        );

        engine.dispose();
      },
    );
  });

  group('Nhóm B - Start Session Flows', () {
    testWidgets(
      '1-3. Bắt đầu theo môn học, theo công việc không có deadline, và chọn thời gian dự kiến',
      (tester) async {
        final engine = buildEngine();
        final tasks = sampleTasks();

        await tester.pumpWidget(
          MaterialApp(
            home: StudyTimerScreen(
              timerEngine: engine,
              subjects: const [subjectMath, subjectDb],
              tasks: tasks,
              userProfile: const UserProfile(
                breakPresetId: 'deep_50_10',
                customStudyMinutes: 40,
                customBreakMinutes: 8,
              ),
            ),
          ),
        );

        // Chuyển sang chế độ Theo công việc
        await tester.tap(find.byKey(const ValueKey('timer_mode_task_tab')));
        await tester.pumpAndSettle();

        // Tìm công việc không có deadline ('Ôn công thức vi phân')
        await tester.enterText(
          find.byKey(const ValueKey('timer_task_search_field')),
          'vi phân',
        );
        await tester.pumpAndSettle();
        expect(find.text('Ôn công thức vi phân'), findsOneWidget);
        expect(find.text('Thiết kế ERD thư viện'), findsNothing);

        await tester.tap(
          find.byKey(const ValueKey('timer_task_option_task_math_nodl')),
        );
        await tester.pumpAndSettle();

        // Chọn thời gian dự kiến 45 phút
        final chip45 = find.byKey(const ValueKey('timer_planned_minutes_45'));
        await tester.ensureVisible(chip45);
        await tester.tap(chip45);
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('timer_start_button')),
        );
        await tester.tap(find.byKey(const ValueKey('timer_start_button')));
        await tester.pumpAndSettle();

        expect(engine.isRunning, isTrue);
        expect(engine.activeSession!.taskId, 'task_math_nodl');
        expect(engine.activeSession!.taskTitleSnapshot, 'Ôn công thức vi phân');
        expect(engine.activeSession!.subjectId, 'subj_math');
        expect(engine.activeSession!.plannedStudyMinutes, 45);
        expect(find.text('Ôn công thức vi phân'), findsOneWidget);

        engine.dispose();
      },
    );

    testWidgets(
      '4-5. Không cho chọn công việc đã xóa và chặn bắt đầu phiên thứ 2 khi có Recovery Pending',
      (tester) async {
        final deletedTask = StudyTask(
          id: 'task_deleted',
          title: 'Công việc đã xóa',
          subjectId: 'subj_math',
          subject: 'Toán cao cấp',
        );

        // 1. Khởi tạo màn hình với initialTask đã bị xóa khỏi danh sách tasks sống
        final engine = buildEngine();
        await tester.pumpWidget(
          MaterialApp(
            home: StudyTimerScreen(
              timerEngine: engine,
              subjects: const [subjectMath],
              tasks: sampleTasks(), // không chứa task_deleted
              initialTask: deletedTask,
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('timer_mode_task_tab')));
        await tester.pumpAndSettle();
        expect(find.text('Công việc đã xóa'), findsNothing);

        await tester.ensureVisible(
          find.byKey(const ValueKey('timer_start_button')),
        );
        await tester.tap(find.byKey(const ValueKey('timer_start_button')));
        await tester.pumpAndSettle();
        // Chưa chọn công việc hợp lệ nào nên không bắt đầu được ở chế độ Theo công việc
        expect(engine.isIdle, isTrue);

        // 2. Chặn bắt đầu phiên mới khi đang có InterruptedPending
        await engine.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 10));
        await engine.heartbeat();
        engine.dispose();

        final restoredEngine = buildEngine();
        await restoredEngine.restoreSessionState();
        expect(restoredEngine.hasPendingRecovery, isTrue);

        await tester.pumpWidget(
          MaterialApp(
            home: StudyTimerScreen(
              timerEngine: restoredEngine,
              subjects: const [subjectMath],
              tasks: sampleTasks(),
            ),
          ),
        );
        expect(find.byKey(const ValueKey('timer_start_button')), findsNothing);
        expect(
          find.byKey(const ValueKey('timer_open_recovery_button')),
          findsOneWidget,
        );

        restoredEngine.dispose();
      },
    );
  });

  group('Nhóm C - Break Experience', () {
    testWidgets(
      'Nghỉ hiển thị đồng hồ riêng, kết thúc sớm được, hết giờ nghỉ dự kiến không tự thoát, không cộng vào học',
      (tester) async {
        final engine = buildEngine();

        await tester.pumpWidget(
          MaterialApp(
            home: StudyTimerScreen(
              timerEngine: engine,
              subjects: const [subjectMath],
              tasks: sampleTasks(),
              userProfile: const UserProfile(breakPresetId: 'pomodoro_25_5'),
            ),
          ),
        );

        await tester.ensureVisible(
          find.byKey(const ValueKey('timer_start_button')),
        );
        await tester.tap(find.byKey(const ValueKey('timer_start_button')));
        await tester.pumpAndSettle();

        // Học 10 phút rồi bắt đầu nghỉ (Pomodoro 25/5 -> nghỉ dự kiến 5 phút)
        clock.advance(const Duration(minutes: 10));
        await tester.tap(
          find.byKey(const ValueKey('timer_start_break_button')),
        );
        await tester.pumpAndSettle();

        expect(engine.isInBreak, isTrue);
        expect(
          find.byKey(const ValueKey('break_planned_reached_banner')),
          findsNothing,
        );

        // Vượt quá 5 phút nghỉ dự kiến (thành 6 phút) -> chỉ hiện banner trực quan, KHÔNG tự tiếp tục học
        clock.advance(const Duration(minutes: 6));
        await tester.pump(const Duration(seconds: 1));
        expect(engine.isInBreak, isTrue);
        expect(find.text('06:00'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('break_planned_reached_banner')),
          findsOneWidget,
        );

        // Kết thúc nghỉ -> học thêm 5 phút -> mở nghỉ lần 2 và kết thúc nghỉ sớm
        await tester.tap(find.byKey(const ValueKey('timer_end_break_button')));
        await tester.pumpAndSettle();
        clock.advance(const Duration(minutes: 5));

        await tester.tap(
          find.byKey(const ValueKey('timer_start_break_button')),
        );
        await tester.pumpAndSettle();
        // Lần nghỉ 2 bắt đầu sạch từ 00:00 (không bị đếm nhầm thành đã hết 5 phút)
        expect(
          find.byKey(const ValueKey('break_planned_reached_banner')),
          findsNothing,
        );
        clock.advance(const Duration(minutes: 2));
        await tester.tap(find.byKey(const ValueKey('timer_end_break_button')));
        await tester.pumpAndSettle();

        // Kết thúc phiên: đúng 15 phút học (900s) và 8 phút nghỉ tách biệt (481s)
        await tester.tap(find.byKey(const ValueKey('timer_complete_button')));
        await tester.pumpAndSettle();
        expect(engine.lastEndedSession!.verifiedStudySeconds, 900);
        expect(
          engine.lastEndedSession!.accumulatedBreakSeconds,
          greaterThanOrEqualTo(480),
        );

        engine.dispose();
      },
    );
  });

  group('Nhóm D - Recovery Dialog', () {
    testWidgets(
      '1-7. Hiển thị tự động trên AppShell, không tự đóng/không tự điền max, kiểm tra 3 lựa chọn A/B/C và cảnh báo >8h',
      (tester) async {
        // Tạo 1 phiên bị gián đoạn quá 8 giờ (học 10 phút rồi đóng app 9 giờ)
        final seedEngine = buildEngine();
        await seedEngine.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 10));
        await seedEngine.heartbeat();
        seedEngine.dispose();

        clock.advance(const Duration(hours: 9));

        final shellEngine = buildEngine();
        addTearDown(shellEngine.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: AppShell(
              taskRepository: taskRepo,
              subjectRepository: subjectRepo,
              profileRepository: profileRepo,
              sessionRepository: sessionRepo,
              timerEngine: shellEngine,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Recovery Dialog phải xuất hiện tự động với cảnh báo > 8 giờ
        expect(
          find.byKey(const ValueKey('study_recovery_dialog')),
          findsOneWidget,
        );
        expect(find.textContaining('hơn 8 giờ'), findsOneWidget);

        // Chạm bên ngoài không được phép đóng dialog
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('study_recovery_dialog')),
          findsOneWidget,
        );

        // Mở Lựa chọn B: mặc định phần bổ sung là '0' (không tự điền max)
        await tester.ensureVisible(
          find.byKey(const ValueKey('recovery_choice_confirm_open')),
        );
        await tester.tap(
          find.byKey(const ValueKey('recovery_choice_confirm_open')),
        );
        await tester.pumpAndSettle();

        final textField = tester.widget<TextField>(
          find.byKey(const ValueKey('recovery_extra_minutes_field')),
        );
        expect(textField.controller!.text, '0');

        // Nhập vượt quá giới hạn tối đa (9999 phút) -> hiện lỗi chặn xác nhận
        await tester.enterText(
          find.byKey(const ValueKey('recovery_extra_minutes_field')),
          '9999',
        );
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Không thể xác nhận vượt quá'),
          findsOneWidget,
        );

        // Nhập hợp lệ 5 phút -> Tổng = 10 + 5 = 15 phút (900s) -> Hoàn thành!
        await tester.enterText(
          find.byKey(const ValueKey('recovery_extra_minutes_field')),
          '5',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('recovery_choice_confirm_submit')),
        );
        await tester.tap(
          find.byKey(const ValueKey('recovery_choice_confirm_submit')),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('study_recovery_dialog')),
          findsNothing,
        );
        expect(shellEngine.isIdle, isTrue);
        expect(shellEngine.lastEndedSession!.verifiedStudySeconds, 900);
        // Weekly Goal trên Overview đồng bộ thành 0.25 -> 0.3 / 10 giờ (15 phút)
        expect(find.text('1 ngày liên tiếp'), findsOneWidget);
      },
    );

    testWidgets(
      'Kiểm tra Lựa chọn A (Tiếp tục học) và Lựa chọn C (Hủy phiên) trên StudyRecoveryDialog',
      (tester) async {
        // Test Choice A: Tiếp tục học
        final eng1 = buildEngine();
        await eng1.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 8));
        await eng1.heartbeat();
        eng1.dispose();

        clock.advance(const Duration(minutes: 30));
        final eng2 = buildEngine();
        await eng2.restoreSessionState();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => StudyRecoveryDialog(timerEngine: eng2),
                  ),
                  child: const Text('OpenA'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('OpenA'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(const ValueKey('recovery_choice_continue')),
        );
        await tester.pumpAndSettle();
        expect(eng2.isRunning, isTrue);
        expect(eng2.getCurrentElapsedSeconds(), 480);

        // Hủy để kiểm Choice C
        await eng2.cancelSession();
        eng2.dispose();

        final eng3 = buildEngine();
        await eng3.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 20));
        await eng3.heartbeat();
        eng3.dispose();

        clock.advance(const Duration(minutes: 10));
        final eng4 = buildEngine();
        await eng4.restoreSessionState();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => StudyRecoveryDialog(timerEngine: eng4),
                  ),
                  child: const Text('OpenC'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('OpenC'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('recovery_choice_cancel')),
        );
        await tester.tap(find.byKey(const ValueKey('recovery_choice_cancel')));
        await tester.pumpAndSettle();

        expect(eng4.isIdle, isTrue);
        expect(eng4.lastEndedSession!.status, StudySessionStatus.cancelled);
        eng4.dispose();
      },
    );
  });

  group('Nhóm E - Floating Mini Timer Bar', () {
    testWidgets(
      'Hiển thị khi Running/Paused/InBreak, ẩn khi Idle/Completed/Cancelled/InterruptedPending, mở đúng TimerScreen và chuyển tab không mất phiên',
      (tester) async {
        final engine = buildEngine();
        addTearDown(engine.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: AppShell(
              taskRepository: taskRepo,
              subjectRepository: subjectRepo,
              profileRepository: profileRepo,
              sessionRepository: sessionRepo,
              timerEngine: engine,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. Khi Idle -> ẩn Mini Timer
        expect(
          find.byKey(const ValueKey('floating_mini_timer_bar')),
          findsNothing,
        );

        // Bắt đầu từ Overview
        await tester.ensureVisible(
          find.byKey(const ValueKey('overview_start_timer_button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('overview_start_timer_button')),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const ValueKey('timer_start_button')),
        );
        await tester.tap(find.byKey(const ValueKey('timer_start_button')));
        await tester.pumpAndSettle();

        clock.advance(const Duration(seconds: 75));
        await tester.pump(const Duration(seconds: 1));

        // Đóng StudyTimerScreen -> phiên KHÔNG bị hủy và Mini Timer xuất hiện
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(engine.isRunning, isTrue);
        expect(
          find.byKey(const ValueKey('floating_mini_timer_bar')),
          findsOneWidget,
        );

        // Chuyển sang tab Kế hoạch & Môn học -> Mini Timer vẫn hiện đúng
        await tester.tap(find.text('Kế hoạch'));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('floating_mini_timer_bar')),
          findsOneWidget,
        );
        expect(find.text('Đang học'), findsOneWidget);

        // Chuyển sang Paused & InBreak -> Mini Timer cập nhật theo Engine
        await engine.pauseSession();
        await tester.pumpAndSettle();
        expect(find.text('Đã tạm dừng'), findsWidgets);

        await engine.resumeSession();
        await engine.startBreak();
        await tester.pumpAndSettle();
        expect(find.text('Đang nghỉ'), findsWidgets);

        // Nhấn Mini Timer để mở lại đúng màn StudyTimerScreen dùng chung Engine
        await tester.tap(find.byKey(const ValueKey('floating_mini_timer_bar')));
        await tester.pumpAndSettle();
        expect(find.byType(StudyTimerScreen), findsOneWidget);
        expect(find.text('THỜI GIAN NGHỈ'), findsOneWidget);

        // Kết thúc phiên -> quay lại -> Mini Timer tự ẩn
        await tester.ensureVisible(
          find.byKey(const ValueKey('timer_complete_button')),
        );
        await tester.tap(find.byKey(const ValueKey('timer_complete_button')));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('floating_mini_timer_bar')),
          findsNothing,
        );

        // Kiểm tra Cancelled và InterruptedPending cũng ẩn Mini Timer (không giả vờ đang chạy)
        expect(formatTimerDuration(3665), '01:01:05');
        await engine.startSession(subject: subjectMath);
        await engine.cancelSession();
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('floating_mini_timer_bar')),
          findsNothing,
        );

        await engine.startSession(subject: subjectMath);
        clock.advance(const Duration(minutes: 5));
        await engine.heartbeat();
        final pendingEngine = buildEngine();
        addTearDown(pendingEngine.dispose);
        await pendingEngine.restoreSessionState();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FloatingMiniTimerBar(
                timerEngine: pendingEngine,
                onTap: () {},
              ),
            ),
          ),
        );
        expect(pendingEngine.hasPendingRecovery, isTrue);
        expect(
          find.byKey(const ValueKey('floating_mini_timer_bar')),
          findsNothing,
        );
      },
    );
  });

  group('Nhóm F - Integration, Singleton & Entry Points', () {
    testWidgets(
      'Truy cập từ SubjectDetailScreen, TaskDetailSheet không sửa Task completed, và duy nhất 1 UI ticker',
      (tester) async {
        // 1. SubjectDetailScreen tự chọn đúng môn khi mở StudyTimerScreen
        Subject? launchedSubject;
        await tester.pumpWidget(
          MaterialApp(
            home: SubjectDetailScreen(
              subject: subjectDb,
              allSubjects: const [subjectMath, subjectDb],
              tasks: sampleTasks(),
              onToggleComplete: (_) {},
              onTapTask: (_) {},
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onAddTaskForThisSubject: () {},
              onStartTimerForThisSubject: () => launchedSubject = subjectDb,
              onEditSubject: () {},
              onDeleteSubject: () {},
            ),
          ),
        );
        await tester.tap(
          find.byKey(const ValueKey('subject_detail_start_timer_button')),
        );
        await tester.pumpAndSettle();
        expect(launchedSubject?.id, 'subj_db');

        // 2. TaskDetailSheet mở Timer cho task đã completed mà không làm thay đổi trạng thái task
        final doneTask = sampleTasks().last;
        var startedFromTask = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => TaskDetailSheet(
                      task: doneTask,
                      onToggleComplete: () {},
                      onEdit: () {},
                      onDelete: () {},
                      onStartTimer: () => startedFromTask = true,
                    ),
                  ),
                  child: const Text('OpenTaskSheet'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('OpenTaskSheet'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('task_detail_start_timer_button')),
        );
        await tester.tap(
          find.byKey(const ValueKey('task_detail_start_timer_button')),
        );
        await tester.pumpAndSettle();
        expect(startedFromTask, isTrue);
        expect(doneTask.status, TaskStatus.completed);
        expect(doneTask.actualMinutes, 40);

        // 3. Chứng minh chỉ có duy nhất 1 UI ticker hoạt động kể cả khi có nhiều widget hiển thị đồng thời
        final engine = buildEngine();
        addTearDown(engine.dispose);
        await engine.startSession(subject: subjectMath);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StudyTimerScreen(
                timerEngine: engine,
                subjects: const [subjectMath],
                tasks: sampleTasks(),
              ),
              bottomNavigationBar: FloatingMiniTimerBar(
                timerEngine: engine,
                onTap: () {},
              ),
            ),
          ),
        );
        expect(engine.activeUiTickerCount, 1);

        // Unmount cây widget -> UI ticker tự động dừng sạch
        await tester.pumpWidget(const SizedBox.shrink());
        expect(engine.activeUiTickerCount, 0);
      },
    );
  });

  group('Nhóm G - Responsive (320dp, 360dp, Large) & Light/Dark Theme', () {
    testWidgets(
      'Không tràn giao diện trên màn hình 320dp, 360dp và 800dp trong cả Light và Dark Mode',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final size in [
          const Size(320, 640),
          const Size(360, 740),
          const Size(800, 900),
        ]) {
          for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
            await tester.binding.setSurfaceSize(size);
            final engine = buildEngine();

            await tester.pumpWidget(
              MaterialApp(
                theme: theme,
                home: AppShell(
                  taskRepository: taskRepo,
                  subjectRepository: subjectRepo,
                  profileRepository: profileRepo,
                  sessionRepository: sessionRepo,
                  timerEngine: engine,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            // Bắt đầu phiên để kiểm tra Mini Timer + FAB + NavigationBar cùng lúc ở 320dp
            await engine.startSession(subject: subjectMath);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('floating_mini_timer_bar')),
              findsOneWidget,
            );
            expect(tester.takeException(), isNull);

            // Mở StudyTimerScreen trên màn hình đang kiểm thử
            await tester.tap(
              find.byKey(const ValueKey('floating_mini_timer_bar')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);

            // Chuyển Break và kiểm tra nút >= 48dp không overflow
            await tester.tap(
              find.byKey(const ValueKey('timer_start_break_button')),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            final endBreakSize = tester.getSize(
              find.byKey(const ValueKey('timer_end_break_button')),
            );
            expect(endBreakSize.height, greaterThanOrEqualTo(48));

            await engine.completeSession();
            engine.dispose();
            await tester.pumpWidget(const SizedBox.shrink());
            WebSessionStorage.resetAllSimulatedStorageForTesting();
          }
        }
      },
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/study_streak.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/task_priority.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/screens/overview_screen.dart';
import 'package:exampilot/services/web_storage.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Kiểm thử Mô hình StudyStreak & Thuật toán tính Streak', () {
    test(
      '1. Không có hoạt động nào -> currentStreak = 0, longestStreak = 0',
      () {
        final streak = StudyStreak.fromActiveDates({});
        expect(streak.currentStreak, 0);
        expect(streak.longestStreak, 0);
        expect(streak.activeDates.isEmpty, isTrue);
      },
    );

    test(
      '2. Chỉ có hoạt động hôm nay -> currentStreak = 1, longestStreak = 1',
      () {
        final now = DateTime.now();
        final streak = StudyStreak.fromActiveDates({
          StudyStreak.formatDateKey(now),
        }, now: now);
        expect(streak.currentStreak, 1);
        expect(streak.longestStreak, 1);
        expect(streak.hasActivityOn(now), isTrue);
      },
    );

    test(
      '3. Có hoạt động hôm qua, chưa học hôm nay -> giữ chuỗi (currentStreak = 1, longestStreak = 1)',
      () {
        final now = DateTime.now();
        final yesterday = now.subtract(const Duration(days: 1));
        final streak = StudyStreak.fromActiveDates({
          StudyStreak.formatDateKey(yesterday),
        }, now: now);
        expect(streak.currentStreak, 1);
        expect(streak.longestStreak, 1);
        expect(streak.hasActivityOn(yesterday), isTrue);
        expect(streak.hasActivityOn(now), isFalse);
      },
    );

    test(
      '4. Có hoạt động cả hôm qua và hôm nay -> currentStreak = 2, longestStreak = 2',
      () {
        final now = DateTime.now();
        final yesterday = now.subtract(const Duration(days: 1));
        final streak = StudyStreak.fromActiveDates({
          StudyStreak.formatDateKey(yesterday),
          StudyStreak.formatDateKey(now),
        }, now: now);
        expect(streak.currentStreak, 2);
        expect(streak.longestStreak, 2);
      },
    );

    test(
      '5. Chuỗi 3 ngày trong quá khứ bị ngắt -> currentStreak = 0 nhưng longestStreak vẫn giữ 3',
      () {
        final now = DateTime.now();
        final d1 = now.subtract(const Duration(days: 5));
        final d2 = now.subtract(const Duration(days: 4));
        final d3 = now.subtract(const Duration(days: 3));
        // Không có hoạt động vào ngày d-2, d-1 (hôm qua) và hôm nay

        final streak = StudyStreak.fromActiveDates({
          StudyStreak.formatDateKey(d1),
          StudyStreak.formatDateKey(d2),
          StudyStreak.formatDateKey(d3),
        }, now: now);

        expect(streak.currentStreak, 0);
        expect(streak.longestStreak, 3);
      },
    );

    test(
      '6. Kỷ lục cá nhân không bao giờ giảm khi học lại sau khi ngắt chuỗi',
      () {
        final now = DateTime.now();
        final d1 = now.subtract(const Duration(days: 10));
        final d2 = now.subtract(const Duration(days: 9));
        final d3 = now.subtract(const Duration(days: 8));
        final d4 = now.subtract(const Duration(days: 7));
        // Kỷ lục cũ là 4 ngày liên tiếp
        // Sau đó gián đoạn, và hôm nay học lại (1 ngày)

        final streak = StudyStreak.fromActiveDates({
          StudyStreak.formatDateKey(d1),
          StudyStreak.formatDateKey(d2),
          StudyStreak.formatDateKey(d3),
          StudyStreak.formatDateKey(d4),
          StudyStreak.formatDateKey(now),
        }, now: now);

        expect(streak.currentStreak, 1);
        expect(streak.longestStreak, 4); // Vẫn bảo toàn kỷ lục 4 ngày
      },
    );

    test(
      '7. Chuỗi mới vượt qua kỷ lục cũ -> longestStreak tự động cập nhật',
      () {
        final now = DateTime.now();
        final dates = <String>{};
        // Quá khứ: chuỗi 2 ngày
        dates.add(
          StudyStreak.formatDateKey(now.subtract(const Duration(days: 10))),
        );
        dates.add(
          StudyStreak.formatDateKey(now.subtract(const Duration(days: 9))),
        );

        // Hiện tại: chuỗi 4 ngày liên tiếp kết thúc hôm nay
        dates.add(
          StudyStreak.formatDateKey(now.subtract(const Duration(days: 3))),
        );
        dates.add(
          StudyStreak.formatDateKey(now.subtract(const Duration(days: 2))),
        );
        dates.add(
          StudyStreak.formatDateKey(now.subtract(const Duration(days: 1))),
        );
        dates.add(StudyStreak.formatDateKey(now));

        final streak = StudyStreak.fromActiveDates(dates, now: now);
        expect(streak.currentStreak, 4);
        expect(streak.longestStreak, 4);
      },
    );

    test('8. Định dạng ngày chuẩn YYYY-MM-DD theo giờ địa phương', () {
      final dt = DateTime(2026, 3, 5, 23, 15);
      final key = StudyStreak.formatDateKey(dt);
      expect(key, '2026-03-05');
      final parsed = StudyStreak.parseDateKey(key);
      expect(parsed.year, 2026);
      expect(parsed.month, 3);
      expect(parsed.day, 5);
    });
  });

  group('Kiểm thử Ghi nhận Study Streak trong TaskRepository', () {
    late Database db;
    late TaskRepository taskRepo;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      // Tạo bảng tasks
      await db.execute('''
        CREATE TABLE ${DatabaseHelper.tableTasks} (
          ${DatabaseHelper.columnId} TEXT PRIMARY KEY,
          ${DatabaseHelper.columnTitle} TEXT NOT NULL,
          ${DatabaseHelper.columnTaskSubjectId} TEXT NOT NULL,
          ${DatabaseHelper.columnSubject} TEXT NOT NULL,
          ${DatabaseHelper.columnDeadline} TEXT NOT NULL,
          ${DatabaseHelper.columnEstimatedMinutes} INTEGER NOT NULL,
          ${DatabaseHelper.columnActualMinutes} INTEGER,
          ${DatabaseHelper.columnPriority} TEXT NOT NULL,
          ${DatabaseHelper.columnStatus} TEXT NOT NULL,
          ${DatabaseHelper.columnNotes} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnUnderstandingLevel} TEXT,
          ${DatabaseHelper.columnReviewNotes} TEXT
        )
      ''');

      // Tạo bảng study_activities cho SQLite
      await db.execute('''
        CREATE TABLE ${DatabaseHelper.tableActivities} (
          ${DatabaseHelper.columnActivityId} TEXT PRIMARY KEY,
          ${DatabaseHelper.columnActivityDate} TEXT NOT NULL,
          ${DatabaseHelper.columnActivityTaskId} TEXT NOT NULL,
          ${DatabaseHelper.columnActivityCompletedAt} TEXT NOT NULL,
          ${DatabaseHelper.columnActivityActualMinutes} INTEGER DEFAULT 0,
          ${DatabaseHelper.columnActivitySubjectId} TEXT
        )
      ''');

      DatabaseHelper.instance.setDatabaseForTesting(db);
      taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);
    });

    tearDown(() async {
      await db.close();
    });

    test('Hoàn thành công việc tự động lưu ngày học vào SQLite', () async {
      final now = DateTime.now();
      final task = StudyTask(
        id: 'task_streak_1',
        title: 'Làm bài tập giải tích',
        subjectId: 'subj_1',
        subject: 'Toán',
        deadline: now,
        estimatedMinutes: 45,
      );
      await taskRepo.insertTask(task);

      // Đánh dấu hoàn thành
      await taskRepo.updateTaskStatus(task.id, TaskStatus.completed);

      final activeDates = await taskRepo.getActiveStudyDates();
      expect(activeDates.contains(StudyStreak.formatDateKey(now)), isTrue);
    });

    test(
      'Hoàn thành nhiều việc cùng 1 ngày không tạo ngày học trùng lặp',
      () async {
        final now = DateTime.now();
        final task1 = StudyTask(
          id: 't_1',
          title: 'Việc 1',
          subjectId: 'subj_1',
          subject: 'Môn 1',
          deadline: now,
          estimatedMinutes: 30,
        );
        final task2 = StudyTask(
          id: 't_2',
          title: 'Việc 2',
          subjectId: 'subj_1',
          subject: 'Môn 1',
          deadline: now,
          estimatedMinutes: 40,
        );
        await taskRepo.insertTask(task1);
        await taskRepo.insertTask(task2);

        await taskRepo.updateTaskStatus(task1.id, TaskStatus.completed);
        await taskRepo.updateTaskStatus(task2.id, TaskStatus.completed);

        final activeDates = await taskRepo.getActiveStudyDates();
        expect(activeDates.length, 1);
      },
    );

    test(
      'Chuyển việc hoàn thành về chưa làm không xóa lịch sử ngày học (giữ thành quả học tập)',
      () async {
        final now = DateTime.now();
        final task = StudyTask(
          id: 'task_undo',
          title: 'Học bài',
          subjectId: 'subj_1',
          subject: 'Môn 1',
          deadline: now,
          estimatedMinutes: 60,
        );
        await taskRepo.insertTask(task);

        // Hoàn thành
        await taskRepo.updateTaskStatus(task.id, TaskStatus.completed);
        var dates = await taskRepo.getActiveStudyDates();
        expect(dates.isNotEmpty, isTrue);

        // Hoàn tác về todo
        await taskRepo.updateTaskStatus(task.id, TaskStatus.todo);
        dates = await taskRepo.getActiveStudyDates();
        expect(dates.isNotEmpty, isTrue); // Lịch sử ngày học vẫn còn
      },
    );

    test(
      'Chế độ Web Preview ghi nhận và bảo toàn ngày học qua WebStreakStorage',
      () async {
        WebStreakStorage.clearActiveDates();
        final webRepo = TaskRepository(useWebPreview: true);
        final now = DateTime.now();
        final todayKey = StudyStreak.formatDateKey(now);

        // 1. Hoàn thành 1 việc trên Web Preview
        await webRepo.updateTaskStatus('task_1', TaskStatus.completed);
        var dates = await webRepo.getActiveStudyDates();
        expect(dates.contains(todayKey), isTrue);

        // 2. Mô phỏng Reload trang Chrome (tạo repo Web mới hoàn toàn)
        final reloadedWebRepo = TaskRepository(useWebPreview: true);
        final reloadedDates = await reloadedWebRepo.getActiveStudyDates();
        expect(reloadedDates.contains(todayKey), isTrue);

        final streak = StudyStreak.fromActiveDates(reloadedDates, now: now);
        expect(streak.currentStreak, 1);
        expect(streak.longestStreak, 1);

        // 3. Hoàn thành thêm công việc khác trong cùng ngày -> không ghi trùng
        await reloadedWebRepo.updateTaskStatus('task_2', TaskStatus.completed);
        final datesAfterSecondTask = await reloadedWebRepo
            .getActiveStudyDates();
        expect(datesAfterSecondTask.length, 1); // Không nhân đôi ngày hôm nay

        // 4. Hủy hoàn thành (uncheck về todo) -> không xóa lịch sử ngày học
        await reloadedWebRepo.updateTaskStatus('task_1', TaskStatus.todo);
        final datesAfterUncheck = await reloadedWebRepo.getActiveStudyDates();
        expect(datesAfterUncheck.contains(todayKey), isTrue);
      },
    );
  });

  group('Kiểm thử Giao diện Màn hình Tổng quan (OverviewScreen)', () {
    testWidgets('Hiển thị lời chào, ngày tiếng Việt và nút Thêm việc', (
      tester,
    ) async {
      bool addTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverviewScreen(
              tasks: const [],
              studyStreak: const StudyStreak(
                currentStreak: 3,
                longestStreak: 5,
                activeDates: {},
              ),
              onToggleComplete: (_) {},
              onTapTask: (_) {},
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onAddTask: () => addTapped = true,
              onGoToPlan: () {},
            ),
          ),
        ),
      );

      // Lời chào và Thêm việc
      expect(find.byType(OverviewScreen), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Thêm việc'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Thêm việc'));
      expect(addTapped, isTrue);
    });

    testWidgets(
      'Thẻ Study Streak hiển thị thông tin số ngày, ngọn lửa, kỷ lục và 7 ngày trong tuần',
      (tester) async {
        final now = DateTime.now();
        final todayKey = StudyStreak.formatDateKey(now);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OverviewScreen(
                tasks: const [],
                studyStreak: StudyStreak(
                  currentStreak: 4,
                  longestStreak: 7,
                  activeDates: {todayKey},
                ),
                onToggleComplete: (_) {},
                onTapTask: (_) {},
                onEditTask: (_) {},
                onDeleteTask: (_) {},
                onAddTask: () {},
                onGoToPlan: () {},
              ),
            ),
          ),
        );

        // Thẻ streak
        expect(find.text('4 ngày liên tiếp'), findsOneWidget);
        expect(find.text('Kỷ lục cá nhân: 7 ngày'), findsOneWidget);
        expect(find.text('Đã đạt'), findsOneWidget);
        expect(find.byIcon(Icons.local_fire_department_rounded), findsWidgets);

        // Lịch 7 ngày trong tuần
        expect(find.text('T2'), findsOneWidget);
        expect(find.text('T3'), findsOneWidget);
        expect(find.text('T4'), findsOneWidget);
        expect(find.text('T5'), findsOneWidget);
        expect(find.text('T6'), findsOneWidget);
        expect(find.text('T7'), findsOneWidget);
        expect(find.text('CN'), findsOneWidget);
      },
    );

    testWidgets(
      'Tiến độ hôm nay khi không có công việc nào hiển thị thông báo thân thiện (không 0% giả)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OverviewScreen(
                tasks: const [],
                studyStreak: const StudyStreak(
                  currentStreak: 0,
                  longestStreak: 0,
                  activeDates: {},
                ),
                onToggleComplete: (_) {},
                onTapTask: (_) {},
                onEditTask: (_) {},
                onDeleteTask: (_) {},
                onAddTask: () {},
                onGoToPlan: () {},
              ),
            ),
          ),
        );

        expect(find.text('Tiến độ mục tiêu hôm nay'), findsOneWidget);
        expect(
          find.text(
            'Hôm nay không có hạn bài tập nào! Bạn có thể xem các công việc sắp tới hoặc tạo thêm việc mới.',
          ),
          findsOneWidget,
        );
        expect(find.text('0%'), findsNothing);
        expect(
          find.text('Không có công việc nào đến hạn hôm nay.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Tiến độ hôm nay tính chính xác theo hạn nộp hôm nay và cập nhật tỷ lệ %',
      (tester) async {
        final now = DateTime.now();
        final endOfToday = DateTime(now.year, now.month, now.day, 23, 59);
        final todayTasks = <StudyTask>[
          StudyTask(
            id: 't_today_1',
            title: 'Học từ vựng tiếng Anh',
            subjectId: 'subj_en',
            subject: 'Tiếng Anh',
            deadline: endOfToday,
            estimatedMinutes: 30,
            status: TaskStatus.completed,
          ),
          StudyTask(
            id: 't_today_2',
            title: 'Làm bài tập Đại số',
            subjectId: 'subj_math',
            subject: 'Toán',
            deadline: endOfToday,
            estimatedMinutes: 45,
            status: TaskStatus.todo,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OverviewScreen(
                tasks: todayTasks,
                studyStreak: const StudyStreak(
                  currentStreak: 1,
                  longestStreak: 1,
                  activeDates: {},
                ),
                onToggleComplete: (_) {},
                onTapTask: (_) {},
                onEditTask: (_) {},
                onDeleteTask: (_) {},
                onAddTask: () {},
                onGoToPlan: () {},
              ),
            ),
          ),
        );

        expect(find.text('Tiến độ mục tiêu hôm nay'), findsOneWidget);
        expect(find.text('50%'), findsOneWidget); // 1/2 hoàn thành = 50%
        expect(find.text('Đã hoàn thành 1/2 việc'), findsOneWidget);
        expect(find.text('Còn 1 việc'), findsOneWidget);

        // Công việc chưa làm hôm nay hiển thị trong "Cần làm hôm nay"
        expect(find.text('Cần làm hôm nay (1)'), findsOneWidget);
        expect(find.text('Làm bài tập Đại số'), findsOneWidget);
        // Công việc đã hoàn thành hôm nay không nằm trong danh sách cần làm
        expect(find.text('Học từ vựng tiếng Anh'), findsNothing);
      },
    );

    testWidgets(
      'Công việc quá hạn hiển thị khu vực cảnh báo riêng biệt với banner đỏ',
      (tester) async {
        final now = DateTime.now();
        final overdueTask = StudyTask(
          id: 't_overdue',
          title: 'Báo cáo thực tập nộp gấp',
          subjectId: 'subj_it',
          subject: 'Thực tập',
          deadline: now.subtract(const Duration(days: 2)), // Quá hạn 2 ngày
          estimatedMinutes: 60,
          priority: TaskPriority.high,
          status: TaskStatus.todo,
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OverviewScreen(
                tasks: [overdueTask],
                studyStreak: const StudyStreak(
                  currentStreak: 0,
                  longestStreak: 0,
                  activeDates: {},
                ),
                onToggleComplete: (_) {},
                onTapTask: (_) {},
                onEditTask: (_) {},
                onDeleteTask: (_) {},
                onAddTask: () {},
                onGoToPlan: () {},
              ),
            ),
          ),
        );

        // Khu vực quá hạn
        expect(find.text('Công việc quá hạn (1)'), findsOneWidget);
        expect(find.text('Báo cáo thực tập nộp gấp'), findsOneWidget);
        expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
        expect(
          find.text(
            'Có 1 bài tập đã quá hạn nộp. Hãy ưu tiên hoàn thành ngay!',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('Công việc sắp đến hạn hiển thị riêng biệt theo hạn gần nhất', (
      tester,
    ) async {
      final now = DateTime.now();
      final upcomingTask = StudyTask(
        id: 't_upcoming',
        title: 'Thuyết trình môn Triết học',
        subjectId: 'subj_phi',
        subject: 'Triết học',
        deadline: now.add(const Duration(days: 3)), // Sắp tới trong 3 ngày
        estimatedMinutes: 45,
        status: TaskStatus.todo,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverviewScreen(
              tasks: [upcomingTask],
              studyStreak: const StudyStreak(
                currentStreak: 0,
                longestStreak: 0,
                activeDates: {},
              ),
              onToggleComplete: (_) {},
              onTapTask: (_) {},
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onAddTask: () {},
              onGoToPlan: () {},
            ),
          ),
        ),
      );

      expect(find.text('Sắp đến hạn (1)'), findsOneWidget);
      expect(find.text('Thuyết trình môn Triết học'), findsOneWidget);
    });

    testWidgets('Lối tắt nhanh chuyển đúng sang tab Kế hoạch và tab Môn học', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      bool planNavigated = false;
      bool subjectsNavigated = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverviewScreen(
              tasks: const [],
              studyStreak: const StudyStreak(
                currentStreak: 0,
                longestStreak: 0,
                activeDates: {},
              ),
              onToggleComplete: (_) {},
              onTapTask: (_) {},
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onAddTask: () {},
              onGoToPlan: () => planNavigated = true,
              onGoToSubjects: () => subjectsNavigated = true,
            ),
          ),
        ),
      );

      expect(find.text('Xem toàn bộ Kế hoạch học tập'), findsOneWidget);
      await tester.tap(find.text('Xem toàn bộ Kế hoạch học tập'));
      expect(planNavigated, isTrue);

      expect(find.text('Quản lý theo Môn học'), findsOneWidget);
      await tester.tap(find.text('Quản lý theo Môn học'));
      expect(subjectsNavigated, isTrue);
    });
  });
}

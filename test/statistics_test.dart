import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/study_activity.dart';
import 'package:exampilot/models/study_statistics.dart';
import 'package:exampilot/models/study_streak.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/models/understanding_level.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/screens/statistics_screen.dart';
import 'package:exampilot/services/web_storage.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('G4: Kiểm thử Bộ tính toán thống kê (StudyStatisticsCalculator)', () {
    final now = DateTime(2026, 11, 9, 14, 0); // Thứ Hai ngày 09/11/2026
    final subjectMath = const Subject(
      id: 'sub_math',
      name: 'Toán cao cấp',
      description: 'Đại số và giải tích',
      color: Color(0xFF3B5BDB),
    );
    final subjectWeb = const Subject(
      id: 'sub_web',
      name: 'Lập trình Web',
      description: 'HTML, CSS, Flutter Web',
      color: Color(0xFF0284C7),
    );
    final subjectEmpty = const Subject(
      id: 'sub_empty',
      name: 'Môn chưa có việc',
      description: 'Môn mới tạo',
      color: Color(0xFF10B981),
    );

    test(
      '1. Tính đúng 6 chỉ số tổng quan thực tế từ công việc và hoạt động',
      () {
        final tasks = [
          StudyTask(
            id: 't1',
            title: 'Bài tập 1',
            subjectId: 'sub_math',
            subject: 'Toán cao cấp',
            deadline: now.add(const Duration(hours: 2)),
            estimatedMinutes: 60,
            status: TaskStatus.completed,
            actualMinutes: 45,
          ),
          StudyTask(
            id: 't2',
            title: 'Bài tập 2',
            subjectId: 'sub_math',
            subject: 'Toán cao cấp',
            deadline: now.add(const Duration(hours: 4)),
            estimatedMinutes: 30,
            status: TaskStatus.todo,
          ),
          StudyTask(
            id: 't3',
            title: 'Bài tập 3',
            subjectId: 'sub_web',
            subject: 'Lập trình Web',
            deadline: now.add(const Duration(days: 1)),
            estimatedMinutes: 45,
            status: TaskStatus.inProgress,
          ),
        ];

        final activities = [
          StudyActivity(
            id: 'a1',
            dateKey: StudyStreak.formatDateKey(now),
            taskId: 't1',
            completedAt: now,
            actualMinutes: 45,
            subjectId: 'sub_math',
          ),
        ];

        final stats = StudyStatisticsCalculator.calculate(
          tasks: tasks,
          subjects: [subjectMath, subjectWeb, subjectEmpty],
          activities: activities,
          period: StatisticsPeriod.allTime,
          now: now,
        );

        expect(stats.totalTasks, 3);
        expect(stats.completedTasks, 1);
        expect(stats.pendingTasks, 2);
        expect(stats.completionRate, closeTo(1 / 3, 0.001));
        expect(stats.totalActualMinutes, 45);
        expect(stats.totalSubjects, 3);
      },
    );

    test(
      '2. Biểu đồ 7 ngày (T2 -> CN) tổng hợp chính xác theo ngày hoàn thành',
      () {
        final monday = DateTime(2026, 11, 9, 10, 0); // Thứ Hai
        final wednesday = DateTime(2026, 11, 11, 15, 0); // Thứ Tư

        final activities = [
          StudyActivity(
            id: 'a_mon',
            dateKey: StudyStreak.formatDateKey(monday),
            taskId: 'task_m1',
            completedAt: monday,
            actualMinutes: 40,
            subjectId: 'sub_math',
          ),
          StudyActivity(
            id: 'a_wed',
            dateKey: StudyStreak.formatDateKey(wednesday),
            taskId: 'task_w1',
            completedAt: wednesday,
            actualMinutes: 60,
            subjectId: 'sub_web',
          ),
        ];

        final stats = StudyStatisticsCalculator.calculate(
          tasks: [],
          subjects: [subjectMath, subjectWeb],
          activities: activities,
          period: StatisticsPeriod.last7Days,
          now: monday,
        );

        expect(stats.weeklyMetrics.length, 7);
        expect(stats.hasWeeklyData, isTrue);

        // Thứ Hai (index 0)
        final monMetric = stats.weeklyMetrics[0];
        expect(monMetric.weekdayLabel, 'T2');
        expect(monMetric.completedTasks, 1);
        expect(monMetric.actualMinutes, 40);

        // Thứ Ba (index 1) - Không có hoạt động
        final tueMetric = stats.weeklyMetrics[1];
        expect(tueMetric.weekdayLabel, 'T3');
        expect(tueMetric.completedTasks, 0);
        expect(tueMetric.actualMinutes, 0);

        // Thứ Tư (index 2)
        final wedMetric = stats.weeklyMetrics[2];
        expect(wedMetric.weekdayLabel, 'T4');
        expect(wedMetric.completedTasks, 1);
        expect(wedMetric.actualMinutes, 60);

        // Chủ Nhật (index 6)
        expect(stats.weeklyMetrics[6].weekdayLabel, 'CN');
      },
    );

    test('3. hasWeeklyData = false khi không có hoạt động nào trong tuần', () {
      final stats = StudyStatisticsCalculator.calculate(
        tasks: [],
        subjects: [subjectMath],
        activities: [],
        period: StatisticsPeriod.last7Days,
        now: now,
      );

      expect(stats.hasWeeklyData, isFalse);
      expect(stats.weeklyMetrics.every((d) => d.completedTasks == 0), isTrue);
      expect(stats.weeklyMetrics.every((d) => d.actualMinutes == 0), isTrue);
    });

    test(
      '4. Thống kê theo môn học liên kết chặt chẽ qua subjectId (kể cả khi đổi tên môn)',
      () {
        // Giả sử môn học được đổi tên thành 'Giải tích chuyên sâu', nhưng subjectId vẫn là 'sub_math'
        final renamedMath = const Subject(
          id: 'sub_math',
          name: 'Giải tích chuyên sâu',
          description: 'Đã đổi tên môn',
          color: Color(0xFF3B5BDB),
        );

        final tasks = [
          StudyTask(
            id: 't_m1',
            title: 'Bài tập ma trận',
            subjectId: 'sub_math',
            subject: 'Toán cao cấp', // Tên cũ trong task
            deadline: now,
            estimatedMinutes: 50,
            status: TaskStatus.completed,
            actualMinutes: 50,
          ),
          StudyTask(
            id: 't_m2',
            title: 'Bài tập chuỗi Fourier',
            subjectId: 'sub_math',
            subject: 'Toán cao cấp',
            deadline: now,
            estimatedMinutes: 60,
            status: TaskStatus.todo,
          ),
        ];

        final activities = [
          StudyActivity(
            id: 'act_1',
            dateKey: StudyStreak.formatDateKey(now),
            taskId: 't_m1',
            completedAt: now,
            actualMinutes: 50,
            subjectId: 'sub_math',
          ),
        ];

        final stats = StudyStatisticsCalculator.calculate(
          tasks: tasks,
          subjects: [renamedMath, subjectEmpty],
          activities: activities,
          period: StatisticsPeriod.allTime,
          now: now,
        );

        final mathMetric = stats.subjectMetrics.firstWhere(
          (m) => m.subject.id == 'sub_math',
        );
        expect(mathMetric.subject.name, 'Giải tích chuyên sâu');
        expect(mathMetric.totalTasks, 2);
        expect(mathMetric.completedTasks, 1);
        expect(mathMetric.completionRate, 0.5);
        expect(mathMetric.actualMinutes, 50);

        // Môn rỗng không có công việc
        final emptyMetric = stats.subjectMetrics.firstWhere(
          (m) => m.subject.id == 'sub_empty',
        );
        expect(emptyMetric.totalTasks, 0);
        expect(emptyMetric.completedTasks, 0);
        expect(emptyMetric.completionRate, 0.0);
        expect(emptyMetric.actualMinutes, 0);
      },
    );

    test('5. Bộ lọc 7 ngày và 30 ngày chỉ tính các hoạt động trong khoảng', () {
      final today = DateTime(2026, 11, 9);
      final day10Ago = today.subtract(const Duration(days: 10));
      final day40Ago = today.subtract(const Duration(days: 40));

      final activities = [
        StudyActivity(
          id: 'act_today',
          dateKey: StudyStreak.formatDateKey(today),
          taskId: 't_today',
          completedAt: today,
          actualMinutes: 30,
          subjectId: 'sub_math',
        ),
        StudyActivity(
          id: 'act_10ago',
          dateKey: StudyStreak.formatDateKey(day10Ago),
          taskId: 't_10ago',
          completedAt: day10Ago,
          actualMinutes: 60,
          subjectId: 'sub_math',
        ),
        StudyActivity(
          id: 'act_40ago',
          dateKey: StudyStreak.formatDateKey(day40Ago),
          taskId: 't_40ago',
          completedAt: day40Ago,
          actualMinutes: 120,
          subjectId: 'sub_math',
        ),
      ];

      // 7 ngày qua: chỉ có act_today (30 phút)
      final stats7 = StudyStatisticsCalculator.calculate(
        tasks: [],
        subjects: [subjectMath],
        activities: activities,
        period: StatisticsPeriod.last7Days,
        now: today,
      );
      expect(stats7.totalActualMinutes, 30);

      // 30 ngày qua: có act_today và act_10ago (30 + 60 = 90 phút)
      final stats30 = StudyStatisticsCalculator.calculate(
        tasks: [],
        subjects: [subjectMath],
        activities: activities,
        period: StatisticsPeriod.last30Days,
        now: today,
      );
      expect(stats30.totalActualMinutes, 90);

      // Tất cả thời gian: cả 3 hoạt động (30 + 60 + 120 = 210 phút)
      final statsAll = StudyStatisticsCalculator.calculate(
        tasks: [],
        subjects: [subjectMath],
        activities: activities,
        period: StatisticsPeriod.allTime,
        now: today,
      );
      expect(statsAll.totalActualMinutes, 210);
    });
  });

  group(
    'G4: Kiểm thử Ghi nhận thời lượng học thực tế trong TaskRepository (SQLite)',
    () {
      late Database db;
      late TaskRepository repository;

      setUp(() async {
        db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
        repository = TaskRepository(dbHelper: DatabaseHelper.instance);
      });

      tearDown(() async {
        await db.close();
      });

      test(
        'Ghi nhận thời lượng thực tế khi hoàn thành và không cộng trùng',
        () async {
          final now = DateTime.now();
          final task = StudyTask(
            id: 'task_g4_1',
            title: 'Học bài SQL',
            subjectId: 'sub_sql',
            subject: 'Cơ sở dữ liệu',
            deadline: now,
            estimatedMinutes: 60,
          );

          await repository.insertTask(task);

          // 1. Hoàn thành lần 1 với 45 phút học thực tế
          await repository.recordTaskCompletion(
            task.id,
            actualMinutes: 45,
            subjectId: 'sub_sql',
          );

          var activities = await repository.getAllActivities();
          expect(activities.length, 1);
          expect(activities.first.actualMinutes, 45);
          expect(activities.first.subjectId, 'sub_sql');

          // 2. Đánh dấu hoàn thành lại với thời lượng mới 55 phút -> Không sinh thêm dòng mới (tránh cộng trùng)
          await repository.recordTaskCompletion(
            task.id,
            actualMinutes: 55,
            subjectId: 'sub_sql',
          );

          activities = await repository.getAllActivities();
          expect(activities.length, 1);
          expect(activities.first.actualMinutes, 55);

          // 3. Cập nhật đánh giá mức độ hiểu kèm sửa thời lượng thực tế
          await repository.updateTaskAssessment(
            task.id,
            UnderstandingLevel.mastered,
            'Đã hiểu rõ index',
            60,
          );

          final allTasks = await repository.getAllTasks();
          final updatedTask = allTasks.firstWhere((t) => t.id == task.id);
          expect(updatedTask.actualMinutes, 60);
          expect(updatedTask.understandingLevel, UnderstandingLevel.mastered);

          activities = await repository.getAllActivities();
          expect(activities.first.actualMinutes, 60);

          // 4. Bỏ tích hoàn thành -> Không xóa lịch sử học tập đã ghi nhận
          await repository.updateTaskStatus(task.id, TaskStatus.todo);
          final dates = await repository.getActiveStudyDates();
          expect(dates.isNotEmpty, isTrue);
        },
      );
    },
  );

  group('G4: Kiểm thử Giao diện Màn hình Thống kê (StatisticsScreen)', () {
    final now = DateTime.now();
    final sampleSubjects = [
      const Subject(
        id: 'sub_1',
        name: 'Toán cao cấp',
        description: 'Giải tích',
        color: Color(0xFF3B5BDB),
      ),
      const Subject(
        id: 'sub_2',
        name: 'Cơ sở dữ liệu',
        description: 'SQL & NoSQL',
        color: Color(0xFF0284C7),
      ),
    ];

    final sampleTasks = [
      StudyTask(
        id: 't1',
        title: 'Học đạo hàm',
        subjectId: 'sub_1',
        subject: 'Toán cao cấp',
        deadline: now,
        estimatedMinutes: 60,
        status: TaskStatus.completed,
        actualMinutes: 50,
      ),
      StudyTask(
        id: 't2',
        title: 'Bài tập SQL JOIN',
        subjectId: 'sub_2',
        subject: 'Cơ sở dữ liệu',
        deadline: now.add(const Duration(days: 1)),
        estimatedMinutes: 45,
        status: TaskStatus.todo,
      ),
    ];

    final sampleActivities = [
      StudyActivity(
        id: 'act_1',
        dateKey: StudyStreak.formatDateKey(now),
        taskId: 't1',
        completedAt: now,
        actualMinutes: 50,
        subjectId: 'sub_1',
      ),
    ];

    testWidgets(
      'Hiển thị đầy đủ tiêu đề, các chỉ số tổng quan và danh sách môn học',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatisticsScreen(
                tasks: sampleTasks,
                subjects: sampleSubjects,
                activities: sampleActivities,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Tiêu đề
        expect(find.text('Thống kê học tập'), findsOneWidget);
        expect(find.text('7 ngày qua'), findsOneWidget);
        expect(find.text('30 ngày qua'), findsOneWidget);
        expect(find.text('Tất cả thời gian'), findsOneWidget);

        // Các chỉ số
        expect(find.text('Tỷ lệ hoàn thành nhiệm vụ'), findsOneWidget);
        expect(find.text('Tổng công việc'), findsOneWidget);
        expect(find.text('Đã hoàn thành'), findsOneWidget);
        expect(find.text('Chưa hoàn thành'), findsOneWidget);
        expect(find.text('Thời lượng thực tế'), findsOneWidget);
        expect(find.text('Môn học quản lý'), findsOneWidget);

        // Biểu đồ tuần
        expect(find.text('Hoạt động học tập tuần này'), findsOneWidget);
        expect(find.text('Số việc hoàn thành'), findsOneWidget);
        expect(find.text('Thời lượng (phút)'), findsOneWidget);

        // Danh sách môn
        expect(find.text('Tiến độ theo môn học'), findsOneWidget);
        expect(find.text('Toán cao cấp'), findsOneWidget);
        expect(find.text('Cơ sở dữ liệu'), findsOneWidget);
      },
    );

    testWidgets('Tương tác chuyển khoảng thời gian cập nhật số liệu', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatisticsScreen(
              tasks: sampleTasks,
              subjects: sampleSubjects,
              activities: sampleActivities,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bấm chọn 'Tất cả thời gian'
      await tester.tap(find.text('Tất cả thời gian'));
      await tester.pumpAndSettle();

      // Số liệu vẫn hiển thị đồng bộ
      expect(find.text('2'), findsWidgets); // 2 tổng công việc
      expect(find.text('1'), findsWidgets); // 1 đã hoàn thành
    });

    testWidgets(
      'Tương tác bấm vào một ngày trong biểu đồ hiển thị chi tiết ngày đó',
      (tester) async {
        tester.view.physicalSize = const Size(800, 2000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatisticsScreen(
                tasks: sampleTasks,
                subjects: sampleSubjects,
                activities: sampleActivities,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Bấm vào cột thứ 4 (T5) - ngày chưa có hoạt động
        await tester.tap(find.text('T5'));
        await tester.pumpAndSettle();

        // Thẻ chi tiết hiển thị cập nhật thông tin
        expect(find.byIcon(Icons.bedtime_outlined), findsWidgets);
      },
    );

    testWidgets('Hiển thị thông báo trạng thái rỗng khi chưa có môn học nào', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: StatisticsScreen(tasks: [], subjects: [], activities: []),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chưa có môn học nào được quản lý.'), findsOneWidget);
      expect(
        find.text(
          'Tuần này chưa có hoạt động học tập nào. Hãy đánh dấu hoàn thành công việc để bắt đầu tích lũy!',
        ),
        findsOneWidget,
      );
    });
  });

  group('G4 Rà soát: 9 trường hợp kiểm thử đặc biệt theo yêu cầu', () {
    final monday = DateTime(2026, 11, 9, 10, 0); // Thứ Hai
    final wednesday = DateTime(2026, 11, 11, 15, 0); // Thứ Tư
    const subjectA = Subject(
      id: 'sub_a',
      name: 'Giải tích 1',
      description: 'Đại số & Giải tích',
      color: Color(0xFF3B5BDB),
    );
    const subjectB = Subject(
      id: 'sub_b',
      name: 'Vật lý đại cương',
      description: 'Cơ và nhiệt',
      color: Color(0xFF10B981),
    );

    test(
      'TH1: Deadline trong tuần nhưng chưa hoàn thành -> Không tính vào biểu đồ tuần và thời lượng',
      () {
        final taskPendingInWeek = StudyTask(
          id: 'task_pending_1',
          title: 'Bài tập tuần chưa làm',
          subjectId: 'sub_a',
          subject: 'Giải tích 1',
          deadline: wednesday, // Deadline Thứ Tư trong tuần
          estimatedMinutes: 60,
          status: TaskStatus.todo,
          actualMinutes: null,
        );

        final stats = StudyStatisticsCalculator.calculate(
          tasks: [taskPendingInWeek],
          subjects: [subjectA],
          activities: [], // Không có hoạt động học nào được ghi nhận
          period: StatisticsPeriod.last7Days,
          now: monday,
        );

        // Biểu đồ tuần không có hoạt động
        expect(stats.hasWeeklyData, isFalse);
        final wedMetric = stats.weeklyMetrics.firstWhere(
          (m) => m.weekdayLabel == 'T4',
        );
        expect(wedMetric.completedTasks, 0);
        expect(wedMetric.actualMinutes, 0);
        expect(stats.totalActualMinutes, 0);
        expect(stats.periodCompletedTasks, 0);
        expect(stats.pendingTasks, 1);
      },
    );

    test(
      'TH2: Hoàn thành trong tuần rồi chuyển lại todo -> Lịch sử hoạt động vẫn được bảo lưu trên biểu đồ tuần và thời lượng',
      () {
        final taskUnchecked = StudyTask(
          id: 'task_done_then_todo',
          title: 'Bài tập hoàn thành rồi chuyển lại todo',
          subjectId: 'sub_a',
          subject: 'Giải tích 1',
          deadline: wednesday,
          estimatedMinutes: 45,
          status: TaskStatus.todo, // Hiện tại trạng thái là todo
          actualMinutes: 45,
        );

        // Lịch sử hoạt động hoàn thành đã được ghi nhận vào Thứ Tư
        final activity = StudyActivity(
          id: 'act_wed_recorded',
          dateKey: StudyStreak.formatDateKey(wednesday),
          taskId: 'task_done_then_todo',
          completedAt: wednesday,
          actualMinutes: 45,
          subjectId: 'sub_a',
        );

        final stats = StudyStatisticsCalculator.calculate(
          tasks: [taskUnchecked],
          subjects: [subjectA],
          activities: [activity],
          period: StatisticsPeriod.last7Days,
          now: DateTime(2026, 11, 11, 18, 0), // Thứ Tư chiều
        );

        // Lịch sử hoạt động học tập vẫn được giữ nguyên trên biểu đồ tuần
        final wedMetric = stats.weeklyMetrics.firstWhere(
          (m) => m.weekdayLabel == 'T4',
        );
        expect(wedMetric.completedTasks, 1);
        expect(wedMetric.actualMinutes, 45);
        expect(stats.totalActualMinutes, 45);
        expect(stats.periodCompletedTasks, 1);
        // Trạng thái hiện tại phản ánh chính xác trạng thái todo của task
        expect(stats.currentCompletedTasks, 0);
        expect(stats.pendingTasks, 1);
      },
    );

    test(
      'TH3: Hoàn thành cách đây 15 ngày -> Không có trong last7Days, nhưng có trong last30Days và allTime',
      () {
        final day15Ago = monday.subtract(const Duration(days: 15));
        final task = StudyTask(
          id: 'task_15d_ago',
          title: 'Bài tập 15 ngày trước',
          subjectId: 'sub_a',
          subject: 'Giải tích 1',
          deadline: day15Ago,
          estimatedMinutes: 60,
          status: TaskStatus.completed,
          actualMinutes: 75,
        );

        final activity = StudyActivity(
          id: 'act_15d_ago',
          dateKey: StudyStreak.formatDateKey(day15Ago),
          taskId: 'task_15d_ago',
          completedAt: day15Ago,
          actualMinutes: 75,
          subjectId: 'sub_a',
        );

        // 1. Khoảng 7 ngày qua
        final stats7 = StudyStatisticsCalculator.calculate(
          tasks: [task],
          subjects: [subjectA],
          activities: [activity],
          period: StatisticsPeriod.last7Days,
          now: monday,
        );
        expect(stats7.periodCompletedTasks, 0);
        expect(stats7.totalActualMinutes, 0);

        // 2. Khoảng 30 ngày qua
        final stats30 = StudyStatisticsCalculator.calculate(
          tasks: [task],
          subjects: [subjectA],
          activities: [activity],
          period: StatisticsPeriod.last30Days,
          now: monday,
        );
        expect(stats30.periodCompletedTasks, 1);
        expect(stats30.totalActualMinutes, 75);

        // 3. Tất cả thời gian
        final statsAll = StudyStatisticsCalculator.calculate(
          tasks: [task],
          subjects: [subjectA],
          activities: [activity],
          period: StatisticsPeriod.allTime,
          now: monday,
        );
        expect(statsAll.periodCompletedTasks, 1);
        expect(statsAll.totalActualMinutes, 75);
      },
    );

    test(
      'TH4: Hai công việc thuộc 2 môn khác nhau -> Thống kê môn học phân định chính xác theo subjectId',
      () {
        final taskA = StudyTask(
          id: 'task_a',
          title: 'Công việc môn A',
          subjectId: 'sub_a',
          subject: 'Giải tích 1',
          deadline: monday,
          estimatedMinutes: 40,
          status: TaskStatus.completed,
          actualMinutes: 40,
        );
        final taskB = StudyTask(
          id: 'task_b',
          title: 'Công việc môn B',
          subjectId: 'sub_b',
          subject: 'Vật lý đại cương',
          deadline: monday,
          estimatedMinutes: 50,
          status: TaskStatus.completed,
          actualMinutes: 50,
        );

        final activityA = StudyActivity(
          id: 'act_a',
          dateKey: StudyStreak.formatDateKey(monday),
          taskId: 'task_a',
          completedAt: monday,
          actualMinutes: 40,
          subjectId: 'sub_a',
        );
        final activityB = StudyActivity(
          id: 'act_b',
          dateKey: StudyStreak.formatDateKey(monday),
          taskId: 'task_b',
          completedAt: monday,
          actualMinutes: 50,
          subjectId: 'sub_b',
        );

        final stats = StudyStatisticsCalculator.calculate(
          tasks: [taskA, taskB],
          subjects: [subjectA, subjectB],
          activities: [activityA, activityB],
          period: StatisticsPeriod.allTime,
          now: monday,
        );

        final metricA = stats.subjectMetrics.firstWhere(
          (m) => m.subject.id == 'sub_a',
        );
        expect(metricA.totalTasks, 1);
        expect(metricA.completedTasks, 1);
        expect(metricA.actualMinutes, 40);

        final metricB = stats.subjectMetrics.firstWhere(
          (m) => m.subject.id == 'sub_b',
        );
        expect(metricB.totalTasks, 1);
        expect(metricB.completedTasks, 1);
        expect(metricB.actualMinutes, 50);
      },
    );

    test(
      'TH5: Đổi tên môn học -> Thống kê môn học vẫn chính xác theo subjectId',
      () {
        const renamedSubjectA = Subject(
          id: 'sub_a',
          name: 'Toán cao cấp A1 (Đổi tên)',
          description: 'Môn đã đổi tên',
          color: Color(0xFF3B5BDB),
        );

        final taskA = StudyTask(
          id: 'task_a_renamed',
          title: 'Bài tập toán',
          subjectId: 'sub_a',
          subject: 'Giải tích 1', // Tên cũ lưu trong task
          deadline: monday,
          estimatedMinutes: 45,
          status: TaskStatus.completed,
          actualMinutes: 45,
        );

        final activityA = StudyActivity(
          id: 'act_a_renamed',
          dateKey: StudyStreak.formatDateKey(monday),
          taskId: 'task_a_renamed',
          completedAt: monday,
          actualMinutes: 45,
          subjectId: 'sub_a',
        );

        final stats = StudyStatisticsCalculator.calculate(
          tasks: [taskA],
          subjects: [renamedSubjectA],
          activities: [activityA],
          period: StatisticsPeriod.allTime,
          now: monday,
        );

        final metricA = stats.subjectMetrics.firstWhere(
          (m) => m.subject.id == 'sub_a',
        );
        expect(metricA.subject.name, 'Toán cao cấp A1 (Đổi tên)');
        expect(metricA.totalTasks, 1);
        expect(metricA.completedTasks, 1);
        expect(metricA.actualMinutes, 45);
      },
    );

    test(
      'TH6: Hoàn thành không nhập thời lượng (null hoặc 0) -> Số việc tăng 1, thời lượng tăng 0 phút',
      () {
        final taskNoMinutes = StudyTask(
          id: 'task_no_min',
          title: 'Hoàn thành nhanh không nhập thời lượng',
          subjectId: 'sub_a',
          subject: 'Giải tích 1',
          deadline: monday,
          estimatedMinutes: 30,
          status: TaskStatus.completed,
          actualMinutes: null, // Hoặc 0
        );

        final activityNoMinutes = StudyActivity(
          id: 'act_no_min',
          dateKey: StudyStreak.formatDateKey(monday),
          taskId: 'task_no_min',
          completedAt: monday,
          actualMinutes: 0,
          subjectId: 'sub_a',
        );

        final stats = StudyStatisticsCalculator.calculate(
          tasks: [taskNoMinutes],
          subjects: [subjectA],
          activities: [activityNoMinutes],
          period: StatisticsPeriod.allTime,
          now: monday,
        );

        expect(stats.currentCompletedTasks, 1);
        expect(stats.periodCompletedTasks, 1);
        expect(stats.totalActualMinutes, 0);

        final monMetric = stats.weeklyMetrics.firstWhere(
          (m) => m.weekdayLabel == 'T2',
        );
        expect(monMetric.completedTasks, 1);
        expect(monMetric.actualMinutes, 0);
      },
    );

    test(
      'TH7: Sửa thời lượng thông qua cập nhật đánh giá -> Cập nhật đúng, không sinh dòng trùng',
      () async {
        final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
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
        final repo = TaskRepository(dbHelper: DatabaseHelper.instance);

        final task = StudyTask(
          id: 'task_th7',
          title: 'Nhiệm vụ kiểm tra cập nhật đánh giá',
          subjectId: 'sub_a',
          subject: 'Giải tích 1',
          deadline: DateTime.now(),
          estimatedMinutes: 50,
        );
        await repo.insertTask(task);

        // 1. Đánh dấu hoàn thành ban đầu với 30 phút
        await repo.recordTaskCompletion(
          task.id,
          actualMinutes: 30,
          subjectId: 'sub_a',
        );
        var activities = await repo.getAllActivities();
        expect(activities.length, 1);
        expect(activities.first.actualMinutes, 30);

        // 2. Cập nhật đánh giá và sửa thời lượng thành 60 phút
        await repo.updateTaskAssessment(
          task.id,
          UnderstandingLevel.mastered,
          'Ghi chú ôn tập',
          60,
        );

        activities = await repo.getAllActivities();
        // Vẫn duy nhất 1 dòng hoạt động, thời lượng được cập nhật thành 60 phút
        expect(activities.length, 1);
        expect(activities.first.actualMinutes, 60);

        await db.close();
      },
    );

    test(
      'TH8: Kiểm tra toàn vẹn dữ liệu khi reload Web Preview qua WebStreakStorage',
      () {
        WebStreakStorage.clearActiveDates();

        final activitiesToSave = [
          StudyActivity(
            id: 'web_act_1',
            dateKey: '2026-11-09',
            taskId: 'task_web_1',
            completedAt: DateTime(2026, 11, 9, 10, 0),
            actualMinutes: 45,
            subjectId: 'sub_a',
          ),
          StudyActivity(
            id: 'web_act_2',
            dateKey: '2026-11-09',
            taskId: 'task_web_2',
            completedAt: DateTime(2026, 11, 9, 15, 30),
            actualMinutes: 55,
            subjectId: 'sub_b',
          ),
        ];

        // 1. Lưu vào WebStreakStorage
        WebStreakStorage.saveActivities(activitiesToSave);
        WebStreakStorage.saveActiveDates({'2026-11-09'});

        // 2. Giả lập tải lại trang bằng cách đọc từ storage
        final loadedActivities = WebStreakStorage.loadActivities();
        final loadedDates = WebStreakStorage.loadActiveDates();

        expect(loadedActivities.length, 2);
        expect(loadedActivities[0].id, 'web_act_1');
        expect(loadedActivities[0].actualMinutes, 45);
        expect(loadedActivities[1].id, 'web_act_2');
        expect(loadedActivities[1].actualMinutes, 55);
        expect(loadedDates.contains('2026-11-09'), isTrue);

        // 3. Tính toán thống kê từ dữ liệu nạp lại
        final stats = StudyStatisticsCalculator.calculate(
          tasks: [],
          subjects: [subjectA, subjectB],
          activities: loadedActivities,
          period: StatisticsPeriod.allTime,
          now: monday,
        );

        expect(stats.totalActualMinutes, 100);
        expect(stats.periodCompletedTasks, 2);

        WebStreakStorage.clearActiveDates();
      },
    );

    test(
      'TH9: Dữ liệu rỗng hoàn toàn -> Các tỷ lệ hiển thị an toàn 0%, không chia cho 0, không crash',
      () {
        final stats = StudyStatisticsCalculator.calculate(
          tasks: [],
          subjects: [],
          activities: [],
          period: StatisticsPeriod.allTime,
          now: monday,
        );

        expect(stats.totalTasks, 0);
        expect(stats.completedTasks, 0);
        expect(stats.currentCompletedTasks, 0);
        expect(stats.pendingTasks, 0);
        expect(stats.completionRate, 0.0);
        expect(stats.currentCompletionRate, 0.0);
        expect(stats.totalActualMinutes, 0);
        expect(stats.totalSubjects, 0);
        expect(stats.subjectMetrics.isEmpty, isTrue);
        expect(stats.hasWeeklyData, isFalse);
        expect(stats.weeklyMetrics.length, 7);
        for (final m in stats.weeklyMetrics) {
          expect(m.completedTasks, 0);
          expect(m.actualMinutes, 0);
        }
      },
    );
  });
}

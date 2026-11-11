import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/task_priority.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/models/understanding_level.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/screens/plan_screen.dart';
import 'package:exampilot/widgets/task_assessment_dialog.dart';
import 'package:exampilot/widgets/task_card.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Kiểm thử Mô hình UnderstandingLevel & StudyTask', () {
    test('UnderstandingLevel cung cấp đầy đủ thông tin nhãn, màu và mô tả', () {
      expect(UnderstandingLevel.notUnderstood.label, 'Chưa hiểu');
      expect(UnderstandingLevel.partiallyUnderstood.label, 'Hiểu một phần');
      expect(UnderstandingLevel.mastered.label, 'Đã nắm vững');

      expect(UnderstandingLevel.notUnderstood.color, isNotNull);
      expect(UnderstandingLevel.partiallyUnderstood.color, isNotNull);
      expect(UnderstandingLevel.mastered.color, isNotNull);
    });

    test(
      'Chuyển đổi StudyTask toMap và fromMap bảo toàn đánh giá và ghi chú gốc',
      () {
        final now = DateTime.now();
        final task = StudyTask(
          id: 't_eval_1',
          title: 'Luyện đề Toán cao cấp',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: now,
          estimatedMinutes: 60,
          priority: TaskPriority.high,
          status: TaskStatus.completed,
          notes: 'Ghi chú gốc ban đầu: Công thức khai triển Maclaurin',
          understandingLevel: UnderstandingLevel.partiallyUnderstood,
          reviewNotes: 'Cần làm thêm bài tập tính phần dư Peano',
        );

        final map = task.toMap();
        expect(map['understanding_level'], 'partiallyUnderstood');
        expect(map['review_notes'], 'Cần làm thêm bài tập tính phần dư Peano');
        expect(
          map['notes'],
          'Ghi chú gốc ban đầu: Công thức khai triển Maclaurin',
        );

        final restored = StudyTask.fromMap(map);
        expect(
          restored.understandingLevel,
          UnderstandingLevel.partiallyUnderstood,
        );
        expect(restored.reviewNotes, 'Cần làm thêm bài tập tính phần dư Peano');
        expect(
          restored.notes,
          'Ghi chú gốc ban đầu: Công thức khai triển Maclaurin',
        );
        expect(restored.isAssessed, isTrue);
      },
    );

    test('copyWith cập nhật đánh giá hoặc xóa đánh giá an toàn', () {
      final task = StudyTask(
        id: 't1',
        title: 'Học bài',
        subject: 'Toán',
        deadline: DateTime.now(),
        estimatedMinutes: 30,
        understandingLevel: UnderstandingLevel.mastered,
        reviewNotes: 'Đã hiểu tốt',
      );

      final cleared = task.copyWith(
        clearUnderstandingLevel: true,
        clearReviewNotes: true,
      );
      expect(cleared.understandingLevel, isNull);
      expect(cleared.reviewNotes, isNull);
      expect(cleared.isAssessed, isFalse);
    });
  });

  group('Kiểm thử TaskRepository lưu trữ đánh giá mức độ hiểu bài', () {
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
      DatabaseHelper.instance.setDatabaseForTesting(db);
      repository = TaskRepository(dbHelper: DatabaseHelper.instance);
    });

    tearDown(() async {
      await db.close();
    });

    test('Cập nhật đánh giá mức độ hiểu trong SQLite bền vững', () async {
      final task = StudyTask(
        id: 'task_sqlite_eval',
        title: 'Thực hành SQL',
        subjectId: 'subj_3',
        subject: 'Cơ sở dữ liệu',
        deadline: DateTime.now(),
        estimatedMinutes: 45,
        status: TaskStatus.completed,
      );

      await repository.insertTask(task);
      await repository.updateTaskAssessment(
        'task_sqlite_eval',
        UnderstandingLevel.mastered,
        'Nắm vững INNER JOIN và LEFT JOIN',
      );

      final loaded = await repository.getAllTasks();
      final target = loaded.firstWhere((t) => t.id == 'task_sqlite_eval');
      expect(target.understandingLevel, UnderstandingLevel.mastered);
      expect(target.reviewNotes, 'Nắm vững INNER JOIN và LEFT JOIN');
    });

    test('Cập nhật đánh giá trong chế độ Web Preview', () async {
      final webRepo = TaskRepository(useWebPreview: true);
      await webRepo.updateTaskAssessment(
        'task_1',
        UnderstandingLevel.notUnderstood,
        'Cần ôn lại đạo hàm hàm hợp',
      );

      final loaded = await webRepo.getAllTasks();
      final target = loaded.firstWhere((t) => t.id == 'task_1');
      expect(target.understandingLevel, UnderstandingLevel.notUnderstood);
      expect(target.reviewNotes, 'Cần ôn lại đạo hàm hàm hợp');
    });
  });

  group('Kiểm thử Giao diện Màn hình Kế hoạch (PlanScreen)', () {
    final now = DateTime.now();
    final testSubjects = [
      const Subject(id: 'subj_1', name: 'Toán cao cấp', description: ''),
      const Subject(id: 'subj_2', name: 'Lập trình Web', description: ''),
      const Subject(id: 'subj_3', name: 'Cơ sở dữ liệu', description: ''),
    ];

    final sampleTasks = [
      StudyTask(
        id: 'task_a',
        title: 'Ôn tập Đạo hàm',
        subjectId: 'subj_1',
        subject: 'Toán cao cấp',
        deadline: now.add(const Duration(hours: 2)),
        estimatedMinutes: 60,
        priority: TaskPriority.high,
        status: TaskStatus.todo,
      ),
      StudyTask(
        id: 'task_b',
        title: 'Viết câu truy vấn SQL',
        subjectId: 'subj_3',
        subject: 'Cơ sở dữ liệu',
        deadline: now.add(const Duration(hours: 6)),
        estimatedMinutes: 45,
        priority: TaskPriority.medium,
        status: TaskStatus.inProgress,
      ),
      StudyTask(
        id: 'task_c',
        title: 'Học CSS Grid nâng cao',
        subjectId: 'subj_2',
        subject: 'Lập trình Web',
        deadline: now.add(const Duration(hours: 10)),
        estimatedMinutes: 30,
        priority: TaskPriority.low,
        status: TaskStatus.completed,
        understandingLevel: UnderstandingLevel.mastered,
      ),
    ];

    Widget createTestableWidget({List<StudyTask>? tasks}) {
      return MaterialApp(
        home: Scaffold(
          body: PlanScreen(
            tasks: tasks ?? sampleTasks,
            subjects: testSubjects,
            onToggleComplete: (_) {},
            onTapTask: (_) {},
            onEditTask: (_) {},
            onDeleteTask: (_) {},
            onAddTask: () {},
          ),
        ),
      );
    }

    testWidgets('Hiển thị đủ 3 công việc và thanh tìm kiếm, bộ lọc', (
      tester,
    ) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pumpAndSettle();

      expect(find.text('Kế hoạch học tập'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Ôn tập Đạo hàm'), findsOneWidget);
      expect(find.text('Viết câu truy vấn SQL'), findsOneWidget);
      expect(find.text('Học CSS Grid nâng cao'), findsOneWidget);
      expect(find.text('Đã nắm vững'), findsOneWidget);
    });

    testWidgets('Tìm kiếm theo thời gian thực lọc đúng kết quả', (
      tester,
    ) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pumpAndSettle();

      // Nhập từ khóa 'SQL' vào ô tìm kiếm
      await tester.enterText(find.byType(TextField), 'SQL');
      await tester.pumpAndSettle();

      expect(find.text('Viết câu truy vấn SQL'), findsOneWidget);
      expect(find.text('Ôn tập Đạo hàm'), findsNothing);
      expect(find.text('Học CSS Grid nâng cao'), findsNothing);
    });

    testWidgets(
      'Tìm kiếm không có kết quả hiển thị trạng thái rỗng và nút xóa bộ lọc',
      (tester) async {
        await tester.pumpWidget(createTestableWidget());
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'từ khóa không tồn tại');
        await tester.pumpAndSettle();

        expect(find.text('Không tìm thấy kết quả phù hợp'), findsOneWidget);
        expect(find.text('Xóa tất cả bộ lọc & tìm kiếm'), findsOneWidget);

        // Bấm nút xóa bộ lọc
        await tester.tap(find.text('Xóa tất cả bộ lọc & tìm kiếm'));
        await tester.pumpAndSettle();

        // Phục hồi lại danh sách 3 việc
        expect(find.text('Ôn tập Đạo hàm'), findsOneWidget);
        expect(find.text('Viết câu truy vấn SQL'), findsOneWidget);
      },
    );

    testWidgets('Lọc theo trạng thái Hoàn thành', (tester) async {
      await tester.pumpWidget(createTestableWidget());
      await tester.pumpAndSettle();

      // Nhấn vào chip 'Hoàn thành'
      await tester.tap(find.text('Hoàn thành'));
      await tester.pumpAndSettle();

      expect(find.text('Học CSS Grid nâng cao'), findsOneWidget);
      expect(find.text('Ôn tập Đạo hàm'), findsNothing);
      expect(find.text('Viết câu truy vấn SQL'), findsNothing);
    });

    testWidgets(
      'Xác nhận xóa công việc qua TaskCard hiển thị hộp thoại xác nhận',
      (tester) async {
        bool deleted = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TaskCard(
                task: sampleTasks.first,
                onToggleComplete: (_) {},
                onTap: () {},
                onEdit: () {},
                onDelete: () => deleted = true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Mở menu popup
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await tester.pumpAndSettle();

        // Chọn Xóa
        await tester.tap(find.text('Xóa'));
        await tester.pumpAndSettle();

        // Hộp thoại xác nhận xuất hiện
        expect(find.text('Xác nhận xóa'), findsOneWidget);
        expect(deleted, isFalse);

        // Bấm Xóa trong hộp thoại
        await tester.tap(find.widgetWithText(FilledButton, 'Xóa'));
        await tester.pumpAndSettle();

        expect(deleted, isTrue);
      },
    );

    testWidgets('Hộp thoại TaskAssessmentDialog chọn mức độ và lưu đánh giá', (
      tester,
    ) async {
      UnderstandingLevel? savedLevel;
      String? savedReview;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskAssessmentDialog(
              task: sampleTasks.first,
              onSave: (lvl, rev) {
                savedLevel = lvl;
                savedReview = rev;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Đánh giá mức độ hiểu bài'), findsOneWidget);
      expect(find.text('Đã nắm vững'), findsOneWidget);

      // Chọn mức 'Đã nắm vững'
      await tester.tap(find.text('Đã nắm vững'));
      await tester.pumpAndSettle();

      // Cuộn đến TextField và nhập ghi chú ôn tập
      final textFieldFinder = find.byKey(
        const ValueKey('assessment_review_notes'),
      );
      await tester.scrollUntilVisible(textFieldFinder, 100);
      await tester.pumpAndSettle();

      await tester.enterText(
        textFieldFinder,
        'Đã hiểu toàn bộ định lý và áp dụng tốt.',
      );
      await tester.pumpAndSettle();

      // Bấm nút Lưu đánh giá
      await tester.tap(find.widgetWithText(FilledButton, 'Lưu đánh giá'));
      await tester.pumpAndSettle();

      expect(savedLevel, UnderstandingLevel.mastered);
      expect(savedReview, 'Đã hiểu toàn bộ định lý và áp dụng tốt.');
    });
  });

  group('G8.2: Hoàn thiện UX Kế hoạch học tập (Tìm kiếm, Sắp xếp, FAB Padding)', () {
    final now = DateTime.now();
    final testSubjects = [
      const Subject(id: 'subj_1', name: 'Toán cao cấp', description: ''),
      const Subject(id: 'subj_2', name: 'Lập trình Web', description: ''),
      const Subject(id: 'subj_3', name: 'Cơ sở dữ liệu', description: ''),
    ];

    Widget buildPlanScreen(List<StudyTask> tasks) {
      return MaterialApp(
        home: Scaffold(
          body: PlanScreen(
            tasks: tasks,
            subjects: testSubjects,
            onToggleComplete: (_) {},
            onTapTask: (_) {},
            onEditTask: (_) {},
            onDeleteTask: (_) {},
            onAddTask: () {},
          ),
        ),
      );
    }

    testWidgets('G8.2-1: Tìm kiếm theo tên công việc', (tester) async {
      final tasks = [
        StudyTask(
          id: 't1',
          title: 'Giải tích hàm một biến',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: now.add(const Duration(hours: 1)),
          estimatedMinutes: 30,
        ),
        StudyTask(
          id: 't2',
          title: 'Thiết kế lược đồ ERD',
          subjectId: 'subj_3',
          subject: 'Cơ sở dữ liệu',
          deadline: now.add(const Duration(hours: 2)),
          estimatedMinutes: 45,
        ),
      ];

      await tester.pumpWidget(buildPlanScreen(tasks));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Giải tích');
      await tester.pumpAndSettle();

      expect(find.text('Giải tích hàm một biến'), findsOneWidget);
      expect(find.text('Thiết kế lược đồ ERD'), findsNothing);
    });

    testWidgets('G8.2-2: Tìm kiếm theo mô tả công việc (notes & reviewNotes)', (
      tester,
    ) async {
      final tasks = [
        StudyTask(
          id: 't1',
          title: 'Bài tập 1',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: now.add(const Duration(hours: 1)),
          estimatedMinutes: 30,
          notes: 'Lưu ý công thức Fermat và Maclaurin',
        ),
        StudyTask(
          id: 't2',
          title: 'Bài tập 2',
          subjectId: 'subj_3',
          subject: 'Cơ sở dữ liệu',
          deadline: now.add(const Duration(hours: 2)),
          estimatedMinutes: 45,
          reviewNotes: 'Khái niệm chỉ mục B-Tree và Hash index',
        ),
      ];

      await tester.pumpWidget(buildPlanScreen(tasks));
      await tester.pumpAndSettle();

      // Tìm theo notes
      await tester.enterText(find.byType(TextField), 'Fermat');
      await tester.pumpAndSettle();
      expect(find.text('Bài tập 1'), findsOneWidget);
      expect(find.text('Bài tập 2'), findsNothing);

      // Tìm theo reviewNotes
      await tester.enterText(find.byType(TextField), 'B-Tree');
      await tester.pumpAndSettle();
      expect(find.text('Bài tập 2'), findsOneWidget);
      expect(find.text('Bài tập 1'), findsNothing);
    });

    testWidgets('G8.2-3: Tìm kiếm theo tên môn học liên kết', (tester) async {
      final tasks = [
        StudyTask(
          id: 't1',
          title: 'Chuẩn bị bài thuyết trình',
          subjectId: 'subj_3',
          subject: 'Cơ sở dữ liệu',
          deadline: now.add(const Duration(hours: 3)),
          estimatedMinutes: 60,
        ),
        StudyTask(
          id: 't2',
          title: 'Làm bài trắc nghiệm',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: now.add(const Duration(hours: 4)),
          estimatedMinutes: 20,
        ),
      ];

      await tester.pumpWidget(buildPlanScreen(tasks));
      await tester.pumpAndSettle();

      // Nhập tên môn 'Cơ sở dữ liệu'
      await tester.enterText(find.byType(TextField), 'Cơ sở dữ liệu');
      await tester.pumpAndSettle();

      expect(find.text('Chuẩn bị bài thuyết trình'), findsOneWidget);
      expect(find.text('Làm bài trắc nghiệm'), findsNothing);
    });

    testWidgets('G8.2-4: Tìm kiếm không phân biệt hoa thường', (tester) async {
      final tasks = [
        StudyTask(
          id: 't1',
          title: 'Thực hành SQL Query',
          subjectId: 'subj_3',
          subject: 'Cơ sở dữ liệu',
          deadline: now.add(const Duration(hours: 3)),
          estimatedMinutes: 60,
        ),
      ];

      await tester.pumpWidget(buildPlanScreen(tasks));
      await tester.pumpAndSettle();

      // Nhập chữ thường 'cơ sở dữ liệu'
      await tester.enterText(find.byType(TextField), 'cơ sở dữ liệu');
      await tester.pumpAndSettle();
      expect(find.text('Thực hành SQL Query'), findsOneWidget);

      // Nhập HOA 'CƠ SỞ DỮ LIỆU'
      await tester.enterText(find.byType(TextField), 'CƠ SỞ DỮ LIỆU');
      await tester.pumpAndSettle();
      expect(find.text('Thực hành SQL Query'), findsOneWidget);

      // Nhập 'sql query'
      await tester.enterText(find.byType(TextField), 'sql query');
      await tester.pumpAndSettle();
      expect(find.text('Thực hành SQL Query'), findsOneWidget);
    });

    testWidgets('G8.2-5: Kết hợp tìm kiếm với bộ lọc trạng thái', (
      tester,
    ) async {
      final tasks = [
        StudyTask(
          id: 't1',
          title: 'Bài tập 1 Toán',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: now.add(const Duration(hours: 1)),
          estimatedMinutes: 30,
          status: TaskStatus.todo,
        ),
        StudyTask(
          id: 't2',
          title: 'Bài tập 2 Toán',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: now.add(const Duration(hours: 2)),
          estimatedMinutes: 30,
          status: TaskStatus.completed,
        ),
        StudyTask(
          id: 't3',
          title: 'Bài tập 3 Web',
          subjectId: 'subj_2',
          subject: 'Lập trình Web',
          deadline: now.add(const Duration(hours: 3)),
          estimatedMinutes: 30,
          status: TaskStatus.todo,
        ),
      ];

      await tester.pumpWidget(buildPlanScreen(tasks));
      await tester.pumpAndSettle();

      // Bật lọc 'Chưa làm'
      await tester.tap(find.text('Chưa làm'));
      await tester.pumpAndSettle();

      // Nhập tìm kiếm 'Toán'
      await tester.enterText(find.byType(TextField), 'Toán');
      await tester.pumpAndSettle();

      // Chỉ có Bài tập 1 Toán (todo) thỏa mãn cả hai điều kiện
      expect(find.text('Bài tập 1 Toán'), findsOneWidget);
      expect(find.text('Bài tập 2 Toán'), findsNothing);
      expect(find.text('Bài tập 3 Web'), findsNothing);
    });

    testWidgets('G8.2-6: Kết hợp tìm kiếm với bộ lọc môn học', (tester) async {
      final tasks = [
        StudyTask(
          id: 't1',
          title: 'Ôn thi trắc nghiệm',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: now.add(const Duration(hours: 1)),
          estimatedMinutes: 30,
        ),
        StudyTask(
          id: 't2',
          title: 'Ôn thi trắc nghiệm',
          subjectId: 'subj_3',
          subject: 'Cơ sở dữ liệu',
          deadline: now.add(const Duration(hours: 2)),
          estimatedMinutes: 45,
        ),
      ];

      await tester.pumpWidget(buildPlanScreen(tasks));
      await tester.pumpAndSettle();

      // Chọn lọc môn 'Toán cao cấp'
      await tester.tap(find.widgetWithText(ActionChip, 'Toán cao cấp'));
      await tester.pumpAndSettle();

      // Tìm kiếm 'trắc nghiệm'
      await tester.enterText(find.byType(TextField), 'trắc nghiệm');
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TaskCard, 'Ôn thi trắc nghiệm'),
        findsOneWidget,
      );
      // Kiểm tra chỉ còn nhiệm vụ của Toán cao cấp, không còn nhiệm vụ của Cơ sở dữ liệu
      expect(find.widgetWithText(TaskCard, 'Toán cao cấp'), findsOneWidget);
      expect(find.widgetWithText(TaskCard, 'Cơ sở dữ liệu'), findsNothing);
    });

    testWidgets('G8.2-7: Sắp xếp deadline khi có công việc không có deadline', (
      tester,
    ) async {
      final tasks = [
        StudyTask(
          id: 't_no_deadline',
          title: 'Việc không hạn chót',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: null,
          estimatedMinutes: 30,
        ),
        StudyTask(
          id: 't_soon',
          title: 'Việc hạn gần',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: now.add(const Duration(hours: 2)),
          estimatedMinutes: 30,
        ),
        StudyTask(
          id: 't_later',
          title: 'Việc hạn xa',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: now.add(const Duration(days: 5)),
          estimatedMinutes: 30,
        ),
      ];

      await tester.pumpWidget(buildPlanScreen(tasks));
      await tester.pumpAndSettle();

      // Mặc định sắp xếp 'Hạn chót gần nhất': Việc hạn gần -> Việc hạn xa -> Việc không hạn chót
      final firstPos = tester.getTopLeft(find.text('Việc hạn gần')).dy;
      final secondPos = tester.getTopLeft(find.text('Việc hạn xa')).dy;
      final thirdPos = tester.getTopLeft(find.text('Việc không hạn chót')).dy;

      expect(firstPos < secondPos, isTrue);
      expect(secondPos < thirdPos, isTrue);
      expect(find.text('Không có hạn chót'), findsOneWidget);
    });

    testWidgets('G8.2-8: Sắp xếp theo ưu tiên và theo trạng thái', (
      tester,
    ) async {
      final tasks = [
        StudyTask(
          id: 't_low',
          title: 'Việc ưu tiên thấp',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          priority: TaskPriority.low,
          status: TaskStatus.completed,
          deadline: now.add(const Duration(hours: 1)),
        ),
        StudyTask(
          id: 't_high',
          title: 'Việc ưu tiên cao',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          priority: TaskPriority.high,
          status: TaskStatus.todo,
          deadline: now.add(const Duration(hours: 2)),
        ),
        StudyTask(
          id: 't_med',
          title: 'Việc ưu tiên trung bình',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          priority: TaskPriority.medium,
          status: TaskStatus.inProgress,
          deadline: now.add(const Duration(hours: 3)),
        ),
      ];

      await tester.pumpWidget(buildPlanScreen(tasks));
      await tester.pumpAndSettle();

      // Mở menu sắp xếp và chọn 'Ưu tiên cao nhất'
      await tester.tap(find.byTooltip('Sắp xếp danh sách'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ưu tiên cao nhất'));
      await tester.pumpAndSettle();

      final highPos = tester.getTopLeft(find.text('Việc ưu tiên cao')).dy;
      final medPos = tester.getTopLeft(find.text('Việc ưu tiên trung bình')).dy;
      final lowPos = tester.getTopLeft(find.text('Việc ưu tiên thấp')).dy;

      expect(highPos < medPos, isTrue);
      expect(medPos < lowPos, isTrue);

      // Mở menu sắp xếp và chọn 'Trạng thái công việc'
      await tester.tap(find.byTooltip('Sắp xếp danh sách'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trạng thái công việc'));
      await tester.pumpAndSettle();

      // Thứ tự trạng thái: todo (Việc ưu tiên cao) -> inProgress (Việc ưu tiên trung bình) -> completed (Việc ưu tiên thấp)
      final statusTodoPos = tester.getTopLeft(find.text('Việc ưu tiên cao')).dy;
      final statusInProgPos = tester
          .getTopLeft(find.text('Việc ưu tiên trung bình'))
          .dy;
      final statusCompPos = tester
          .getTopLeft(find.text('Việc ưu tiên thấp'))
          .dy;

      expect(statusTodoPos < statusInProgPos, isTrue);
      expect(statusInProgPos < statusCompPos, isTrue);
    });

    testWidgets(
      'G8.2-9: FAB không che nội dung cuối danh sách (Bottom padding >= 80dp)',
      (tester) async {
        final tasks = List.generate(
          10,
          (i) => StudyTask(
            id: 'task_$i',
            title: 'Nhiệm vụ dài $i',
            subjectId: 'subj_1',
            subject: 'Toán cao cấp',
            deadline: now.add(Duration(hours: i + 1)),
          ),
        );

        await tester.pumpWidget(buildPlanScreen(tasks));
        await tester.pumpAndSettle();

        // Kiểm tra ListView có bottom padding >= 80dp để đảm bảo không bị FAB che
        final listView = tester.widget<ListView>(find.byType(ListView));
        final padding = listView.padding as EdgeInsets;
        expect(padding.bottom, greaterThanOrEqualTo(80.0));
      },
    );

    testWidgets(
      'G8.2-10: Hiển thị đúng Empty State khi không có kết quả và xóa bộ lọc',
      (tester) async {
        final tasks = [
          StudyTask(
            id: 't1',
            title: 'Học bài',
            subjectId: 'subj_1',
            subject: 'Toán cao cấp',
            deadline: now.add(const Duration(hours: 1)),
          ),
        ];

        await tester.pumpWidget(buildPlanScreen(tasks));
        await tester.pumpAndSettle();

        // Tìm từ khóa vô nghĩa
        await tester.enterText(find.byType(TextField), 'zyxwvu_invalid');
        await tester.pumpAndSettle();

        expect(find.text('Không tìm thấy kết quả phù hợp'), findsOneWidget);
        expect(find.text('Xóa tất cả bộ lọc & tìm kiếm'), findsOneWidget);

        // Bấm nút xóa bộ lọc
        await tester.tap(find.text('Xóa tất cả bộ lọc & tìm kiếm'));
        await tester.pumpAndSettle();

        expect(find.text('Học bài'), findsOneWidget);
      },
    );
  });
}

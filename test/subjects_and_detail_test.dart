import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/models/understanding_level.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/screens/subject_detail_screen.dart';
import 'package:exampilot/screens/subjects_screen.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SubjectRepository subjectRepo;
  late TaskRepository taskRepo;

  final now = DateTime.now();

  setUp(() async {
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // Tạo bảng subjects
    await db.execute('''
      CREATE TABLE ${DatabaseHelper.tableSubjects} (
        ${DatabaseHelper.columnSubjectId} TEXT PRIMARY KEY,
        ${DatabaseHelper.columnSubjectName} TEXT NOT NULL,
        ${DatabaseHelper.columnSubjectDescription} TEXT NOT NULL,
        ${DatabaseHelper.columnSubjectIcon} INTEGER NOT NULL,
        ${DatabaseHelper.columnSubjectColor} INTEGER NOT NULL
      )
    ''');

    // Tạo bảng study_tasks
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
    subjectRepo = SubjectRepository(dbHelper: DatabaseHelper.instance);
    taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);

    // Nạp các môn mặc định
    for (final s in SubjectRepository.getDefaultSubjects()) {
      await subjectRepo.insertSubject(s);
    }
  });

  tearDown(() async {
    await db.close();
  });

  group('Kiểm thử Giai đoạn 2: Quản lý Môn học trong Repository & SQLite', () {
    test('1. Thêm môn học mới và lưu trữ bền vững', () async {
      const newSubject = Subject(
        id: 'subj_mobile',
        name: 'Lập trình Di động',
        description: 'Phát triển ứng dụng Flutter & Dart',
        icon: Icons.phone_android_rounded,
        color: Color(0xFF009688),
      );

      await subjectRepo.insertSubject(newSubject);
      final list = await subjectRepo.getAllSubjects();

      expect(list.any((s) => s.id == 'subj_mobile'), isTrue);
      final found = list.firstWhere((s) => s.id == 'subj_mobile');
      expect(found.name, 'Lập trình Di động');
      expect(found.description, 'Phát triển ứng dụng Flutter & Dart');
    });

    test(
      '2. Chỉnh sửa tên và mô tả môn học và đồng bộ tên môn trong task',
      () async {
        final oldSub = (await subjectRepo.getAllSubjects()).firstWhere(
          (s) => s.id == 'subj_1',
        );
        final updatedSub = oldSub.copyWith(
          name: 'Toán cao cấp A1',
          description: 'Giải tích một biến và phương trình vi phân',
        );

        await subjectRepo.updateSubject(updatedSub);
        await taskRepo.updateTasksSubjectName('subj_1', 'Toán cao cấp A1');

        final list = await subjectRepo.getAllSubjects();
        expect(
          list.firstWhere((s) => s.id == 'subj_1').name,
          'Toán cao cấp A1',
        );
      },
    );

    test(
      '3. Xóa môn học an toàn và chuyển giao nhiệm vụ sang môn khác',
      () async {
        // Thêm 2 nhiệm vụ thuộc môn subj_4 (Tiếng Anh)
        await taskRepo.insertTask(
          StudyTask(
            id: 't_eng_1',
            title: 'Học 30 từ vựng IT',
            subjectId: 'subj_4',
            subject: 'Tiếng Anh',
            deadline: now,
            estimatedMinutes: 30,
          ),
        );

        // Chuyển toàn bộ nhiệm vụ của subj_4 sang subj_2 (Lập trình Web)
        await taskRepo.migrateTasksSubject('subj_4', 'subj_2', 'Lập trình Web');
        await subjectRepo.deleteSubject('subj_4');

        final subjects = await subjectRepo.getAllSubjects();
        expect(subjects.any((s) => s.id == 'subj_4'), isFalse);

        final tasks = await taskRepo.getAllTasks();
        final migratedTask = tasks.firstWhere((t) => t.id == 't_eng_1');
        expect(migratedTask.subjectId, 'subj_2');
        expect(migratedTask.subject, 'Lập trình Web');
      },
    );

    test(
      '12. Thao tác trên môn này không ảnh hưởng đến dữ liệu các môn khác',
      () async {
        await taskRepo.insertTask(
          StudyTask(
            id: 't_math_unique',
            title: 'Làm đề thi thử Toán',
            subjectId: 'subj_1',
            subject: 'Toán cao cấp',
            deadline: now,
            estimatedMinutes: 90,
            status: TaskStatus.completed,
            understandingLevel: UnderstandingLevel.mastered,
          ),
        );
        await taskRepo.insertTask(
          StudyTask(
            id: 't_web_unique',
            title: 'Thiết kế giao diện CSS',
            subjectId: 'subj_2',
            subject: 'Lập trình Web',
            deadline: now,
            estimatedMinutes: 45,
            status: TaskStatus.todo,
          ),
        );

        // Cập nhật môn Toán sang hoàn thành đánh giá khác
        await taskRepo.updateTaskAssessment(
          't_math_unique',
          UnderstandingLevel.partiallyUnderstood,
          'Cần luyện thêm',
        );

        final tasks = await taskRepo.getAllTasks();
        final mathTask = tasks.firstWhere((t) => t.id == 't_math_unique');
        final webTask = tasks.firstWhere((t) => t.id == 't_web_unique');

        expect(
          mathTask.understandingLevel,
          UnderstandingLevel.partiallyUnderstood,
        );
        expect(webTask.status, TaskStatus.todo);
        expect(webTask.understandingLevel, isNull);
      },
    );
  });

  group('Kiểm thử Giao diện Màn hình Môn học (SubjectsScreen) & Thẻ tiến độ', () {
    testWidgets(
      'Thẻ môn học hiển thị đầy đủ tên, mô tả, số việc và thanh tiến độ thực tế',
      (tester) async {
        final subjects = SubjectRepository.getDefaultSubjects();
        final tasks = [
          StudyTask(
            id: 't1',
            title: 'Bài tập 1',
            subjectId: 'subj_1',
            subject: 'Toán cao cấp',
            deadline: now,
            estimatedMinutes: 30,
            status: TaskStatus.completed,
          ),
          StudyTask(
            id: 't2',
            title: 'Bài tập 2',
            subjectId: 'subj_1',
            subject: 'Toán cao cấp',
            deadline: now,
            estimatedMinutes: 45,
            status: TaskStatus.todo,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SubjectsScreen(
                subjects: subjects,
                tasks: tasks,
                onAddSubject: (_) {},
                onUpdateSubject: (_) {},
                onDeleteSubject: (_, {migrateToSubjectId}) {},
                onToggleCompleteTask: (_) {},
                onTapTask: (_) {},
                onEditTask: (_) {},
                onDeleteTask: (_) {},
                onAddTaskForSubject: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Môn học của tôi'), findsOneWidget);
        expect(find.text('Toán cao cấp'), findsWidgets);
        // Môn Toán có 2 việc, 1 hoàn thành -> "1/2 việc đã hoàn thành" & "50%"
        expect(find.text('1/2 việc đã hoàn thành'), findsOneWidget);
        expect(find.text('50%'), findsOneWidget);
        // Các môn chưa có việc -> "Chưa có công việc" & "0%"
        expect(find.text('Chưa có công việc'), findsWidgets);
      },
    );

    testWidgets('Trạng thái rỗng khi không có môn học nào', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SubjectsScreen(
              subjects: const [],
              tasks: const [],
              onAddSubject: (_) {},
              onUpdateSubject: (_) {},
              onDeleteSubject: (_, {migrateToSubjectId}) {},
              onToggleCompleteTask: (_) {},
              onTapTask: (_) {},
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onAddTaskForSubject: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Chưa có môn học nào'), findsOneWidget);
      expect(find.text('Tạo môn học đầu tiên'), findsOneWidget);
    });
  });

  group('Kiểm thử Giao diện Màn hình Chi tiết Môn học (SubjectDetailScreen)', () {
    const testSubject = Subject(
      id: 'subj_test',
      name: 'Kiến trúc Phần mềm',
      description: 'Mô hình MVC, Clean Architecture và Design Patterns',
      icon: Icons.architecture_rounded,
      color: Color(0xFF7C3AED),
    );

    testWidgets(
      '5. Môn học không có công việc: Hiển thị 0% tiến độ và thông báo phù hợp',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: SubjectDetailScreen(
              subject: testSubject,
              allSubjects: const [testSubject],
              tasks: const [],
              onToggleComplete: (_) {},
              onTapTask: (_) {},
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onAddTaskForThisSubject: () {},
              onEditSubject: () {},
              onDeleteSubject: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Kiến trúc Phần mềm'), findsWidgets);
        expect(find.text('Tổng nhiệm vụ'), findsOneWidget);
        expect(find.text('0% hoàn thành'), findsOneWidget);
        expect(
          find.text('Môn "Kiến trúc Phần mềm" chưa có nhiệm vụ nào.'),
          findsOneWidget,
        );
        expect(find.text('Thêm nhiệm vụ ngay'), findsOneWidget);
        expect(find.text('Thêm việc môn này'), findsOneWidget);
      },
    );

    testWidgets(
      '6 & 7. Môn có công việc: Tính toán đúng các chỉ số và lọc chính xác theo subjectId',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final tasks = [
          StudyTask(
            id: 't_match_1',
            title: 'Học Clean Architecture',
            subjectId: 'subj_test',
            subject: 'Kiến trúc Phần mềm',
            deadline: now,
            estimatedMinutes: 60,
            status: TaskStatus.completed,
            understandingLevel: UnderstandingLevel.mastered,
          ),
          StudyTask(
            id: 't_match_2',
            title: 'Thiết kế mẫu Singleton & Factory',
            subjectId: 'subj_test',
            subject: 'Kiến trúc Phần mềm',
            deadline: now.add(const Duration(hours: 3)),
            estimatedMinutes: 45,
            status: TaskStatus.inProgress,
          ),
          // Task của môn khác không được hiển thị ở đây
          StudyTask(
            id: 't_other',
            title: 'Bài tập môn khác',
            subjectId: 'subj_other',
            subject: 'Môn khác',
            deadline: now,
            estimatedMinutes: 30,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: SubjectDetailScreen(
              subject: testSubject,
              allSubjects: const [testSubject],
              tasks: tasks,
              onToggleComplete: (_) {},
              onTapTask: (_) {},
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onAddTaskForThisSubject: () {},
              onEditSubject: () {},
              onDeleteSubject: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Chỉ hiển thị 2 task thuộc môn Kiến trúc Phần mềm
        expect(find.text('Học Clean Architecture'), findsOneWidget);
        expect(find.text('Thiết kế mẫu Singleton & Factory'), findsOneWidget);
        expect(find.text('Bài tập môn khác'), findsNothing);

        // Số liệu: 2 việc, 1 hoàn thành, 1 chưa hoàn thành, 50%
        expect(find.text('2'), findsWidgets);
        expect(find.text('1'), findsWidgets);
        expect(find.text('50% hoàn thành'), findsOneWidget);

        // Hiển thị huy hiệu đánh giá mức độ hiểu bài của bài đã hoàn thành
        expect(find.text('Đã nắm vững'), findsOneWidget);
      },
    );

    testWidgets('Lọc theo trạng thái trong chi tiết môn học', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final tasks = [
        StudyTask(
          id: 't_done',
          title: 'Viết tài liệu thiết kế',
          subjectId: 'subj_test',
          subject: 'Kiến trúc Phần mềm',
          deadline: now,
          estimatedMinutes: 45,
          status: TaskStatus.completed,
        ),
        StudyTask(
          id: 't_todo',
          title: 'Cài đặt mã nguồn mẫu',
          subjectId: 'subj_test',
          subject: 'Kiến trúc Phần mềm',
          deadline: now,
          estimatedMinutes: 30,
          status: TaskStatus.todo,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: SubjectDetailScreen(
            subject: testSubject,
            allSubjects: const [testSubject],
            tasks: tasks,
            onToggleComplete: (_) {},
            onTapTask: (_) {},
            onEditTask: (_) {},
            onDeleteTask: (_) {},
            onAddTaskForThisSubject: () {},
            onEditSubject: () {},
            onDeleteSubject: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Viết tài liệu thiết kế'), findsOneWidget);
      expect(find.text('Cài đặt mã nguồn mẫu'), findsOneWidget);

      // Bấm chip lọc Hoàn thành
      await tester.tap(find.text('Hoàn thành'));
      await tester.pumpAndSettle();

      expect(find.text('Viết tài liệu thiết kế'), findsOneWidget);
      expect(find.text('Cài đặt mã nguồn mẫu'), findsNothing);
    });

    testWidgets(
      '8. Nút thêm công việc kích hoạt callback với môn học hiện tại',
      (tester) async {
        bool addTriggered = false;

        await tester.pumpWidget(
          MaterialApp(
            home: SubjectDetailScreen(
              subject: testSubject,
              allSubjects: const [testSubject],
              tasks: const [],
              onToggleComplete: (_) {},
              onTapTask: (_) {},
              onEditTask: (_) {},
              onDeleteTask: (_) {},
              onAddTaskForThisSubject: () => addTriggered = true,
              onEditSubject: () {},
              onDeleteSubject: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Thêm việc môn này'));
        await tester.pumpAndSettle();

        expect(addTriggered, isTrue);
      },
    );
  });
}

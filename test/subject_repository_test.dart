import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late SubjectRepository subjectRepo;
  late TaskRepository taskRepo;

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
        ${DatabaseHelper.columnPriority} TEXT NOT NULL,
        ${DatabaseHelper.columnStatus} TEXT NOT NULL,
        ${DatabaseHelper.columnNotes} TEXT NOT NULL DEFAULT ''
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

  group('Kiểm thử quản lý môn học trong SQLite (Giai đoạn 1)', () {
    test('1. Thêm môn học và xác nhận dữ liệu được lưu bền vững', () async {
      const newSubject = Subject(
        id: 'subj_ai',
        name: 'Trí tuệ nhân tạo',
        description: 'Machine Learning và Deep Learning cơ bản',
        color: Color(0xFF7C3AED),
      );

      await subjectRepo.insertSubject(newSubject);

      // Đọc lại từ database
      final subjects = await subjectRepo.getAllSubjects();
      expect(subjects.any((s) => s.id == 'subj_ai'), true);
      final found = subjects.firstWhere((s) => s.id == 'subj_ai');
      expect(found.name, 'Trí tuệ nhân tạo');
      expect(found.description, 'Machine Learning và Deep Learning cơ bản');
    });

    test(
      '2. Sửa tên môn và xác nhận nhiệm vụ vẫn liên kết đúng qua subjectId',
      () async {
        // Thêm task thuộc subj_1 (Toán cao cấp)
        final task = StudyTask(
          id: 't_math_1',
          title: 'Giải đề thi số 1',
          subjectId: 'subj_1',
          subject: 'Toán cao cấp',
          deadline: DateTime.now().add(const Duration(days: 2)),
          estimatedMinutes: 60,
        );
        await taskRepo.insertTask(task);

        // Cập nhật tên môn subj_1 thành 'Toán giải tích'
        const updatedSubject = Subject(
          id: 'subj_1',
          name: 'Toán giải tích',
          description: 'Tích phân đường và mặt',
        );
        await subjectRepo.updateSubject(updatedSubject);
        await taskRepo.updateTasksSubjectName('subj_1', 'Toán giải tích');

        // Kiểm tra môn học đã đổi tên
        final subjects = await subjectRepo.getAllSubjects();
        expect(
          subjects.firstWhere((s) => s.id == 'subj_1').name,
          'Toán giải tích',
        );

        // Kiểm tra task vẫn thuộc subj_1 và tên hiển thị được đồng bộ
        final tasks = await taskRepo.getAllTasks();
        final taskAfter = tasks.firstWhere((t) => t.id == 't_math_1');
        expect(taskAfter.subjectId, 'subj_1');
        expect(taskAfter.subject, 'Toán giải tích');
      },
    );

    test('3. Mở từng môn và chỉ thấy các nhiệm vụ thuộc môn đó', () async {
      // Thêm 2 task ở 2 môn khác nhau
      await taskRepo.insertTask(
        StudyTask(
          id: 't_web',
          title: 'Học React/Flutter',
          subjectId: 'subj_2',
          subject: 'Lập trình Web',
          deadline: DateTime.now(),
          estimatedMinutes: 40,
        ),
      );
      await taskRepo.insertTask(
        StudyTask(
          id: 't_db',
          title: 'Thiết kế ERD',
          subjectId: 'subj_3',
          subject: 'Cơ sở dữ liệu',
          deadline: DateTime.now(),
          estimatedMinutes: 45,
        ),
      );

      final allTasks = await taskRepo.getAllTasks();

      // Lọc task theo subj_2 (Web)
      final webTasks = allTasks.where((t) => t.subjectId == 'subj_2').toList();
      expect(webTasks.length, 1);
      expect(webTasks.first.id, 't_web');

      // Lọc task theo subj_3 (DB)
      final dbTasks = allTasks.where((t) => t.subjectId == 'subj_3').toList();
      expect(dbTasks.length, 1);
      expect(dbTasks.first.id, 't_db');
    });

    test('4. Môn chưa có nhiệm vụ hiển thị rỗng', () async {
      final allTasks = await taskRepo.getAllTasks();
      final englishTasks = allTasks
          .where((t) => t.subjectId == 'subj_4')
          .toList();
      expect(englishTasks.isEmpty, true);
    });

    test('5. Đổi nhiệm vụ sang môn khác cập nhật chính xác', () async {
      final task = StudyTask(
        id: 't_move',
        title: 'Làm bài tập lớn',
        subjectId: 'subj_2',
        subject: 'Lập trình Web',
        deadline: DateTime.now(),
        estimatedMinutes: 60,
      );
      await taskRepo.insertTask(task);

      // Đổi sang môn Cơ sở dữ liệu (subj_3)
      final updatedTask = task.copyWith(
        subjectId: 'subj_3',
        subject: 'Cơ sở dữ liệu',
      );
      await taskRepo.updateTask(updatedTask);

      final allTasks = await taskRepo.getAllTasks();
      final webTasks = allTasks.where((t) => t.subjectId == 'subj_2').toList();
      final dbTasks = allTasks.where((t) => t.subjectId == 'subj_3').toList();

      expect(webTasks.any((t) => t.id == 't_move'), false);
      expect(dbTasks.any((t) => t.id == 't_move'), true);
    });

    test('6. Xóa môn học không có nhiệm vụ thành công', () async {
      // Môn subj_4 (Tiếng Anh) hiện không có task
      await subjectRepo.deleteSubject('subj_4');

      final subjects = await subjectRepo.getAllSubjects();
      expect(subjects.any((s) => s.id == 'subj_4'), false);
    });

    test(
      '7. Xóa môn có nhiệm vụ: chuyển nhiệm vụ sang môn khác an toàn không mất dữ liệu',
      () async {
        // Thêm 2 task cho môn Toán (subj_1)
        await taskRepo.insertTask(
          StudyTask(
            id: 't_m1',
            title: 'Bài tập 1',
            subjectId: 'subj_1',
            subject: 'Toán cao cấp',
            deadline: DateTime.now(),
            estimatedMinutes: 30,
          ),
        );
        await taskRepo.insertTask(
          StudyTask(
            id: 't_m2',
            title: 'Bài tập 2',
            subjectId: 'subj_1',
            subject: 'Toán cao cấp',
            deadline: DateTime.now(),
            estimatedMinutes: 30,
          ),
        );

        // Chuyển toàn bộ nhiệm vụ của subj_1 sang subj_2 (Lập trình Web) rồi xóa subj_1
        await taskRepo.migrateTasksSubject('subj_1', 'subj_2', 'Lập trình Web');
        await subjectRepo.deleteSubject('subj_1');

        // Xác nhận môn subj_1 đã bị xóa
        final subjects = await subjectRepo.getAllSubjects();
        expect(subjects.any((s) => s.id == 'subj_1'), false);

        // Xác nhận 2 nhiệm vụ cũ KHÔNG bị mất và đã chuyển sang subj_2
        final allTasks = await taskRepo.getAllTasks();
        final migratedTasks = allTasks
            .where((t) => t.subjectId == 'subj_2')
            .toList();
        expect(migratedTasks.any((t) => t.id == 't_m1'), true);
        expect(migratedTasks.any((t) => t.id == 't_m2'), true);
        expect(
          migratedTasks.firstWhere((t) => t.id == 't_m1').subject,
          'Lập trình Web',
        );
      },
    );

    test('8. Kiểm tra dữ liệu cũ sau migration tự động có subjectId', () {
      // Giả lập đọc bản ghi cũ chỉ có 'subject' mà chưa có 'subject_id'
      final oldMap = {
        'id': 'old_task',
        'title': 'Task từ CSDL cũ',
        'subject': 'Lập trình Web',
        'deadline': DateTime.now().toIso8601String(),
        'estimated_minutes': 45,
        'priority': 'medium',
        'status': 'todo',
        'notes': 'Không có subject_id trong bản ghi cũ',
      };

      final restored = StudyTask.fromMap(oldMap);
      expect(restored.subjectId, 'subj_2');
      expect(restored.subject, 'Lập trình Web');
    });

    test(
      '9. Kiểm tra Web Preview của SubjectRepository hoạt động độc lập không gọi SQLite',
      () async {
        final webSubjectRepo = SubjectRepository(useWebPreview: true);
        expect(webSubjectRepo.isWebPreview, true);

        // Tự nạp 4 môn mặc định
        final defaultSubs = await webSubjectRepo.getAllSubjects();
        expect(defaultSubs.length, 4);

        // Thêm môn trên Web
        await webSubjectRepo.insertSubject(
          const Subject(
            id: 'web_sub_new',
            name: 'Môn Web mới',
            description: 'Mô tả',
          ),
        );
        final afterAdd = await webSubjectRepo.getAllSubjects();
        expect(afterAdd.length, 5);
        expect(afterAdd.any((s) => s.id == 'web_sub_new'), true);

        // Đảm bảo SQLite FFI không bị ảnh hưởng
        final sqliteSubs = await subjectRepo.getAllSubjects();
        expect(sqliteSubs.any((s) => s.id == 'web_sub_new'), false);
      },
    );
  });
}

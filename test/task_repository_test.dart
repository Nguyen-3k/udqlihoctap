import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/task_priority.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/repositories/task_repository.dart';

void main() {
  // Khởi tạo sqflite FFI cho môi trường kiểm thử máy tính
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TaskRepository repository;

  setUp(() async {
    // Tạo CSDL SQLite trong bộ nhớ tạm thời cho mỗi bài test
    db = await databaseFactory.openDatabase(inMemoryDatabasePath);

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
    repository = TaskRepository(dbHelper: DatabaseHelper.instance);
  });

  tearDown(() async {
    await db.close();
  });

  group('Kiểm thử chuyển đổi Model StudyTask toMap / fromMap', () {
    test('Chuyển đổi đầy đủ các trường và phục hồi chính xác', () {
      final now = DateTime.now();
      final task = StudyTask(
        id: 'test_1',
        title: 'Luyện tập giải đề Toán',
        subject: 'Toán cao cấp',
        deadline: now,
        estimatedMinutes: 90,
        priority: TaskPriority.high,
        status: TaskStatus.inProgress,
        notes: 'Ôn kỹ phần chuỗi Taylor',
      );

      final map = task.toMap();
      expect(map['id'], 'test_1');
      expect(map['title'], 'Luyện tập giải đề Toán');
      expect(map['subject_id'], 'subj_1');
      expect(map['subject'], 'Toán cao cấp');
      expect(map['estimated_minutes'], 90);
      expect(map['priority'], 'high');
      expect(map['status'], 'inProgress');
      expect(map['notes'], 'Ôn kỹ phần chuỗi Taylor');

      final restored = StudyTask.fromMap(map);
      expect(restored.id, task.id);
      expect(restored.title, task.title);
      expect(restored.subjectId, 'subj_1');
      expect(restored.subject, task.subject);
      expect(restored.estimatedMinutes, task.estimatedMinutes);
      expect(restored.priority, TaskPriority.high);
      expect(restored.status, TaskStatus.inProgress);
      expect(restored.notes, task.notes);
    });

    test(
      'Phục hồi chính xác các định dạng status và priority khác nhau không bị reset về todo',
      () {
        final taskCompleted1 = StudyTask.fromMap({
          'id': 'parse_1',
          'title': 'Test 1',
          'subject': 'Toán',
          'status': 'completed',
          'priority': 'high',
        });
        expect(taskCompleted1.status, TaskStatus.completed);
        expect(taskCompleted1.isCompleted, true);

        // Dạng enum chuỗi có tiền tố (ví dụ "TaskStatus.completed")
        final taskCompleted2 = StudyTask.fromMap({
          'id': 'parse_2',
          'title': 'Test 2',
          'subject': 'Toán',
          'status': 'TaskStatus.completed',
          'priority': 'TaskPriority.high',
        });
        expect(taskCompleted2.status, TaskStatus.completed);
        expect(taskCompleted2.priority, TaskPriority.high);
        expect(taskCompleted2.isCompleted, true);
      },
    );
  });

  group('Kiểm thử các thao tác SQLite qua TaskRepository', () {
    test('Thêm công việc và lấy danh sách', () async {
      final task = StudyTask(
        id: 't1',
        title: 'Học bài mới',
        subject: 'Lập trình Web',
        deadline: DateTime.now().add(const Duration(days: 1)),
        estimatedMinutes: 45,
        priority: TaskPriority.medium,
        status: TaskStatus.todo,
        notes: 'Tìm hiểu về Flutter Widget',
      );

      await repository.insertTask(task);
      final tasks = await repository.getAllTasks();

      expect(tasks.length, 1);
      expect(tasks.first.id, 't1');
      expect(tasks.first.title, 'Học bài mới');
      expect(tasks.first.subject, 'Lập trình Web');
      expect(tasks.first.notes, 'Tìm hiểu về Flutter Widget');
    });

    test('Cập nhật thông tin công việc trong SQLite', () async {
      final task = StudyTask(
        id: 't2',
        title: 'Tiêu đề cũ',
        subject: 'Tiếng Anh',
        deadline: DateTime.now(),
        estimatedMinutes: 30,
        priority: TaskPriority.low,
      );
      await repository.insertTask(task);

      final updated = task.copyWith(
        title: 'Tiêu đề mới đã sửa',
        estimatedMinutes: 60,
        priority: TaskPriority.high,
        notes: 'Ghi chú bổ sung',
      );
      await repository.updateTask(updated);

      final tasks = await repository.getAllTasks();
      expect(tasks.length, 1);
      expect(tasks.first.title, 'Tiêu đề mới đã sửa');
      expect(tasks.first.estimatedMinutes, 60);
      expect(tasks.first.priority, TaskPriority.high);
      expect(tasks.first.notes, 'Ghi chú bổ sung');
    });

    test('Cập nhật trạng thái hoàn thành', () async {
      final task = StudyTask(
        id: 't3',
        title: 'Làm bài tập CSDL',
        subject: 'Cơ sở dữ liệu',
        deadline: DateTime.now(),
        estimatedMinutes: 45,
        status: TaskStatus.todo,
      );
      await repository.insertTask(task);

      await repository.updateTaskStatus('t3', TaskStatus.completed);

      final tasks = await repository.getAllTasks();
      expect(tasks.first.status, TaskStatus.completed);
      expect(tasks.first.isCompleted, true);
    });

    test(
      'Mô phỏng đóng app hoàn toàn và mở lại: nhiệm vụ thêm mới và trạng thái hoàn thành vẫn tồn tại trong SQLite',
      () async {
        // 1. Thêm một nhiệm vụ mới
        final newTask = StudyTask(
          id: 'persistent_task_1',
          title: 'Nhiệm vụ kiểm tra độ bền vững',
          subject: 'Cơ sở dữ liệu',
          deadline: DateTime.now().add(const Duration(days: 2)),
          estimatedMinutes: 60,
          status: TaskStatus.todo,
        );
        await repository.insertTask(newTask);

        // 2. Đánh dấu hoàn thành
        await repository.updateTaskStatus(
          'persistent_task_1',
          TaskStatus.completed,
        );

        // 3. Giả lập đóng app: tạo mới một TaskRepository độc lập từ CSDL
        final reopenedRepository = TaskRepository(
          dbHelper: DatabaseHelper.instance,
        );
        final tasks = await reopenedRepository.getAllTasks();

        // 4. Xác nhận dữ liệu không bị reset
        expect(tasks.any((t) => t.id == 'persistent_task_1'), true);
        final savedTask = tasks.firstWhere((t) => t.id == 'persistent_task_1');
        expect(savedTask.title, 'Nhiệm vụ kiểm tra độ bền vững');
        expect(savedTask.status, TaskStatus.completed);
        expect(savedTask.isCompleted, true);
      },
    );

    test('Xóa công việc trong SQLite', () async {
      final task = StudyTask(
        id: 't4',
        title: 'Công việc cần xóa',
        subject: 'Toán cao cấp',
        deadline: DateTime.now(),
        estimatedMinutes: 20,
      );
      await repository.insertTask(task);

      var tasks = await repository.getAllTasks();
      expect(tasks.length, 1);

      await repository.deleteTask('t4');

      tasks = await repository.getAllTasks();
      expect(tasks.isEmpty, true);
    });

    test('Xóa toàn bộ và nạp lại công việc mẫu', () async {
      final sample = [
        StudyTask(
          id: 's1',
          title: 'Mẫu 1',
          subject: 'Toán',
          deadline: DateTime.now(),
          estimatedMinutes: 30,
        ),
        StudyTask(
          id: 's2',
          title: 'Mẫu 2',
          subject: 'Lý',
          deadline: DateTime.now(),
          estimatedMinutes: 40,
        ),
      ];

      await repository.resetSampleTasks(sample);
      var tasks = await repository.getAllTasks();
      expect(tasks.length, 2);

      await repository.clearAllTasks();
      tasks = await repository.getAllTasks();
      expect(tasks.isEmpty, true);
    });
  });

  group('Kiểm thử chế độ Web Preview (In-memory) tách biệt khỏi SQLite', () {
    late TaskRepository webRepo;

    setUp(() {
      webRepo = TaskRepository(useWebPreview: true);
    });

    test(
      'Chế độ Web Preview tự động khởi tạo dữ liệu mẫu và isWebPreview = true',
      () async {
        expect(webRepo.isWebPreview, true);
        final tasks = await webRepo.getAllTasks();
        expect(tasks.length, 3);
        expect(tasks.any((t) => t.title == 'Ôn tập chương 3 Đạo hàm'), true);
      },
    );

    test('Thêm công việc trong Web Preview không ảnh hưởng SQLite', () async {
      final newTask = StudyTask(
        id: 'web_task_1',
        title: 'Công việc test trên Chrome',
        subject: 'Lập trình Web',
        deadline: DateTime.now().add(const Duration(hours: 1)),
        estimatedMinutes: 30,
      );

      await webRepo.insertTask(newTask);
      final tasks = await webRepo.getAllTasks();
      expect(tasks.length, 4);
      expect(tasks.any((t) => t.id == 'web_task_1'), true);

      // Đảm bảo SQLite trên Android/FFI không bị ghi dữ liệu tạm này
      final sqliteTasks = await repository.getAllTasks();
      expect(sqliteTasks.any((t) => t.id == 'web_task_1'), false);
    });

    test('Cập nhật trạng thái và chỉnh sửa trong Web Preview', () async {
      await webRepo.updateTaskStatus('task_1', TaskStatus.completed);
      var tasks = await webRepo.getAllTasks();
      final task1 = tasks.firstWhere((t) => t.id == 'task_1');
      expect(task1.status, TaskStatus.completed);

      final edited = task1.copyWith(title: 'Tiêu đề đã sửa trên Web');
      await webRepo.updateTask(edited);
      tasks = await webRepo.getAllTasks();
      expect(
        tasks.firstWhere((t) => t.id == 'task_1').title,
        'Tiêu đề đã sửa trên Web',
      );
    });

    test('Xóa công việc và khôi phục trong Web Preview', () async {
      await webRepo.deleteTask('task_2');
      var tasks = await webRepo.getAllTasks();
      expect(tasks.any((t) => t.id == 'task_2'), false);

      await webRepo.clearAllTasks();
      tasks = await webRepo.getAllTasks();
      expect(tasks.isEmpty, true);
    });
  });
}

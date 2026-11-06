import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/main.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TaskRepository taskRepo;
  late SubjectRepository subjectRepo;

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
    taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);
    subjectRepo = SubjectRepository(dbHelper: DatabaseHelper.instance);

    // Chèn 4 môn học mặc định
    final defaultSubjects = SubjectRepository.getDefaultSubjects();
    for (final s in defaultSubjects) {
      await subjectRepo.insertSubject(s);
    }

    // Thêm 1 task vào SQLite để test hiển thị
    await taskRepo.insertTask(
      StudyTask(
        id: 't_mock',
        title: 'Nhiệm vụ kiểm thử SQLite',
        subjectId: 'subj_3',
        subject: 'Cơ sở dữ liệu',
        deadline: DateTime.now().add(const Duration(hours: 3)),
        estimatedMinutes: 45,
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  testWidgets(
    'ExamPilotApp khởi động với SQLite, nạp công việc và hiển thị 5 tab',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ExamPilotApp(taskRepository: taskRepo, subjectRepository: subjectRepo),
      );

      // Cho phép tác vụ bất đồng bộ SQLite FFI hoàn tất
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // Kiểm tra tên ứng dụng hiển thị trên AppBar
      expect(find.text('ExamPilot'), findsOneWidget);

      // Kiểm tra hiển thị công việc đã tải từ SQLite
      expect(find.text('Nhiệm vụ kiểm thử SQLite'), findsOneWidget);

      // Kiểm tra hiển thị đầy đủ 5 tab tiếng Việt
      expect(find.text('Tổng quan'), findsWidgets);
      expect(find.text('Kế hoạch'), findsOneWidget);
      expect(find.text('Môn học'), findsOneWidget);
      expect(find.text('Thống kê'), findsOneWidget);
      expect(find.text('Cá nhân'), findsOneWidget);
    },
  );

  testWidgets(
    'Chuyển tab Kế hoạch và Thống kê hoạt động trơn tru với hệ thống giao diện mới',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ExamPilotApp(taskRepository: taskRepo, subjectRepository: subjectRepo),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // Chuyển sang tab Kế hoạch
      await tester.tap(find.text('Kế hoạch'));
      await tester.pumpAndSettle();

      // Kiểm tra tiêu đề trang Kế hoạch và các bộ lọc
      expect(find.text('Kế hoạch học tập'), findsOneWidget);
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Chưa làm'), findsOneWidget);
      expect(find.text('Đang làm'), findsOneWidget);
      expect(find.text('Hoàn thành'), findsOneWidget);

      // Chuyển sang tab Thống kê
      await tester.tap(find.text('Thống kê'));
      await tester.pumpAndSettle();

      expect(find.text('Thống kê học tập'), findsOneWidget);
      expect(find.text('Tỷ lệ hoàn thành nhiệm vụ'), findsOneWidget);
    },
  );

  testWidgets(
    'Nhấn vào môn học mở màn hình chi tiết môn học và hiển thị đúng các nhiệm vụ thuộc môn đó',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        ExamPilotApp(taskRepository: taskRepo, subjectRepository: subjectRepo),
      );

      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      // Chuyển sang tab Môn học
      await tester.tap(find.text('Môn học'));
      await tester.pumpAndSettle();

      expect(find.text('Môn học của tôi'), findsOneWidget);
      expect(find.text('Cơ sở dữ liệu'), findsWidgets);

      // Nhấn vào thẻ môn Cơ sở dữ liệu
      await tester.tap(find.text('Cơ sở dữ liệu').first);
      await tester.pumpAndSettle();

      // Xác nhận đã vào màn hình SubjectDetailScreen
      expect(find.text('Tổng nhiệm vụ'), findsOneWidget);
      expect(find.text('Đã hoàn thành'), findsOneWidget);
      expect(find.text('Chưa hoàn thành'), findsOneWidget);
      expect(find.text('Nhiệm vụ kiểm thử SQLite'), findsOneWidget);

      // Nhấn nút quay lại
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Xác nhận quay lại tab Môn học an toàn
      expect(find.text('Môn học của tôi'), findsOneWidget);
    },
  );

  testWidgets(
    'ExamPilotApp khởi động với Web Preview repository mượt mà và không lỗi database',
    (WidgetTester tester) async {
      final webTaskRepo = TaskRepository(useWebPreview: true);
      final webSubRepo = SubjectRepository(useWebPreview: true);

      await tester.pumpWidget(
        ExamPilotApp(
          taskRepository: webTaskRepo,
          subjectRepository: webSubRepo,
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Kiểm tra tên ứng dụng và nội dung dữ liệu xem trước
      expect(find.text('ExamPilot'), findsOneWidget);
      expect(find.text('Ôn tập chương 3 Đạo hàm'), findsOneWidget);

      // Kiểm tra không có thông báo lỗi cơ sở dữ liệu
      expect(find.text('Lỗi truy xuất cơ sở dữ liệu'), findsNothing);
    },
  );
}

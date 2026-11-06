import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../models/task_priority.dart';
import '../models/task_status.dart';

/// Lớp quản lý cơ sở dữ liệu SQLite cục bộ cho ExamPilot.
/// Hỗ trợ lưu trữ bền vững cho cả `subjects` (môn học) và `study_tasks` (nhiệm vụ).
/// Chặn cuộc gọi sqflite trên Web để giữ an toàn cho trình duyệt.
class DatabaseHelper {
  static const _databaseName = 'exampilot.db';
  static const _databaseVersion =
      2; // Nâng version lên 2 để hỗ trợ bảng subjects và liên kết subject_id

  static const tableTasks = 'study_tasks';
  static const tableSubjects = 'subjects';

  // Định nghĩa tên các cột trong bảng study_tasks
  static const columnId = 'id';
  static const columnTitle = 'title';
  static const columnTaskSubjectId = 'subject_id';
  static const columnSubject = 'subject';
  static const columnDeadline = 'deadline';
  static const columnEstimatedMinutes = 'estimated_minutes';
  static const columnPriority = 'priority';
  static const columnStatus = 'status';
  static const columnNotes = 'notes';

  // Định nghĩa tên các cột trong bảng subjects
  static const columnSubjectId = 'id';
  static const columnSubjectName = 'name';
  static const columnSubjectDescription = 'description';
  static const columnSubjectIcon = 'icon_code';
  static const columnSubjectColor = 'color_value';

  DatabaseHelper._privateConstructor();
  static final DatabaseHelper instance = DatabaseHelper._privateConstructor();

  static Database? _database;
  static Future<Database>? _databaseFuture;

  /// Lấy instance cơ sở dữ liệu (tự động mở nếu chưa mở và đồng bộ hóa các cuộc gọi đồng thời).
  Future<Database> get database async {
    if (kIsWeb) {
      throw UnsupportedError(
        'SQLite qua sqflite không được hỗ trợ trên nền tảng Web. '
        'Vui lòng sử dụng chế độ Web Preview trên trình duyệt.',
      );
    }
    if (_database != null && _database!.isOpen) return _database!;
    _databaseFuture ??= _initDatabase();
    _database = await _databaseFuture!;
    return _database!;
  }

  /// Cho phép gán Database tùy biến (hỗ trợ kiểm thử hoặc test in-memory).
  void setDatabaseForTesting(Database? db) {
    _database = db;
    _databaseFuture = db != null ? Future.value(db) : null;
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Khởi tạo cấu trúc bảng khi CSDL được tạo lần đầu tiên.
  Future<void> _onCreate(Database db, int version) async {
    // 1. Tạo bảng môn học (subjects)
    await db.execute('''
      CREATE TABLE $tableSubjects (
        $columnSubjectId TEXT PRIMARY KEY,
        $columnSubjectName TEXT NOT NULL,
        $columnSubjectDescription TEXT NOT NULL,
        $columnSubjectIcon INTEGER NOT NULL,
        $columnSubjectColor INTEGER NOT NULL
      )
    ''');

    // 2. Tạo bảng công việc học tập (study_tasks) có khóa ngoại liên kết subject_id
    await db.execute('''
      CREATE TABLE $tableTasks (
        $columnId TEXT PRIMARY KEY,
        $columnTitle TEXT NOT NULL,
        $columnTaskSubjectId TEXT NOT NULL,
        $columnSubject TEXT NOT NULL,
        $columnDeadline TEXT NOT NULL,
        $columnEstimatedMinutes INTEGER NOT NULL,
        $columnPriority TEXT NOT NULL,
        $columnStatus TEXT NOT NULL,
        $columnNotes TEXT NOT NULL DEFAULT ''
      )
    ''');

    // Chèn dữ liệu mẫu ban đầu cho CSDL mới tạo
    await _seedInitialSubjects(db);
    await _seedInitialTasks(db);
  }

  /// Nạp danh mục môn học mẫu ban đầu (chỉ khi bảng chưa có dữ liệu).
  Future<void> _seedInitialSubjects(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $tableSubjects'),
    );
    if (count != null && count > 0) {
      return; // Đã có dữ liệu môn học thì không ghi đè
    }

    final defaultSubjects = [
      const Subject(
        id: 'subj_1',
        name: 'Toán cao cấp',
        description: 'Đạo hàm, tích phân và đại số tuyến tính',
        icon: Icons.functions_rounded,
        color: Color(0xFF3B5BDB),
      ),
      const Subject(
        id: 'subj_2',
        name: 'Lập trình Web',
        description: 'HTML, CSS, JavaScript và kiến trúc Web',
        icon: Icons.code_rounded,
        color: Color(0xFF0284C7),
      ),
      const Subject(
        id: 'subj_3',
        name: 'Cơ sở dữ liệu',
        description: 'Mô hình quan hệ, SQL và chuẩn hóa dữ liệu',
        icon: Icons.storage_rounded,
        color: Color(0xFFD97706),
      ),
      const Subject(
        id: 'subj_4',
        name: 'Tiếng Anh',
        description: 'Từ vựng chuyên ngành CNTT và ngữ pháp',
        icon: Icons.language_rounded,
        color: Color(0xFFE11D48),
      ),
    ];

    final batch = db.batch();
    for (final s in defaultSubjects) {
      batch.insert(
        tableSubjects,
        s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Nạp các công việc mẫu ban đầu có liên kết subject_id (chỉ khi bảng chưa có dữ liệu).
  Future<void> _seedInitialTasks(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM $tableTasks'),
    );
    if (count != null && count > 0) {
      return; // Đã có dữ liệu công việc thì không ghi đè
    }

    final now = DateTime.now();
    final sampleTasks = [
      StudyTask(
        id: 'task_1',
        title: 'Ôn tập chương 3 Đạo hàm',
        subjectId: 'subj_1',
        subject: 'Toán cao cấp',
        deadline: now.add(const Duration(hours: 4)),
        estimatedMinutes: 60,
        priority: TaskPriority.high,
        status: TaskStatus.inProgress,
        notes: 'Cần chú ý công thức đạo hàm hàm hợp và định lý Fermat.',
      ),
      StudyTask(
        id: 'task_2',
        title: 'Thực hành viết câu lệnh SQL JOIN',
        subjectId: 'subj_3',
        subject: 'Cơ sở dữ liệu',
        deadline: now.add(const Duration(days: 1)),
        estimatedMinutes: 45,
        priority: TaskPriority.medium,
        status: TaskStatus.todo,
        notes: 'Phân biệt rõ ràng giữa INNER JOIN và LEFT JOIN.',
      ),
      StudyTask(
        id: 'task_3',
        title: 'Đọc tài liệu CSS Flexbox & Grid',
        subjectId: 'subj_2',
        subject: 'Lập trình Web',
        deadline: now.subtract(const Duration(hours: 2)),
        estimatedMinutes: 30,
        priority: TaskPriority.low,
        status: TaskStatus.completed,
        notes: 'Đã nắm vững align-items và justify-content.',
      ),
    ];

    final batch = db.batch();
    for (final task in sampleTasks) {
      batch.insert(
        tableTasks,
        task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// Nâng cấp schema an toàn không làm mất dữ liệu người dùng.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 1. Tạo bảng subjects nếu chưa có
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableSubjects (
          $columnSubjectId TEXT PRIMARY KEY,
          $columnSubjectName TEXT NOT NULL,
          $columnSubjectDescription TEXT NOT NULL,
          $columnSubjectIcon INTEGER NOT NULL,
          $columnSubjectColor INTEGER NOT NULL
        )
      ''');

      // 2. Chèn các môn mặc định nếu bảng subjects còn rỗng
      final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM $tableSubjects'),
      );
      if (count == null || count == 0) {
        await _seedInitialSubjects(db);
      }

      // 3. Bổ sung cột subject_id vào bảng study_tasks nếu chưa có
      final tableInfo = await db.rawQuery('PRAGMA table_info($tableTasks)');
      final hasSubjectId = tableInfo.any(
        (col) => col['name'] == columnTaskSubjectId,
      );

      if (!hasSubjectId) {
        await db.execute(
          'ALTER TABLE $tableTasks ADD COLUMN $columnTaskSubjectId TEXT',
        );
      }

      // 4. Cập nhật subject_id cho các bản ghi cũ dựa theo tên môn học
      await db.rawUpdate(
        "UPDATE $tableTasks SET $columnTaskSubjectId = 'subj_1' WHERE $columnSubject = 'Toán cao cấp' AND ($columnTaskSubjectId IS NULL OR $columnTaskSubjectId = '')",
      );
      await db.rawUpdate(
        "UPDATE $tableTasks SET $columnTaskSubjectId = 'subj_2' WHERE $columnSubject = 'Lập trình Web' AND ($columnTaskSubjectId IS NULL OR $columnTaskSubjectId = '')",
      );
      await db.rawUpdate(
        "UPDATE $tableTasks SET $columnTaskSubjectId = 'subj_3' WHERE $columnSubject = 'Cơ sở dữ liệu' AND ($columnTaskSubjectId IS NULL OR $columnTaskSubjectId = '')",
      );
      await db.rawUpdate(
        "UPDATE $tableTasks SET $columnTaskSubjectId = 'subj_4' WHERE $columnSubject = 'Tiếng Anh' AND ($columnTaskSubjectId IS NULL OR $columnTaskSubjectId = '')",
      );
      // Với bất kỳ bản ghi nào khác chưa có ID, gán về subj_1 mặc định an toàn
      await db.rawUpdate(
        "UPDATE $tableTasks SET $columnTaskSubjectId = 'subj_1' WHERE $columnTaskSubjectId IS NULL OR $columnTaskSubjectId = ''",
      );
    }
  }

  /// Đóng kết nối cơ sở dữ liệu.
  Future<void> close() async {
    final db = _database;
    if (db != null && db.isOpen) {
      await db.close();
      _database = null;
      _databaseFuture = null;
    }
  }
}

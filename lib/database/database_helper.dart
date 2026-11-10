import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../models/task_priority.dart';
import '../models/task_status.dart';
import '../models/understanding_level.dart';

/// Lớp quản lý cơ sở dữ liệu SQLite cục bộ cho ExamPilot.
/// Hỗ trợ lưu trữ bền vững cho `subjects`, `study_tasks` và `study_activities` (Study Streak).
/// Chặn cuộc gọi sqflite trên Web để giữ an toàn cho trình duyệt.
class DatabaseHelper {
  static const _databaseName = 'exampilot.db';
  static const _databaseVersion =
      6; // Nâng version lên 6: Hồ sơ cá nhân, Mục tiêu & Cài đặt (Giai đoạn 5)

  static const tableTasks = 'study_tasks';
  static const tableSubjects = 'subjects';
  static const tableActivities = 'study_activities';
  static const tableProfile = 'user_profile';

  // Định nghĩa tên các cột trong bảng study_tasks
  static const columnId = 'id';
  static const columnTitle = 'title';
  static const columnTaskSubjectId = 'subject_id';
  static const columnSubject = 'subject';
  static const columnDeadline = 'deadline';
  static const columnEstimatedMinutes = 'estimated_minutes';
  static const columnActualMinutes = 'actual_minutes';
  static const columnPriority = 'priority';
  static const columnStatus = 'status';
  static const columnNotes = 'notes';
  static const columnUnderstandingLevel = 'understanding_level';
  static const columnReviewNotes = 'review_notes';

  // Định nghĩa tên các cột trong bảng subjects
  static const columnSubjectId = 'id';
  static const columnSubjectName = 'name';
  static const columnSubjectDescription = 'description';
  static const columnSubjectIcon = 'icon_code';
  static const columnSubjectColor = 'color_value';

  // Định nghĩa tên các cột trong bảng study_activities (Study Streak & Thống kê G4)
  static const columnActivityId = 'id';
  static const columnActivityDate = 'activity_date';
  static const columnActivityTaskId = 'task_id';
  static const columnActivityCompletedAt = 'completed_at';
  static const columnActivityActualMinutes = 'actual_minutes';
  static const columnActivitySubjectId = 'subject_id';

  // Định nghĩa tên các cột trong bảng user_profile (Hồ sơ & Cài đặt G5)
  static const columnProfileId = 'id';
  static const columnProfileName = 'name';
  static const columnProfileUniversity = 'university';
  static const columnProfileMajor = 'major';
  static const columnProfileAcademicYear = 'academic_year';
  static const columnProfileAvatarId = 'avatar_id';
  static const columnProfileTargetHours = 'weekly_target_hours';
  static const columnProfileTargetTasks = 'weekly_target_tasks';
  static const columnProfileThemeMode = 'theme_mode';
  static const columnProfileReminderEnabled = 'reminder_enabled';

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

    // 2. Tạo bảng công việc học tập (study_tasks) có khóa ngoại subject_id, thời lượng thực tế và các trường đánh giá
    await db.execute('''
      CREATE TABLE $tableTasks (
        $columnId TEXT PRIMARY KEY,
        $columnTitle TEXT NOT NULL,
        $columnTaskSubjectId TEXT NOT NULL,
        $columnSubject TEXT NOT NULL,
        $columnDeadline TEXT NOT NULL,
        $columnEstimatedMinutes INTEGER NOT NULL,
        $columnActualMinutes INTEGER,
        $columnPriority TEXT NOT NULL,
        $columnStatus TEXT NOT NULL,
        $columnNotes TEXT NOT NULL DEFAULT '',
        $columnUnderstandingLevel TEXT,
        $columnReviewNotes TEXT
      )
    ''');

    // 3. Tạo bảng ghi nhận lịch sử học tập (study_activities) phục vụ Study Streak & Thống kê
    await db.execute('''
      CREATE TABLE $tableActivities (
        $columnActivityId TEXT PRIMARY KEY,
        $columnActivityDate TEXT NOT NULL,
        $columnActivityTaskId TEXT,
        $columnActivityCompletedAt TEXT NOT NULL,
        $columnActivityActualMinutes INTEGER DEFAULT 0,
        $columnActivitySubjectId TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_activity_date ON $tableActivities($columnActivityDate)',
    );

    // 4. Tạo bảng hồ sơ cá nhân và cài đặt (user_profile)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $tableProfile (
        $columnProfileId TEXT PRIMARY KEY,
        $columnProfileName TEXT NOT NULL DEFAULT '',
        $columnProfileUniversity TEXT NOT NULL DEFAULT '',
        $columnProfileMajor TEXT NOT NULL DEFAULT '',
        $columnProfileAcademicYear TEXT NOT NULL DEFAULT '',
        $columnProfileAvatarId TEXT NOT NULL DEFAULT 'school',
        $columnProfileTargetHours REAL NOT NULL DEFAULT 10.0,
        $columnProfileTargetTasks INTEGER NOT NULL DEFAULT 5,
        $columnProfileThemeMode TEXT NOT NULL DEFAULT 'system',
        $columnProfileReminderEnabled INTEGER NOT NULL DEFAULT 0
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
        understandingLevel: UnderstandingLevel.mastered,
        reviewNotes: 'Đã áp dụng thành thạo CSS Flexbox vào bố cục dự án.',
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
      await db.rawUpdate(
        "UPDATE $tableTasks SET $columnTaskSubjectId = 'subj_1' WHERE $columnTaskSubjectId IS NULL OR $columnTaskSubjectId = ''",
      );
    }

    if (oldVersion < 3) {
      // Bổ sung các cột tự đánh giá mức độ hiểu bài vào bảng study_tasks
      final tableInfo = await db.rawQuery('PRAGMA table_info($tableTasks)');
      final hasUnderstandingLevel = tableInfo.any(
        (col) => col['name'] == columnUnderstandingLevel,
      );
      if (!hasUnderstandingLevel) {
        await db.execute(
          'ALTER TABLE $tableTasks ADD COLUMN $columnUnderstandingLevel TEXT',
        );
      }

      final hasReviewNotes = tableInfo.any(
        (col) => col['name'] == columnReviewNotes,
      );
      if (!hasReviewNotes) {
        await db.execute(
          'ALTER TABLE $tableTasks ADD COLUMN $columnReviewNotes TEXT',
        );
      }
    }

    if (oldVersion < 4) {
      // Bổ sung bảng study_activities phục vụ tính năng Study Streak
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableActivities (
          $columnActivityId TEXT PRIMARY KEY,
          $columnActivityDate TEXT NOT NULL,
          $columnActivityTaskId TEXT,
          $columnActivityCompletedAt TEXT NOT NULL
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_activity_date ON $tableActivities($columnActivityDate)',
      );
    }

    if (oldVersion < 5) {
      // 1. Bổ sung cột actual_minutes vào bảng study_tasks nếu chưa có
      final tasksInfo = await db.rawQuery('PRAGMA table_info($tableTasks)');
      final hasActualMinutes = tasksInfo.any(
        (col) => col['name'] == columnActualMinutes,
      );
      if (!hasActualMinutes) {
        await db.execute(
          'ALTER TABLE $tableTasks ADD COLUMN $columnActualMinutes INTEGER',
        );
      }

      // 2. Bổ sung cột actual_minutes và subject_id vào bảng study_activities nếu chưa có
      final activitiesInfo = await db.rawQuery(
        'PRAGMA table_info($tableActivities)',
      );
      final hasActMinutes = activitiesInfo.any(
        (col) => col['name'] == columnActivityActualMinutes,
      );
      if (!hasActMinutes) {
        await db.execute(
          'ALTER TABLE $tableActivities ADD COLUMN $columnActivityActualMinutes INTEGER DEFAULT 0',
        );
      }
      final hasActSubjectId = activitiesInfo.any(
        (col) => col['name'] == columnActivitySubjectId,
      );
      if (!hasActSubjectId) {
        await db.execute(
          'ALTER TABLE $tableActivities ADD COLUMN $columnActivitySubjectId TEXT',
        );
      }
    }

    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS $tableProfile (
          $columnProfileId TEXT PRIMARY KEY,
          $columnProfileName TEXT NOT NULL DEFAULT '',
          $columnProfileUniversity TEXT NOT NULL DEFAULT '',
          $columnProfileMajor TEXT NOT NULL DEFAULT '',
          $columnProfileAcademicYear TEXT NOT NULL DEFAULT '',
          $columnProfileAvatarId TEXT NOT NULL DEFAULT 'school',
          $columnProfileTargetHours REAL NOT NULL DEFAULT 10.0,
          $columnProfileTargetTasks INTEGER NOT NULL DEFAULT 5,
          $columnProfileThemeMode TEXT NOT NULL DEFAULT 'system',
          $columnProfileReminderEnabled INTEGER NOT NULL DEFAULT 0
        )
      ''');
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

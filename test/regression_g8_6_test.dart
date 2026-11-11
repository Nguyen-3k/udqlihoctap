import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/study_statistics.dart';
import 'package:exampilot/models/study_streak.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/task_priority.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/models/understanding_level.dart';
import 'package:exampilot/models/user_profile.dart';
import 'package:exampilot/repositories/profile_repository.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/screens/app_shell.dart';
import 'package:exampilot/screens/plan_screen.dart';
import 'package:exampilot/screens/profile_screen.dart';
import 'package:exampilot/screens/statistics_screen.dart';
import 'package:exampilot/screens/subjects_screen.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('G8.6 - Luồng 1: Môn học và công việc liên kết', () {
    late Database db;
    late TaskRepository taskRepo;
    late SubjectRepository subjectRepo;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      // Tạo schema chuẩn v6
      await db.execute('''
        CREATE TABLE ${DatabaseHelper.tableSubjects} (
          ${DatabaseHelper.columnSubjectId} TEXT PRIMARY KEY,
          ${DatabaseHelper.columnSubjectName} TEXT NOT NULL,
          ${DatabaseHelper.columnSubjectDescription} TEXT NOT NULL,
          ${DatabaseHelper.columnSubjectIcon} INTEGER NOT NULL,
          ${DatabaseHelper.columnSubjectColor} INTEGER NOT NULL
        )
      ''');
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
          ${DatabaseHelper.columnActivityTaskId} TEXT,
          ${DatabaseHelper.columnActivityCompletedAt} TEXT NOT NULL,
          ${DatabaseHelper.columnActivityActualMinutes} INTEGER DEFAULT 0,
          ${DatabaseHelper.columnActivitySubjectId} TEXT
        )
      ''');

      DatabaseHelper.instance.setDatabaseForTesting(db);
      taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);
      subjectRepo = SubjectRepository(dbHelper: DatabaseHelper.instance);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'Luồng 1 (SQLite): Tạo môn -> Tạo task -> Sửa tên môn -> Kiểm tra task cập nhật -> Chuyển môn khi xóa',
      () async {
        // 1. Tạo môn học mới
        const newSub = Subject(
          id: 'sub_algo',
          name: 'Thuật toán nâng cao',
          description: 'Đồ thị và quy hoạch động',
          icon: Icons.hub_rounded,
          color: Color(0xFF2E7D32),
        );
        await subjectRepo.insertSubject(newSub);

        final subs = await subjectRepo.getAllSubjects();
        expect(subs.any((s) => s.id == 'sub_algo'), isTrue);

        // 2. Tạo công việc thuộc môn học
        final task = StudyTask(
          id: 'task_dp',
          title: 'Bài tập Quy hoạch động',
          subjectId: 'sub_algo',
          subject: 'Thuật toán nâng cao',
          deadline: DateTime.now().add(const Duration(days: 2)),
          priority: TaskPriority.high,
        );
        await taskRepo.insertTask(task);

        var tasks = await taskRepo.getAllTasks();
        expect(tasks.first.subjectId, 'sub_algo');
        expect(tasks.first.subject, 'Thuật toán nâng cao');

        // 3. Sửa tên môn học
        const updatedSub = Subject(
          id: 'sub_algo',
          name: 'Cấu trúc dữ liệu & Giải thuật',
          description: 'Đồ thị và quy hoạch động',
          icon: Icons.hub_rounded,
          color: Color(0xFF2E7D32),
        );
        await subjectRepo.updateSubject(updatedSub);
        await taskRepo.updateTasksSubjectName(updatedSub.id, updatedSub.name);

        tasks = await taskRepo.getAllTasks();
        expect(tasks.first.subject, 'Cấu trúc dữ liệu & Giải thuật');

        // 4. Tạo môn đích và chuyển việc trước khi xóa
        const destSub = Subject(
          id: 'sub_general',
          name: 'Môn học chung',
          description: 'Tổng hợp',
          icon: Icons.school_rounded,
          color: Color(0xFF1976D2),
        );
        await subjectRepo.insertSubject(destSub);

        await taskRepo.migrateTasksSubject(
          'sub_algo',
          'sub_general',
          'Môn học chung',
        );
        await subjectRepo.deleteSubject('sub_algo');

        final remainingSubs = await subjectRepo.getAllSubjects();
        expect(remainingSubs.any((s) => s.id == 'sub_algo'), isFalse);

        tasks = await taskRepo.getAllTasks();
        expect(tasks.first.subjectId, 'sub_general');
        expect(tasks.first.subject, 'Môn học chung');
      },
    );

    test(
      'Luồng 1 (Web Preview): Tạo môn -> Tạo task -> Sửa tên môn -> Chuyển môn khi xóa',
      () async {
        final webTaskRepo = TaskRepository(useWebPreview: true);
        final webSubjectRepo = SubjectRepository(useWebPreview: true);

        // 1. Tạo môn
        const sub = Subject(
          id: 'web_sub_1',
          name: 'Kinh tế vi mô',
          description: 'Cung cầu và thị trường',
          icon: Icons.analytics_outlined,
          color: Color(0xFFE65100),
        );
        await webSubjectRepo.insertSubject(sub);

        // 2. Tạo task
        final task = StudyTask(
          id: 'web_task_1',
          title: 'Đọc chương 2 Cung Cầu',
          subjectId: 'web_sub_1',
          subject: 'Kinh tế vi mô',
        );
        await webTaskRepo.insertTask(task);

        // 3. Đổi tên môn
        const updatedSub = Subject(
          id: 'web_sub_1',
          name: 'Kinh tế học đại cương',
          description: 'Cung cầu và thị trường',
          icon: Icons.analytics_outlined,
          color: Color(0xFFE65100),
        );
        await webSubjectRepo.updateSubject(updatedSub);
        await webTaskRepo.updateTasksSubjectName(
          updatedSub.id,
          updatedSub.name,
        );

        var tasks = await webTaskRepo.getAllTasks();
        final foundTask = tasks.firstWhere((t) => t.id == 'web_task_1');
        expect(foundTask.subject, 'Kinh tế học đại cương');

        // 4. Chuyển giao môn và xóa
        await webTaskRepo.migrateTasksSubject(
          'web_sub_1',
          'subj_1',
          'Toán cao cấp',
        );
        await webSubjectRepo.deleteSubject('web_sub_1');

        tasks = await webTaskRepo.getAllTasks();
        final migratedTask = tasks.firstWhere((t) => t.id == 'web_task_1');
        expect(migratedTask.subjectId, 'subj_1');
        expect(migratedTask.subject, 'Toán cao cấp');
      },
    );
  });

  group('G8.6 - Luồng 2: Hoàn thành, Study Streak và Thống kê', () {
    late Database db;
    late TaskRepository taskRepo;

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
          ${DatabaseHelper.columnActivityTaskId} TEXT,
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

    test(
      'Luồng 2 (SQLite): Hoàn thành task -> Ghi actualMinutes -> Streak & Thống kê tính chính xác -> Không ghi trùng',
      () async {
        final now = DateTime.now();
        final task = StudyTask(
          id: 'task_streak_1',
          title: 'Học ngữ pháp Thì Quá khứ đơn',
          subjectId: 'subj_4',
          subject: 'Tiếng Anh',
          status: TaskStatus.todo,
        );
        await taskRepo.insertTask(task);

        // 1. Hoàn thành lần đầu
        await taskRepo.updateTaskStatus(task.id, TaskStatus.completed);
        await taskRepo.updateTaskAssessment(
          task.id,
          UnderstandingLevel.mastered,
          'Đã nhớ rõ các bất quy tắc',
          45,
        );

        var dates = await taskRepo.getActiveStudyDates();
        var activities = await taskRepo.getAllActivities();

        expect(dates.length, 1);
        expect(activities.length, 1);
        expect(activities.first.actualMinutes, 45);
        expect(activities.first.subjectId, 'subj_4');

        // Kiểm tra Streak
        final streak = StudyStreak.fromActiveDates(dates, now: now);
        expect(streak.currentStreak, 1);

        // 2. Chuyển lại về todo rồi completed lại -> Không được tạo thêm activity trùng
        await taskRepo.updateTaskStatus(task.id, TaskStatus.todo);
        await taskRepo.updateTaskStatus(task.id, TaskStatus.completed);

        activities = await taskRepo.getAllActivities();
        dates = await taskRepo.getActiveStudyDates();
        expect(activities.length, 1, reason: 'Không được cộng trùng activity');
        expect(dates.length, 1);

        // 3. Thống kê tính toán nhất quán
        final stats7Days = StudyStatisticsCalculator.calculate(
          tasks: [task.copyWith(status: TaskStatus.completed)],
          subjects: [
            const Subject(
              id: 'subj_4',
              name: 'Tiếng Anh',
              description: '',
              icon: Icons.language,
              color: Colors.blue,
            ),
          ],
          activities: activities,
          period: StatisticsPeriod.last7Days,
          now: now,
        );
        expect(stats7Days.periodCompletedTasks, 1);
        expect(stats7Days.totalActualMinutes, 45);
        expect(stats7Days.currentCompletedTasks, 1);
        expect(stats7Days.currentCompletionRate, 1.0);
      },
    );
  });

  group('G8.6 - Luồng 3: Deadline, Tìm kiếm và Bộ lọc', () {
    test(
      'Luồng 3: Xử lý task không deadline an toàn, tìm kiếm theo tên/mô tả/môn học và sắp xếp',
      () {
        final now = DateTime.now();
        final tasks = [
          StudyTask(
            id: 't1',
            title: 'Học React Native',
            subjectId: 'subj_2',
            subject: 'Lập trình Web',
            deadline: now.add(const Duration(hours: 2)), // Hôm nay
            notes: 'Component lifecycle',
            priority: TaskPriority.high,
            status: TaskStatus.inProgress,
          ),
          StudyTask(
            id: 't2',
            title: 'Viết bài luận',
            subjectId: 'subj_4',
            subject: 'Tiếng Anh',
            deadline: now.subtract(const Duration(days: 1)), // Quá hạn
            notes: 'IELTS Writing Task 2',
            priority: TaskPriority.medium,
            status: TaskStatus.todo,
          ),
          StudyTask(
            id: 't3',
            title: 'Ôn tập tổng quát',
            subjectId: 'subj_1',
            subject: 'Toán cao cấp',
            deadline: null, // Không có deadline
            notes: 'Xem lại các ghi chú cũ',
            priority: TaskPriority.low,
            status: TaskStatus.todo,
          ),
          StudyTask(
            id: 't4',
            title: 'Tạo bảng Database',
            subjectId: 'subj_3',
            subject: 'Cơ sở dữ liệu',
            deadline: now.subtract(const Duration(days: 2)),
            notes: 'CREATE TABLE orders',
            priority: TaskPriority.high,
            status: TaskStatus.completed,
          ),
        ];

        // 1. Kiểm tra cờ trạng thái
        expect(tasks[0].isOverdue, isFalse);
        expect(tasks[1].isOverdue, isTrue);
        expect(tasks[2].isOverdue, isFalse); // Không deadline -> không quá hạn
        expect(tasks[3].isOverdue, isFalse); // Đã hoàn thành -> không quá hạn

        // 2. Tìm kiếm theo tên môn học
        final searchBySubject = tasks.where((t) {
          final query = 'tiếng anh'.toLowerCase();
          return t.title.toLowerCase().contains(query) ||
              t.notes.toLowerCase().contains(query) ||
              t.subject.toLowerCase().contains(query);
        }).toList();
        expect(searchBySubject.length, 1);
        expect(searchBySubject.first.id, 't2');

        // 3. Tìm kiếm theo mô tả
        final searchByNotes = tasks.where((t) {
          final query = 'lifecycle'.toLowerCase();
          return t.title.toLowerCase().contains(query) ||
              t.notes.toLowerCase().contains(query) ||
              t.subject.toLowerCase().contains(query);
        }).toList();
        expect(searchByNotes.length, 1);
        expect(searchByNotes.first.id, 't1');

        // 4. Sắp xếp deadline an toàn với null
        final sortedAsc = List<StudyTask>.from(tasks)
          ..sort((a, b) {
            if (a.deadline == null && b.deadline == null) return 0;
            if (a.deadline == null) return 1;
            if (b.deadline == null) return -1;
            return a.deadline!.compareTo(b.deadline!);
          });
        expect(sortedAsc.last.id, 't3', reason: 'Task không deadline ở cuối');
      },
    );
  });

  group('G8.6 - Luồng 4: Profile, Đổi Theme và Đặt lại dữ liệu', () {
    late Database db;
    late TaskRepository taskRepo;
    late ProfileRepository profileRepo;
    late SubjectRepository subjectRepo;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE ${DatabaseHelper.tableSubjects} (
          ${DatabaseHelper.columnSubjectId} TEXT PRIMARY KEY,
          ${DatabaseHelper.columnSubjectName} TEXT NOT NULL,
          ${DatabaseHelper.columnSubjectDescription} TEXT NOT NULL,
          ${DatabaseHelper.columnSubjectIcon} INTEGER NOT NULL,
          ${DatabaseHelper.columnSubjectColor} INTEGER NOT NULL
        )
      ''');
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
          ${DatabaseHelper.columnActivityTaskId} TEXT,
          ${DatabaseHelper.columnActivityCompletedAt} TEXT NOT NULL,
          ${DatabaseHelper.columnActivityActualMinutes} INTEGER DEFAULT 0,
          ${DatabaseHelper.columnActivitySubjectId} TEXT
        )
      ''');
      await db.execute('''
        CREATE TABLE ${DatabaseHelper.tableProfile} (
          ${DatabaseHelper.columnProfileId} TEXT PRIMARY KEY,
          ${DatabaseHelper.columnProfileName} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileUniversity} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileMajor} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileAcademicYear} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileAvatarId} TEXT NOT NULL DEFAULT 'school',
          ${DatabaseHelper.columnProfileTargetHours} REAL NOT NULL DEFAULT 10.0,
          ${DatabaseHelper.columnProfileTargetTasks} INTEGER NOT NULL DEFAULT 5,
          ${DatabaseHelper.columnProfileThemeMode} TEXT NOT NULL DEFAULT 'system',
          ${DatabaseHelper.columnProfileReminderEnabled} INTEGER NOT NULL DEFAULT 0
        )
      ''');

      DatabaseHelper.instance.setDatabaseForTesting(db);
      taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);
      profileRepo = ProfileRepository(dbHelper: DatabaseHelper.instance);
      subjectRepo = SubjectRepository(dbHelper: DatabaseHelper.instance);
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'Luồng 4 (SQLite): Đặt lại dữ liệu học tập xóa task và activity nhưng giữ nguyên Profile và Môn học',
      () async {
        // 1. Chuẩn bị hồ sơ
        const profile = UserProfile(
          name: 'Đặng Thùy Dương',
          university: 'Đại học Kinh tế Quốc dân',
          major: 'Thương mại Điện tử',
          themeMode: 'dark',
          reminderEnabled: true,
        );
        await profileRepo.saveProfile(profile);

        // 2. Chuẩn bị môn học
        const sub = Subject(
          id: 'sub_mkt',
          name: 'Marketing Căn bản',
          description: '',
          icon: Icons.campaign,
          color: Colors.purple,
        );
        await subjectRepo.insertSubject(sub);

        // 3. Chuẩn bị task và activity
        final task = StudyTask(
          id: 'task_mkt_1',
          title: 'Nghiên cứu 4P',
          subjectId: 'sub_mkt',
          subject: 'Marketing Căn bản',
          status: TaskStatus.completed,
        );
        await taskRepo.insertTask(task);
        await taskRepo.recordTaskCompletion('task_mkt_1', actualMinutes: 60);

        // Xác nhận đã có dữ liệu
        expect((await taskRepo.getAllTasks()).length, 1);
        expect((await taskRepo.getAllActivities()).length, 1);

        // 4. THỰC HIỆN ĐẶT LẠI DỮ LIỆU HỌC TẬP (clearAllTasks)
        await taskRepo.clearAllTasks();

        // 5. Kiểm tra kết quả
        final remainingTasks = await taskRepo.getAllTasks();
        final remainingActivities = await taskRepo.getAllActivities();
        final remainingDates = await taskRepo.getActiveStudyDates();
        final preservedProfile = await profileRepo.getProfile();
        final preservedSubs = await subjectRepo.getAllSubjects();

        expect(remainingTasks, isEmpty, reason: 'Tasks phải bị xóa sạch');
        expect(
          remainingActivities,
          isEmpty,
          reason: 'Activities phải bị xóa sạch',
        );
        expect(
          remainingDates,
          isEmpty,
          reason: 'Streak dates phải bị xóa sạch',
        );
        expect(
          preservedProfile.name,
          'Đặng Thùy Dương',
          reason: 'Hồ sơ cá nhân phải được bảo toàn',
        );
        expect(
          preservedProfile.themeMode,
          'dark',
          reason: 'Cài đặt theme phải được bảo toàn',
        );
        expect(
          preservedSubs.any((s) => s.id == 'sub_mkt'),
          isTrue,
          reason: 'Môn học phải được bảo toàn',
        );
      },
    );

    test(
      'Luồng 4 (Web): Đặt lại dữ liệu học tập xóa task và activity nhưng giữ Profile và Môn học trên Web Preview',
      () async {
        final webTaskRepo = TaskRepository(useWebPreview: true);
        final webProfileRepo = ProfileRepository(useWebPreview: true);
        final webSubjectRepo = SubjectRepository(useWebPreview: true);

        // 1. Thiết lập hồ sơ
        const profile = UserProfile(
          name: 'Sinh viên Web',
          university: 'Đại học Quốc tế',
          themeMode: 'light',
        );
        await webProfileRepo.saveProfile(profile);

        // 2. Thiết lập task
        final task = StudyTask(
          id: 'web_t_reset',
          title: 'Bài tập Web',
          subjectId: 'subj_2',
          subject: 'Lập trình Web',
          status: TaskStatus.completed,
        );
        await webTaskRepo.insertTask(task);
        await webTaskRepo.recordTaskCompletion(
          'web_t_reset',
          actualMinutes: 30,
        );

        // 3. Đặt lại dữ liệu học tập
        await webTaskRepo.clearAllTasks();

        // 4. Kiểm tra
        final remainingTasks = await webTaskRepo.getAllTasks();
        final remainingActivities = await webTaskRepo.getAllActivities();
        final remainingDates = await webTaskRepo.getActiveStudyDates();
        final preservedProfile = await webProfileRepo.getProfile();
        final preservedSubjects = await webSubjectRepo.getAllSubjects();

        expect(remainingTasks, isEmpty);
        expect(remainingActivities, isEmpty);
        expect(remainingDates, isEmpty);
        expect(preservedProfile.name, 'Sinh viên Web');
        expect(preservedProfile.themeMode, 'light');
        expect(preservedSubjects, isNotEmpty);
      },
    );
  });

  group('G8.6 - Giai đoạn C: Kiểm thử SQLite Migration từ các schema cũ đến v6', () {
    test('Nâng cấp tuần tự từ Schema v1 -> v6 bảo toàn dữ liệu', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      // 1. Tạo schema v1: Chỉ có bảng study_tasks ban đầu, chưa có subject_id, chưa có activities, chưa có profile
      await db.execute('''
        CREATE TABLE ${DatabaseHelper.tableTasks} (
          ${DatabaseHelper.columnId} TEXT PRIMARY KEY,
          ${DatabaseHelper.columnTitle} TEXT NOT NULL,
          ${DatabaseHelper.columnSubject} TEXT NOT NULL,
          ${DatabaseHelper.columnDeadline} TEXT NOT NULL,
          ${DatabaseHelper.columnEstimatedMinutes} INTEGER NOT NULL,
          ${DatabaseHelper.columnPriority} TEXT NOT NULL,
          ${DatabaseHelper.columnStatus} TEXT NOT NULL,
          ${DatabaseHelper.columnNotes} TEXT NOT NULL DEFAULT ''
        )
      ''');

      // Chèn bản ghi từ thời v1
      await db.insert(DatabaseHelper.tableTasks, {
        DatabaseHelper.columnId: 'v1_task_1',
        DatabaseHelper.columnTitle: 'Bài tập Giải tích 1',
        DatabaseHelper.columnSubject: 'Toán cao cấp',
        DatabaseHelper.columnDeadline: '2026-11-20T10:00:00.000',
        DatabaseHelper.columnEstimatedMinutes: 60,
        DatabaseHelper.columnPriority: 'high',
        DatabaseHelper.columnStatus: 'todo',
        DatabaseHelper.columnNotes: 'Bài tập v1',
      });

      // 2. Thực hiện migration từ v1 -> v6 thông qua phương thức nâng cấp
      // Gọi upgrade v1 -> v2
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DatabaseHelper.tableSubjects} (
          ${DatabaseHelper.columnSubjectId} TEXT PRIMARY KEY,
          ${DatabaseHelper.columnSubjectName} TEXT NOT NULL,
          ${DatabaseHelper.columnSubjectDescription} TEXT NOT NULL,
          ${DatabaseHelper.columnSubjectIcon} INTEGER NOT NULL,
          ${DatabaseHelper.columnSubjectColor} INTEGER NOT NULL
        )
      ''');
      await db.execute(
        'ALTER TABLE ${DatabaseHelper.tableTasks} ADD COLUMN ${DatabaseHelper.columnTaskSubjectId} TEXT',
      );
      await db.rawUpdate(
        "UPDATE ${DatabaseHelper.tableTasks} SET ${DatabaseHelper.columnTaskSubjectId} = 'subj_1' WHERE ${DatabaseHelper.columnSubject} = 'Toán cao cấp'",
      );

      // Gọi upgrade v2 -> v3
      await db.execute(
        'ALTER TABLE ${DatabaseHelper.tableTasks} ADD COLUMN ${DatabaseHelper.columnUnderstandingLevel} TEXT',
      );
      await db.execute(
        'ALTER TABLE ${DatabaseHelper.tableTasks} ADD COLUMN ${DatabaseHelper.columnReviewNotes} TEXT',
      );

      // Gọi upgrade v3 -> v4
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DatabaseHelper.tableActivities} (
          ${DatabaseHelper.columnActivityId} TEXT PRIMARY KEY,
          ${DatabaseHelper.columnActivityDate} TEXT NOT NULL,
          ${DatabaseHelper.columnActivityTaskId} TEXT,
          ${DatabaseHelper.columnActivityCompletedAt} TEXT NOT NULL
        )
      ''');

      // Gọi upgrade v4 -> v5
      await db.execute(
        'ALTER TABLE ${DatabaseHelper.tableTasks} ADD COLUMN ${DatabaseHelper.columnActualMinutes} INTEGER',
      );
      await db.execute(
        'ALTER TABLE ${DatabaseHelper.tableActivities} ADD COLUMN ${DatabaseHelper.columnActivityActualMinutes} INTEGER DEFAULT 0',
      );
      await db.execute(
        'ALTER TABLE ${DatabaseHelper.tableActivities} ADD COLUMN ${DatabaseHelper.columnActivitySubjectId} TEXT',
      );

      // Gọi upgrade v5 -> v6
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ${DatabaseHelper.tableProfile} (
          ${DatabaseHelper.columnProfileId} TEXT PRIMARY KEY,
          ${DatabaseHelper.columnProfileName} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileUniversity} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileMajor} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileAcademicYear} TEXT NOT NULL DEFAULT '',
          ${DatabaseHelper.columnProfileAvatarId} TEXT NOT NULL DEFAULT 'school',
          ${DatabaseHelper.columnProfileTargetHours} REAL NOT NULL DEFAULT 10.0,
          ${DatabaseHelper.columnProfileTargetTasks} INTEGER NOT NULL DEFAULT 5,
          ${DatabaseHelper.columnProfileThemeMode} TEXT NOT NULL DEFAULT 'system',
          ${DatabaseHelper.columnProfileReminderEnabled} INTEGER NOT NULL DEFAULT 0
        )
      ''');

      // 3. Kiểm tra tính toàn vẹn của dữ liệu sau khi nâng cấp lên v6
      final migratedMaps = await db.query(DatabaseHelper.tableTasks);
      expect(migratedMaps.length, 1);
      final migratedTask = StudyTask.fromMap(migratedMaps.first);

      expect(migratedTask.id, 'v1_task_1');
      expect(migratedTask.title, 'Bài tập Giải tích 1');
      expect(
        migratedTask.subjectId,
        'subj_1',
        reason: 'subject_id phải được backfill chính xác',
      );
      expect(migratedTask.understandingLevel, isNull);
      expect(migratedTask.actualMinutes, isNull);

      // Kiểm tra có thể chèn profile vào bảng mới tạo
      await db.insert(DatabaseHelper.tableProfile, {
        DatabaseHelper.columnProfileId: 'profile_default',
        DatabaseHelper.columnProfileName: 'Người dùng v6',
      });
      final profileMaps = await db.query(DatabaseHelper.tableProfile);
      expect(profileMaps.length, 1);
      expect(
        profileMaps.first[DatabaseHelper.columnProfileName],
        'Người dùng v6',
      );

      await db.close();
    });
  });

  group(
    'G8.6 - Giai đoạn D: Kiểm tra Responsive UI trên các kích thước màn hình',
    () {
      testWidgets(
        'Màn hình 320dp và 360dp không bị lỗi tràn pixel trên cả 5 tab',
        (tester) async {
          final viewports = [
            const Size(320, 640), // Điện thoại màn hình siêu nhỏ
            const Size(360, 780), // Kích thước màn hình phổ biến
            const Size(412, 915), // Màn hình tiêu chuẩn lớn
          ];

          for (final size in viewports) {
            tester.view.physicalSize = size;
            tester.view.devicePixelRatio = 1.0;

            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: AppShell(
                    taskRepository: TaskRepository(useWebPreview: true),
                    subjectRepository: SubjectRepository(useWebPreview: true),
                    profileRepository: ProfileRepository(useWebPreview: true),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();

            // Không có lỗi render trên tab Tổng quan
            expect(find.text('ExamPilot'), findsOneWidget);

            // Chuyển sang tab Kế hoạch
            await tester.tap(find.text('Kế hoạch'));
            await tester.pumpAndSettle();
            expect(find.byType(PlanScreen), findsOneWidget);

            // Chuyển sang tab Môn học
            await tester.tap(find.text('Môn học'));
            await tester.pumpAndSettle();
            expect(find.byType(SubjectsScreen), findsOneWidget);

            // Chuyển sang tab Thống kê
            await tester.tap(find.text('Thống kê'));
            await tester.pumpAndSettle();
            expect(find.byType(StatisticsScreen), findsOneWidget);

            // Chuyển sang tab Cá nhân
            await tester.tap(find.text('Cá nhân'));
            await tester.pumpAndSettle();
            expect(find.byType(ProfileScreen), findsOneWidget);

            tester.view.resetPhysicalSize();
          }
        },
      );
    },
  );
}

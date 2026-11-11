import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:exampilot/database/database_helper.dart';
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
import 'package:exampilot/screens/profile_screen.dart';
import 'package:exampilot/services/backup_service.dart';
import 'package:exampilot/services/web_storage.dart';
import 'package:exampilot/widgets/backup_dialogs.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Database db;
  late TaskRepository taskRepo;
  late SubjectRepository subjectRepo;
  late ProfileRepository profileRepo;
  late BackupService backupService;

  Future<void> setupInMemoryDatabase() async {
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

    // Tạo bảng study_activities
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

    // Tạo bảng user_profile
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

    DatabaseHelper.instance.setDatabaseForTesting(db);
    taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);
    subjectRepo = SubjectRepository(dbHelper: DatabaseHelper.instance);
    profileRepo = ProfileRepository(
      dbHelper: DatabaseHelper.instance,
      useWebPreview: false,
    );
    backupService = BackupService(
      taskRepository: taskRepo,
      subjectRepository: subjectRepo,
      profileRepository: profileRepo,
      dbHelper: DatabaseHelper.instance,
    );
  }

  setUp(() async {
    BackupService.testFilePicker = null;
    BackupService.testFileSharer = null;
    WebStreakStorage.clearStudyActivitiesAndDates();
    WebStreakStorage.clearProfile();
    await setupInMemoryDatabase();
  });

  tearDown(() async {
    await db.close();
    DatabaseHelper.instance.setDatabaseForTesting(null);
  });

  group('1. BackupService - Tạo bản sao lưu (Create Backup)', () {
    test('Tạo bản sao lưu khi cơ sở dữ liệu rỗng', () async {
      final backupMap = await backupService.createBackupData();

      expect(backupMap['app'], equals('ExamPilot'));
      expect(backupMap['formatVersion'], equals(1));
      expect(backupMap['appVersion'], equals('1.0.0'));
      expect(backupMap['createdAt'], isNotNull);

      final metadata = backupMap['metadata'] as Map<String, dynamic>;
      expect(metadata['totalSubjects'], equals(0));
      expect(metadata['totalTasks'], equals(0));
      expect(metadata['totalActivities'], equals(0));

      final data = backupMap['data'] as Map<String, dynamic>;
      expect((data['subjects'] as List).isEmpty, isTrue);
      expect((data['tasks'] as List).isEmpty, isTrue);
      expect((data['activities'] as List).isEmpty, isTrue);
      expect(data['profile'], isNotNull);

      // Checksum không rỗng và dài 8 ký tự hex
      final checksum = backupMap['checksum'] as String;
      expect(checksum.length, equals(8));

      // Xuất sang chuỗi JSON hợp lệ
      final jsonString = backupService.exportBackupJson(backupMap);
      expect(jsonString, contains('"app": "ExamPilot"'));
      expect(jsonString, contains('"formatVersion": 1'));
    });

    test('Tạo bản sao lưu với dữ liệu đầy đủ và đa dạng trường', () async {
      // 1. Thêm 3 môn học
      final sub1 = const Subject(
        id: 'sub_1',
        name: 'Toán cao cấp',
        description: 'Giải tích và đại số',
        icon: Icons.functions,
        color: Colors.blue,
      );
      final sub2 = const Subject(
        id: 'sub_2',
        name: 'Cơ sở dữ liệu',
        description: 'SQL & RDBMS',
        icon: Icons.storage,
        color: Colors.orange,
      );
      final sub3 = const Subject(
        id: 'sub_3',
        name: 'Lập trình Flutter',
        description: 'Cross-platform app dev',
        icon: Icons.phone_android,
        color: Colors.teal,
      );
      await subjectRepo.insertSubject(sub1);
      await subjectRepo.insertSubject(sub2);
      await subjectRepo.insertSubject(sub3);

      // 2. Thêm 5 công việc (bao gồm cả deadline null và deadline cụ thể, các trạng thái khác nhau)
      final now = DateTime.now();
      final task1 = StudyTask(
        id: 'task_1',
        title: 'Làm bài tập tích phân',
        subjectId: 'sub_1',
        subject: 'Toán cao cấp',
        deadline: now.add(const Duration(days: 2)),
        estimatedMinutes: 60,
        actualMinutes: 45,
        priority: TaskPriority.high,
        status: TaskStatus.completed,
        notes: 'Ghi chú quan trọng',
        understandingLevel: UnderstandingLevel.mastered,
        reviewNotes: 'Đã nắm chắc phương pháp từng phần',
      );
      final task2 = StudyTask(
        id: 'task_2',
        title: 'Thiết kế ERD bài tập lớn',
        subjectId: 'sub_2',
        subject: 'Cơ sở dữ liệu',
        deadline: null, // Deadline null
        estimatedMinutes: 90,
        priority: TaskPriority.medium,
        status: TaskStatus.inProgress,
        notes: 'Chưa chốt quan hệ n-n',
      );
      final task3 = StudyTask(
        id: 'task_3',
        title: 'Đọc tài liệu Provider & Riverpod',
        subjectId: 'sub_3',
        subject: 'Lập trình Flutter',
        deadline: now.subtract(const Duration(days: 1)),
        estimatedMinutes: 40,
        priority: TaskPriority.low,
        status: TaskStatus.todo,
      );
      final task4 = StudyTask(
        id: 'task_4',
        title: 'Thực hành câu lệnh GROUP BY HAVING',
        subjectId: 'sub_2',
        subject: 'Cơ sở dữ liệu',
        deadline: now.add(const Duration(hours: 6)),
        estimatedMinutes: 50,
        actualMinutes: 50,
        priority: TaskPriority.high,
        status: TaskStatus.completed,
        understandingLevel: UnderstandingLevel.partiallyUnderstood,
      );
      final task5 = StudyTask(
        id: 'task_5',
        title: 'Xem lại bài giảng chuỗi số',
        subjectId: 'sub_1',
        subject: 'Toán cao cấp',
        deadline: null, // Deadline null
        estimatedMinutes: 30,
        priority: TaskPriority.medium,
        status: TaskStatus.todo,
      );

      await taskRepo.insertTask(task1);
      await taskRepo.insertTask(task2);
      await taskRepo.insertTask(task3);
      await taskRepo.insertTask(task4);
      await taskRepo.insertTask(task5);

      // 3. Thêm 4 hoạt động học tập
      await taskRepo.recordTaskCompletion(
        'task_1',
        completedAt: now.subtract(const Duration(days: 2)),
        actualMinutes: 45,
        subjectId: 'sub_1',
      );
      await taskRepo.recordTaskCompletion(
        'task_4',
        completedAt: now.subtract(const Duration(days: 1)),
        actualMinutes: 50,
        subjectId: 'sub_2',
      );
      await taskRepo.recordTaskCompletion(
        'task_3',
        completedAt: now,
        actualMinutes: 60,
        subjectId: 'sub_3',
      );
      await taskRepo.recordTaskCompletion(
        'task_2',
        completedAt: now,
        actualMinutes: 30,
        subjectId: 'sub_2',
      );

      // 4. Cập nhật hồ sơ cá nhân
      const customProfile = UserProfile(
        name: 'Trần Văn An',
        university: 'Đại học Bách Khoa',
        major: 'Kỹ thuật Phần mềm',
        academicYear: 'K65',
        avatarId: 'developer',
        weeklyTargetHours: 15.0,
        weeklyTargetTasks: 8,
        themeMode: 'dark',
        reminderEnabled: true,
      );
      await profileRepo.saveProfile(customProfile);

      // 5. Tạo dữ liệu sao lưu
      final backupMap = await backupService.createBackupData();
      final metadata = backupMap['metadata'] as Map<String, dynamic>;
      expect(metadata['totalSubjects'], equals(3));
      expect(metadata['totalTasks'], equals(5));
      expect(metadata['totalActivities'], equals(4));

      final data = backupMap['data'] as Map<String, dynamic>;
      final subjectsList = data['subjects'] as List;
      final tasksList = data['tasks'] as List;
      final activitiesList = data['activities'] as List;
      final profileData = data['profile'] as Map<String, dynamic>;

      expect(subjectsList.length, equals(3));
      expect(tasksList.length, equals(5));
      expect(activitiesList.length, equals(4));
      expect(profileData['name'], equals('Trần Văn An'));
      expect(profileData['weekly_target_hours'], equals(15.0));

      // Kiểm tra tính hợp lệ của Checksum
      final canonicalDataJson = jsonEncode(data);
      final expectedChecksum = BackupService.computeChecksum(canonicalDataJson);
      expect(backupMap['checksum'], equals(expectedChecksum));
    });
  });

  group(
    '2. BackupService - Xác thực tính toàn vẹn (Checksum & Validation)',
    () {
      test('Xác thực chuỗi JSON rỗng hoặc khoảng trắng', () {
        final res1 = backupService.validateBackupJson('');
        expect(res1.isValid, isFalse);
        expect(res1.errorMessage, contains('rỗng'));

        final res2 = backupService.validateBackupJson('   \n  ');
        expect(res2.isValid, isFalse);
        expect(res2.errorMessage, contains('rỗng'));
      });

      test('Xác thực chuỗi JSON cú pháp sai', () {
        final res = backupService.validateBackupJson('{ bad json : 123');
        expect(res.isValid, isFalse);
        expect(res.errorMessage, contains('định dạng JSON'));
      });

      test('Xác thực chuỗi JSON không phải Map', () {
        final res = backupService.validateBackupJson('[1, 2, 3]');
        expect(res.isValid, isFalse);
        expect(res.errorMessage, contains('Cấu trúc'));
      });

      test('Từ chối tệp không thuộc về ExamPilot', () {
        final map = {
          'app': 'SomeOtherApp',
          'formatVersion': 1,
          'appVersion': '1.0.0',
          'data': {},
          'checksum': '12345678',
        };
        final res = backupService.validateBackupJson(jsonEncode(map));
        expect(res.isValid, isFalse);
        expect(res.errorMessage, contains('ExamPilot'));
      });

      test(
        'Từ chối tệp thiếu version hoặc version mới hơn phiên bản hỗ trợ',
        () {
          final mapNoVer = {
            'app': 'ExamPilot',
            'appVersion': '1.0.0',
            'data': {},
            'checksum': '12345678',
          };
          final resNoVer = backupService.validateBackupJson(
            jsonEncode(mapNoVer),
          );
          expect(resNoVer.isValid, isFalse);
          expect(resNoVer.errorMessage, contains('phiên bản'));

          final mapFutureVer = {
            'app': 'ExamPilot',
            'formatVersion': 99,
            'appVersion': '99.0.0',
            'data': {},
            'checksum': '12345678',
          };
          final resFutureVer = backupService.validateBackupJson(
            jsonEncode(mapFutureVer),
          );
          expect(resFutureVer.isValid, isFalse);
          expect(resFutureVer.errorMessage, contains('mới hơn'));
        },
      );

      test('Từ chối tệp thiếu khối dữ liệu data hoặc các trường bắt buộc', () {
        final mapNoData = {
          'app': 'ExamPilot',
          'formatVersion': 1,
          'appVersion': '1.0.0',
          'checksum': '12345678',
        };
        final resNoData = backupService.validateBackupJson(
          jsonEncode(mapNoData),
        );
        expect(resNoData.isValid, isFalse);
        expect(resNoData.errorMessage, contains('data'));

        final mapIncompleteData = {
          'app': 'ExamPilot',
          'formatVersion': 1,
          'appVersion': '1.0.0',
          'data': {'subjects': []},
          'checksum': '12345678',
        };
        final resIncomplete = backupService.validateBackupJson(
          jsonEncode(mapIncompleteData),
        );
        expect(resIncomplete.isValid, isFalse);
        expect(resIncomplete.errorMessage, contains('tasks'));
      });

      test('Phát hiện sửa đổi dữ liệu (Checksum Mismatch)', () async {
        // 1. Tạo bản sao lưu hợp lệ
        final backupMap = await backupService.createBackupData();
        final validJson = backupService.exportBackupJson(backupMap);

        // Xác thực bản sao lưu gốc phải hợp lệ
        final validRes = backupService.validateBackupJson(validJson);
        expect(validRes.isValid, isTrue);
        expect(validRes.preview, isNotNull);

        // 2. Sửa lén 1 trường trong data mà không tính lại checksum
        final parsed = jsonDecode(validJson) as Map<String, dynamic>;
        final dataBlock = parsed['data'] as Map<String, dynamic>;
        dataBlock['hackedField'] = 'malicious';

        final tamperedJson = jsonEncode(parsed);
        final tamperedRes = backupService.validateBackupJson(tamperedJson);

        expect(tamperedRes.isValid, isFalse);
        expect(tamperedRes.errorMessage, contains('Checksum không khớp'));
      });
    },
  );

  group(
    '3. BackupService - Khôi phục dữ liệu trên SQLite (Restore on SQLite)',
    () {
      test(
        'Khôi phục thành công thay thế dữ liệu cũ và bảo toàn quan hệ',
        () async {
          // Dữ liệu cũ trước khi khôi phục
          final oldSub = const Subject(
            id: 'old_sub',
            name: 'Môn học cũ',
            description: 'Cũ',
            icon: Icons.book,
            color: Colors.red,
          );
          await subjectRepo.insertSubject(oldSub);

          final oldTask = StudyTask(
            id: 'old_task',
            title: 'Việc cũ',
            subjectId: 'old_sub',
            subject: 'Môn học cũ',
            deadline: DateTime.now(),
            estimatedMinutes: 20,
          );
          await taskRepo.insertTask(oldTask);

          // Chuẩn bị dữ liệu sao lưu mới để khôi phục
          final newDate = DateTime(2026, 11, 10, 14, 30);
          final backupSubjects = [
            {
              'id': 'sub_it1',
              'name': 'Cấu trúc dữ liệu & Giải thuật',
              'description': 'Tree, Graph, Sorting',
              'icon_code': Icons.account_tree.codePoint,
              'color_value': Colors.indigo.toARGB32(),
            },
            {
              'id': 'sub_it2',
              'name': 'Hệ điều hành',
              'description': 'Process, Thread, Deadlock',
              'icon_code': Icons.memory.codePoint,
              'color_value': Colors.deepOrange.toARGB32(),
            },
          ];

          final backupTasks = [
            {
              'id': 'task_algo_1',
              'title': 'Cài đặt thuật toán Dijkstra',
              'subject_id': 'sub_it1',
              'subject': 'Cấu trúc dữ liệu & Giải thuật',
              'deadline': newDate.toIso8601String(),
              'estimated_minutes': 60,
              'actual_minutes': 55,
              'priority': 'high',
              'status': 'completed',
              'notes': 'Dùng PriorityQueue tối ưu O(E log V)',
              'understanding_level': 'mastered',
              'review_notes': 'Đã làm xong',
            },
            {
              'id': 'task_os_1',
              'title': 'Đọc chương Semaphore & Mutex',
              'subject_id': 'sub_it2',
              'subject': 'Hệ điều hành',
              'deadline': '', // deadline null
              'estimated_minutes': 45,
              'actual_minutes': 0,
              'priority': 'medium',
              'status': 'todo',
              'notes': '',
              'understanding_level': null,
              'review_notes': null,
            },
          ];

          final backupActivities = [
            {
              'id': 'act_1',
              'activity_date': '2026-11-10',
              'task_id': 'task_algo_1',
              'completed_at': newDate.toIso8601String(),
              'actual_minutes': 55,
              'subject_id': 'sub_it1',
            },
          ];

          final backupProfile = {
            'id': 'user_profile_main',
            'name': 'Nguyễn Văn Nam',
            'university': 'Đại học Quốc gia',
            'major': 'Công nghệ Thông tin',
            'academic_year': 'Năm 3',
            'avatar_id': 'laptop',
            'weekly_target_hours': 12.0,
            'weekly_target_tasks': 6,
            'theme_mode': 'dark',
            'reminder_enabled': 1,
          };

          final dataBlock = {
            'subjects': backupSubjects,
            'tasks': backupTasks,
            'activities': backupActivities,
            'profile': backupProfile,
          };

          final checksum = BackupService.computeChecksum(jsonEncode(dataBlock));

          final backupMap = {
            'app': 'ExamPilot',
            'formatVersion': 1,
            'appVersion': '1.0.0',
            'createdAt': newDate.toIso8601String(),
            'metadata': {
              'totalSubjects': 2,
              'totalTasks': 2,
              'totalActivities': 1,
            },
            'data': dataBlock,
            'checksum': checksum,
          };

          // Thực hiện khôi phục
          await backupService.restoreBackup(backupMap);

          // Kiểm tra môn học trong SQLite
          final subjectsAfter = await subjectRepo.getAllSubjects();
          expect(subjectsAfter.length, equals(2));
          expect(
            subjectsAfter.any((s) => s.name == 'Cấu trúc dữ liệu & Giải thuật'),
            isTrue,
          );
          expect(subjectsAfter.any((s) => s.name == 'Hệ điều hành'), isTrue);
          expect(
            subjectsAfter.any((s) => s.name == 'Môn học cũ'),
            isFalse,
          ); // Đã bị xóa

          // Kiểm tra công việc trong SQLite
          final tasksAfter = await taskRepo.getAllTasks();
          expect(tasksAfter.length, equals(2));
          final dijkstraTask = tasksAfter.firstWhere(
            (t) => t.id == 'task_algo_1',
          );
          expect(dijkstraTask.subjectId, equals('sub_it1'));
          expect(dijkstraTask.deadline, isNotNull);
          expect(dijkstraTask.status, equals(TaskStatus.completed));
          expect(
            dijkstraTask.understandingLevel,
            equals(UnderstandingLevel.mastered),
          );

          final osTask = tasksAfter.firstWhere((t) => t.id == 'task_os_1');
          expect(osTask.subjectId, equals('sub_it2'));
          expect(
            osTask.deadline,
            isNull,
          ); // Deadline rỗng được phục hồi là null
          expect(osTask.status, equals(TaskStatus.todo));

          // Kiểm tra hoạt động & Study Streak
          final activitiesAfter = await taskRepo.getAllActivities();
          expect(activitiesAfter.length, equals(1));
          expect(activitiesAfter.first.dateKey, equals('2026-11-10'));

          final activeDatesAfter = await taskRepo.getActiveStudyDates();
          expect(activeDatesAfter.contains('2026-11-10'), isTrue);

          // Kiểm tra hồ sơ cá nhân
          final profileAfter = await profileRepo.getProfile();
          expect(profileAfter.name, equals('Nguyễn Văn Nam'));
          expect(profileAfter.major, equals('Công nghệ Thông tin'));
          expect(profileAfter.weeklyTargetHours, equals(12.0));
          expect(profileAfter.weeklyTargetTasks, equals(6));
          expect(profileAfter.themeMode, equals('dark'));
          expect(profileAfter.reminderEnabled, isTrue);
        },
      );

      test(
        'Tự động bổ sung môn học nếu task tham chiếu subjectId chưa có',
        () async {
          // Dữ liệu khôi phục có task tham chiếu 'sub_missing' nhưng danh sách subjects không có
          final dataBlock = {
            'subjects': <Map<String, dynamic>>[],
            'tasks': [
              {
                'id': 'task_orphan',
                'title': 'Bài tập không có môn cha',
                'subject_id': 'sub_orphan_1',
                'subject': 'Môn Học Ảo',
                'deadline': '',
                'estimated_minutes': 30,
                'priority': 'low',
                'status': 'todo',
              },
            ],
            'activities': <Map<String, dynamic>>[],
            'profile': const UserProfile().toMap(),
          };

          final checksum = BackupService.computeChecksum(jsonEncode(dataBlock));
          final backupMap = {
            'app': 'ExamPilot',
            'formatVersion': 1,
            'appVersion': '1.0.0',
            'createdAt': DateTime.now().toIso8601String(),
            'metadata': {
              'totalSubjects': 0,
              'totalTasks': 1,
              'totalActivities': 0,
            },
            'data': dataBlock,
            'checksum': checksum,
          };

          await backupService.restoreBackup(backupMap);

          // Môn học phải được tự động bổ sung để tránh orphaned tasks
          final subjects = await subjectRepo.getAllSubjects();
          expect(subjects.length, equals(1));
          expect(subjects.first.id, equals('sub_orphan_1'));
          expect(subjects.first.name, equals('Môn Học Ảo'));

          final tasks = await taskRepo.getAllTasks();
          expect(tasks.length, equals(1));
          expect(tasks.first.subjectId, equals('sub_orphan_1'));
        },
      );
    },
  );

  group(
    '4. BackupService - Khôi phục dữ liệu trên Web Preview (Restore on Web Preview)',
    () {
      test('Khôi phục dữ liệu chuẩn xác vào WebStreakStorage', () async {
        final webTaskRepo = TaskRepository(useWebPreview: true);
        final webSubRepo = SubjectRepository(useWebPreview: true);
        final webProfileRepo = ProfileRepository(useWebPreview: true);
        final webBackupService = BackupService(
          taskRepository: webTaskRepo,
          subjectRepository: webSubRepo,
          profileRepository: webProfileRepo,
        );

        final now = DateTime.now();
        final backupMap = {
          'app': 'ExamPilot',
          'formatVersion': 1,
          'appVersion': '1.0.0',
          'createdAt': now.toIso8601String(),
          'metadata': {
            'totalSubjects': 1,
            'totalTasks': 1,
            'totalActivities': 1,
          },
          'data': {
            'subjects': [
              {
                'id': 'web_sub_1',
                'name': 'Web Frontend',
                'description': 'HTML/CSS/JS',
                'icon_code': Icons.language.codePoint,
                'color_value': Colors.blue.toARGB32(),
              },
            ],
            'tasks': [
              {
                'id': 'web_task_1',
                'title': 'Responsive Layout CSS',
                'subject_id': 'web_sub_1',
                'subject': 'Web Frontend',
                'deadline': now.toIso8601String(),
                'estimated_minutes': 45,
                'priority': 'medium',
                'status': 'completed',
                'actual_minutes': 45,
              },
            ],
            'activities': [
              {
                'id': 'web_act_1',
                'activity_date': StudyStreak.formatDateKey(now),
                'task_id': 'web_task_1',
                'completed_at': now.toIso8601String(),
                'actual_minutes': 45,
                'subject_id': 'web_sub_1',
              },
            ],
            'profile': const UserProfile(
              name: 'Sinh viên Web Preview',
              university: 'Đại học FPT',
              major: 'Kỹ thuật phần mềm',
              weeklyTargetHours: 8.0,
              weeklyTargetTasks: 4,
            ).toMap(),
          },
        };

        await webBackupService.restoreBackup(backupMap);

        // Đọc lại từ web repositories
        final subjects = await webSubRepo.getAllSubjects();
        expect(subjects.length, equals(1));
        expect(subjects.first.name, equals('Web Frontend'));

        final tasks = await webTaskRepo.getAllTasks();
        expect(tasks.length, equals(1));
        expect(tasks.first.title, equals('Responsive Layout CSS'));

        final activities = await webTaskRepo.getAllActivities();
        expect(activities.length, equals(1));

        final activeDates = await webTaskRepo.getActiveStudyDates();
        expect(activeDates.contains(StudyStreak.formatDateKey(now)), isTrue);

        final profile = await webProfileRepo.getProfile();
        expect(profile.name, equals('Sinh viên Web Preview'));
        expect(profile.weeklyTargetHours, equals(8.0));
      });
    },
  );

  group('5. BackupService - Cơ chế Transaction & Rollback khi lỗi', () {
    test(
      'Rollback nguyên vẹn khi xảy ra lỗi trong quá trình khôi phục SQLite',
      () async {
        // 1. Dữ liệu ban đầu
        final initialSubject = const Subject(
          id: 'safe_sub',
          name: 'Môn học an toàn',
          description: 'Bảo vệ dữ liệu',
          icon: Icons.shield,
          color: Colors.green,
        );
        await subjectRepo.insertSubject(initialSubject);

        final initialTask = StudyTask(
          id: 'safe_task',
          title: 'Công việc an toàn',
          subjectId: 'safe_sub',
          subject: 'Môn học an toàn',
          deadline: DateTime.now(),
          estimatedMinutes: 30,
        );
        await taskRepo.insertTask(initialTask);

        // 2. Tạo một backup map cố ý gây lỗi khi thực thi transaction
        // Ví dụ: task có cấu trúc làm ném exception khi map hoặc xử lý
        final badDataBlock = {
          'subjects': [
            {
              'id': 'new_sub',
              'name': 'Môn học mới',
              'description': 'Mô tả',
              'icon_code': Icons.book.codePoint,
              'color_value': Colors.blue.toARGB32(),
            },
          ],
          // Cố ý đưa trường bị lỗi kiểu khiến câu lệnh SQLite hoặc convert ném lỗi
          'tasks': [
            {
              'id': 'bad_task',
              'title': 'Bad Task',
              'subject_id': 'new_sub',
              'subject': 'Môn học mới',
              // deadline ép kiểu sai để ném FormatException hoặc SQLite type exception
              'deadline': null,
              'estimated_minutes': 'invalid_string_not_int', // Lỗi kiểu dữ liệu
            },
          ],
          'activities': <Map<String, dynamic>>[],
          'profile': const UserProfile().toMap(),
        };

        final backupMap = {
          'app': 'ExamPilot',
          'formatVersion': 1,
          'appVersion': '1.0.0',
          'createdAt': DateTime.now().toIso8601String(),
          'metadata': {
            'totalSubjects': 1,
            'totalTasks': 1,
            'totalActivities': 0,
          },
          'data': badDataBlock,
          'checksum': 'any',
        };

        // 3. Gọi khôi phục và kỳ vọng ném Exception
        expect(
          () async => await backupService.restoreBackup(backupMap),
          throwsA(isA<Exception>()),
        );

        // 4. Kiểm tra dữ liệu cũ: Phải được giữ nguyên 100% (Rollback thành công)
        final subjectsAfterFail = await subjectRepo.getAllSubjects();
        expect(subjectsAfterFail.length, equals(1));
        expect(subjectsAfterFail.first.name, equals('Môn học an toàn'));

        final tasksAfterFail = await taskRepo.getAllTasks();
        expect(tasksAfterFail.length, equals(1));
        expect(tasksAfterFail.first.title, equals('Công việc an toàn'));
      },
    );
  });

  group('6. Giao diện người dùng - Widget Tests cho Backup & Restore', () {
    testWidgets('ProfileScreen hiển thị khối Sao lưu & Khôi phục dữ liệu', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      bool backupTriggered = false;
      bool restoreTriggered = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProfileScreen(
              profile: const UserProfile(name: 'Nguyễn Văn Test'),
              activities: const [],
              lastBackupTime: null,
              onBackupData: () async {
                backupTriggered = true;
              },
              onRestoreData: () async {
                restoreTriggered = true;
              },
              onUpdateProfile: (_) {},
              onUpdateGoals: (_, _) {},
              onUpdateThemeMode: (_) {},
              onUpdateReminderEnabled: (_) {},
              onResetStudyData: () async {},
              onResetProfile: () async {},
              onResetSampleData: () async {},
              onResetAllData: () async {},
            ),
          ),
        ),
      );

      // Kiểm tra tiêu đề khu vực
      expect(find.text('Sao lưu & Khôi phục'), findsOneWidget);

      // Bấm nút Sao lưu dữ liệu
      final backupBtn = find.byKey(const ValueKey('backup_data_button'));
      expect(backupBtn, findsOneWidget);
      await tester.tap(backupBtn);
      await tester.pumpAndSettle();
      expect(backupTriggered, isTrue);

      // Bấm nút Khôi phục dữ liệu
      final restoreBtn = find.byKey(const ValueKey('restore_data_button'));
      expect(restoreBtn, findsOneWidget);
      await tester.tap(restoreBtn);
      await tester.pumpAndSettle();
      expect(restoreTriggered, isTrue);
    });

    testWidgets(
      'BackupSuccessDialog hiển thị kết quả và cho phép sao chép JSON',
      (tester) async {
        final sampleBackupMap = {
          'metadata': {
            'totalSubjects': 4,
            'totalTasks': 10,
            'totalActivities': 7,
          },
        };

        final testBackupService = BackupService(
          subjectRepository: SubjectRepository(useWebPreview: true),
          taskRepository: TaskRepository(useWebPreview: true),
          profileRepository: ProfileRepository(useWebPreview: true),
        );

        bool shareCalled = false;
        BackupService.testFileSharer = (path, name) async {
          shareCalled = true;
        };
        addTearDown(() {
          BackupService.testFileSharer = null;
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: BackupSuccessDialog(
                backupMap: sampleBackupMap,
                jsonString: '{"test": 123}',
                filePath: '/storage/emulated/0/Download/backup.json',
                backupService: testBackupService,
              ),
            ),
          ),
        );

        expect(find.text('Sao lưu thành công!'), findsOneWidget);
        expect(find.text('4 môn'), findsOneWidget);
        expect(find.text('10 việc'), findsOneWidget);
        expect(find.text('7 lượt'), findsOneWidget);
        expect(
          find.text('/storage/emulated/0/Download/backup.json'),
          findsOneWidget,
        );

        // Nút Chia sẻ / Lưu tệp ra ngoài
        final shareBtn = find.byKey(const ValueKey('share_backup_file_button'));
        expect(shareBtn, findsOneWidget);

        await tester.tap(shareBtn);
        await tester.pumpAndSettle();
        expect(shareCalled, isTrue);

        // Nút Sao chép mã JSON
        final copyBtn = find.byKey(const ValueKey('copy_backup_json_button'));
        expect(copyBtn, findsOneWidget);
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();
        expect(find.byType(SnackBar), findsOneWidget);

        // Nút Đóng
        final closeBtn = find.widgetWithText(FilledButton, 'Đóng');
        expect(closeBtn, findsOneWidget);
        await tester.tap(closeBtn);
        await tester.pumpAndSettle();
      },
    );

    testWidgets('RestoreInputDialog nhập dữ liệu và xác thực', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      BackupValidationResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: ctx,
                      builder: (_) => RestoreInputDialog(
                        backupService: backupService,
                        onValidBackup: (res) {
                          capturedResult = res;
                        },
                      ),
                    );
                  },
                  child: const Text('Mở hộp thoại'),
                );
              },
            ),
          ),
        ),
      );

      // Mở dialog
      await tester.tap(find.text('Mở hộp thoại'));
      await tester.pumpAndSettle();

      expect(find.text('Khôi phục dữ liệu'), findsOneWidget);
      final validateBtn = find.byKey(const ValueKey('validate_backup_button'));

      // Bấm khi ô nhập rỗng -> hiển thị lỗi
      await tester.tap(validateBtn);
      await tester.pumpAndSettle();
      expect(
        find.text('Vui lòng dán hoặc nhập nội dung tệp sao lưu JSON.'),
        findsOneWidget,
      );

      // Nhập JSON không hợp lệ
      final inputField = find.byKey(const ValueKey('restore_json_input_field'));
      await tester.enterText(inputField, '{"app": "WrongApp"}');
      await tester.tap(validateBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('Tệp này không phải là bản sao lưu của ExamPilot.'),
        findsOneWidget,
      );

      // Chuẩn bị dữ liệu hợp lệ thuần túy không phụ thuộc I/O
      final validDataBlock = {
        'profile': const UserProfile(name: 'Test User').toMap(),
        'subjects': [
          {
            'id': 'sub_1',
            'name': 'Toán',
            'description': 'Mô tả',
            'icon_code': 123,
            'color_value': 456,
          },
        ],
        'tasks': [
          {
            'id': 'task_1',
            'title': 'Học bài',
            'subject_id': 'sub_1',
            'subject': 'Toán',
            'deadline': '',
            'estimated_minutes': 30,
            'priority': 'medium',
            'status': 'todo',
          },
        ],
        'activities': <Map<String, dynamic>>[],
      };
      final checksum = BackupService.computeChecksum(
        jsonEncode(validDataBlock),
      );
      final validBackupMap = {
        'app': 'ExamPilot',
        'formatVersion': 1,
        'appVersion': '1.0.0',
        'createdAt': DateTime.now().toIso8601String(),
        'metadata': {'totalSubjects': 1, 'totalTasks': 1, 'totalActivities': 0},
        'data': validDataBlock,
        'checksum': checksum,
      };
      final validJson = jsonEncode(validBackupMap);

      await tester.enterText(inputField, validJson);
      await tester.tap(validateBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(capturedResult, isNotNull);
      expect(capturedResult!.isValid, isTrue);
    });

    testWidgets(
      'RestorePreviewDialog hiển thị bản xem trước, cảnh báo và nút xác nhận',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        bool restoreConfirmed = false;
        final preview = BackupPreview(
          formatVersion: 1,
          appVersion: '1.0.0',
          createdAt: DateTime(2026, 11, 11, 10, 0),
          totalSubjects: 5,
          totalTasks: 12,
          totalActivities: 8,
          userName: 'Lê Hoàng Minh',
          weeklyTargetHours: 14.0,
          weeklyTargetTasks: 7,
          themeMode: 'system',
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  return ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: ctx,
                        builder: (_) => RestorePreviewDialog(
                          preview: preview,
                          onConfirmRestore: () {
                            restoreConfirmed = true;
                          },
                        ),
                      );
                    },
                    child: const Text('Mở xem trước'),
                  );
                },
              ),
            ),
          ),
        );

        // Mở dialog xem trước
        await tester.tap(find.text('Mở xem trước'));
        await tester.pumpAndSettle();

        expect(find.text('Xem trước bản sao lưu'), findsOneWidget);
        expect(find.text('5 môn'), findsOneWidget);
        expect(find.text('12 việc'), findsOneWidget);
        expect(find.text('8 lượt'), findsOneWidget);
        expect(find.text('Lê Hoàng Minh'), findsOneWidget);
        expect(find.textContaining('CẢNH BÁO'), findsOneWidget);

        // Bấm nút Hủy
        final cancelBtn = find.widgetWithText(TextButton, 'Hủy');
        await tester.tap(cancelBtn);
        await tester.pumpAndSettle();
        expect(restoreConfirmed, isFalse);

        // Mở lại và bấm Xác nhận khôi phục
        await tester.tap(find.text('Mở xem trước'));
        await tester.pumpAndSettle();

        final confirmBtn = find.byKey(const ValueKey('confirm_restore_button'));
        await tester.tap(confirmBtn);
        await tester.pumpAndSettle();
        expect(restoreConfirmed, isTrue);
      },
    );

    testWidgets('RestoreInputDialog chọn tệp sao lưu qua FilePicker', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      BackupValidationResult? capturedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: ctx,
                      builder: (_) => RestoreInputDialog(
                        backupService: backupService,
                        onValidBackup: (res) {
                          capturedResult = res;
                        },
                      ),
                    );
                  },
                  child: const Text('Mở hộp thoại'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Mở hộp thoại'));
      await tester.pumpAndSettle();

      final pickBtn = find.byKey(const ValueKey('pick_backup_file_button'));
      expect(pickBtn, findsOneWidget);

      // 1. Trường hợp người dùng hủy chọn tệp (trả về null)
      BackupService.testFilePicker = () async => null;
      await tester.tap(pickBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(capturedResult, isNull);
      expect(find.text('Khôi phục dữ liệu'), findsOneWidget);

      // 2. Trường hợp chọn tệp JSON hợp lệ
      final validDataBlock = {
        'profile': const UserProfile(name: 'File Picker User').toMap(),
        'subjects': [
          {
            'id': 'sub_fp_1',
            'name': 'Môn từ tệp',
            'description': 'Mô tả',
            'icon_code': 123,
            'color_value': 456,
          },
        ],
        'tasks': [
          {
            'id': 'task_fp_1',
            'title': 'Việc từ tệp',
            'subject_id': 'sub_fp_1',
            'subject': 'Môn từ tệp',
            'deadline': '',
            'estimated_minutes': 25,
            'priority': 'high',
            'status': 'todo',
          },
        ],
        'activities': <Map<String, dynamic>>[],
      };
      final checksum = BackupService.computeChecksum(
        jsonEncode(validDataBlock),
      );
      final validBackupMap = {
        'app': 'ExamPilot',
        'formatVersion': 1,
        'appVersion': '1.0.0',
        'createdAt': DateTime.now().toIso8601String(),
        'metadata': {'totalSubjects': 1, 'totalTasks': 1, 'totalActivities': 0},
        'data': validDataBlock,
        'checksum': checksum,
      };

      BackupService.testFilePicker = () async => jsonEncode(validBackupMap);
      await tester.tap(pickBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(capturedResult, isNotNull);
      expect(capturedResult!.isValid, isTrue);
      expect(capturedResult!.preview?.userName, equals('File Picker User'));
    });
  });

  group('7. G8.7.1 - Quy trình hoàn chỉnh đa nền tảng (End-to-End)', () {
    testWidgets(
      'Quy trình: Mở hộp thoại -> Chọn tệp -> Xem trước -> Bấm Hủy (Dữ liệu cũ giữ nguyên)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final endToEndTaskRepo = TaskRepository(useWebPreview: true);
        final endToEndSubRepo = SubjectRepository(useWebPreview: true);
        final endToEndProfileRepo = ProfileRepository(useWebPreview: true);
        final endToEndBackupService = BackupService(
          taskRepository: endToEndTaskRepo,
          subjectRepository: endToEndSubRepo,
          profileRepository: endToEndProfileRepo,
        );

        // 1. Dữ liệu ban đầu
        final originalSub = const Subject(
          id: 'orig_sub',
          name: 'Môn gốc ban đầu',
          description: 'Không được mất',
          icon: Icons.bookmark,
          color: Colors.blue,
        );
        await endToEndSubRepo.insertSubject(originalSub);

        final originalTask = StudyTask(
          id: 'orig_task',
          title: 'Việc gốc ban đầu',
          subjectId: 'orig_sub',
          subject: 'Môn gốc ban đầu',
          deadline: DateTime.now(),
          estimatedMinutes: 20,
        );
        await endToEndTaskRepo.insertTask(originalTask);

        // 2. Chuẩn bị tệp sao lưu mới
        final newDate = DateTime(2026, 11, 11, 15, 0);
        final newDataBlock = {
          'profile': const UserProfile(name: 'Người dùng mới').toMap(),
          'subjects': [
            {
              'id': 'new_sub_1',
              'name': 'Môn mới từ tệp',
              'description': 'Mô tả',
              'icon_code': 111,
              'color_value': 222,
            },
          ],
          'tasks': [
            {
              'id': 'new_task_1',
              'title': 'Việc mới từ tệp',
              'subject_id': 'new_sub_1',
              'subject': 'Môn mới từ tệp',
              'deadline': '',
              'estimated_minutes': 40,
              'priority': 'medium',
              'status': 'todo',
            },
          ],
          'activities': <Map<String, dynamic>>[],
        };
        final checksum = BackupService.computeChecksum(
          jsonEncode(newDataBlock),
        );
        final newBackupMap = {
          'app': 'ExamPilot',
          'formatVersion': 1,
          'appVersion': '1.0.0',
          'createdAt': newDate.toIso8601String(),
          'metadata': {
            'totalSubjects': 1,
            'totalTasks': 1,
            'totalActivities': 0,
          },
          'data': newDataBlock,
          'checksum': checksum,
        };

        BackupService.testFilePicker = () async => jsonEncode(newBackupMap);

        // 3. Hiển thị UI và kích hoạt quy trình
        bool restored = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  return ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: ctx,
                        builder: (dialogCtx) => RestoreInputDialog(
                          backupService: endToEndBackupService,
                          onValidBackup: (validationResult) {
                            final preview = validationResult.preview;
                            final bMap = validationResult.backupMap;
                            if (preview == null || bMap == null) return;

                            showDialog(
                              context: ctx,
                              builder: (_) => RestorePreviewDialog(
                                preview: preview,
                                onConfirmRestore: () async {
                                  await endToEndBackupService.restoreBackup(
                                    bMap,
                                  );
                                  restored = true;
                                },
                              ),
                            );
                          },
                        ),
                      );
                    },
                    child: const Text('Bắt đầu khôi phục'),
                  );
                },
              ),
            ),
          ),
        );

        // Mở dialog input
        await tester.tap(find.text('Bắt đầu khôi phục'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Bấm nút Chọn tệp sao lưu
        await tester.tap(find.byKey(const ValueKey('pick_backup_file_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // Màn hình RestorePreviewDialog xuất hiện
        expect(find.text('Xem trước bản sao lưu'), findsOneWidget);
        expect(find.text('Người dùng mới'), findsOneWidget);
        expect(find.text('1 môn'), findsOneWidget);
        expect(find.text('1 việc'), findsOneWidget);

        // Bấm HỦY
        await tester.tap(find.widgetWithText(TextButton, 'Hủy'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(restored, isFalse);

        // Kiểm tra dữ liệu: Phải giữ nguyên dữ liệu gốc, không nạp dữ liệu từ tệp bị hủy
        final subjects = await endToEndSubRepo.getAllSubjects();
        expect(subjects.any((s) => s.id == 'orig_sub'), isTrue);
        expect(subjects.any((s) => s.id == 'new_sub_1'), isFalse);

        final tasks = await endToEndTaskRepo.getAllTasks();
        expect(tasks.any((t) => t.id == 'orig_task'), isTrue);
        expect(
          tasks.firstWhere((t) => t.id == 'orig_task').title,
          equals('Việc gốc ban đầu'),
        );
        expect(tasks.any((t) => t.id == 'new_task_1'), isFalse);
      },
    );

    testWidgets(
      'Quy trình: Mở hộp thoại -> Chọn tệp -> Xem trước -> Xác nhận khôi phục -> CSDL cập nhật chuẩn xác',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1400);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        final endToEndTaskRepo = TaskRepository(useWebPreview: true);
        final endToEndSubRepo = SubjectRepository(useWebPreview: true);
        final endToEndProfileRepo = ProfileRepository(useWebPreview: true);
        final endToEndBackupService = BackupService(
          taskRepository: endToEndTaskRepo,
          subjectRepository: endToEndSubRepo,
          profileRepository: endToEndProfileRepo,
        );

        // 1. Dữ liệu ban đầu
        final originalSub = const Subject(
          id: 'orig_sub',
          name: 'Môn gốc',
          description: 'Mô tả',
          icon: Icons.bookmark,
          color: Colors.blue,
        );
        await endToEndSubRepo.insertSubject(originalSub);

        // 2. Chuẩn bị tệp sao lưu
        final newDataBlock = {
          'profile': const UserProfile(
            name: 'Sinh viên Chuyên cần',
            university: 'Đại học Quốc gia',
          ).toMap(),
          'subjects': [
            {
              'id': 'sub_restore_1',
              'name': 'Môn học mới khôi phục',
              'description': 'Mô tả mới',
              'icon_code': 111,
              'color_value': 222,
            },
          ],
          'tasks': [
            {
              'id': 'task_restore_1',
              'title': 'Công việc mới khôi phục',
              'subject_id': 'sub_restore_1',
              'subject': 'Môn học mới khôi phục',
              'deadline': '',
              'estimated_minutes': 50,
              'priority': 'high',
              'status': 'completed',
            },
          ],
          'activities': <Map<String, dynamic>>[],
        };
        final checksum = BackupService.computeChecksum(
          jsonEncode(newDataBlock),
        );
        final newBackupMap = {
          'app': 'ExamPilot',
          'formatVersion': 1,
          'appVersion': '1.0.0',
          'createdAt': DateTime.now().toIso8601String(),
          'metadata': {
            'totalSubjects': 1,
            'totalTasks': 1,
            'totalActivities': 0,
          },
          'data': newDataBlock,
          'checksum': checksum,
        };

        BackupService.testFilePicker = () async => jsonEncode(newBackupMap);

        bool restored = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) {
                  return ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: ctx,
                        builder: (dialogCtx) => RestoreInputDialog(
                          backupService: endToEndBackupService,
                          onValidBackup: (validationResult) {
                            final preview = validationResult.preview;
                            final bMap = validationResult.backupMap;
                            if (preview == null || bMap == null) return;

                            showDialog(
                              context: ctx,
                              builder: (_) => RestorePreviewDialog(
                                preview: preview,
                                onConfirmRestore: () async {
                                  await endToEndBackupService.restoreBackup(
                                    bMap,
                                  );
                                  restored = true;
                                },
                              ),
                            );
                          },
                        ),
                      );
                    },
                    child: const Text('Khôi phục'),
                  );
                },
              ),
            ),
          ),
        );

        await tester.tap(find.text('Khôi phục'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        await tester.tap(find.byKey(const ValueKey('pick_backup_file_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text('Xem trước bản sao lưu'), findsOneWidget);

        // Bấm XÁC NHẬN KHÔI PHỤC
        await tester.tap(find.byKey(const ValueKey('confirm_restore_button')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(restored, isTrue);

        // Xác minh dữ liệu đã thay thế hoàn toàn
        final subjects = await endToEndSubRepo.getAllSubjects();
        expect(subjects.length, equals(1));
        expect(subjects.first.name, equals('Môn học mới khôi phục'));

        final tasks = await endToEndTaskRepo.getAllTasks();
        expect(tasks.length, equals(1));
        expect(tasks.first.title, equals('Công việc mới khôi phục'));
        expect(tasks.first.subjectId, equals('sub_restore_1'));

        final profile = await endToEndProfileRepo.getProfile();
        expect(profile.name, equals('Sinh viên Chuyên cần'));
        expect(profile.university, equals('Đại học Quốc gia'));
      },
    );

    test(
      'Quy trình chọn tệp và khôi phục SQLite thực tế bảo toàn ACID',
      () async {
        // 1. Dữ liệu ban đầu
        final originalSub = const Subject(
          id: 'orig_sub_sql',
          name: 'Môn SQLite gốc',
          description: 'Không được mất nếu lỗi',
          icon: Icons.bookmark,
          color: Colors.blue,
        );
        await subjectRepo.insertSubject(originalSub);

        // 2. Giả lập chọn tệp qua BackupService
        final newDataBlock = {
          'profile': const UserProfile(
            name: 'Sinh viên SQLite G8',
            university: 'Bách Khoa',
          ).toMap(),
          'subjects': [
            {
              'id': 'sub_sql_restored',
              'name': 'Môn SQLite Khôi Phục',
              'description': 'Mô tả',
              'icon_code': 123,
              'color_value': 456,
            },
          ],
          'tasks': [
            {
              'id': 'task_sql_restored',
              'title': 'Task SQLite Khôi Phục',
              'subject_id': 'sub_sql_restored',
              'subject': 'Môn SQLite Khôi Phục',
              'deadline': '',
              'estimated_minutes': 45,
              'priority': 'high',
              'status': 'completed',
            },
          ],
          'activities': <Map<String, dynamic>>[],
        };
        final checksum = BackupService.computeChecksum(
          jsonEncode(newDataBlock),
        );
        final backupMap = {
          'app': 'ExamPilot',
          'formatVersion': 1,
          'appVersion': '1.0.0',
          'createdAt': DateTime.now().toIso8601String(),
          'metadata': {
            'totalSubjects': 1,
            'totalTasks': 1,
            'totalActivities': 0,
          },
          'data': newDataBlock,
          'checksum': checksum,
        };

        BackupService.testFilePicker = () async => jsonEncode(backupMap);

        // 3. Đọc từ file picker
        final fileContent = await backupService.pickAndReadBackupFile();
        expect(fileContent, isNotNull);

        // 4. Validate
        final valResult = backupService.validateBackupJson(fileContent!);
        expect(valResult.isValid, isTrue);

        // 5. Restore vào SQLite
        await backupService.restoreBackup(valResult.backupMap!);

        // 6. Kiểm tra CSDL SQLite đã được thay thế hoàn toàn
        final subjects = await subjectRepo.getAllSubjects();
        expect(subjects.length, equals(1));
        expect(subjects.first.name, equals('Môn SQLite Khôi Phục'));

        final tasks = await taskRepo.getAllTasks();
        expect(tasks.length, equals(1));
        expect(tasks.first.title, equals('Task SQLite Khôi Phục'));

        final profile = await profileRepo.getProfile();
        expect(profile.name, equals('Sinh viên SQLite G8'));
        expect(profile.university, equals('Bách Khoa'));
      },
    );
  });
}

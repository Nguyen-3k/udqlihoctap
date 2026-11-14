import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/study_session.dart';
import 'package:exampilot/models/study_streak.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/models/user_profile.dart';
import 'package:exampilot/repositories/profile_repository.dart';
import 'package:exampilot/repositories/session_repository.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/screens/overview_screen.dart';
import 'package:exampilot/services/session_storage.dart';
import 'package:exampilot/services/web_storage.dart';
import 'package:exampilot/widgets/weekly_goal_summary_card.dart';

Future<void> _seedAuthenticV6Database(Database db) async {
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

  await db.insert(DatabaseHelper.tableSubjects, {
    DatabaseHelper.columnSubjectId: 'subj_v6_math',
    DatabaseHelper.columnSubjectName: 'Giải tích 1',
    DatabaseHelper.columnSubjectDescription: 'Giới hạn và tích phân',
    DatabaseHelper.columnSubjectIcon: Icons.calculate_rounded.codePoint,
    DatabaseHelper.columnSubjectColor: 0xFF3B5BDB,
  });

  await db.insert(DatabaseHelper.tableTasks, {
    DatabaseHelper.columnId: 'task_v6_1',
    DatabaseHelper.columnTitle: 'Làm đề cương chương 2',
    DatabaseHelper.columnTaskSubjectId: 'subj_v6_math',
    DatabaseHelper.columnSubject: 'Giải tích 1',
    DatabaseHelper.columnDeadline: '2026-11-12T17:00:00.000',
    DatabaseHelper.columnEstimatedMinutes: 60,
    DatabaseHelper.columnActualMinutes: 45,
    DatabaseHelper.columnPriority: 'high',
    DatabaseHelper.columnStatus: 'completed',
    DatabaseHelper.columnNotes: 'Ôn công thức tích phân',
    DatabaseHelper.columnUnderstandingLevel: 'mastered',
    DatabaseHelper.columnReviewNotes: 'Đã nắm chắc dạng bài cơ bản',
  });

  await db.insert(DatabaseHelper.tableActivities, {
    DatabaseHelper.columnActivityId: 'act_v6_1',
    DatabaseHelper.columnActivityDate: '2026-11-10',
    DatabaseHelper.columnActivityTaskId: 'task_v6_1',
    DatabaseHelper.columnActivityCompletedAt: '2026-11-10T14:20:00.000',
    DatabaseHelper.columnActivityActualMinutes: 45,
    DatabaseHelper.columnActivitySubjectId: 'subj_v6_math',
  });

  await db.insert(DatabaseHelper.tableProfile, {
    DatabaseHelper.columnProfileId: UserProfile.defaultId,
    DatabaseHelper.columnProfileName: 'Minh Anh',
    DatabaseHelper.columnProfileUniversity: 'ĐH Bách Khoa',
    DatabaseHelper.columnProfileMajor: 'Khoa học Máy tính',
    DatabaseHelper.columnProfileAcademicYear: 'Năm 3',
    DatabaseHelper.columnProfileAvatarId: 'rocket',
    DatabaseHelper.columnProfileTargetHours: 14.5,
    DatabaseHelper.columnProfileTargetTasks: 8,
    DatabaseHelper.columnProfileThemeMode: 'dark',
    DatabaseHelper.columnProfileReminderEnabled: 1,
  });
}

Future<Database> _openFreshV7Database(String dbPath) async {
  return databaseFactoryFfi.openDatabase(
    dbPath,
    options: OpenDatabaseOptions(
      version: DatabaseHelper.databaseVersion,
      onConfigure: DatabaseHelper.configureDatabase,
      onCreate: (db, version) async {
        await DatabaseHelper.instance.createForTesting(db, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await DatabaseHelper.instance.upgradeForTesting(
          db,
          oldVersion,
          newVersion,
        );
      },
    ),
  );
}

StudySession _buildSession({
  required String id,
  String? subjectId = 'subj_1',
  String subjectNameSnapshot = 'Cơ sở dữ liệu',
  int? subjectColorSnapshot = 0xFF3B5BDB,
  String? taskId = 'task_1',
  String? taskTitleSnapshot = 'Ôn tập SQL',
  String? scheduledSessionId,
  DateTime? startedAt,
  DateTime? endedAt,
  String studyDate = '2026-11-11',
  int verifiedStudySeconds = 1800,
  int accumulatedBreakSeconds = 300,
  StudySessionStatus status = StudySessionStatus.completed,
  StudySessionMode sessionMode = StudySessionMode.pomodoro25_5,
  int plannedStudyMinutes = 25,
  int plannedBreakMinutes = 5,
  String notes = '',
}) {
  final startUtc = (startedAt ?? DateTime.utc(2026, 11, 11, 8, 0)).toUtc();
  final resolvedEndedAt =
      status == StudySessionStatus.completed ||
          status == StudySessionStatus.cancelled
      ? (endedAt ?? startUtc.add(Duration(seconds: verifiedStudySeconds)))
            .toUtc()
      : endedAt?.toUtc();
  return StudySession(
    id: id,
    subjectId: subjectId,
    subjectNameSnapshot: subjectNameSnapshot,
    subjectColorSnapshot: subjectColorSnapshot,
    taskId: taskId,
    taskTitleSnapshot: taskTitleSnapshot,
    scheduledSessionId: scheduledSessionId,
    startedAt: startUtc,
    endedAt: resolvedEndedAt,
    lastHeartbeatAt: startUtc.add(const Duration(seconds: 60)),
    lastStateChangedAt: startUtc,
    studyDate: studyDate,
    verifiedStudySeconds: verifiedStudySeconds,
    accumulatedBreakSeconds: accumulatedBreakSeconds,
    status: status,
    sessionMode: sessionMode,
    plannedStudyMinutes: plannedStudyMinutes,
    plannedBreakMinutes: plannedBreakMinutes,
    notes: notes,
  );
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  Database? openTestDb;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('exampilot_phase1_');
    WebSessionStorage.resetAllSimulatedStorageForTesting();
    WebStreakStorage.clearProfile();
    WebStreakStorage.clearStudyActivitiesAndDates();
    DatabaseHelper.instance.setDatabaseForTesting(null);
  });

  tearDown(() async {
    DatabaseHelper.instance.setDatabaseForTesting(null);
    if (openTestDb != null && openTestDb!.isOpen) {
      await openTestDb!.close();
    }
    openTestDb = null;
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('Group A - Migration v6 -> v7 & Foreign Keys', () {
    test(
      '1. Database v6 nâng cấp thành công lên v7 với bảng và index đầy đủ',
      () async {
        final dbPath = p.join(tempDir.path, 'mig_upgrade.db');

        final v6Db = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 6,
            onCreate: (db, _) async => _seedAuthenticV6Database(db),
          ),
        );
        await v6Db.close();

        openTestDb = await _openFreshV7Database(dbPath);
        final userVersion = Sqflite.firstIntValue(
          await openTestDb!.rawQuery('PRAGMA user_version'),
        );
        expect(userVersion, greaterThanOrEqualTo(7));

        final tables = await openTestDb!.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [DatabaseHelper.tableSessions],
        );
        expect(tables, hasLength(1));

        final indexes = await openTestDb!.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name=?",
          [DatabaseHelper.tableSessions],
        );
        final indexNames = indexes.map((r) => r['name']).toSet();
        expect(
          indexNames,
          containsAll([
            'idx_sessions_status',
            'idx_sessions_study_date',
            'idx_sessions_subject_id',
            'idx_sessions_task_id',
            'idx_sessions_started_at',
          ]),
        );
      },
    );

    test(
      '2. Toàn bộ subjects, tasks, activities và profile cũ còn nguyên; không tạo session giả',
      () async {
        final dbPath = p.join(tempDir.path, 'mig_preserve.db');

        final v6Db = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 6,
            onCreate: (db, _) async => _seedAuthenticV6Database(db),
          ),
        );
        await v6Db.close();

        openTestDb = await _openFreshV7Database(dbPath);

        final subjects = await openTestDb!.query(DatabaseHelper.tableSubjects);
        expect(subjects, hasLength(1));
        expect(subjects.first['name'], 'Giải tích 1');

        final tasks = await openTestDb!.query(DatabaseHelper.tableTasks);
        expect(tasks, hasLength(1));
        expect(tasks.first['title'], 'Làm đề cương chương 2');
        expect(tasks.first['actual_minutes'], 45);
        expect(tasks.first['understanding_level'], 'mastered');

        final activities = await openTestDb!.query(
          DatabaseHelper.tableActivities,
        );
        expect(activities, hasLength(1));
        expect(activities.first['id'], 'act_v6_1');
        expect(activities.first['actual_minutes'], 45);

        final sessions = await openTestDb!.query(DatabaseHelper.tableSessions);
        expect(sessions, isEmpty);

        DatabaseHelper.instance.setDatabaseForTesting(openTestDb);
        final loadedProfile = await ProfileRepository().getProfile();
        expect(loadedProfile.name, 'Minh Anh');
        expect(loadedProfile.university, 'ĐH Bách Khoa');
        expect(loadedProfile.weeklyTargetHours, 14.5);
        expect(loadedProfile.weeklyTargetTasks, 8);
        expect(loadedProfile.themeMode, 'dark');
        expect(loadedProfile.reminderEnabled, isTrue);
      },
    );

    test(
      '3. Giá trị mặc định profile mới được tạo chính xác và đồng nhất với model',
      () async {
        final dbPath = p.join(tempDir.path, 'mig_defaults.db');

        final v6Db = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 6,
            onCreate: (db, _) async => _seedAuthenticV6Database(db),
          ),
        );
        await v6Db.close();

        openTestDb = await _openFreshV7Database(dbPath);
        DatabaseHelper.instance.setDatabaseForTesting(openTestDb);

        final profile = await ProfileRepository().getProfile();
        const defaults = UserProfile();

        expect(profile.alarmSoundId, defaults.alarmSoundId);
        expect(profile.breakSoundId, defaults.breakSoundId);
        expect(profile.preReminderMinutes, defaults.preReminderMinutes);
        expect(profile.breakPresetId, defaults.breakPresetId);
        expect(profile.customStudyMinutes, defaults.customStudyMinutes);
        expect(profile.customBreakMinutes, defaults.customBreakMinutes);
        expect(profile.autoBreakReminder, isTrue);
        expect(profile.notifyPreStudy, isTrue);
        expect(profile.notifyAlarmOnTime, isTrue);
        expect(profile.notifySessionStart, isTrue);
        expect(profile.notifyBreakStart, isTrue);
        expect(profile.notifyBreakEnd, isTrue);
        expect(profile.dailyStudyLimitMinutes, 240);
      },
    );

    test(
      '4. Mở lại database không chạy migration lặp và upgrade là idempotent',
      () async {
        final dbPath = p.join(tempDir.path, 'mig_reopen.db');

        final v6Db = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 6,
            onCreate: (db, _) async => _seedAuthenticV6Database(db),
          ),
        );
        await v6Db.close();

        var upgradeCalls = 0;
        final firstV7 = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 7,
            onConfigure: DatabaseHelper.configureDatabase,
            onUpgrade: (db, oldV, newV) async {
              upgradeCalls++;
              await DatabaseHelper.instance.upgradeForTesting(db, oldV, newV);
            },
          ),
        );
        expect(upgradeCalls, 1);
        await firstV7.close();

        openTestDb = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 7,
            onConfigure: DatabaseHelper.configureDatabase,
            onUpgrade: (db, oldV, newV) async {
              upgradeCalls++;
              await DatabaseHelper.instance.upgradeForTesting(db, oldV, newV);
            },
          ),
        );
        expect(upgradeCalls, 1);

        // Chạy trực tiếp upgradeForTesting lần nữa cũng không được lỗi trùng cột.
        await DatabaseHelper.instance.upgradeForTesting(openTestDb!, 6, 7);
        final cols = await openTestDb!.rawQuery(
          'PRAGMA table_info(${DatabaseHelper.tableProfile})',
        );
        expect(
          cols.map((c) => c['name']).toSet(),
          containsAll(DatabaseHelper.profileV7ColumnDefs.keys),
        );
      },
    );

    test(
      '5. Migration lỗi không để database ở trạng thái nửa nâng cấp (rollback toàn phần)',
      () async {
        final dbPath = p.join(tempDir.path, 'mig_rollback.db');

        final v6Db = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(
            version: 6,
            onCreate: (db, _) async => _seedAuthenticV6Database(db),
          ),
        );
        await v6Db.close();

        await expectLater(
          databaseFactoryFfi.openDatabase(
            dbPath,
            options: OpenDatabaseOptions(
              version: 7,
              onConfigure: DatabaseHelper.configureDatabase,
              onUpgrade: (db, oldV, newV) async {
                await DatabaseHelper.instance.upgradeForTesting(db, oldV, newV);
                throw StateError('Simulated migration crash');
              },
            ),
          ),
          throwsStateError,
        );

        // Kiểm tra database vẫn nguyên ở v6, không có bảng study_sessions hay cột nửa vời.
        final checkDb = await databaseFactoryFfi.openDatabase(
          dbPath,
          options: OpenDatabaseOptions(version: 6),
        );
        final versionAfterFail = Sqflite.firstIntValue(
          await checkDb.rawQuery('PRAGMA user_version'),
        );
        expect(versionAfterFail, 6);

        final sessionsTable = await checkDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [DatabaseHelper.tableSessions],
        );
        expect(sessionsTable, isEmpty);

        final profileCols = await checkDb.rawQuery(
          'PRAGMA table_info(${DatabaseHelper.tableProfile})',
        );
        expect(
          profileCols
              .map((c) => c['name'])
              .contains('daily_study_limit_minutes'),
          isFalse,
        );
        expect(await checkDb.query(DatabaseHelper.tableTasks), hasLength(1));
        await checkDb.close();

        // Nâng cấp lại bình thường vẫn thành công sạch sẽ.
        openTestDb = await _openFreshV7Database(dbPath);
        final recoveredVersion = Sqflite.firstIntValue(
          await openTestDb!.rawQuery('PRAGMA user_version'),
        );
        expect(recoveredVersion, greaterThanOrEqualTo(7));
      },
    );

    test('6. Kiểm tra PRAGMA foreign_keys thực sự được bật', () async {
      final dbPath = p.join(tempDir.path, 'fk_check.db');
      openTestDb = await _openFreshV7Database(dbPath);

      final fkRows = await openTestDb!.rawQuery('PRAGMA foreign_keys');
      expect(fkRows.single.values.first, 1);

      DatabaseHelper.instance.setDatabaseForTesting(openTestDb);
      final sessionRepo = SessionRepository(dbHelper: DatabaseHelper.instance);

      await expectLater(
        sessionRepo.createSession(
          _buildSession(id: 'sess_bad_fk', subjectId: 'missing_subject'),
        ),
        throwsException,
      );
    });

    test(
      '7. Xóa subject không xóa session lịch sử; subject_id thành NULL và giữ nguyên snapshot',
      () async {
        final dbPath = p.join(tempDir.path, 'fk_delete_subject.db');
        openTestDb = await _openFreshV7Database(dbPath);
        DatabaseHelper.instance.setDatabaseForTesting(openTestDb);

        final subjectRepo = SubjectRepository(
          dbHelper: DatabaseHelper.instance,
        );
        final sessionRepo = SessionRepository(
          dbHelper: DatabaseHelper.instance,
        );

        await subjectRepo.insertSubject(
          const Subject(
            id: 'subj_phy',
            name: 'Vật lý đại cương',
            description: 'Cơ nhiệt điện',
          ),
        );
        await sessionRepo.createSession(
          _buildSession(
            id: 'sess_phy_1',
            subjectId: 'subj_phy',
            subjectNameSnapshot: 'Vật lý đại cương',
            taskId: null,
            taskTitleSnapshot: null,
            verifiedStudySeconds: 2100,
          ),
        );

        await subjectRepo.updateSubject(
          const Subject(
            id: 'subj_phy',
            name: 'Vật lý đại cương (Đã đổi tên)',
            description: 'Cơ nhiệt điện',
          ),
        );
        final afterRename = await sessionRepo.getSessionById('sess_phy_1');
        expect(afterRename!.subjectNameSnapshot, 'Vật lý đại cương');

        await subjectRepo.deleteSubject('subj_phy');

        final persisted = await sessionRepo.getSessionById('sess_phy_1');
        expect(persisted, isNotNull);
        expect(persisted!.subjectId, isNull);
        expect(persisted.subjectNameSnapshot, 'Vật lý đại cương');
        expect(persisted.verifiedStudySeconds, 2100);
      },
    );

    test(
      '8. Xóa task không xóa session lịch sử; task_id thành NULL và giữ nguyên snapshot',
      () async {
        final dbPath = p.join(tempDir.path, 'fk_delete_task.db');
        openTestDb = await _openFreshV7Database(dbPath);
        DatabaseHelper.instance.setDatabaseForTesting(openTestDb);

        final subjectRepo = SubjectRepository(
          dbHelper: DatabaseHelper.instance,
        );
        final taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);
        final sessionRepo = SessionRepository(
          dbHelper: DatabaseHelper.instance,
        );

        await subjectRepo.insertSubject(
          const Subject(
            id: 'subj_eng',
            name: 'Tiếng Anh',
            description: 'IELTS',
          ),
        );
        await taskRepo.insertTask(
          StudyTask(
            id: 'task_eng_1',
            title: 'Luyện Reading Passage 3',
            subjectId: 'subj_eng',
            subject: 'Tiếng Anh',
            deadline: DateTime(2026, 11, 20),
          ),
        );
        await sessionRepo.createSession(
          _buildSession(
            id: 'sess_eng_1',
            subjectId: 'subj_eng',
            subjectNameSnapshot: 'Tiếng Anh',
            taskId: 'task_eng_1',
            taskTitleSnapshot: 'Luyện Reading Passage 3',
            verifiedStudySeconds: 1500,
          ),
        );

        await taskRepo.deleteTask('task_eng_1');

        final persisted = await sessionRepo.getSessionById('sess_eng_1');
        expect(persisted, isNotNull);
        expect(persisted!.taskId, isNull);
        expect(persisted.subjectId, 'subj_eng');
        expect(persisted.taskTitleSnapshot, 'Luyện Reading Passage 3');
        expect(persisted.subjectNameSnapshot, 'Tiếng Anh');
      },
    );
  });

  group('Group B - Model (StudySession & UserProfile v7)', () {
    test(
      '1. Serialize và deserialize đầy đủ StudySession qua toMap / fromMap',
      () {
        final original = _buildSession(
          id: 'sess_full',
          subjectId: 'subj_cs',
          subjectNameSnapshot: 'Hệ điều hành',
          subjectColorSnapshot: 0xFF1E88E5,
          taskId: 'task_os_1',
          taskTitleSnapshot: 'Ôn thuật toán lập lịch CPU',
          scheduledSessionId: 'sched_99',
          startedAt: DateTime.utc(2026, 11, 11, 13, 0, 5),
          endedAt: DateTime.utc(2026, 11, 11, 13, 55, 5),
          studyDate: '2026-11-11',
          verifiedStudySeconds: 3000,
          accumulatedBreakSeconds: 300,
          status: StudySessionStatus.completed,
          sessionMode: StudySessionMode.deep50_10,
          plannedStudyMinutes: 50,
          plannedBreakMinutes: 10,
          notes: 'Hiểu rõ Round Robin',
        );

        final map = original.toMap();
        final decoded = StudySession.fromMap(map);
        expect(decoded, original);
        expect(decoded.scheduledSessionId, 'sched_99');
        expect(decoded.sessionMode, StudySessionMode.deep50_10);
        expect(decoded.notes, 'Hiểu rõ Round Robin');
      },
    );

    test('2. Xử lý chuẩn xác các trường nullable trong StudySession', () {
      final runningSession = _buildSession(
        id: 'sess_nullable',
        subjectId: null,
        subjectNameSnapshot: 'Toán rời rạc',
        subjectColorSnapshot: null,
        taskId: null,
        taskTitleSnapshot: null,
        scheduledSessionId: null,
        endedAt: null,
        status: StudySessionStatus.running,
        verifiedStudySeconds: 120,
      );

      final decoded = StudySession.fromMap({
        ...runningSession.toMap(),
        'subject_id': '',
        'task_id': '',
      });
      expect(decoded.subjectId, isNull);
      expect(decoded.subjectColorSnapshot, isNull);
      expect(decoded.taskId, isNull);
      expect(decoded.taskTitleSnapshot, isNull);
      expect(decoded.scheduledSessionId, isNull);
      expect(decoded.endedAt, isNull);
    });

    test('3. Chuẩn hóa và ép buộc UTC timestamps chuẩn ISO-8601 (Z)', () {
      final localStart = DateTime(2026, 11, 11, 21, 15, 0);
      final session = StudySession.createNew(
        id: 'sess_utc',
        subjectId: 'subj_1',
        subjectNameSnapshot: 'Mạng máy tính',
        startedAt: localStart,
      );

      expect(session.startedAt.isUtc, isTrue);
      expect(session.lastHeartbeatAt.isUtc, isTrue);
      expect(session.lastStateChangedAt.isUtc, isTrue);

      final serialized = session.toMap();
      expect((serialized['started_at'] as String).endsWith('Z'), isTrue);
      expect((serialized['last_heartbeat_at'] as String).endsWith('Z'), isTrue);

      // Reject bare timestamp string without timezone suffix (Z or +/-HH:MM)
      expect(
        () => StudySession.fromMap({
          ...serialized,
          'started_at': '2026-11-11T21:15:00.000',
        }),
        throwsFormatException,
      );
    });

    test(
      '4. study_date giữ nguyên ngày lịch địa phương đã đóng dấu, không suy ra lại từ UTC',
      () {
        // Ví dụ người dùng ở UTC+7 bắt đầu học lúc 01:30 sáng ngày 2026-11-11
        // nhưng trên UTC vẫn là 18:30 ngày 2026-11-10.
        final session = StudySession(
          id: 'sess_date_anchor',
          subjectId: null,
          subjectNameSnapshot: 'Tư duy thiết kế',
          startedAt: DateTime.utc(2026, 11, 10, 18, 30),
          endedAt: DateTime.utc(2026, 11, 10, 19, 15),
          lastHeartbeatAt: DateTime.utc(2026, 11, 10, 19, 15),
          lastStateChangedAt: DateTime.utc(2026, 11, 10, 18, 30),
          studyDate: '2026-11-11',
          verifiedStudySeconds: 2700,
          status: StudySessionStatus.completed,
        );

        final roundTripped = StudySession.fromMap(session.toMap());
        expect(roundTripped.studyDate, '2026-11-11');

        expect(
          () => _buildSession(id: 'bad_date', studyDate: '2026-02-30'),
          throwsArgumentError,
        );
      },
    );

    test(
      '5. Từ chối status không hợp lệ hoặc mâu thuẫn trạng thái/endedAt',
      () {
        final validMap = _buildSession(
          id: 'sess_status',
          status: StudySessionStatus.completed,
        ).toMap();

        expect(
          () => StudySession.fromMap({...validMap, 'status': 'unknown_state'}),
          throwsArgumentError,
        );
        expect(
          () => StudySession.fromMap({...validMap, 'status': ''}),
          throwsArgumentError,
        );
        expect(
          () => _buildSession(
            id: 'bad_running_end',
            status: StudySessionStatus.running,
            endedAt: DateTime.utc(2026, 11, 11, 9, 0),
          ),
          throwsArgumentError,
        );
        expect(
          () => StudySession(
            id: 'bad_completed_no_end',
            subjectNameSnapshot: 'Toán',
            startedAt: DateTime.utc(2026, 11, 11, 8, 0),
            endedAt: null,
            lastHeartbeatAt: DateTime.utc(2026, 11, 11, 8, 0),
            lastStateChangedAt: DateTime.utc(2026, 11, 11, 8, 0),
            studyDate: '2026-11-11',
            verifiedStudySeconds: 900,
            status: StudySessionStatus.completed,
          ),
          throwsArgumentError,
        );
      },
    );

    test('6. Không chấp nhận thời lượng âm ở model và fromMap', () {
      expect(
        () => _buildSession(id: 'neg_study', verifiedStudySeconds: -1),
        throwsArgumentError,
      );
      expect(
        () => _buildSession(id: 'neg_break', accumulatedBreakSeconds: -10),
        throwsArgumentError,
      );
      expect(
        () => _buildSession(id: 'neg_planned', plannedStudyMinutes: -5),
        throwsArgumentError,
      );

      final validMap = _buildSession(id: 'neg_from_map').toMap();
      expect(
        () =>
            StudySession.fromMap({...validMap, 'verified_study_seconds': -60}),
        throwsArgumentError,
      );
    });

    test(
      '7. UserProfile v7 round-trip, đọc lại dữ liệu v6 an toàn và validate()',
      () async {
        const fullProfile = UserProfile(
          name: 'Bảo Ngọc',
          alarmSoundId: 'alarm_school_bell',
          breakSoundId: 'break_marimba',
          preReminderMinutes: 15,
          breakPresetId: 'deep_50_10',
          customStudyMinutes: 45,
          customBreakMinutes: 8,
          autoBreakReminder: false,
          notifyPreStudy: false,
          notifyAlarmOnTime: true,
          notifySessionStart: false,
          notifyBreakStart: true,
          notifyBreakEnd: false,
          dailyStudyLimitMinutes: 300,
        );

        fullProfile.validate();
        final decodedFull = UserProfile.fromMap(fullProfile.toMap());
        expect(decodedFull.alarmSoundId, 'alarm_school_bell');
        expect(decodedFull.breakSoundId, 'break_marimba');
        expect(decodedFull.preReminderMinutes, 15);
        expect(decodedFull.breakPresetId, 'deep_50_10');
        expect(decodedFull.customStudyMinutes, 45);
        expect(decodedFull.customBreakMinutes, 8);
        expect(decodedFull.autoBreakReminder, isFalse);
        expect(decodedFull.notifyPreStudy, isFalse);
        expect(decodedFull.notifySessionStart, isFalse);
        expect(decodedFull.notifyBreakEnd, isFalse);
        expect(decodedFull.dailyStudyLimitMinutes, 300);

        // Tương thích ngược với map v6 thiếu 13 cột mới
        final legacyV6Map = <String, dynamic>{
          'id': UserProfile.defaultId,
          'name': 'Sinh viên v6',
          'weekly_target_hours': 12.0,
          'weekly_target_tasks': 6,
          'theme_mode': 'light',
          'reminder_enabled': 1,
        };
        final decodedV6 = UserProfile.fromMap(legacyV6Map);
        expect(decodedV6.dailyStudyLimitMinutes, 240);
        expect(decodedV6.alarmSoundId, UserProfile.defaultAlarmSoundId);
        expect(decodedV6.breakPresetId, UserProfile.defaultBreakPresetId);

        expect(
          () => const UserProfile(dailyStudyLimitMinutes: 10).validate(),
          throwsArgumentError,
        );
        expect(
          () => const UserProfile(alarmSoundId: 'invalid_sound').validate(),
          throwsArgumentError,
        );
        expect(
          () => const UserProfile(customStudyMinutes: 0).validate(),
          throwsArgumentError,
        );
      },
    );
  });

  group('Group C - SessionRepository (SQLite)', () {
    late SessionRepository sessionRepo;
    late SubjectRepository subjectRepo;
    late TaskRepository taskRepo;

    setUp(() async {
      final dbPath = p.join(tempDir.path, 'session_repo.db');
      openTestDb = await _openFreshV7Database(dbPath);
      DatabaseHelper.instance.setDatabaseForTesting(openTestDb);

      subjectRepo = SubjectRepository(dbHelper: DatabaseHelper.instance);
      taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);
      sessionRepo = SessionRepository(dbHelper: DatabaseHelper.instance);

      await subjectRepo.insertSubject(
        const Subject(id: 'subj_1', name: 'Môn 1', description: 'Mô tả 1'),
      );
      await subjectRepo.insertSubject(
        const Subject(id: 'subj_2', name: 'Môn 2', description: 'Mô tả 2'),
      );
      await taskRepo.insertTask(
        StudyTask(
          id: 'task_1',
          title: 'Task 1',
          subjectId: 'subj_1',
          subject: 'Môn 1',
          actualMinutes: 20,
        ),
      );
    });

    test('1. CRUD cơ bản và chặn trùng ID', () async {
      final created = _buildSession(
        id: 'sess_crud_1',
        status: StudySessionStatus.running,
        verifiedStudySeconds: 300,
      );
      await sessionRepo.createSession(created);

      await expectLater(sessionRepo.createSession(created), throwsException);

      final loaded = await sessionRepo.getSessionById('sess_crud_1');
      expect(loaded, created);

      final updated = created.copyWith(
        status: StudySessionStatus.completed,
        verifiedStudySeconds: 1800,
        endedAt: DateTime.utc(2026, 11, 11, 8, 30),
        notes: 'Hoàn thành tốt',
      );
      await sessionRepo.updateSession(updated);

      final reloaded = await sessionRepo.getSessionById('sess_crud_1');
      expect(reloaded!.status, StudySessionStatus.completed);
      expect(reloaded.verifiedStudySeconds, 1800);
      expect(reloaded.notes, 'Hoàn thành tốt');

      await sessionRepo.deleteSession('sess_crud_1');
      expect(await sessionRepo.getSessionById('sess_crud_1'), isNull);
    });

    test('2. Query theo subject và theo task chính xác', () async {
      await sessionRepo.createSession(
        _buildSession(id: 's1', subjectId: 'subj_1', taskId: 'task_1'),
      );
      await sessionRepo.createSession(
        _buildSession(
          id: 's2',
          subjectId: 'subj_2',
          subjectNameSnapshot: 'Môn 2',
          taskId: null,
          taskTitleSnapshot: null,
          status: StudySessionStatus.cancelled,
        ),
      );

      final bySubj1 = await sessionRepo.getSessionsBySubject('subj_1');
      expect(bySubj1.map((s) => s.id), ['s1']);

      final bySubj2Completed = await sessionRepo.getSessionsBySubject(
        'subj_2',
        status: StudySessionStatus.completed,
      );
      expect(bySubj2Completed, isEmpty);

      final byTask1 = await sessionRepo.getSessionsByTask('task_1');
      expect(byTask1.map((s) => s.id), ['s1']);
    });

    test(
      '3. Query theo khoảng ngày bao gồm hai đầu mút và sắp xếp ổn định',
      () async {
        await sessionRepo.createSession(
          _buildSession(
            id: 'd_out_before',
            studyDate: '2026-11-08',
            startedAt: DateTime.utc(2026, 11, 8, 10),
          ),
        );
        await sessionRepo.createSession(
          _buildSession(
            id: 'd_start',
            studyDate: '2026-11-09',
            startedAt: DateTime.utc(2026, 11, 9, 9),
          ),
        );
        await sessionRepo.createSession(
          _buildSession(
            id: 'd_mid_b',
            studyDate: '2026-11-11',
            startedAt: DateTime.utc(2026, 11, 11, 8),
          ),
        );
        await sessionRepo.createSession(
          _buildSession(
            id: 'd_mid_a',
            studyDate: '2026-11-11',
            startedAt: DateTime.utc(2026, 11, 11, 8),
          ),
        );
        await sessionRepo.createSession(
          _buildSession(
            id: 'd_end',
            studyDate: '2026-11-15',
            startedAt: DateTime.utc(2026, 11, 15, 20),
          ),
        );

        final range = await sessionRepo.getSessionsByDateRange(
          '2026-11-09',
          '2026-11-15',
        );
        expect(range.map((s) => s.id).toList(), [
          'd_end',
          'd_mid_a',
          'd_mid_b',
          'd_start',
        ]);
      },
    );

    test('4. Query session đang hoạt động và chờ Recovery', () async {
      await sessionRepo.createSession(
        _buildSession(id: 'st_run', status: StudySessionStatus.running),
      );
      await sessionRepo.createSession(
        _buildSession(id: 'st_pause', status: StudySessionStatus.paused),
      );
      await sessionRepo.createSession(
        _buildSession(id: 'st_break', status: StudySessionStatus.inBreak),
      );
      await sessionRepo.createSession(
        _buildSession(
          id: 'st_pending',
          status: StudySessionStatus.interruptedPending,
        ),
      );
      await sessionRepo.createSession(
        _buildSession(id: 'st_done', status: StudySessionStatus.completed),
      );
      await sessionRepo.createSession(
        _buildSession(id: 'st_cancel', status: StudySessionStatus.cancelled),
      );

      final active = await sessionRepo.getActiveOrPendingSessions();
      expect(active.map((s) => s.id).toSet(), {
        'st_run',
        'st_pause',
        'st_break',
        'st_pending',
      });
    });

    test(
      '5. Không tự thay đổi actual_minutes của task hay tạo study_activities',
      () async {
        await sessionRepo.createSession(
          _buildSession(
            id: 'sess_isolated',
            subjectId: 'subj_1',
            taskId: 'task_1',
            verifiedStudySeconds: 3600,
            status: StudySessionStatus.completed,
          ),
        );

        final tasks = await openTestDb!.query(
          DatabaseHelper.tableTasks,
          where: '${DatabaseHelper.columnId} = ?',
          whereArgs: ['task_1'],
        );
        expect(tasks.single['actual_minutes'], 20);

        final activities = await openTestDb!.query(
          DatabaseHelper.tableActivities,
        );
        expect(activities, isEmpty);
      },
    );

    test(
      '6. Safe empty return khi truy vấn DB tối giản chưa có bảng study_sessions',
      () async {
        final minimalDb = await databaseFactoryFfi.openDatabase(
          p.join(tempDir.path, 'minimal_legacy.db'),
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute(
                'CREATE TABLE ${DatabaseHelper.tableSubjects} (id TEXT PRIMARY KEY)',
              );
            },
          ),
        );
        DatabaseHelper.instance.setDatabaseForTesting(minimalDb);

        final minimalRepo = SessionRepository(
          dbHelper: DatabaseHelper.instance,
        );
        expect(await minimalRepo.getAllSessions(), isEmpty);
        expect(await minimalRepo.getActiveOrPendingSessions(), isEmpty);

        await minimalDb.close();
        DatabaseHelper.instance.setDatabaseForTesting(openTestDb);
      },
    );
  });

  group('Group D - WebSessionStorage & Web Preview Repository', () {
    test('1. Lưu và đọc session qua Web Preview repository', () async {
      final repo = SessionRepository(useWebPreview: true);
      final s1 = _buildSession(
        id: 'web_s1',
        subjectId: 'subj_web_1',
        taskId: 'task_web_1',
        verifiedStudySeconds: 1200,
      );
      await repo.createSession(s1);

      expect(await repo.getSessionById('web_s1'), s1);
      expect((await repo.getSessionsBySubject('subj_web_1')).map((s) => s.id), [
        'web_s1',
      ]);
      expect((await repo.getSessionsByTask('task_web_1')).map((s) => s.id), [
        'web_s1',
      ]);
      expect(
        (await repo.getSessionsByDateRange('2026-11-11', '2026-11-11')).length,
        1,
      );

      await repo.detachTaskForWeb('task_web_1');
      final afterDetachTask = await repo.getSessionById('web_s1');
      expect(afterDetachTask!.taskId, isNull);
      expect(afterDetachTask.taskTitleSnapshot, 'Ôn tập SQL');
    });

    test(
      '2. Mô phỏng reload ứng dụng trên Web không làm mất session đã lưu',
      () async {
        final repoBeforeReload = SessionRepository(useWebPreview: true);
        await repoBeforeReload.createSession(
          _buildSession(id: 'web_persist_1', verifiedStudySeconds: 2400),
        );

        // Tạo instance repository mới hoàn toàn như khi người dùng tải lại trang.
        final repoAfterReload = SessionRepository(useWebPreview: true);
        final loaded = await repoAfterReload.getAllSessions();
        expect(loaded, hasLength(1));
        expect(loaded.first.id, 'web_persist_1');
        expect(loaded.first.verifiedStudySeconds, 2400);
      },
    );

    test(
      '3. JSON lỗi hoặc bản ghi hỏng trong localStorage được xử lý an toàn',
      () {
        WebSessionStorage.setRawStorageValueForTesting(
          WebSessionStorage.storageKey,
          '{corrupted_json',
        );
        expect(WebSessionStorage.loadSessions(), isEmpty);

        WebSessionStorage.setRawStorageValueForTesting(
          WebSessionStorage.storageKey,
          '{"not":"a_list"}',
        );
        expect(WebSessionStorage.loadSessions(), isEmpty);

        final valid = _buildSession(id: 'web_valid_1').toMap();
        final invalidNegative = {
          ..._buildSession(id: 'web_bad_neg').toMap(),
          'verified_study_seconds': -99,
        };
        WebSessionStorage.setRawStorageValueForTesting(
          WebSessionStorage.storageKey,
          jsonEncode([valid, 'not_a_map', invalidNegative]),
        );

        final recovered = WebSessionStorage.loadSessions();
        expect(recovered.map((s) => s.id), ['web_valid_1']);
      },
    );

    test(
      '4. WebSessionStorage dùng key riêng, không ghi đè dữ liệu profile hay streak',
      () async {
        const sampleProfile = UserProfile(
          name: 'Bảo toàn Web',
          weeklyTargetHours: 16,
        );
        WebStreakStorage.saveProfile(sampleProfile);
        WebStreakStorage.saveActiveDates({'2026-11-10', '2026-11-11'});

        final repo = SessionRepository(useWebPreview: true);
        await repo.createSession(_buildSession(id: 'web_isolated_1'));
        await repo.clearAllSessions();

        expect(WebSessionStorage.storageKey, 'exampilot_web_study_sessions_v1');
        expect(WebStreakStorage.loadProfile()?.name, 'Bảo toàn Web');
        expect(WebStreakStorage.loadProfile()?.weeklyTargetHours, 16);
        expect(WebStreakStorage.loadActiveDates(), {
          '2026-11-10',
          '2026-11-11',
        });
      },
    );
  });

  group('Group E - WeeklyGoalSummaryCard', () {
    final wednesday = DateTime(2026, 11, 11, 14, 0);

    testWidgets(
      '1. Không có session thì hiển thị trạng thái 0 rõ ràng và giải thích Timer',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WeeklyGoalSummaryCard(
                profile: const UserProfile(weeklyTargetHours: 10),
                sessions: const [],
                now: wednesday,
              ),
            ),
          ),
        );

        expect(find.text('Mục tiêu học tuần này'), findsOneWidget);
        expect(find.text('0 / 10 giờ'), findsOneWidget);
        expect(find.text('0 giờ'), findsOneWidget);
        expect(find.text('0%'), findsNothing);
        expect(
          find.textContaining('Chưa có phiên học từ Đồng hồ trong tuần này'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '2. Có session thì tính đúng thời lượng Timer tuần hiện tại (T2-CN), bỏ qua ngoài tuần và phiên chưa hoàn thành',
      (tester) async {
        final sessions = [
          // Hợp lệ Thứ Hai 2026-11-09: 90 phút
          _buildSession(
            id: 'wk_mon',
            studyDate: '2026-11-09',
            verifiedStudySeconds: 5400,
            status: StudySessionStatus.completed,
          ),
          // Hợp lệ Chủ Nhật 2026-11-15: 90 phút => Tổng 180 phút = 3 giờ
          _buildSession(
            id: 'wk_sun',
            studyDate: '2026-11-15',
            verifiedStudySeconds: 5400,
            status: StudySessionStatus.completed,
          ),
          // Đang chạy / Đã hủy / Chờ khôi phục trong tuần: KHÔNG cộng
          _buildSession(
            id: 'wk_running',
            studyDate: '2026-11-11',
            verifiedStudySeconds: 3600,
            status: StudySessionStatus.running,
          ),
          _buildSession(
            id: 'wk_cancelled',
            studyDate: '2026-11-11',
            verifiedStudySeconds: 3600,
            status: StudySessionStatus.cancelled,
          ),
          _buildSession(
            id: 'wk_pending',
            studyDate: '2026-11-11',
            verifiedStudySeconds: 3600,
            status: StudySessionStatus.interruptedPending,
          ),
          // Ngoài tuần (Chủ Nhật tuần trước 2026-11-08 & Thứ Hai tuần sau 2026-11-16): KHÔNG cộng
          _buildSession(
            id: 'prev_sun',
            studyDate: '2026-11-08',
            verifiedStudySeconds: 7200,
            status: StudySessionStatus.completed,
          ),
          _buildSession(
            id: 'next_mon',
            studyDate: '2026-11-16',
            verifiedStudySeconds: 7200,
            status: StudySessionStatus.completed,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: WeeklyGoalSummaryCard(
                profile: const UserProfile(weeklyTargetHours: 10),
                sessions: sessions,
                now: wednesday,
              ),
            ),
          ),
        );

        expect(find.text('3 / 10 giờ'), findsOneWidget);
        expect(find.text('30%'), findsOneWidget);
        expect(
          find.text('Đã ghi nhận 180 phút học từ Đồng hồ trong tuần này.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '3 & 4. Không lấy số task hoàn thành hoặc actualMinutes nhập tay cũ làm giờ học Timer',
      (tester) async {
        final completedTasksWithManualMinutes = [
          StudyTask(
            id: 't_done_1',
            title: 'Bài tập lớn CSDL',
            subjectId: 'subj_db',
            subject: 'CSDL',
            deadline: DateTime.now(),
            status: TaskStatus.completed,
            actualMinutes: 240,
          ),
          StudyTask(
            id: 't_done_2',
            title: 'Báo cáo Thực tập',
            subjectId: 'subj_intern',
            subject: 'Thực tập',
            deadline: DateTime.now(),
            status: TaskStatus.completed,
            actualMinutes: 120,
          ),
        ];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: OverviewScreen(
                tasks: completedTasksWithManualMinutes,
                studyStreak: const StudyStreak(
                  currentStreak: 2,
                  longestStreak: 2,
                  activeDates: {},
                ),
                userProfile: const UserProfile(
                  weeklyTargetHours: 10,
                  weeklyTargetTasks: 2,
                ),
                sessions: const [],
                onToggleComplete: (_) {},
                onTapTask: (_) {},
                onEditTask: (_) {},
                onDeleteTask: (_) {},
                onAddTask: () {},
                onGoToPlan: () {},
              ),
            ),
          ),
        );

        expect(
          find.byKey(const ValueKey('weekly_goal_summary_card')),
          findsOneWidget,
        );
        expect(find.text('0 / 10 giờ'), findsOneWidget);
        expect(find.text('0 giờ'), findsOneWidget);
      },
    );

    testWidgets(
      '5. Responsive an toàn không tràn giao diện ở màn hình nhỏ 320dp và 360dp',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));

        for (final width in [320.0, 360.0]) {
          await tester.binding.setSurfaceSize(Size(width, 640));
          var tappedConfig = false;

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                floatingActionButton: FloatingActionButton(
                  onPressed: () {},
                  child: const Icon(Icons.add),
                ),
                body: OverviewScreen(
                  tasks: const [],
                  studyStreak: const StudyStreak(
                    currentStreak: 3,
                    longestStreak: 5,
                    activeDates: {},
                  ),
                  userProfile: const UserProfile(
                    weeklyTargetHours: 12.5,
                    weeklyTargetTasks: 8,
                  ),
                  sessions: [
                    _buildSession(
                      id: 'resp_s1',
                      studyDate: StudySession.formatLocalDateKey(
                        DateTime.now(),
                      ),
                      verifiedStudySeconds: 1800,
                    ),
                  ],
                  onToggleComplete: (_) {},
                  onTapTask: (_) {},
                  onEditTask: (_) {},
                  onDeleteTask: (_) {},
                  onAddTask: () {},
                  onGoToPlan: () {},
                  onGoToProfile: () => tappedConfig = true,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          final configBtn = find.byKey(
            const ValueKey('weekly_goal_configure_button'),
          );
          await tester.ensureVisible(configBtn);
          await tester.pumpAndSettle();
          await tester.tap(configBtn);
          expect(tappedConfig, isTrue);
        }
      },
    );
  });
}

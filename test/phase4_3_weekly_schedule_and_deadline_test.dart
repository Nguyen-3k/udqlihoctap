import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/alarm_state.dart';
import 'package:exampilot/models/class_schedule.dart';
import 'package:exampilot/models/notification_type.dart';
import 'package:exampilot/models/study_task.dart';
import 'package:exampilot/models/task_status.dart';
import 'package:exampilot/models/user_profile.dart';
import 'package:exampilot/repositories/profile_repository.dart';
import 'package:exampilot/repositories/schedule_repository.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/services/alarm_service.dart';
import 'package:exampilot/services/alarm_state_manager.dart';
import 'package:exampilot/services/alarm_store.dart';
import 'package:exampilot/services/audio_playback_gateway.dart';
import 'package:exampilot/services/backup_service.dart';
import 'package:exampilot/services/notification_permission_service.dart';
import 'package:exampilot/services/notification_scheduler.dart';
import 'package:exampilot/services/notification_service.dart';
import 'package:exampilot/services/sound_catalog.dart';
import 'package:exampilot/services/study_notification_coordinator.dart';
import 'package:exampilot/services/study_timer_engine.dart';
import 'package:exampilot/services/web_storage.dart';

class _FakeNotificationRecord {
  final int id;
  final AppNotificationType type;
  final String title;
  final String body;
  final String? payload;
  final DateTime? scheduledAtUtc;
  final bool usedExact;

  const _FakeNotificationRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.payload,
    this.scheduledAtUtc,
    this.usedExact = false,
  });
}

class _FakeNotificationService implements NotificationService {
  final Map<int, _FakeNotificationRecord> scheduled = {};
  final List<int> cancelledIds = [];

  @override
  Future<void> initialize({
    void Function(String? payload, String? actionId)? onResponse,
  }) async {}

  @override
  Future<NotificationDispatchResult> showImmediate({
    required int id,
    required AppNotificationType type,
    required UserProfile profile,
    required String title,
    required String body,
    String? payload,
    bool ongoing = false,
  }) async {
    return NotificationDispatchResult.ok;
  }

  @override
  Future<NotificationDispatchResult> scheduleAt({
    required int id,
    required DateTime scheduledAtUtc,
    required AppNotificationType type,
    required UserProfile profile,
    required String title,
    required String body,
    String? payload,
    bool allowExact = true,
  }) async {
    scheduled[id] = _FakeNotificationRecord(
      id: id,
      type: type,
      title: title,
      body: body,
      payload: payload,
      scheduledAtUtc: scheduledAtUtc,
      usedExact: allowExact,
    );
    return NotificationDispatchResult.ok;
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async {
    cancelledIds.addAll(scheduled.keys);
    scheduled.clear();
  }

  @override
  Future<List<int>> getPendingNotificationIds() async => scheduled.keys.toList();
}

class _FakePermissionService implements NotificationPermissionService {
  NotificationPermissionStatus status = const NotificationPermissionStatus(
    notificationsGranted: true,
    exactAlarmsGranted: true,
  );

  @override
  Future<NotificationPermissionStatus> checkStatus() async => status;

  @override
  Future<bool> requestNotificationPermission() async =>
      status.notificationsGranted;

  @override
  Future<bool> requestExactAlarmPermission() async =>
      status.exactAlarmsGranted;

  @override
  Future<bool> openSystemNotificationSettings() async => true;
}

class _FakeAlarmPlatformBridge implements AlarmPlatformBridge {
  final Map<String, AlarmRecord> osScheduled = {};

  @override
  bool get supportsBackgroundAlarm => true;

  @override
  void attachListeners({
    required void Function(AlarmRecord p1) onNativeAlarmUpdated,
    void Function(String? alarmKey)? onNativeLaunchStartRequested,
  }) {}

  @override
  Future<bool> scheduleAlarm(AlarmRecord record) async {
    osScheduled[record.alarmKey] = record;
    return true;
  }

  @override
  Future<void> startRingingForeground(AlarmRecord record) async {}

  @override
  Future<void> stopRingingForeground() async {}

  @override
  Future<void> syncAlarmRecord(AlarmRecord record) async {
    if (record.isTerminal) {
      osScheduled.remove(record.alarmKey);
    }
  }

  @override
  Future<void> cancelAlarm(AlarmRecord record) async {
    osScheduled.remove(record.alarmKey);
  }

  @override
  Future<void> cancelAllAlarms() async {
    osScheduled.clear();
  }

  @override
  Future<List<AlarmRecord>> getStoredNativeAlarms() async => const [];

  @override
  Future<({String action, String? alarmKey})?>
  consumePendingLaunchAction() async => null;

  @override
  void dispose() {}
}

class _FakeAudioGateway extends AudioPlaybackGateway {
  @override
  bool get isPreviewPlaying => false;
  @override
  String? get currentPreviewSoundId => null;
  @override
  SoundGroup? get currentPreviewGroup => null;
  @override
  bool get isAlarmLoopPlaying => false;
  @override
  String? get activeAlarmSoundId => null;

  @override
  Future<void> playPreview(String soundId, {required SoundGroup group}) async {}
  @override
  Future<void> stopPreview() async {}
  @override
  Future<void> playOneShotCue(String soundId, {required SoundGroup group}) async {}
  @override
  Future<void> startAlarmLoop(String soundId) async {}
  @override
  Future<void> stopAlarmLoop() async {}
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late FakeTimerClock clock;
  late _FakeNotificationService notifService;
  late _FakePermissionService permService;
  late _FakeAlarmPlatformBridge alarmBridge;
  late _FakeAudioGateway audioGateway;
  late LocalAlarmStore alarmStore;

  setUp(() {
    WebScheduleStorage.clearSchedules();
    clock = FakeTimerClock(DateTime.utc(2026, 11, 16, 7, 0)); // Thứ Hai 07:00 UTC
    notifService = _FakeNotificationService();
    permService = _FakePermissionService();
    alarmBridge = _FakeAlarmPlatformBridge();
    audioGateway = _FakeAudioGateway();
    alarmStore = LocalAlarmStore(useMemoryOnly: true);
  });

  group('Nhóm 1: ClassSchedule Model & Overlap Logic', () {
    test('Khởi tạo hợp lệ, kiểm tra giờ bắt đầu < kết thúc', () {
      const valid = ClassSchedule(
        id: 'cs_1',
        subjectId: 'subj_1',
        subjectName: 'Toán cao cấp',
        dayOfWeek: 1, // Thứ Hai
        startTime: '08:00',
        endTime: '09:30',
        location: 'Phòng B204',
      );

      expect(valid.isValidTime, isTrue);
      expect(valid.startHour, 8);
      expect(valid.startMinute, 0);
      expect(valid.endHour, 9);
      expect(valid.endMinute, 30);
      expect(valid.dayOfWeekText, 'Thứ Hai');
      expect(valid.timeRangeText, '08:00 - 09:30');

      const invalid = ClassSchedule(
        id: 'cs_2',
        subjectId: 'subj_1',
        subjectName: 'Toán cao cấp',
        dayOfWeek: 1,
        startTime: '10:00',
        endTime: '09:00', // start > end
      );
      expect(invalid.isValidTime, isFalse);
    });

    test('Phát hiện trùng lịch trên cùng thứ trong tuần', () {
      const s1 = ClassSchedule(
        id: 'cs_1',
        subjectId: 'subj_1',
        subjectName: 'Toán cao cấp',
        dayOfWeek: 1,
        startTime: '08:00',
        endTime: '09:30',
      );

      // Trùng 1 phần: 09:00 - 10:30 vào Thứ Hai
      const s2 = ClassSchedule(
        id: 'cs_2',
        subjectId: 'subj_2',
        subjectName: 'Lập trình Web',
        dayOfWeek: 1,
        startTime: '09:00',
        endTime: '10:30',
      );
      expect(s1.overlapsWith(s2), isTrue);

      // Cùng giờ nhưng khác thứ: không trùng
      const s3 = ClassSchedule(
        id: 'cs_3',
        subjectId: 'subj_2',
        subjectName: 'Lập trình Web',
        dayOfWeek: 2, // Thứ Ba
        startTime: '08:00',
        endTime: '09:30',
      );
      expect(s1.overlapsWith(s3), isFalse);

      // Chạm mốc nhưng không đè nhau: 09:30 - 11:00 -> không trùng
      const s4 = ClassSchedule(
        id: 'cs_4',
        subjectId: 'subj_3',
        subjectName: 'Cơ sở dữ liệu',
        dayOfWeek: 1,
        startTime: '09:30',
        endTime: '11:00',
      );
      expect(s1.overlapsWith(s4), isFalse);
    });

    test('Phát sinh ScheduledStudySlot cho các lần lặp trong tương lai', () {
      // Giả sử hiện tại là Thứ Hai (16/11/2026) lúc 07:00
      final now = DateTime(2026, 11, 16, 7, 0);

      const mondaySchedule = ClassSchedule(
        id: 'sched_mon',
        subjectId: 'subj_1',
        subjectName: 'Toán',
        dayOfWeek: 1,
        startTime: '08:00',
        endTime: '09:30',
        repeatWeekly: true,
      );

      final slots = mondaySchedule.generateUpcomingSlots(
        fromTime: now,
        daysAhead: 14,
      );

      // Trong 14 ngày tới sẽ có: Thứ Hai tuần này (16/11) và Thứ Hai tuần sau (23/11)
      expect(slots.length, 2);
      expect(slots[0].id, 'sched_mon_20261116');
      expect(slots[0].subjectName, 'Toán');
      expect(slots[1].id, 'sched_mon_20261123');

      // Nếu repeatWeekly = false, chỉ phát sinh 1 lần gần nhất
      const singleSchedule = ClassSchedule(
        id: 'sched_single',
        subjectId: 'subj_1',
        subjectName: 'Toán',
        dayOfWeek: 1,
        startTime: '08:00',
        endTime: '09:30',
        repeatWeekly: false,
      );
      final singleSlots = singleSchedule.generateUpcomingSlots(
        fromTime: now,
        daysAhead: 14,
      );
      expect(singleSlots.length, 1);
    });
  });

  group('Nhóm 2: ScheduleRepository CRUD (SQLite & Web)', () {
    test('Thao tác CRUD lịch học trên SQLite', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);
      await db.execute('''
        CREATE TABLE ${DatabaseHelper.tableSubjects} (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT NOT NULL,
          icon_code INTEGER NOT NULL,
          color_value INTEGER NOT NULL
        )
      ''');
      await DatabaseHelper.createClassSchedulesTable(db);
      DatabaseHelper.instance.setDatabaseForTesting(db);

      final repo = ScheduleRepository(dbHelper: DatabaseHelper.instance);

      const s1 = ClassSchedule(
        id: 's_1',
        subjectId: 'subj_1',
        subjectName: 'Toán',
        dayOfWeek: 1,
        startTime: '08:00',
        endTime: '09:30',
      );
      const s2 = ClassSchedule(
        id: 's_2',
        subjectId: 'subj_2',
        subjectName: 'Web',
        dayOfWeek: 3,
        startTime: '13:30',
        endTime: '15:00',
      );

      // 1. Thêm
      await repo.insertSchedule(s1);
      await repo.insertSchedule(s2);
      final list = await repo.getAllSchedules();
      expect(list.length, 2);

      // 2. Lấy theo ID
      final fetched = await repo.getScheduleById('s_1');
      expect(fetched?.subjectName, 'Toán');

      // 3. Sửa
      final updated = s1.copyWith(startTime: '08:30');
      await repo.updateSchedule(updated);
      final fetchedUpdated = await repo.getScheduleById('s_1');
      expect(fetchedUpdated?.startTime, '08:30');

      // 4. Bật / Tắt
      await repo.toggleScheduleActive('s_1', false);
      final activeList = await repo.getActiveSchedules();
      expect(activeList.length, 1);
      expect(activeList.first.id, 's_2');

      // 5. Xóa
      await repo.deleteSchedule('s_1');
      final afterDelete = await repo.getAllSchedules();
      expect(afterDelete.length, 1);
      expect(afterDelete.first.id, 's_2');

      await db.close();
      DatabaseHelper.instance.setDatabaseForTesting(null);
    });

    test('Thao tác CRUD lịch học trên Web Preview (Bộ nhớ tạm)', () async {
      final repo = ScheduleRepository(useWebPreview: true);

      const s = ClassSchedule(
        id: 'web_s1',
        subjectId: 'subj_1',
        subjectName: 'Toán Web',
        dayOfWeek: 2,
        startTime: '07:30',
        endTime: '09:00',
      );

      await repo.insertSchedule(s);
      final all = await repo.getAllSchedules();
      expect(all.length, 1);
      expect(all.first.subjectName, 'Toán Web');

      await repo.toggleScheduleActive('web_s1', false);
      expect(await repo.getActiveSchedules(), isEmpty);

      await repo.deleteSchedule('web_s1');
      expect(await repo.getAllSchedules(), isEmpty);
    });
  });

  group('Nhóm 3: Đồng bộ Báo thức Lịch học & Thay đổi thời gian nhắc trước', () {
    test(
      'Tạo báo thức cho lịch học tuần; đổi thời gian nhắc trước (10p -> 5p) cập nhật chính xác',
      () async {
        final alarmMgr = AlarmStateManager(
          store: alarmStore,
          platformBridge: alarmBridge,
          audioGateway: audioGateway,
          clock: clock,
        );
        final scheduler = NotificationScheduler(
          notificationService: notifService,
          alarmStateManager: alarmMgr,
          clock: clock,
        );

        // Giả sử Thứ Hai lúc 08:00 UTC (16/11/2026) bắt đầu buổi học
        final classTime = DateTime.utc(2026, 11, 16, 8, 0);
        final slot = ScheduledStudySlot(
          id: 'slot_math_1',
          subjectName: 'Toán cao cấp',
          startAtUtc: classTime,
        );

        final coordinator = StudyNotificationCoordinator(
          initialProfile: const UserProfile(
            reminderEnabled: true,
            preReminderMinutes: 10,
            notifyPreStudy: true,
            notifyAlarmOnTime: true,
            alarmSoundId: 'alarm_dawn',
          ),
          notificationService: notifService,
          permissionService: permService,
          audioGateway: audioGateway,
          alarmStateManager: alarmMgr,
          scheduler: scheduler,
          clock: clock,
          scheduleSlotsProvider: () => [slot],
        );
        await coordinator.initialize();

        // 1. Kiểm tra ban đầu: Nhắc trước 10 phút (07:50) và Báo thức đúng giờ (08:00)
        expect(coordinator.lastSyncReport.preStudyScheduledCount, 1);
        expect(coordinator.lastSyncReport.alarmsScheduledCount, 1);
        expect(alarmBridge.osScheduled.containsKey('slot:slot_math_1'), isTrue);
        expect(
          alarmBridge.osScheduled['slot:slot_math_1']!.scheduledAtUtc,
          classTime,
        );

        final preNotifId = NotificationIds.preStudyForSlot('slot_math_1');
        expect(notifService.scheduled.containsKey(preNotifId), isTrue);
        expect(
          notifService.scheduled[preNotifId]!.scheduledAtUtc,
          classTime.subtract(const Duration(minutes: 10)),
        );
        expect(
          notifService.scheduled[preNotifId]!.title,
          contains('Toán cao cấp'),
        );
        expect(
          notifService.scheduled[preNotifId]!.body,
          contains('Còn 10 phút tới giờ học'),
        );

        // 2. Người dùng đổi tùy chọn nhắc trước thành 5 phút
        await coordinator.applyProfile(
          coordinator.profile.copyWith(preReminderMinutes: 5),
        );

        expect(
          notifService.scheduled[preNotifId]!.scheduledAtUtc,
          classTime.subtract(const Duration(minutes: 5)),
        );
        expect(
          notifService.scheduled[preNotifId]!.body,
          contains('Còn 5 phút tới giờ học'),
        );

        // 3. Tắt lịch học hoặc xóa lịch -> Hủy toàn bộ báo thức và thông báo chờ
        await coordinator.syncSchedules(const []);
        expect(notifService.scheduled, isEmpty);
        expect(alarmBridge.osScheduled['slot:slot_math_1'], isNull);
      },
    );
  });

  group('Nhóm 4: Nhắc trước Deadline Task & Hoàn thành hủy báo thức', () {
    test(
      'Đặt báo thức deadline, sửa hạn chót, hoàn thành công việc thì hủy báo thức',
      () async {
        final alarmMgr = AlarmStateManager(
          store: alarmStore,
          platformBridge: alarmBridge,
          audioGateway: audioGateway,
          clock: clock,
        );
        final scheduler = NotificationScheduler(
          notificationService: notifService,
          alarmStateManager: alarmMgr,
          clock: clock,
        );

        // Deadline lúc 20:00 UTC, nhắc trước 10 phút -> báo lúc 19:50
        final deadline = DateTime.utc(2026, 11, 16, 20, 0);
        final task = StudyTask(
          id: 'task_essay',
          title: 'Nộp bài tiểu luận',
          subjectId: 'subj_web',
          subject: 'Lập trình Web',
          deadline: deadline,
          reminderEnabled: true,
          reminderMinutes: 10,
        );

        final coordinator = StudyNotificationCoordinator(
          initialProfile: const UserProfile(
            reminderEnabled: true,
            notifyAlarmOnTime: true,
            alarmSoundId: 'alarm_school_bell',
          ),
          notificationService: notifService,
          permissionService: permService,
          audioGateway: audioGateway,
          alarmStateManager: alarmMgr,
          scheduler: scheduler,
          clock: clock,
          tasksProvider: () => [task],
        );
        await coordinator.initialize();

        // 1. Báo thức deadline được lên lịch thành công lúc 19:50 (trước deadline 10 phút)
        final expectedTriggerUtc = deadline.subtract(const Duration(minutes: 10));
        final taskAlarmKey = 'task_deadline:task_essay';

        expect(alarmBridge.osScheduled.containsKey(taskAlarmKey), isTrue);
        final alarmRecord = alarmBridge.osScheduled[taskAlarmKey]!;
        expect(alarmRecord.scheduledAtUtc, expectedTriggerUtc);
        expect(alarmRecord.title, 'Hạn chót: Nộp bài tiểu luận');
        expect(alarmRecord.taskTitle, contains('Lập trình Web'));
        expect(alarmRecord.taskTitle, contains('Còn 10 phút tới hạn hoàn thành'));
        expect(alarmRecord.soundId, 'alarm_school_bell');

        // 2. Chống tạo báo thức trùng: gọi lại scheduleTaskDeadline không nhân đôi ID
        await coordinator.scheduleTaskDeadline(task);
        expect(alarmBridge.osScheduled.length, 1);

        // 3. Người dùng sửa deadline sang 21:00 và nhắc trước 15 phút
        final newDeadline = DateTime.utc(2026, 11, 16, 21, 0);
        final updatedTask = task.copyWith(
          deadline: newDeadline,
          reminderMinutes: 15,
        );
        await coordinator.scheduleTaskDeadline(updatedTask);
        final updatedAlarm = alarmBridge.osScheduled[taskAlarmKey]!;
        expect(
          updatedAlarm.scheduledAtUtc,
          newDeadline.subtract(const Duration(minutes: 15)),
        );

        // 4. Khi công việc Hoàn thành -> Hủy ngay báo thức deadline chưa đến
        await coordinator.scheduleTaskDeadline(
          updatedTask.copyWith(status: TaskStatus.completed),
        );
        expect(alarmBridge.osScheduled.containsKey(taskAlarmKey), isFalse);
      },
    );
  });

  group('Nhóm 5: Database Migration v8 & Backup / Restore tương thích', () {
    test('Migration nâng từ schema v7 lên v8 thành công', () async {
      final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      // Giả lập cơ sở dữ liệu ở Schema v7
      await db.execute('''
        CREATE TABLE ${DatabaseHelper.tableSubjects} (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          description TEXT NOT NULL,
          icon_code INTEGER NOT NULL,
          color_value INTEGER NOT NULL
        )
      ''');
      await db.execute('''
        CREATE TABLE ${DatabaseHelper.tableTasks} (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          subject_id TEXT NOT NULL,
          subject TEXT NOT NULL,
          deadline TEXT NOT NULL,
          estimated_minutes INTEGER NOT NULL,
          actual_minutes INTEGER,
          priority TEXT NOT NULL,
          status TEXT NOT NULL,
          notes TEXT NOT NULL DEFAULT '',
          understanding_level TEXT,
          review_notes TEXT
        )
      ''');
      await DatabaseHelper.createProfileTable(db);
      await DatabaseHelper.createSessionsTable(db);

      // Chèn 1 task cũ
      await db.insert(DatabaseHelper.tableTasks, {
        'id': 'old_task',
        'title': 'Task cũ',
        'subject_id': 's1',
        'subject': 'Môn cũ',
        'deadline': '2026-11-20T10:00:00.000',
        'estimated_minutes': 45,
        'priority': 'medium',
        'status': 'todo',
      });

      // Thực hiện migration lên version 8
      DatabaseHelper.instance.setDatabaseForTesting(db);
      await DatabaseHelper.instance.upgradeForTesting(db, 7, 8);

      // Kiểm tra bảng class_schedules đã được tạo
      final schedulesTable = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='${DatabaseHelper.tableClassSchedules}'",
      );
      expect(schedulesTable, isNotEmpty);

      // Kiểm tra cột reminder_enabled và reminder_minutes đã được thêm vào study_tasks
      final tasksCols = await db.rawQuery('PRAGMA table_info(${DatabaseHelper.tableTasks})');
      expect(tasksCols.any((c) => c['name'] == 'reminder_enabled'), isTrue);
      expect(tasksCols.any((c) => c['name'] == 'reminder_minutes'), isTrue);

      // Đọc lại task cũ: không bị mất dữ liệu
      final taskRows = await db.query(DatabaseHelper.tableTasks);
      expect(taskRows.length, 1);
      final restoredTask = StudyTask.fromMap(taskRows.first);
      expect(restoredTask.title, 'Task cũ');
      expect(restoredTask.reminderEnabled, isFalse); // giá trị mặc định an toàn
      expect(restoredTask.reminderMinutes, 10);

      await db.close();
      DatabaseHelper.instance.setDatabaseForTesting(null);
    });

    test('Bản sao lưu cũ (Format v1 không có schedules) vẫn khôi phục bình thường', () async {
      final taskRepo = TaskRepository(useWebPreview: true);
      final subjRepo = SubjectRepository(useWebPreview: true);
      final profileRepo = ProfileRepository(useWebPreview: true);
      final schedRepo = ScheduleRepository(useWebPreview: true);

      final backupService = BackupService(
        taskRepository: taskRepo,
        subjectRepository: subjRepo,
        profileRepository: profileRepo,
        scheduleRepository: schedRepo,
      );

      // Giả lập JSON bản sao lưu v1 cũ (hoàn toàn không có trường 'schedules')
      final oldBackupMap = {
        'app': 'ExamPilot',
        'formatVersion': 1,
        'appVersion': '1.0.0',
        'createdAt': DateTime.now().toIso8601String(),
        'metadata': {
          'totalSubjects': 1,
          'totalTasks': 1,
          'totalActivities': 0,
        },
        'data': {
          'profile': {'name': 'Sinh viên v1'},
          'subjects': [
            {
              'id': 'subj_old',
              'name': 'Môn học v1',
              'description': 'Mô tả v1',
              'icon_code': 1,
              'color_value': 0xFF3B5BDB,
            }
          ],
          'tasks': [
            {
              'id': 'task_old',
              'title': 'Bài tập v1',
              'subject_id': 'subj_old',
              'subject': 'Môn học v1',
              'deadline': '2026-11-25T15:00:00.000',
              'estimated_minutes': 30,
              'priority': 'high',
              'status': 'todo',
            }
          ],
          'activities': <Map<String, dynamic>>[],
        },
      };

      // Xác thực hợp lệ
      final val = backupService.validateBackupJson(jsonEncode(oldBackupMap));
      expect(val.isValid, isTrue);

      // Khôi phục thành công
      await backupService.restoreBackup(oldBackupMap);
      final restoredTasks = await taskRepo.getAllTasks();
      expect(restoredTasks.any((t) => t.id == 'task_old'), isTrue);
      final restoredSchedules = await schedRepo.getAllSchedules();
      expect(restoredSchedules, isEmpty); // không lỗi, schedules rỗng sạch sẽ
    });

    test('Bản sao lưu mới kèm schedules tạo và khôi phục toàn vẹn', () async {
      final taskRepo = TaskRepository(useWebPreview: true);
      final subjRepo = SubjectRepository(useWebPreview: true);
      final profileRepo = ProfileRepository(useWebPreview: true);
      final schedRepo = ScheduleRepository(useWebPreview: true);

      final backupService = BackupService(
        taskRepository: taskRepo,
        subjectRepository: subjRepo,
        profileRepository: profileRepo,
        scheduleRepository: schedRepo,
      );

      const testSchedule = ClassSchedule(
        id: 'sched_backup_1',
        subjectId: 'subj_1',
        subjectName: 'Toán cao cấp',
        dayOfWeek: 4,
        startTime: '14:00',
        endTime: '16:00',
        location: 'Phòng C101',
      );
      await schedRepo.insertSchedule(testSchedule);

      // Tạo sao lưu
      final backupData = await backupService.createBackupData();
      final dataBlock = backupData['data'] as Map;
      expect(dataBlock.containsKey('schedules'), isTrue);
      expect((dataBlock['schedules'] as List).length, 1);

      // Xóa dữ liệu rồi khôi phục
      await schedRepo.clearAllSchedules();
      expect(await schedRepo.getAllSchedules(), isEmpty);

      await backupService.restoreBackup(backupData);
      final restored = await schedRepo.getAllSchedules();
      expect(restored.length, 1);
      expect(restored.first.id, 'sched_backup_1');
      expect(restored.first.location, 'Phòng C101');
    });
  });
}

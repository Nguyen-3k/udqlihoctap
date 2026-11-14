import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:exampilot/config/supabase_config.dart';
import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/ai_timetable_model.dart';
import 'package:exampilot/models/class_schedule.dart';
import 'package:exampilot/models/class_schedule_occurrence.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/timetable_import_model.dart';
import 'package:exampilot/repositories/profile_repository.dart';
import 'package:exampilot/repositories/schedule_repository.dart';
import 'package:exampilot/repositories/subject_repository.dart';
import 'package:exampilot/repositories/task_repository.dart';
import 'package:exampilot/services/ai/timetable_ai_service.dart';
import 'package:exampilot/services/backup_service.dart';
import 'package:exampilot/services/class_schedule_resolver.dart';
import 'package:exampilot/services/image_timetable_importer.dart';
import 'package:exampilot/widgets/image_timetable_import_dialog.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Cấu hình tạm thời cho SupabaseConfig trong test
  setUpAll(() {
    SupabaseConfig.override(
      url: 'https://test-project.supabase.co',
      anonKey: 'test-anon-key',
    );
  });

  // =========================================================================
  // NHÓM A: EDGE FUNCTION CONTRACT & MOCK GEMINI JSON
  // =========================================================================
  group('Nhóm A: Edge Function Contract & Mock Gemini JSON', () {
    test('A1: Parse full structured JSON response from Gemini Vision', () {
      final jsonResponse = {
        'success': true,
        'message': 'Phân tích thành công',
        'weeks': [
          {
            'weekNumber': 11,
            'startDate': '2026-11-16',
            'endDate': '2026-11-22',
            'classes': [
              {
                'subject': 'Lập trình Di động',
                'classDate': '2026-11-17',
                'weekday': 2,
                'session': 'morning',
                'startPeriod': 1,
                'endPeriod': 4,
                'startTime': '07:00',
                'endTime': '10:15',
                'teacher': 'ThS. Nguyễn Văn A',
                'location': 'P.A201',
                'format': 'offline',
                'notes': 'Mang laptop',
                'confidence': 0.95,
                'needsReview': false,
                'reviewReasons': [],
              },
              {
                'subject': 'Học máy & Ứng dụng',
                'classDate': '2026-11-19',
                'weekday': 4,
                'session': 'afternoon',
                'startPeriod': 7,
                'endPeriod': 10,
                'startTime': '13:00',
                'endTime': '16:15',
                'teacher': 'TS. Trần Thị B',
                'location': 'Trực tuyến Google Meet',
                'format': 'online',
                'notes': 'Link Meet trong email',
                'confidence': 0.88,
                'needsReview': false,
                'reviewReasons': [],
              },
            ],
          },
        ],
        'totalDetected': 2,
        'validCount': 2,
        'needsReviewCount': 0,
        'ignoredCount': 0,
      };

      final result = AiTimetableResult.fromJson(jsonResponse);
      expect(result.success, isTrue);
      expect(result.weeks.length, 1);
      expect(result.allClasses.length, 2);

      final c1 = result.allClasses[0];
      expect(c1.subject, 'Lập trình Di động');
      expect(c1.classDate, '2026-11-17');
      expect(c1.weekday, 2);
      expect(c1.startTime, '07:00');
      expect(c1.endTime, '10:15');
      expect(c1.startPeriod, 1);
      expect(c1.endPeriod, 4);
      expect(c1.teacher, 'ThS. Nguyễn Văn A');
      expect(c1.location, 'P.A201');
      expect(c1.format, 'offline');
      expect(c1.confidence, 0.95);
      expect(c1.needsReview, isFalse);

      final c2 = result.allClasses[1];
      expect(c2.subject, 'Học máy & Ứng dụng');
      expect(c2.format, 'online');
      expect(c2.location, 'Trực tuyến Google Meet');
    });

    test('A2: Parse item with missing clock times (period only), preserving periods with needsReview=true', () {
      final jsonResponse = {
        'success': true,
        'message': 'Phân tích thành công',
        'weeks': [
          {
            'weekNumber': 12,
            'classes': [
              {
                'subject': 'Toán Rời Rạc',
                'classDate': '2026-11-24',
                'weekday': 2,
                'session': 'morning',
                'startPeriod': 1,
                'endPeriod': 4,
                'startTime': null,
                'endTime': null,
                'confidence': 0.65,
                'needsReview': true,
                'reviewReasons': ['Thiếu giờ học chính xác, chỉ có tiết (1-4)'],
              },
            ],
          },
        ],
        'totalDetected': 1,
        'validCount': 0,
        'needsReviewCount': 1,
        'ignoredCount': 0,
      };

      final result = AiTimetableResult.fromJson(jsonResponse);
      expect(result.allClasses.length, 1);
      final item = result.allClasses.first;
      expect(item.subject, 'Toán Rời Rạc');
      expect(item.startPeriod, 1);
      expect(item.endPeriod, 4);
      expect(item.startTime, isNull);
      expect(item.endTime, isNull);
      expect(item.needsReview, isTrue);
      expect(item.reviewReasons.first, contains('Thiếu giờ học chính xác'));
    });

    test('A3: Validate rejection of prohibited subjects', () {
      expect(isProhibitedSubjectName('Thứ 2'), isTrue);
      expect(isProhibitedSubjectName('Sáng'), isTrue);
      expect(isProhibitedSubjectName('Buổi'), isTrue);
      expect(isProhibitedSubjectName('Học phần'), isTrue);
      expect(isProhibitedSubjectName('Thời khóa biểu'), isTrue);
      expect(isProhibitedSubjectName('Tuần 11'), isTrue);
      expect(isProhibitedSubjectName('Từ ngày 16/11 đến ngày 22/11'), isTrue);

      expect(isProhibitedSubjectName('Lập trình hướng đối tượng'), isFalse);
      expect(isProhibitedSubjectName('Toán cao cấp A1'), isFalse);
    });

    test('A4: Validate clamping of confidence scores (0.0 .. 1.0)', () {
      final jsonLow = {
        'subject': 'Môn Test',
        'confidence': -0.5,
      };
      final classLow = AiTimetableClass.fromJson(jsonLow);
      expect(classLow.confidence, 0.0);

      final jsonHigh = {
        'subject': 'Môn Test',
        'confidence': 1.5,
      };
      final classHigh = AiTimetableClass.fromJson(jsonHigh);
      expect(classHigh.confidence, 1.0);
    });

    test('A5: Validate conversion of AiTimetableClass to Occurrence and ClassSchedule', () {
      const aiClass = AiTimetableClass(
        subject: 'Cấu trúc Dữ liệu',
        classDate: '2026-11-18',
        weekday: 3,
        startPeriod: 1,
        endPeriod: 3,
        startTime: '07:30',
        endTime: '10:00',
        teacher: 'ThS. Lê Văn C',
        location: 'P.B102',
        notes: 'Bài tập tuần',
      );

      final occ = aiClass.toOccurrence(targetSubjectId: 'subj_ds');
      expect(occ.subjectId, 'subj_ds');
      expect(occ.subjectName, 'Cấu trúc Dữ liệu');
      expect(occ.classDate, '2026-11-18');
      expect(occ.startTime, '07:30');
      expect(occ.endTime, '10:00');
      expect(occ.teacher, 'ThS. Lê Văn C');
      expect(occ.location, 'P.B102');
      expect(occ.scheduleId, isNull);

      final sched = aiClass.toClassSchedule(targetSubjectId: 'subj_ds');
      expect(sched.subjectId, 'subj_ds');
      expect(sched.subjectName, 'Cấu trúc Dữ liệu');
      expect(sched.dayOfWeek, 3);
      expect(sched.startTime, '07:30');
      expect(sched.endTime, '10:00');
      expect(sched.repeatWeekly, isTrue);
    });
  });

  // =========================================================================
  // NHÓM B: TIMETABLE AI SERVICE (FLUTTER CLIENT)
  // =========================================================================
  group('Nhóm B: TimetableAiService (Flutter Client)', () {
    test('B1: Service returns AiTimetableResult successfully on HTTP 200', () async {
      final mockClient = MockClient((request) async {
        expect(request.url.path, contains('analyze-timetable-image'));
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], contains('Bearer test-anon-key'));

        return http.Response(
          jsonEncode({
            'success': true,
            'message': 'OK',
            'weeks': [
              {
                'weekNumber': 1,
                'classes': [
                  {
                    'subject': 'An toàn thông tin',
                    'classDate': '2026-11-20',
                    'weekday': 5,
                    'startTime': '08:00',
                    'endTime': '10:30',
                  }
                ]
              }
            ],
            'totalDetected': 1,
            'validCount': 1,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = SupabaseTimetableAiService(client: mockClient);
      final result = await service.analyzeTimetable(
        imageBytes: Uint8List.fromList([1, 2, 3, 4]),
        mimeType: 'image/jpeg',
      );

      expect(result.success, isTrue);
      expect(result.allClasses.length, 1);
      expect(result.allClasses.first.subject, 'An toàn thông tin');
    });

    test('B2: Service handles Edge Function 429 (Rate Limit)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'error': 'Quá giới hạn tần suất yêu cầu (Tối đa 15 yêu cầu / phút).'
          }),
          429,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = SupabaseTimetableAiService(client: mockClient);
      final result = await service.analyzeTimetable(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(result.success, isFalse);
      expect(result.message, contains('giới hạn'));
    });

    test('B3: Service handles Edge Function 413 (Payload Too Large)', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Dung lượng ảnh vượt quá 10MB.'}),
          413,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = SupabaseTimetableAiService(client: mockClient);
      final result = await service.analyzeTimetable(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(result.success, isFalse);
      expect(result.message, contains('vượt quá'));
    });

    test('B4: Service handles Edge Function 500 / 502 gracefully', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'error': 'Lỗi kết nối tới Google Gemini API'}),
          502,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final service = SupabaseTimetableAiService(client: mockClient);
      final result = await service.analyzeTimetable(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Google Gemini'));
    });

    test('B5: Service handles timeout / network exception gracefully', () async {
      final mockClient = MockClient((request) async {
        throw http.ClientException('Mất kết nối mạng Internet');
      });

      final service = SupabaseTimetableAiService(client: mockClient);
      final result = await service.analyzeTimetable(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        mimeType: 'image/jpeg',
      );

      expect(result.success, isFalse);
      expect(result.message, contains('Không thể kết nối'));
    });
  });

  // =========================================================================
  // NHÓM C: UNIFIED SCHEDULE ARCHITECTURE (RESOLVER & OCCURRENCES)
  // =========================================================================
  group('Nhóm C: Unified Schedule Architecture (Resolver & Occurrences)', () {
    test('C1: ClassScheduleOccurrence serialization & copyWith', () {
      final occ = ClassScheduleOccurrence(
        id: 'occ_101',
        scheduleId: 'sched_1',
        subjectId: 'subj_1',
        subjectName: 'Giải Tích',
        classDate: '2026-11-18',
        startTime: '08:00',
        endTime: '11:15',
        startPeriod: 1,
        endPeriod: 4,
        teacher: 'ThS. Nguyễn Văn A',
        location: 'P.301',
        notes: 'Kiểm tra 15 phút',
        status: 'scheduled',
        source: 'image_import',
        createdAt: '2026-11-14T00:00:00Z',
        updatedAt: '2026-11-14T00:00:00Z',
      );

      final map = occ.toMap();
      final fromMap = ClassScheduleOccurrence.fromMap(map);
      expect(fromMap.id, 'occ_101');
      expect(fromMap.scheduleId, 'sched_1');
      expect(fromMap.subjectName, 'Giải Tích');
      expect(fromMap.classDate, '2026-11-18');
      expect(fromMap.startPeriod, 1);
      expect(fromMap.endPeriod, 4);
      expect(fromMap.teacher, 'ThS. Nguyễn Văn A');

      final updated = occ.copyWith(status: 'cancelled');
      expect(updated.isCancelled, isTrue);
      expect(updated.isScheduled, isFalse);
    });

    test('C2: ClassScheduleResolver.resolveForDate unifies fixed, override, cancellation and standalone', () {
      const resolver = ClassScheduleResolver();

      // Lịch cố định Thứ 3 (weekday = 2)
      final fixedSchedules = [
        const ClassSchedule(
          id: 'sched_tue_1',
          subjectId: 'subj_math',
          subjectName: 'Toán Cao Cấp',
          dayOfWeek: 2, // Thứ 3
          startTime: '08:00',
          endTime: '10:00',
          location: 'P.101',
          isActive: true,
        ),
        const ClassSchedule(
          id: 'sched_tue_2',
          subjectId: 'subj_phys',
          subjectName: 'Vật Lý Đại Cương',
          dayOfWeek: 2, // Thứ 3
          startTime: '13:00',
          endTime: '15:00',
          location: 'P.102',
          isActive: true,
        ),
      ];

      // 1. Ngày 2026-11-17 là Thứ 3: Có override cho Toán và hủy cho Vật Lý, thêm standalone buổi tối
      final occurrences = [
        // Override sched_tue_1 (đổi phòng sang P.999 và dời giờ)
        const ClassScheduleOccurrence(
          id: 'occ_ovr_1',
          scheduleId: 'sched_tue_1',
          subjectId: 'subj_math',
          subjectName: 'Toán Cao Cấp (Đổi phòng)',
          classDate: '2026-11-17',
          startTime: '08:30',
          endTime: '10:30',
          location: 'P.999',
          status: 'scheduled',
          createdAt: '',
          updatedAt: '',
        ),
        // Hủy sched_tue_2 vào ngày 2026-11-17
        const ClassScheduleOccurrence(
          id: 'occ_canc_1',
          scheduleId: 'sched_tue_2',
          subjectId: 'subj_phys',
          subjectName: 'Vật Lý Đại Cương',
          classDate: '2026-11-17',
          startTime: '13:00',
          endTime: '15:00',
          status: 'cancelled',
          createdAt: '',
          updatedAt: '',
        ),
        // Standalone buổi tối
        const ClassScheduleOccurrence(
          id: 'occ_std_1',
          scheduleId: null,
          subjectId: 'subj_extra',
          subjectName: 'Chuyên đề AI',
          classDate: '2026-11-17',
          startTime: '18:00',
          endTime: '20:00',
          status: 'scheduled',
          createdAt: '',
          updatedAt: '',
        ),
      ];

      final resolved = resolver.resolveForDate(
        fixedSchedules: fixedSchedules,
        occurrences: occurrences,
        date: DateTime(2026, 11, 17),
      );

      // Kết quả phải gồm 2 buổi học hoạt động: Toán (đã override, không bị nhân đôi) và Chuyên đề AI
      // Vật Lý bị hủy (isCancelled=true) nên không xuất hiện trong danh sách hiển thị
      expect(resolved.length, 2);

      final math = resolved.firstWhere((r) => r.subjectId == 'subj_math');
      expect(math.isOverride, isTrue);
      expect(math.location, 'P.999');
      expect(math.startTime, '08:30');

      expect(resolved.any((r) => r.subjectId == 'subj_phys'), isFalse);

      final extra = resolved.firstWhere((r) => r.subjectId == 'subj_extra');
      expect(extra.isOccurrence, isTrue);
      expect(extra.isOverride, isFalse);
      expect(extra.startTime, '18:00');
    });

    test('C3: ClassScheduleResolver.resolveSlots suppresses cancelled and avoids duplicates', () {
      const resolver = ClassScheduleResolver();

      final fixed = [
        const ClassSchedule(
          id: 'sched_day',
          subjectId: 'subj_1',
          subjectName: 'Lịch Cố Định',
          dayOfWeek: 3, // Thứ 4
          startTime: '08:00',
          endTime: '10:00',
        ),
      ];

      // Giả sử ngày 2026-11-18 là Thứ 4
      final occ = [
        const ClassScheduleOccurrence(
          id: 'occ_cancel',
          scheduleId: 'sched_day',
          subjectId: 'subj_1',
          subjectName: 'Lịch Cố Định',
          classDate: '2026-11-18',
          startTime: '08:00',
          endTime: '10:00',
          status: 'cancelled',
          createdAt: '',
          updatedAt: '',
        ),
      ];

      final slots = resolver.resolveSlots(
        fixedSchedules: fixed,
        occurrences: occ,
        fromDate: DateTime(2026, 11, 18),
        daysAhead: 1,
      );

      // Buổi học bị hủy phải bị loại bỏ khỏi danh sách slot báo thức
      expect(slots.isEmpty, isTrue);
    });
  });

  // =========================================================================
  // NHÓM D: SQLITE MIGRATION V10 & BATCH IMPORT
  // =========================================================================
  group('Nhóm D: SQLite Migration v10 & Batch Import', () {
    late Database db;
    late ScheduleRepository scheduleRepo;
    late TaskRepository taskRepo;
    late SubjectRepository subjectRepo;
    late ProfileRepository profileRepo;
    late BackupService backupService;

    setUp(() async {
      db = await databaseFactory.openDatabase(inMemoryDatabasePath);

      // Tạo cấu trúc database
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
          ${DatabaseHelper.columnReviewNotes} TEXT,
          ${DatabaseHelper.columnTaskReminderEnabled} INTEGER NOT NULL DEFAULT 0,
          ${DatabaseHelper.columnTaskReminderMinutes} INTEGER NOT NULL DEFAULT 10
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

      await DatabaseHelper.createProfileTable(db);
      await DatabaseHelper.createClassSchedulesTable(db);
      await DatabaseHelper.createScheduleOccurrencesTable(db);

      DatabaseHelper.instance.setDatabaseForTesting(db);

      scheduleRepo = ScheduleRepository(dbHelper: DatabaseHelper.instance);
      taskRepo = TaskRepository(dbHelper: DatabaseHelper.instance);
      subjectRepo = SubjectRepository(dbHelper: DatabaseHelper.instance);
      profileRepo = ProfileRepository(dbHelper: DatabaseHelper.instance);

      backupService = BackupService(
        taskRepository: taskRepo,
        subjectRepository: subjectRepo,
        profileRepository: profileRepo,
        scheduleRepository: scheduleRepo,
        dbHelper: DatabaseHelper.instance,
      );
    });

    tearDown(() async {
      await db.close();
      DatabaseHelper.instance.setDatabaseForTesting(null);
    });

    test('D1: Table class_schedule_occurrences is created with proper columns', () async {
      final info = await db.rawQuery('PRAGMA table_info(class_schedule_occurrences)');
      final colNames = info.map((c) => c['name'].toString()).toSet();

      expect(colNames.contains('id'), isTrue);
      expect(colNames.contains('schedule_id'), isTrue);
      expect(colNames.contains('subject_id'), isTrue);
      expect(colNames.contains('class_date'), isTrue);
      expect(colNames.contains('start_time'), isTrue);
      expect(colNames.contains('end_time'), isTrue);
      expect(colNames.contains('start_period'), isTrue);
      expect(colNames.contains('end_period'), isTrue);
      expect(colNames.contains('teacher'), isTrue);
      expect(colNames.contains('location'), isTrue);
      expect(colNames.contains('status'), isTrue);
    });

    test('D2: importOccurrencesWithSubjectsBatch atomic transaction works correctly', () async {
      const newSubject = Subject(
        id: 'subj_ai_new',
        name: 'Trí tuệ Nhân tạo',
        description: 'Môn học mới',
        icon: Icons.psychology_rounded,
        color: Colors.blue,
      );

      final occurrence = ClassScheduleOccurrence(
        id: 'occ_test_1',
        scheduleId: null,
        subjectId: 'subj_ai_new',
        subjectName: 'Trí tuệ Nhân tạo',
        classDate: '2026-11-20',
        startTime: '08:00',
        endTime: '11:15',
        startPeriod: 1,
        endPeriod: 4,
        teacher: 'GS. Nguyễn',
        createdAt: '2026-11-14T00:00:00Z',
        updatedAt: '2026-11-14T00:00:00Z',
      );

      await scheduleRepo.importOccurrencesWithSubjectsBatch(
        occurrences: [occurrence],
        newSubjects: [newSubject],
      );

      final loadedSubjects = await subjectRepo.getAllSubjects();
      expect(loadedSubjects.any((s) => s.id == 'subj_ai_new'), isTrue);

      final loadedOccurrences = await scheduleRepo.getAllOccurrences();
      expect(loadedOccurrences.length, 1);
      expect(loadedOccurrences.first.subjectName, 'Trí tuệ Nhân tạo');
      expect(loadedOccurrences.first.classDate, '2026-11-20');
    });

    test('D3: BackupService exports and restores occurrences seamlessly', () async {
      // 1. Chèn occurrence vào database
      final occurrence = ClassScheduleOccurrence(
        id: 'occ_backup_1',
        scheduleId: null,
        subjectId: 'subj_backup',
        subjectName: 'Môn Sao Lưu',
        classDate: '2026-11-21',
        startTime: '13:00',
        endTime: '15:30',
        createdAt: '2026-11-14T00:00:00Z',
        updatedAt: '2026-11-14T00:00:00Z',
      );
      await scheduleRepo.insertOccurrence(occurrence);

      // 2. Tạo bản sao lưu
      final backupData = await backupService.createBackupData();
      expect(backupData['data']['occurrences'], isNotNull);
      final occList = backupData['data']['occurrences'] as List;
      expect(occList.length, 1);
      expect(occList.first['subject_name'], 'Môn Sao Lưu');

      // 3. Xóa dữ liệu
      await scheduleRepo.clearAllOccurrences();
      final emptyList = await scheduleRepo.getAllOccurrences();
      expect(emptyList.isEmpty, isTrue);

      // 4. Khôi phục từ bản sao lưu
      await backupService.restoreBackup(backupData);
      final restoredList = await scheduleRepo.getAllOccurrences();
      expect(restoredList.length, 1);
      expect(restoredList.first.subjectName, 'Môn Sao Lưu');
      expect(restoredList.first.classDate, '2026-11-21');
    });
  });

  // =========================================================================
  // NHÓM E: IMAGE IMPORT UI & REVIEW FLOW
  // =========================================================================
  group('Nhóm E: Image Import UI & Review Flow', () {
    testWidgets('E1: UI displays review reason and disables save button when no valid items', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockAiService = MockTimetableAiService(
        resultToReturn: const AiTimetableResult(
          success: true,
          message: 'OK',
          weeks: [
            AiTimetableWeek(
              weekNumber: 1,
              classes: [
                AiTimetableClass(
                  subject: 'Môn Cần Kiểm Tra',
                  classDate: '2026-11-17',
                  weekday: 2,
                  startPeriod: 1,
                  endPeriod: 4,
                  startTime: null, // Thiếu giờ -> needsReview
                  endTime: null,
                  needsReview: true,
                  reviewReasons: ['Thiếu giờ học chính xác'],
                  isSelected: false,
                ),
              ],
            ),
          ],
          totalDetected: 1,
          validCount: 0,
          needsReviewCount: 1,
        ),
      );

      final mockCoordinator = ImageTimetableCoordinator(
        imagePicker: MockImagePicker(
          imageToReturn: TimetableImage(
            name: 'test_timetable.jpg',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImageTimetableImportDialog(
              subjects: const [],
              existingSchedules: const [],
              aiService: mockAiService,
              coordinator: mockCoordinator,
              onImport: ({required schedules, required newSubjects}) async {},
              onImportOccurrences: ({required occurrences, required newSubjects}) async {},
            ),
          ),
        ),
      );

      // Chọn ảnh
      final pickButton = find.byKey(const ValueKey('pick_timetable_gallery_button'));
      expect(pickButton, findsOneWidget);
      await tester.tap(pickButton);
      await tester.pumpAndSettle();

      // Bấm nút quét AI
      final scanButton = find.byKey(const ValueKey('start_ocr_recognition_button'));
      expect(scanButton, findsOneWidget);
      await tester.tap(scanButton);
      await tester.pumpAndSettle();

      // Kiểm tra: Hiển thị lý do cần xem xét
      expect(find.textContaining('Thiếu giờ học chính xác'), findsWidgets);

      // Nút lưu phải bị disable vì 0 lịch hợp lệ được chọn
      final saveButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('confirm_save_image_schedule_button')),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('E2: User edits item to add times and saves as occurrence', (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      List<ClassScheduleOccurrence>? savedOccurrences;

      final mockAiService = MockTimetableAiService(
        resultToReturn: const AiTimetableResult(
          success: true,
          message: 'OK',
          weeks: [
            AiTimetableWeek(
              weekNumber: 1,
              classes: [
                AiTimetableClass(
                  subject: 'Lập trình Flutter',
                  classDate: '2026-11-18',
                  weekday: 3,
                  startTime: '08:00',
                  endTime: '11:15',
                  teacher: 'TS. Nguyễn',
                  location: 'P.Lab 01',
                  confidence: 0.95,
                  needsReview: false,
                ),
              ],
            ),
          ],
          totalDetected: 1,
          validCount: 1,
        ),
      );

      final mockCoordinator = ImageTimetableCoordinator(
        imagePicker: MockImagePicker(
          imageToReturn: TimetableImage(
            name: 'test_timetable.jpg',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImageTimetableImportDialog(
              subjects: const [],
              existingSchedules: const [],
              aiService: mockAiService,
              coordinator: mockCoordinator,
              onImport: ({required schedules, required newSubjects}) async {},
              onImportOccurrences: ({required occurrences, required newSubjects}) async {
                savedOccurrences = occurrences;
              },
            ),
          ),
        ),
      );

      // Chọn ảnh và quét AI
      await tester.tap(find.byKey(const ValueKey('pick_timetable_gallery_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('start_ocr_recognition_button')));
      await tester.pumpAndSettle();

      // Kiểm tra: Môn học hợp lệ được nhận diện
      expect(find.text('Lập trình Flutter'), findsOneWidget);
      expect(find.textContaining('Tin cậy: 95%'), findsOneWidget);

      // Bấm nút Lưu
      final saveButtonFinder = find.byKey(const ValueKey('confirm_save_image_schedule_button'));
      expect(saveButtonFinder, findsOneWidget);
      await tester.tap(saveButtonFinder);
      await tester.pumpAndSettle();

      // Kiểm tra callback onImportOccurrences đã được gọi
      expect(savedOccurrences, isNotNull);
      expect(savedOccurrences!.length, 1);
      expect(savedOccurrences!.first.subjectName, 'Lập trình Flutter');
      expect(savedOccurrences!.first.classDate, '2026-11-18');
      expect(savedOccurrences!.first.startTime, '08:00');
      expect(savedOccurrences!.first.endTime, '11:15');
    });

    testWidgets('E3: Full Image Import Flow with periods 1-4, 3-4, 7-10, 9-10 and unconfigured 5-6', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mockAiService = MockTimetableAiService(
        resultToReturn: const AiTimetableResult(
          success: true,
          message: 'OK',
          weeks: [
            AiTimetableWeek(
              weekNumber: 1,
              classes: [
                AiTimetableClass(
                  subject: 'Toán cao cấp',
                  classDate: '2026-11-16',
                  weekday: 1,
                  startPeriod: 1,
                  endPeriod: 4,
                  confidence: 0.95,
                ),
                AiTimetableClass(
                  subject: 'Vật lý đại cương',
                  classDate: '2026-11-17',
                  weekday: 2,
                  startPeriod: 3,
                  endPeriod: 4,
                  confidence: 0.92,
                ),
                AiTimetableClass(
                  subject: 'Lập trình Web',
                  classDate: '2026-11-18',
                  weekday: 3,
                  startPeriod: 7,
                  endPeriod: 10,
                  confidence: 0.96,
                ),
                AiTimetableClass(
                  subject: 'Cơ sở dữ liệu',
                  classDate: '2026-11-19',
                  weekday: 4,
                  startPeriod: 9,
                  endPeriod: 10,
                  confidence: 0.90,
                ),
                AiTimetableClass(
                  subject: 'Môn Chưa Cấu Hình',
                  classDate: '2026-11-20',
                  weekday: 5,
                  startPeriod: 5,
                  endPeriod: 6,
                  confidence: 0.85,
                  needsReview: true,
                  reviewReasons: ['Tiết 5–6 chưa có cấu hình giờ chính thức'],
                ),
              ],
            ),
          ],
          totalDetected: 5,
          validCount: 4,
          needsReviewCount: 1,
        ),
      );

      final mockCoordinator = ImageTimetableCoordinator(
        imagePicker: MockImagePicker(
          imageToReturn: TimetableImage(
            name: 'test_periods.jpg',
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ImageTimetableImportDialog(
              subjects: const [],
              existingSchedules: const [],
              aiService: mockAiService,
              coordinator: mockCoordinator,
              onImport: ({required schedules, required newSubjects}) async {},
              onImportOccurrences: ({required occurrences, required newSubjects}) async {},
            ),
          ),
        ),
      );

      // Chọn ảnh và quét AI
      await tester.tap(find.byKey(const ValueKey('pick_timetable_gallery_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('start_ocr_recognition_button')));
      await tester.pumpAndSettle();

      // Kiểm tra các môn được hiển thị
      expect(find.text('Toán cao cấp'), findsOneWidget);
      expect(find.text('Vật lý đại cương'), findsOneWidget);
      expect(find.text('Lập trình Web'), findsOneWidget);
      expect(find.text('Cơ sở dữ liệu'), findsOneWidget);
      expect(find.text('Môn Chưa Cấu Hình'), findsOneWidget);

      // Kiểm tra hiển thị giờ quy đổi: 07:00-10:30, 09:00-10:30, 13:30-17:00, 15:30-17:00
      expect(find.textContaining('07:00 - 10:30'), findsOneWidget);
      expect(find.textContaining('09:00 - 10:30'), findsOneWidget);
      expect(find.textContaining('13:30 - 17:00'), findsOneWidget);
      expect(find.textContaining('15:30 - 17:00'), findsOneWidget);

      // Môn tiết 5-6 báo lý do cần xem xét / chưa cấu hình
      expect(find.textContaining('chưa có cấu hình giờ chính thức'), findsWidgets);
    });
  });
}

// =========================================================================
// MOCK IMPLEMENTATIONS FOR TESTS
// =========================================================================

class MockTimetableAiService implements TimetableAiService {
  final AiTimetableResult resultToReturn;

  MockTimetableAiService({required this.resultToReturn});

  @override
  Future<AiTimetableResult> analyzeTimetableImage({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    return resultToReturn;
  }

  @override
  Future<AiTimetableResult> analyzeTimetable({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    return resultToReturn;
  }
}

class MockImagePicker implements TimetableImagePicker {
  final TimetableImage? imageToReturn;

  MockImagePicker({this.imageToReturn});

  @override
  Future<TimetableImage?> pickImage({
    TimetableImageSource source = TimetableImageSource.gallery,
  }) async {
    return imageToReturn;
  }
}

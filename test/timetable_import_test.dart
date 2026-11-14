import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:exampilot/models/class_schedule.dart';
import 'package:exampilot/models/class_schedule_occurrence.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/timetable_import_model.dart';
import 'package:exampilot/services/class_period_time_mapper.dart';
import 'package:exampilot/services/class_schedule_resolver.dart';
import 'package:exampilot/services/timetable_import_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final List<Subject> sampleSubjects = [
    const Subject(
      id: 'subj_math',
      name: 'Toán cao cấp',
      description: 'Môn toán cao cấp',
    ),
    const Subject(
      id: 'subj_web',
      name: 'Lập trình Web',
      description: 'Môn lập trình web',
    ),
  ];

  final sampleSchedules = [
    const ClassSchedule(
      id: 'sched_tue_fixed',
      subjectId: 'subj_math',
      subjectName: 'Toán cao cấp',
      dayOfWeek: 2, // Thứ 3
      startTime: '07:00',
      endTime: '10:30',
      location: 'P.101',
      isActive: true,
    ),
  ];

  group('PHASE 6D.2.1 – Phần 1: Kiểm tra TimetableImportService & Quy đổi tiết học', () {
    test('1.1. Nhập CSV có khung giờ cụ thể: Bảo toàn giờ gốc từ tệp, không ghi đè', () {
      final csvString = '''
Tên môn,Thứ,Giờ bắt đầu,Giờ kết thúc,Phòng học,Ghi chú
Toán cao cấp,Thứ 2,08:00,09:30,A101,Lý thuyết
Lập trình Web,Thứ 4,14:00,16:30,B202,Thực hành
''';
      final bytes = Uint8List.fromList(utf8.encode(csvString));

      final result = TimetableImportService.parseFileBytes(
        bytes: bytes,
        fileName: 'timetable_clock_times.csv',
        existingSubjects: sampleSubjects,
        existingSchedules: sampleSchedules,
      );

      expect(result.fatalError, isNull);
      expect(result.items.length, 2);

      final item1 = result.items[0];
      expect(item1.rawSubjectName, 'Toán cao cấp');
      expect(item1.startTime, '08:00'); // Bảo toàn giờ gốc
      expect(item1.endTime, '09:30');
      expect(item1.dayOfWeek, 1);
      expect(item1.status, ImportItemStatus.valid);

      final item2 = result.items[1];
      expect(item2.rawSubjectName, 'Lập trình Web');
      expect(item2.startTime, '14:00');
      expect(item2.endTime, '16:30');
      expect(item2.dayOfWeek, 3);
      expect(item2.status, ImportItemStatus.valid);
    });

    test('1.2. Nhập CSV có cột Tiết học (1-4, 3-4, 7-10, 9-10): Quy đổi giờ chính xác theo bảng trường', () {
      final csvString = '''
Môn học,Thứ,Tiết học,Phòng
Toán cao cấp,Thứ 2,Tiết 1-4,A101
Cấu trúc dữ liệu,Thứ 3,3-4,A102
Lập trình Web,Thứ 4,Tiết 7-10,Lab 1
Mạng máy tính,Thứ 5,9-10,Lab 2
''';
      final bytes = Uint8List.fromList(utf8.encode(csvString));

      final result = TimetableImportService.parseFileBytes(
        bytes: bytes,
        fileName: 'timetable_periods.csv',
        existingSubjects: sampleSubjects,
        existingSchedules: [],
      );

      expect(result.fatalError, isNull);
      expect(result.items.length, 4);

      // Tiết 1-4: 07:00–10:30, 180 phút học thực tế
      final item1 = result.items[0];
      expect(item1.startPeriod, 1);
      expect(item1.endPeriod, 4);
      expect(item1.startTime, '07:00');
      expect(item1.endTime, '10:30');
      expect(item1.actualStudyMinutes, 180);
      expect(item1.periodRangeText, 'Tiết 1-4');
      expect(item1.status, ImportItemStatus.valid);

      // Tiết 3-4: 09:00–10:30, 90 phút học thực tế
      final item2 = result.items[1];
      expect(item2.startPeriod, 3);
      expect(item2.endPeriod, 4);
      expect(item2.startTime, '09:00');
      expect(item2.endTime, '10:30');
      expect(item2.actualStudyMinutes, 90);
      expect(item2.periodRangeText, 'Tiết 3-4');

      // Tiết 7-10: 13:30–17:00, 180 phút học thực tế
      final item3 = result.items[2];
      expect(item3.startPeriod, 7);
      expect(item3.endPeriod, 10);
      expect(item3.startTime, '13:30');
      expect(item3.endTime, '17:00');
      expect(item3.actualStudyMinutes, 180);
      expect(item3.periodRangeText, 'Tiết 7-10');

      // Tiết 9-10: 15:30–17:00, 90 phút học thực tế
      final item4 = result.items[3];
      expect(item4.startPeriod, 9);
      expect(item4.endPeriod, 10);
      expect(item4.startTime, '15:30');
      expect(item4.endTime, '17:00');
      expect(item4.actualStudyMinutes, 90);
      expect(item4.periodRangeText, 'Tiết 9-10');
    });

    test('1.3. Nhập CSV có tiết 5-6 (chưa cấu hình): Báo lỗi missing field, không tự bịa giờ', () {
      final csvString = '''
Môn học,Thứ,Tiết học,Phòng
Giáo dục thể chất,Thứ 6,Tiết 5-6,Sân vận động
''';
      final bytes = Uint8List.fromList(utf8.encode(csvString));

      final result = TimetableImportService.parseFileBytes(
        bytes: bytes,
        fileName: 'timetable_unconfigured.csv',
        existingSubjects: sampleSubjects,
        existingSchedules: [],
      );

      expect(result.fatalError, isNull);
      expect(result.items.length, 1);

      final item = result.items[0];
      expect(item.startPeriod, 5);
      expect(item.endPeriod, 6);
      expect(item.startTime, isNull);
      expect(item.endTime, isNull);
      expect(item.status, ImportItemStatus.errorMissingField);
      expect(item.errorMessage, contains('chưa có cấu hình giờ chính thức'));
      expect(item.isSelected, isFalse); // Bị loại khỏi lưu tự động
    });

    test('1.4. Phát hiện trùng lịch học với lịch cố định đã có trong cơ sở dữ liệu', () {
      // sampleSchedules có Toán cao cấp: Thứ 3, 07:00 - 10:30
      final csvString = '''
Môn học,Thứ,Tiết học,Phòng
Vật lý đại cương,Thứ 3,Tiết 1-4,B301
''';
      final bytes = Uint8List.fromList(utf8.encode(csvString));

      final result = TimetableImportService.parseFileBytes(
        bytes: bytes,
        fileName: 'timetable_conflict.csv',
        existingSubjects: sampleSubjects,
        existingSchedules: sampleSchedules,
      );

      expect(result.items.length, 1);
      final item = result.items[0];
      expect(item.status, ImportItemStatus.warningOverlap);
      expect(item.warningMessage, contains('Trùng khung giờ với môn "Toán cao cấp"'));
      expect(item.overlappingSchedule, isNotNull);
    });
  });

  group('PHASE 6D.2.1 – Phần 2: Bảo toàn dữ liệu lịch cũ và không thay đổi lịch sử học tập', () {
    test('2.1. Lịch cố định cũ đã có startTime/endTime được giữ nguyên', () {
      const oldSchedule = ClassSchedule(
        id: 'old_sched_1',
        subjectId: 'subj_math',
        subjectName: 'Toán cao cấp',
        dayOfWeek: 1,
        startTime: '07:30', // Giờ cũ do người dùng nhập trước đây
        endTime: '09:00',
        location: 'P.201',
      );

      expect(oldSchedule.startTime, '07:30');
      expect(oldSchedule.endTime, '09:00');
      expect(oldSchedule.startMinutesSinceMidnight, 7 * 60 + 30);
    });

    test('2.2. Lịch Occurrence cũ có giờ được bảo toàn, nếu chỉ có tiết hợp lệ thì map sang giờ mới', () {
      // Occurrence có sẵn giờ: bảo toàn
      const occWithTime = ClassScheduleOccurrence(
        id: 'occ_explicit',
        subjectId: 'subj_math',
        subjectName: 'Toán cao cấp',
        classDate: '2026-11-16',
        startTime: '08:15',
        endTime: '10:00',
        startPeriod: 1,
        endPeriod: 4,
        createdAt: '2026-11-14T00:00:00Z',
        updatedAt: '2026-11-14T00:00:00Z',
      );
      expect(occWithTime.startTime, '08:15');
      expect(occWithTime.endTime, '10:00');
      // actualStudyMinutes tính theo số tiết 1-4 = 180 phút
      expect(occWithTime.actualStudyMinutes, 180);

      // Occurrence được tạo chỉ với số tiết (missing time): dùng ClassPeriodTimeMapper
      final mapping = ClassPeriodTimeMapper.mapPeriodsToTime(7, 10);
      final occFromPeriod = ClassScheduleOccurrence(
        id: 'occ_from_period',
        subjectId: 'subj_web',
        subjectName: 'Lập trình Web',
        classDate: '2026-11-17',
        startTime: mapping!.startTime,
        endTime: mapping.endTime,
        startPeriod: 7,
        endPeriod: 10,
        createdAt: '2026-11-14T00:00:00Z',
        updatedAt: '2026-11-14T00:00:00Z',
      );
      expect(occFromPeriod.startTime, '13:30');
      expect(occFromPeriod.endTime, '17:00');
      expect(occFromPeriod.actualStudyMinutes, 180);
    });
  });

  group('PHASE 6D.2.1 – Phần 3: Kiểm tra Nhắc nhở & Báo thức (Alarms / Resolver Slots)', () {
    const resolver = ClassScheduleResolver();

    test('3.1. Slot lịch học phát sinh đúng giờ bắt đầu của các khoảng tiết', () {
      final monday = DateTime(2026, 11, 16); // Thứ 2 (weekday = 1)

      final fixedSchedules = [
        const ClassSchedule(
          id: 'sched_mon_1_4',
          subjectId: 'subj_math',
          subjectName: 'Toán (Tiết 1-4)',
          dayOfWeek: 1,
          startTime: '07:00',
          endTime: '10:30',
        ),
        const ClassSchedule(
          id: 'sched_mon_7_10',
          subjectId: 'subj_web',
          subjectName: 'Web (Tiết 7-10)',
          dayOfWeek: 1,
          startTime: '13:30',
          endTime: '17:00',
        ),
      ];

      final occurrences = [
        const ClassScheduleOccurrence(
          id: 'occ_mon_3_4',
          subjectId: 'subj_math',
          subjectName: 'Toán bổ trợ (Tiết 3-4)',
          classDate: '2026-11-16',
          startTime: '09:00',
          endTime: '10:30',
          startPeriod: 3,
          endPeriod: 4,
          createdAt: '2026-11-14T00:00:00Z',
          updatedAt: '2026-11-14T00:00:00Z',
        ),
        const ClassScheduleOccurrence(
          id: 'occ_mon_9_10',
          subjectId: 'subj_web',
          subjectName: 'Web chuyên đề (Tiết 9-10)',
          classDate: '2026-11-16',
          startTime: '15:30',
          endTime: '17:00',
          startPeriod: 9,
          endPeriod: 10,
          createdAt: '2026-11-14T00:00:00Z',
          updatedAt: '2026-11-14T00:00:00Z',
        ),
      ];

      final resolved = resolver.resolveForDate(
        fixedSchedules: fixedSchedules,
        occurrences: occurrences,
        date: monday,
      );

      // Kết quả phải gồm đủ 4 buổi học được sắp xếp theo thứ tự thời gian
      expect(resolved.length, 4);

      // 1. Tiết 1-4 bắt đầu lúc 07:00
      expect(resolved[0].startTime, '07:00');
      expect(resolved[0].startHour, 7);
      expect(resolved[0].startMinute, 0);

      // 2. Tiết 3-4 bắt đầu lúc 09:00
      expect(resolved[1].startTime, '09:00');
      expect(resolved[1].startHour, 9);
      expect(resolved[1].startMinute, 0);

      // 3. Tiết 7-10 bắt đầu lúc 13:30
      expect(resolved[2].startTime, '13:30');
      expect(resolved[2].startHour, 13);
      expect(resolved[2].startMinute, 30);

      // 4. Tiết 9-10 bắt đầu lúc 15:30
      expect(resolved[3].startTime, '15:30');
      expect(resolved[3].startHour, 15);
      expect(resolved[3].startMinute, 30);
    });

    test('3.2. Buổi học bị hủy (Cancellation) không phát sinh slot nhắc nhở', () {
      final tuesday = DateTime(2026, 11, 17); // Thứ 3 (weekday = 2)

      final fixedSchedules = [
        const ClassSchedule(
          id: 'sched_tue_cancelled',
          subjectId: 'subj_math',
          subjectName: 'Toán cao cấp',
          dayOfWeek: 2,
          startTime: '07:00',
          endTime: '10:30',
        ),
      ];

      // Bản ghi hủy buổi học Thứ 3 ngày 2026-11-17
      final occurrences = [
        const ClassScheduleOccurrence(
          id: 'occ_cancel_tue',
          scheduleId: 'sched_tue_cancelled',
          subjectId: 'subj_math',
          subjectName: 'Toán cao cấp',
          classDate: '2026-11-17',
          startTime: '07:00',
          endTime: '10:30',
          status: 'cancelled',
          createdAt: '2026-11-14T00:00:00Z',
          updatedAt: '2026-11-14T00:00:00Z',
        ),
      ];

      final resolved = resolver.resolveForDate(
        fixedSchedules: fixedSchedules,
        occurrences: occurrences,
        date: tuesday,
      );

      // Không có buổi học nào hoạt động
      expect(resolved.isEmpty, isTrue);

      // resolveSlots cũng không sinh slot nào
      final slots = resolver.resolveSlots(
        fixedSchedules: fixedSchedules,
        occurrences: occurrences,
        fromDate: tuesday.subtract(const Duration(hours: 1)),
        daysAhead: 1,
      );
      expect(slots.isEmpty, isTrue);
    });

    test('3.3. Buổi học Override cập nhật giờ bắt đầu chính xác và không tạo slot trùng lặp', () {
      final tuesday = DateTime(2026, 11, 17); // Thứ 3 (weekday = 2)

      final fixedSchedules = [
        const ClassSchedule(
          id: 'sched_tue_override',
          subjectId: 'subj_math',
          subjectName: 'Toán cao cấp',
          dayOfWeek: 2,
          startTime: '07:00',
          endTime: '10:30',
        ),
      ];

      // Đổi ca sang chiều (Tiết 7-10: 13:30 - 17:00) cho ngày này
      final occurrences = [
        const ClassScheduleOccurrence(
          id: 'occ_override_tue',
          scheduleId: 'sched_tue_override',
          subjectId: 'subj_math',
          subjectName: 'Toán cao cấp (Học bù ca chiều)',
          classDate: '2026-11-17',
          startTime: '13:30',
          endTime: '17:00',
          startPeriod: 7,
          endPeriod: 10,
          status: 'scheduled',
          createdAt: '2026-11-14T00:00:00Z',
          updatedAt: '2026-11-14T00:00:00Z',
        ),
      ];

      final resolved = resolver.resolveForDate(
        fixedSchedules: fixedSchedules,
        occurrences: occurrences,
        date: tuesday,
      );

      expect(resolved.length, 1);
      final item = resolved.first;
      expect(item.isOverride, isTrue);
      expect(item.startTime, '13:30');
      expect(item.startHour, 13);
      expect(item.startMinute, 30);
      expect(item.actualStudyMinutes, 180);
    });
  });

  group('PHASE 6D.2.1 – Phần 4: Kiểm tra Thời lượng học thực tế (actualStudyMinutes)', () {
    test('4.1. Tiết 1-4 và Tiết 7-10: Đúng 180 phút thực học, loại bỏ 30 phút nghỉ giải lao', () {
      final rMorning = ClassPeriodTimeMapper.mapPeriodsToTime(1, 4)!;
      expect(rMorning.actualStudyMinutes, 180);
      expect(rMorning.totalSpanMinutes, 210); // 07:00 đến 10:30 là 210 phút
      expect(rMorning.hasBreak, isTrue);
      expect(rMorning.breakMinutes, 30);

      final rAfternoon = ClassPeriodTimeMapper.mapPeriodsToTime(7, 10)!;
      expect(rAfternoon.actualStudyMinutes, 180);
      expect(rAfternoon.totalSpanMinutes, 210); // 13:30 đến 17:00 là 210 phút
      expect(rAfternoon.hasBreak, isTrue);
      expect(rAfternoon.breakMinutes, 30);
    });

    test('4.2. Tiết 1-3 và Tiết 7-9: Đúng 135 phút thực học, loại bỏ 30 phút nghỉ giải lao', () {
      final r1 = ClassPeriodTimeMapper.mapPeriodsToTime(1, 3)!;
      expect(r1.actualStudyMinutes, 135);
      expect(r1.totalSpanMinutes, 165); // 07:00 đến 09:45
      expect(r1.hasBreak, isTrue);

      final r2 = ClassPeriodTimeMapper.mapPeriodsToTime(7, 9)!;
      expect(r2.actualStudyMinutes, 135);
      expect(r2.totalSpanMinutes, 165); // 13:30 đến 16:15
      expect(r2.hasBreak, isTrue);
    });

    test('4.3. Tiết 3-4 và Tiết 9-10 không có giờ nghỉ ở giữa: Đúng 90 phút thực học', () {
      final r1 = ClassPeriodTimeMapper.mapPeriodsToTime(3, 4)!;
      expect(r1.actualStudyMinutes, 90);
      expect(r1.hasBreak, isFalse);
      expect(r1.breakMinutes, 0);

      final r2 = ClassPeriodTimeMapper.mapPeriodsToTime(9, 10)!;
      expect(r2.actualStudyMinutes, 90);
      expect(r2.hasBreak, isFalse);
      expect(r2.breakMinutes, 0);
    });
  });
}

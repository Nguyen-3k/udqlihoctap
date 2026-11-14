import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:exampilot/database/database_helper.dart';
import 'package:exampilot/models/class_schedule.dart';
import 'package:exampilot/models/subject.dart';
import 'package:exampilot/models/timetable_import_model.dart';
import 'package:exampilot/repositories/schedule_repository.dart';
import 'package:exampilot/services/image_timetable_importer.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late PatternBasedTimetableTextParser parser;

  setUp(() {
    parser = PatternBasedTimetableTextParser();
  });

  group('Nhóm 1: Bóc tách ô học phần và phân tích bảng thời khóa biểu đa tuần', () {
    test(
        'Test 1: Một ô học phần nhiều dòng được phân tích thành đúng 1 mục lịch học hoàn chỉnh',
        () {
      // Giả lập cấu trúc OCR của một ô trong ma trận: Thứ Hai (col 1), Buổi Sáng (row 1)
      final blocks = [
        // Tiêu đề các cột Thứ
        const OcrTextBlock(
          text: 'Thứ 2',
          left: 100,
          top: 50,
          right: 200,
          bottom: 80,
        ),
        const OcrTextBlock(
          text: 'Thứ 3',
          left: 210,
          top: 50,
          right: 310,
          bottom: 80,
        ),
        // Tiêu đề hàng buổi
        const OcrTextBlock(
          text: 'Sáng',
          left: 20,
          top: 100,
          right: 80,
          bottom: 140,
        ),
        // Ô học phần Thứ 2, Sáng (chứa nhiều dòng thông tin môn học, tiết, giảng viên, phòng, PM)
        const OcrTextBlock(
          text: 'HP: Thương mại điện tử\n(1-4)\nGV: Nguyễn Thị Như\nPhòng: 7.3.18\nPM: Google Meet, mã: meet.google.com/xyz',
          left: 105,
          top: 105,
          right: 195,
          bottom: 250,
        ),
      ];

      final results = parser.parseTextToSchedules(
        rawText: '',
        textBlocks: [],
        structuredBlocks: blocks,
        existingSubjects: [],
        existingSchedules: [],
      );

      // Phải gom lại thành đúng 1 mục lịch học, KHÔNG ĐƯỢC tách thành nhiều dòng riêng lẻ
      expect(results.length, equals(1));
      final item = results.first;

      expect(item.rawSubjectName, equals('Thương mại điện tử'));
      expect(item.matchedSubjectName, equals('Thương mại điện tử'));
      expect(item.dayOfWeek, equals(1)); // Thứ Hai
      expect(item.startTime, equals('07:00')); // Tiết 1-4 ca sáng: 07:00 - 10:30 (Phase 6D.2)
      expect(item.endTime, equals('10:30'));
      expect(item.teacher, equals('Nguyễn Thị Như'));
      expect(item.location, equals('7.3.18'));
      expect(item.notes, contains('Tiết 1-4'));
      expect(item.notes, contains('meet.google.com/xyz'));
      expect(item.hasError, isFalse);
      expect(item.isValidForSave, isTrue);
    });

    test(
        'Test 2: Ô học phần buổi chiều với Tiết (7-10) ánh xạ chính xác sang khung giờ 13:30 - 17:00',
        () {
      final blocks = [
        const OcrTextBlock(
          text: 'Thứ 4',
          left: 100,
          top: 50,
          right: 200,
          bottom: 80,
        ),
        const OcrTextBlock(
          text: 'Thứ 5',
          left: 210,
          top: 50,
          right: 310,
          bottom: 80,
        ),
        const OcrTextBlock(
          text: 'Chiều',
          left: 20,
          top: 100,
          right: 80,
          bottom: 140,
        ),
        const OcrTextBlock(
          text: 'HP: Lập trình Web\n(7-10)\nGV: ThS. Lê Văn Nam\nPhòng: 5.2.01',
          left: 105,
          top: 105,
          right: 195,
          bottom: 250,
        ),
      ];

      final results = parser.parseTextToSchedules(
        rawText: '',
        textBlocks: [],
        structuredBlocks: blocks,
        existingSubjects: [],
        existingSchedules: [],
      );

      expect(results.length, equals(1));
      final item = results.first;
      expect(item.dayOfWeek, equals(3)); // Thứ 4
      expect(item.startTime, equals('13:30'));
      expect(item.endTime, equals('17:00'));
      expect(item.teacher, equals('ThS. Lê Văn Nam'));
      expect(item.location, equals('5.2.01'));
      expect(item.notes, contains('Tiết 7-10'));
      expect(item.isValidForSave, isTrue);
    });

    test(
        'Test 3: Phân vùng bảng thời khóa biểu đa tuần xếp chồng không làm lẫn lộn các tuần hoặc nhân bản',
        () {
      // Giả lập 2 bảng tuần xếp chồng theo chiều dọc:
      // Tuần 1: Header Y = 100
      // Tuần 2: Header Y = 600
      final blocks = [
        // Bảng Tuần 1
        const OcrTextBlock(
          text: 'Thứ 2',
          left: 100,
          top: 100,
          right: 200,
          bottom: 130,
        ),
        const OcrTextBlock(
          text: 'Thứ 3',
          left: 210,
          top: 100,
          right: 310,
          bottom: 130,
        ),
        const OcrTextBlock(
          text: 'Sáng',
          left: 20,
          top: 150,
          right: 80,
          bottom: 190,
        ),
        const OcrTextBlock(
          text: 'HP: Cấu trúc dữ liệu\n(1-4)\nGV: TS. Hoàng\nPhòng: 101',
          left: 105,
          top: 155,
          right: 195,
          bottom: 250,
        ),

        // Bảng Tuần 2
        const OcrTextBlock(
          text: 'Thứ 2',
          left: 100,
          top: 600,
          right: 200,
          bottom: 630,
        ),
        const OcrTextBlock(
          text: 'Thứ 3',
          left: 210,
          top: 600,
          right: 310,
          bottom: 630,
        ),
        const OcrTextBlock(
          text: 'Chiều',
          left: 20,
          top: 650,
          right: 80,
          bottom: 690,
        ),
        const OcrTextBlock(
          text: 'HP: Hệ điều hành\n(7-10)\nGV: TS. Quân\nPhòng: 202',
          left: 215,
          top: 655,
          right: 305,
          bottom: 750,
        ),
      ];

      final results = parser.parseTextToSchedules(
        rawText: '',
        textBlocks: [],
        structuredBlocks: blocks,
        existingSubjects: [],
        existingSchedules: [],
      );

      // Cả 2 môn từ 2 bảng tuần phải được phân vùng độc lập và trích xuất đúng
      expect(results.length, equals(2));

      final ctdl = results.firstWhere((s) => s.matchedSubjectName == 'Cấu trúc dữ liệu');
      expect(ctdl.dayOfWeek, equals(1)); // Thứ 2
      expect(ctdl.startTime, equals('07:00'));
      expect(ctdl.endTime, equals('10:30'));

      final hdh = results.firstWhere((s) => s.matchedSubjectName == 'Hệ điều hành');
      expect(hdh.dayOfWeek, equals(2)); // Thứ 3
      expect(hdh.startTime, equals('13:30'));
      expect(hdh.endTime, equals('17:00'));
    });

    test(
        'Test 4: Lọc sạch các khối tiêu đề bảng và từ nhiễu không bao giờ biến thành lịch học',
        () {
      final noiseBlocks = [
        const OcrTextBlock(text: 'Thứ', left: 10, top: 10, right: 50, bottom: 30),
        const OcrTextBlock(text: 'Buổi', left: 10, top: 40, right: 50, bottom: 60),
        const OcrTextBlock(text: 'Sáng', left: 10, top: 70, right: 50, bottom: 90),
        const OcrTextBlock(text: 'Chiều', left: 10, top: 100, right: 50, bottom: 120),
        const OcrTextBlock(text: 'Tối', left: 10, top: 130, right: 50, bottom: 150),
        const OcrTextBlock(text: 'Từ ngày 04/09 đến 10/09', left: 10, top: 160, right: 200, bottom: 180),
        const OcrTextBlock(text: 'STT', left: 10, top: 190, right: 50, bottom: 210),
        const OcrTextBlock(text: 'Mã HP', left: 10, top: 220, right: 50, bottom: 240),
        const OcrTextBlock(text: 'Thời khóa biểu tuần 01', left: 10, top: 250, right: 200, bottom: 270),
      ];

      final results = parser.parseTextToSchedules(
        rawText: 'Thứ\nBuổi\nSáng\nChiều\nTối\nTừ ngày 04/09 đến 10/09\nSTT\nMã HP',
        textBlocks: noiseBlocks.map((b) => b.text).toList(),
        structuredBlocks: noiseBlocks,
        existingSubjects: [],
        existingSchedules: [],
      );

      // Không có bất kỳ mục nào được tạo từ tiêu đề bảng
      expect(results, isEmpty);
    });
  });

  group('Nhóm 2: Chống nhận diện nhầm thứ & kiểm tra hợp lệ giờ/thứ nghiêm ngặt', () {
    test(
        'Test 5: Tên môn chứa các chuỗi con như "CN", "Thu", "Mon" không bị nhận diện sai thứ',
        () {
      // 3 môn học dễ bị false positive nếu dùng contains('cn') hoặc contains('thu')
      const text = '''
HP: Công nghệ thông tin
(1-3)
GV: ThS. Nam
Phòng: Lab 1

HP: Thuế nhà nước
(1-3)
GV: ThS. Mai
Phòng: 302

HP: Môn học đại cương
(1-3)
GV: ThS. Long
Phòng: 303
''';

      final results = parser.parseTextToSchedules(
        rawText: text,
        textBlocks: text.split('\n\n'),
        structuredBlocks: [],
        existingSubjects: [],
        existingSchedules: [],
      );

      expect(results.length, equals(3));

      // Do trong text không ghi Thứ mấy, dayOfWeek phải là null (chờ người dùng chọn)
      // TUYỆT ĐỐI KHÔNG ĐƯỢC nhận diện "Công nghệ" thành Chủ nhật (CN/7),
      // "Thuế" thành Thứ Năm (Thu/4), hay "Môn học" thành Thứ Hai (Mon/1)!
      final cntt = results.firstWhere((s) => s.matchedSubjectName == 'Công nghệ thông tin');
      expect(cntt.dayOfWeek, isNull);
      expect(cntt.status, equals(ImportItemStatus.errorMissingField));

      final thue = results.firstWhere((s) => s.matchedSubjectName == 'Thuế nhà nước');
      expect(thue.dayOfWeek, isNull);
      expect(thue.status, equals(ImportItemStatus.errorMissingField));

      final mon = results.firstWhere((s) => s.matchedSubjectName == 'Môn học đại cương');
      expect(mon.dayOfWeek, isNull);
      expect(mon.status, equals(ImportItemStatus.errorMissingField));
    });

    test(
        'Test 6: Giờ không hợp lệ (08:88, 25:00, -1:00) hoặc giờ bắt đầu >= giờ kết thúc bị chặn và ném lỗi',
        () {
      expect(isValidTimeString('08:88'), isFalse);
      expect(isValidTimeString('25:00'), isFalse);
      expect(isValidTimeString('-1:00'), isFalse);
      expect(isValidTimeString('08:30'), isTrue);

      // Trường hợp giờ bắt đầu >= kết thúc
      final itemInvalidRange = ImportedScheduleItem(
        rowIndex: 1,
        rawSubjectName: 'Toán',
        matchedSubjectName: 'Toán',
        dayOfWeek: 2,
        startTime: '10:00',
        endTime: '08:00', // Đảo ngược giờ
        status: ImportItemStatus.errorInvalidTime,
      );

      expect(itemInvalidRange.isValidForSave, isFalse);
      expect(
        () => itemInvalidRange.toClassSchedule(targetSubjectId: 'sub1'),
        throwsA(isA<StateError>()),
      );

      // Trường hợp giờ chứa phút không hợp lệ
      final itemInvalidMinute = ImportedScheduleItem(
        rowIndex: 2,
        rawSubjectName: 'Lý',
        matchedSubjectName: 'Lý',
        dayOfWeek: 3,
        startTime: '08:88',
        endTime: '09:30',
        status: ImportItemStatus.valid, // Giả sử status chưa kịp set
      );
      expect(itemInvalidMinute.isValidForSave, isFalse);
      expect(
        () => itemInvalidMinute.toClassSchedule(targetSubjectId: 'sub2'),
        throwsA(isA<StateError>()),
      );
    });

    test(
        'Test 7: Thiếu trường bắt buộc (thiếu thứ hoặc thiếu giờ) chặn lưu toClassSchedule',
        () {
      final missingDayItem = ImportedScheduleItem(
        rowIndex: 1,
        rawSubjectName: 'Hóa',
        matchedSubjectName: 'Hóa',
        dayOfWeek: null, // Thiếu thứ
        startTime: '08:00',
        endTime: '09:30',
        status: ImportItemStatus.errorMissingField,
      );
      expect(missingDayItem.hasError, isTrue);
      expect(missingDayItem.isValidForSave, isFalse);
      expect(
        () => missingDayItem.toClassSchedule(targetSubjectId: 'sub1'),
        throwsA(isA<StateError>()),
      );

      final missingTimeItem = ImportedScheduleItem(
        rowIndex: 2,
        rawSubjectName: 'Sinh',
        matchedSubjectName: 'Sinh',
        dayOfWeek: 2,
        startTime: null, // Thiếu giờ
        endTime: null,
        status: ImportItemStatus.errorMissingField,
      );
      expect(missingTimeItem.hasError, isTrue);
      expect(missingTimeItem.isValidForSave, isFalse);
      expect(
        () => missingTimeItem.toClassSchedule(targetSubjectId: 'sub2'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('Nhóm 3: Phát hiện xung đột trùng lịch học', () {
    test(
        'Test 8: Phát hiện xung đột trùng giờ giữa 2 môn trong cùng một đợt nhập (Intra-batch conflict)',
        () {
      // 2 môn cùng Thứ 3 (dayOfWeek = 2), môn 1 học 08:00 - 10:00, môn 2 học 09:00 - 11:00 (chồng lấn 09:00-10:00)
      final blocks = [
        const OcrTextBlock(text: 'Thứ 3', left: 100, top: 50, right: 200, bottom: 80),
        const OcrTextBlock(text: 'Thứ 4', left: 210, top: 50, right: 310, bottom: 80),
        const OcrTextBlock(
          text: 'HP: Môn A\n08:00 - 10:00\nGV: GV A',
          left: 105,
          top: 100,
          right: 195,
          bottom: 180,
        ),
        const OcrTextBlock(
          text: 'HP: Môn B\n09:00 - 11:00\nGV: GV B',
          left: 105,
          top: 200,
          right: 195,
          bottom: 280,
        ),
      ];

      final results = parser.parseTextToSchedules(
        rawText: '',
        textBlocks: [],
        structuredBlocks: blocks,
        existingSubjects: [],
        existingSchedules: [],
      );

      expect(results.length, equals(2));
      // Cả 2 môn đều phải được cảnh báo trùng lịch trong cùng file
      expect(results[0].status, equals(ImportItemStatus.warningOverlap));
      expect(results[0].warningMessage, contains('Trùng giờ với Môn B'));
      expect(results[1].status, equals(ImportItemStatus.warningOverlap));
      expect(results[1].warningMessage, contains('Trùng giờ với Môn A'));
    });

    test(
        'Test 9: Phát hiện xung đột trùng giờ với cơ sở dữ liệu hiện có (existingSchedules)',
        () {
      const existing = ClassSchedule(
        id: 'sched_exist_1',
        subjectId: 'sub_exist',
        subjectName: 'Môn Đã Có',
        dayOfWeek: 4, // Thứ Năm
        startTime: '13:00',
        endTime: '15:00',
        location: '301',
        isActive: true,
      );

      final blocks = [
        const OcrTextBlock(text: 'Thứ 5', left: 100, top: 50, right: 200, bottom: 80),
        const OcrTextBlock(text: 'Thứ 6', left: 210, top: 50, right: 310, bottom: 80),
        const OcrTextBlock(
          text: 'HP: Môn Mới Nhập\n14:00 - 16:00\nGV: ThS Tuấn',
          left: 105,
          top: 100,
          right: 195,
          bottom: 180,
        ),
      ];

      final results = parser.parseTextToSchedules(
        rawText: '',
        textBlocks: [],
        structuredBlocks: blocks,
        existingSubjects: [],
        existingSchedules: [existing],
      );

      expect(results.length, equals(1));
      final item = results.first;
      expect(item.status, equals(ImportItemStatus.warningOverlap));
      expect(item.warningMessage, contains('Môn Đã Có'));
      expect(item.overlappingSchedule?.id, equals('sched_exist_1'));
    });
  });

  group('Nhóm 4: Tính toàn vẹn giao dịch và chỉnh sửa thủ công', () {
    test(
        'Test 10: Rollback giao dịch trong SQLite khi lưu hàng loạt môn học và lịch học thất bại',
        () async {
      final db = await openDatabase(
        inMemoryDatabasePath,
        version: DatabaseHelper.databaseVersion,
        onCreate: (d, v) async {
          await d.execute('''
            CREATE TABLE IF NOT EXISTS ${DatabaseHelper.tableSubjects} (
              ${DatabaseHelper.columnSubjectId} TEXT PRIMARY KEY,
              ${DatabaseHelper.columnSubjectName} TEXT NOT NULL,
              ${DatabaseHelper.columnSubjectDescription} TEXT NOT NULL,
              ${DatabaseHelper.columnSubjectIcon} INTEGER NOT NULL,
              ${DatabaseHelper.columnSubjectColor} INTEGER NOT NULL
            )
          ''');
          await DatabaseHelper.createClassSchedulesTable(d);
        },
      );

      final dbHelper = DatabaseHelper.instance;
      dbHelper.setDatabaseForTesting(db);
      final repo = ScheduleRepository(dbHelper: dbHelper);

      final newSubject = const Subject(
        id: 'subj_test_rollback',
        name: 'Môn Giao Dịch',
        description: 'Test Rollback',
      );

      // Thử thực thi giao dịch có lỗi: chèn môn học trước, sau đó chèn bảng không tồn tại
      expect(
        () async {
          final database = await dbHelper.database;
          await database.transaction((txn) async {
            await txn.insert(
              DatabaseHelper.tableSubjects,
              newSubject.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            // Gây lỗi để kích hoạt Rollback
            await txn.rawInsert('INSERT INTO table_not_exists VALUES (1)');
          });
        },
        throwsA(isA<Exception>()),
      );

      // Kiểm tra tính toàn vẹn: Bảng subjects KHÔNG được lưu newSubject do đã rollback
      final subjects = await db.query(
        DatabaseHelper.tableSubjects,
        where: '${DatabaseHelper.columnSubjectId} = ?',
        whereArgs: [newSubject.id],
      );
      expect(subjects, isEmpty);

      // Bây giờ kiểm tra importSchedulesWithSubjectsBatch khi dữ liệu hợp lệ
      const validSchedule = ClassSchedule(
        id: 'sched_tx_success_1',
        subjectId: 'subj_test_rollback',
        subjectName: 'Môn Giao Dịch',
        dayOfWeek: 2,
        startTime: '08:00',
        endTime: '10:00',
      );

      await repo.importSchedulesWithSubjectsBatch(
        schedules: [validSchedule],
        newSubjects: [newSubject],
      );

      final subjectsAfter = await db.query(
        DatabaseHelper.tableSubjects,
        where: '${DatabaseHelper.columnSubjectId} = ?',
        whereArgs: [newSubject.id],
      );
      expect(subjectsAfter.length, equals(1));

      final schedulesAfter = await db.query(
        DatabaseHelper.tableClassSchedules,
        where: '${DatabaseHelper.columnScheduleId} = ?',
        whereArgs: [validSchedule.id],
      );
      expect(schedulesAfter.length, equals(1));

      await db.close();
      dbHelper.setDatabaseForTesting(null);
    });

    test(
        'Test 11: Người dùng chỉnh sửa thủ công một mục thiếu trường (errorMissingField) thành hợp lệ',
        () {
      // Mục ban đầu OCR không nhận ra thứ và giờ
      final rawItem = ImportedScheduleItem(
        rowIndex: 1,
        rawSubjectName: 'Xác suất thống kê',
        matchedSubjectName: 'Xác suất thống kê',
        dayOfWeek: null,
        startTime: null,
        endTime: null,
        status: ImportItemStatus.errorMissingField,
        errorMessage: 'Chưa có giờ học',
      );

      expect(rawItem.isValidForSave, isFalse);

      // Người dùng chỉnh sửa chọn Thứ 5 lúc 08:00 - 10:15
      final editedItem = rawItem.copyWith(
        dayOfWeek: 4,
        startTime: '08:00',
        endTime: '10:15',
        status: ImportItemStatus.valid,
        errorMessage: null,
      );

      expect(editedItem.hasError, isFalse);
      expect(editedItem.isValidForSave, isTrue);

      // Chuyển đổi thành ClassSchedule thành công
      final schedule = editedItem.toClassSchedule(targetSubjectId: 'sub_xstk');
      expect(schedule.subjectName, equals('Xác suất thống kê'));
      expect(schedule.dayOfWeek, equals(4));
      expect(schedule.startTime, equals('08:00'));
      expect(schedule.endTime, equals('10:15'));
      expect(schedule.subjectId, equals('sub_xstk'));
    });

    test(
        'Test 12: Xử lý an toàn khi OCR trả về rỗng hoặc văn bản rác, không gây crash ứng dụng',
        () {
      // Khi toàn bộ input rỗng
      final resEmpty = parser.parseTextToSchedules(
        rawText: '',
        textBlocks: [],
        structuredBlocks: [],
        existingSubjects: [],
        existingSchedules: [],
      );
      expect(resEmpty, isEmpty);

      // Khi input chứa toàn ký tự ngẫu nhiên / ký tự vô nghĩa không có cấu trúc
      final resGarbage = parser.parseTextToSchedules(
        rawText: ';;; /// --- === !!! 12345 @@#\$%^',
        textBlocks: [';;; ///', '--- === !!!', '12345 @@#\$%^'],
        structuredBlocks: [],
        existingSubjects: [],
        existingSchedules: [],
      );
      expect(resGarbage, isEmpty);
    });
  });
}

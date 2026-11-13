import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../models/class_schedule.dart';
import '../models/subject.dart';
import '../models/timetable_import_model.dart';

/// Dịch vụ đọc, phân tích và chuẩn hóa thời khóa biểu từ tệp CSV và Excel (.xlsx)
class TimetableImportService {
  TimetableImportService._();

  /// Phân tích tệp thời khóa biểu từ dữ liệu nhị phân (Uint8List)
  static TimetableParseResult parseFileBytes({
    required Uint8List bytes,
    required String fileName,
    required List<Subject> existingSubjects,
    required List<ClassSchedule> existingSchedules,
  }) {
    if (bytes.isEmpty) {
      return TimetableParseResult(
        fileName: fileName,
        totalRowsRead: 0,
        items: const [],
        fatalError: 'Tệp được chọn có kích thước rỗng (0 bytes).',
      );
    }

    final lowerName = fileName.toLowerCase();
    List<List<dynamic>> rawRows = [];

    try {
      if (lowerName.endsWith('.csv')) {
        rawRows = _parseCsvRows(bytes);
      } else if (lowerName.endsWith('.xlsx')) {
        rawRows = _parseExcelRows(bytes);
      } else {
        return TimetableParseResult(
          fileName: fileName,
          totalRowsRead: 0,
          items: const [],
          fatalError: 'Định dạng tệp không được hỗ trợ. Vui lòng chọn tệp .xlsx hoặc .csv.',
        );
      }
    } catch (e) {
      return TimetableParseResult(
        fileName: fileName,
        totalRowsRead: 0,
        items: const [],
        fatalError: 'Không thể đọc nội dung tệp: ${e.toString()}',
      );
    }

    if (rawRows.isEmpty) {
      return TimetableParseResult(
        fileName: fileName,
        totalRowsRead: 0,
        items: const [],
        fatalError: 'Tệp không chứa dữ liệu hoặc bảng tính bị trống.',
      );
    }

    // Xác định dòng tiêu đề (header)
    final headerDetection = _detectHeaderRow(rawRows);
    if (headerDetection == null) {
      return TimetableParseResult(
        fileName: fileName,
        totalRowsRead: rawRows.length,
        items: const [],
        fatalError:
            'Không tìm thấy tiêu đề cột phù hợp. Tệp cần chứa tối thiểu các cột: '
            'Tên môn học, Thứ trong tuần, và Giờ bắt đầu / Giờ kết thúc.',
      );
    }

    final headerIndex = headerDetection.rowIndex;
    final colMap = headerDetection.columnIndices;
    final items = <ImportedScheduleItem>[];
    final warnings = <String>[];

    for (int i = headerIndex + 1; i < rawRows.length; i++) {
      final row = rawRows[i];
      if (_isRowEmpty(row)) continue;

      final rowIndex = i + 1; // 1-based index cho người dùng dễ đọc
      final rawSubject = _extractCellValue(row, colMap.subjectCol)?.trim() ?? '';
      final rawDay = _extractCellValue(row, colMap.dayCol);
      var rawStart = _extractCellValue(row, colMap.startCol);
      var rawEnd = _extractCellValue(row, colMap.endCol);
      final location = _extractCellValue(row, colMap.locationCol)?.trim() ?? '';
      final notes = _extractCellValue(row, colMap.notesCol)?.trim() ?? '';

      // Trường hợp cột thời gian gộp chung (ví dụ "08:00 - 09:30")
      if ((rawStart == null || rawStart.isEmpty) && colMap.combinedTimeCol != null) {
        final combined = _extractCellValue(row, colMap.combinedTimeCol);
        if (combined != null && combined.isNotEmpty) {
          final splitTimes = _splitCombinedTime(combined);
          rawStart = splitTimes.$1;
          rawEnd = splitTimes.$2;
        }
      }

      final parsedDay = _parseDayOfWeek(rawDay);
      final parsedStart = _parseTime(rawStart);
      final parsedEnd = _parseTime(rawEnd);

      String? errorMsg;
      ImportItemStatus status = ImportItemStatus.valid;

      if (rawSubject.isEmpty) {
        status = ImportItemStatus.errorMissingField;
        errorMsg = 'Thiếu tên môn học';
      } else if (parsedDay == null) {
        status = ImportItemStatus.errorMissingField;
        errorMsg = 'Thứ không hợp lệ hoặc bị thiếu ("$rawDay")';
      } else if (parsedStart == null) {
        status = ImportItemStatus.errorMissingField;
        errorMsg = 'Giờ bắt đầu không hợp lệ hoặc bị thiếu ("$rawStart")';
      } else if (parsedEnd == null) {
        status = ImportItemStatus.errorMissingField;
        errorMsg = 'Giờ kết thúc không hợp lệ hoặc bị thiếu ("$rawEnd")';
      } else if (!_isStartTimeBeforeEndTime(parsedStart, parsedEnd)) {
        status = ImportItemStatus.errorInvalidTime;
        errorMsg = 'Giờ bắt đầu ($parsedStart) phải trước giờ kết thúc ($parsedEnd)';
      }

      // Khớp với môn học hiện có
      String? matchedId;
      String matchedName = rawSubject;
      bool isNewSubject = false;

      if (rawSubject.isNotEmpty) {
        final matchedSub = _findMatchingSubject(rawSubject, existingSubjects);
        if (matchedSub != null) {
          matchedId = matchedSub.id;
          matchedName = matchedSub.name;
        } else {
          isNewSubject = true;
          if (status == ImportItemStatus.valid) {
            status = ImportItemStatus.newSubject;
          }
        }
      }

      // Kiểm tra trùng giờ với lịch hiện có
      ClassSchedule? overlapping;
      String? warningMsg;

      if (status == ImportItemStatus.valid || status == ImportItemStatus.newSubject) {
        if (parsedDay != null && parsedStart != null && parsedEnd != null) {
          overlapping = _findOverlappingSchedule(
            dayOfWeek: parsedDay,
            startTime: parsedStart,
            endTime: parsedEnd,
            existingSchedules: existingSchedules,
          );
          if (overlapping != null) {
            status = ImportItemStatus.warningOverlap;
            warningMsg =
                'Trùng khung giờ với môn "${overlapping.subjectName}" '
                '(${overlapping.dayOfWeekText}, ${overlapping.timeRangeText})';
          }
        }
      }

      items.add(
        ImportedScheduleItem(
          rowIndex: rowIndex,
          rawSubjectName: rawSubject,
          matchedSubjectId: matchedId,
          matchedSubjectName: matchedName,
          isNewSubject: isNewSubject,
          dayOfWeek: parsedDay,
          startTime: parsedStart,
          endTime: parsedEnd,
          location: location,
          notes: notes,
          isSelected: !status.hasError,
          status: status,
          errorMessage: errorMsg,
          warningMessage: warningMsg,
          overlappingSchedule: overlapping,
        ),
      );
    }

    if (items.isEmpty) {
      return TimetableParseResult(
        fileName: fileName,
        totalRowsRead: rawRows.length,
        items: const [],
        fatalError: 'Không tìm thấy dòng dữ liệu nào sau dòng tiêu đề.',
      );
    }

    return TimetableParseResult(
      fileName: fileName,
      totalRowsRead: rawRows.length,
      items: items,
      warnings: warnings,
    );
  }

  // --- TRÌNH ĐỌC FILE CSV ---

  static List<List<dynamic>> _parseCsvRows(Uint8List bytes) {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      try {
        content = latin1.decode(bytes);
      } catch (_) {
        content = String.fromCharCodes(bytes);
      }
    }

    if (content.startsWith('\uFEFF')) {
      content = content.substring(1);
    }

    final firstLine = content.split(RegExp(r'\r\n|\n|\r')).firstWhere(
      (line) => line.trim().isNotEmpty,
      orElse: () => '',
    );
    final commaCount = ','.allMatches(firstLine).length;
    final semicolonCount = ';'.allMatches(firstLine).length;
    final tabCount = '\t'.allMatches(firstLine).length;

    String delimiter = ',';
    if (semicolonCount > commaCount && semicolonCount > tabCount) {
      delimiter = ';';
    } else if (tabCount > commaCount && tabCount > semicolonCount) {
      delimiter = '\t';
    }

    try {
      final decoder = CsvDecoder(
        fieldDelimiter: delimiter,
        skipEmptyLines: false,
        dynamicTyping: false,
      );
      final rows = decoder.convert(content);
      if (rows.isNotEmpty) return rows;
    } catch (_) {}

    try {
      return const CsvDecoder(
        skipEmptyLines: false,
        dynamicTyping: false,
      ).convert(content);
    } catch (_) {
      return [];
    }
  }

  // --- TRÌNH ĐỌC FILE EXCEL (.xlsx) ---

  static List<List<dynamic>> _parseExcelRows(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return [];

    // Lấy bảng tính đầu tiên có dữ liệu
    Sheet? targetSheet;
    for (final sheet in excel.tables.values) {
      if (sheet.rows.isNotEmpty) {
        targetSheet = sheet;
        break;
      }
    }

    if (targetSheet == null) return [];

    final result = <List<dynamic>>[];
    for (final row in targetSheet.rows) {
      final rowValues = <dynamic>[];
      for (final cell in row) {
        if (cell == null) {
          rowValues.add('');
          continue;
        }
        final val = cell.value;
        if (val == null) {
          rowValues.add('');
        } else if (val is TextCellValue) {
          rowValues.add(val.value.text ?? '');
        } else if (val is IntCellValue) {
          rowValues.add(val.value.toString());
        } else if (val is DoubleCellValue) {
          rowValues.add(val.value.toString());
        } else if (val is TimeCellValue) {
          final h = val.hour.toString().padLeft(2, '0');
          final m = val.minute.toString().padLeft(2, '0');
          rowValues.add('$h:$m');
        } else if (val is DateTimeCellValue) {
          final h = val.hour.toString().padLeft(2, '0');
          final m = val.minute.toString().padLeft(2, '0');
          rowValues.add('$h:$m');
        } else if (val is DateCellValue) {
          rowValues.add('${val.year}-${val.month}-${val.day}');
        } else {
          rowValues.add(val.toString());
        }
      }
      result.add(rowValues);
    }
    return result;
  }

  // --- NHẬN DIỆN CỘT TIÊU ĐỀ ---

  static _HeaderDetectionResult? _detectHeaderRow(List<List<dynamic>> rows) {
    // Quét 8 dòng đầu tiên để tìm dòng tiêu đề
    final maxScan = rows.length < 8 ? rows.length : 8;

    for (int r = 0; r < maxScan; r++) {
      final row = rows[r];
      int? subjectCol;
      int? dayCol;
      int? startCol;
      int? endCol;
      int? combinedTimeCol;
      int? locationCol;
      int? notesCol;

      for (int c = 0; c < row.length; c++) {
        final cellText = row[c]?.toString().trim().toLowerCase() ?? '';
        if (cellText.isEmpty) continue;

        if (_isSubjectHeader(cellText)) {
          subjectCol ??= c;
        } else if (_isDayHeader(cellText)) {
          dayCol ??= c;
        } else if (_isStartTimeHeader(cellText)) {
          startCol ??= c;
        } else if (_isEndTimeHeader(cellText)) {
          endCol ??= c;
        } else if (_isCombinedTimeHeader(cellText)) {
          combinedTimeCol ??= c;
        } else if (_isLocationHeader(cellText)) {
          locationCol ??= c;
        } else if (_isNotesHeader(cellText)) {
          notesCol ??= c;
        }
      }

      // Dòng được xem là header nếu có tối thiểu Môn + Thứ + (Giờ bắt đầu hoặc Giờ gộp)
      final hasTime = (startCol != null) || (combinedTimeCol != null);
      if (subjectCol != null && dayCol != null && hasTime) {
        return _HeaderDetectionResult(
          rowIndex: r,
          columnIndices: _ColumnIndices(
            subjectCol: subjectCol,
            dayCol: dayCol,
            startCol: startCol,
            endCol: endCol,
            combinedTimeCol: combinedTimeCol,
            locationCol: locationCol,
            notesCol: notesCol,
          ),
        );
      }
    }
    return null;
  }

  static bool _isSubjectHeader(String s) {
    return s.contains('môn') ||
        s.contains('học phần') ||
        s.contains('subject') ||
        s.contains('course') ||
        s == 'tên';
  }

  static bool _isDayHeader(String s) {
    return s == 'thứ' ||
        s.contains('thứ trong tuần') ||
        s == 'thứ học' ||
        s == 'ngày' ||
        s == 'day' ||
        s == 'weekday';
  }

  static bool _isStartTimeHeader(String s) {
    return s.contains('bắt đầu') ||
        s.contains('start') ||
        s.contains('từ giờ') ||
        s.contains('giờ vào') ||
        s == 'tg bd';
  }

  static bool _isEndTimeHeader(String s) {
    return s.contains('kết thúc') ||
        s.contains('end') ||
        s.contains('đến giờ') ||
        s.contains('giờ ra') ||
        s == 'tg kt';
  }

  static bool _isCombinedTimeHeader(String s) {
    return s.contains('giờ học') ||
        s.contains('khung giờ') ||
        s.contains('thời gian') ||
        s.contains('tiết học') ||
        s == 'time';
  }

  static bool _isLocationHeader(String s) {
    return s.contains('phòng') ||
        s.contains('địa điểm') ||
        s.contains('room') ||
        s.contains('location') ||
        s.contains('lớp học') ||
        s.contains('giảng đường');
  }

  static bool _isNotesHeader(String s) {
    return s.contains('ghi chú') ||
        s.contains('note') ||
        s.contains('mô tả') ||
        s.contains('giảng viên') ||
        s == 'gv';
  }

  // --- CHUẨN HÓA DỮ LIỆU ---

  /// Chuẩn hóa thứ trong tuần về số nguyên từ 1 (Thứ Hai) đến 7 (Chủ Nhật)
  static int? _parseDayOfWeek(dynamic raw) {
    if (raw == null) return null;
    final str = raw.toString().trim().toLowerCase();
    if (str.isEmpty) return null;

    // Khớp dạng số hoặc chữ thuần túy
    if (str == '2' || str == 'thứ 2' || str == 'thứ hai' || str == 't2' || str == 'hai' || str.startsWith('mon')) {
      return 1;
    }
    if (str == '3' || str == 'thứ 3' || str == 'thứ ba' || str == 't3' || str == 'ba' || str.startsWith('tue')) {
      return 2;
    }
    if (str == '4' || str == 'thứ 4' || str == 'thứ tư' || str == 't4' || str == 'tư' || str.startsWith('wed')) {
      return 3;
    }
    if (str == '5' || str == 'thứ 5' || str == 'thứ năm' || str == 't5' || str == 'năm' || str.startsWith('thu')) {
      return 4;
    }
    if (str == '6' || str == 'thứ 6' || str == 'thứ sáu' || str == 't6' || str == 'sáu' || str.startsWith('fri')) {
      return 5;
    }
    if (str == '7' || str == 'thứ 7' || str == 'thứ bảy' || str == 't7' || str == 'bảy' || str.startsWith('sat')) {
      return 6;
    }
    if (str == '8' || str == 'cn' || str == 'chủ nhật' || str == 'chu nhat' || str.startsWith('sun')) {
      return 7;
    }

    // Thử regex số
    final matchNum = RegExp(r'(\d+)').firstMatch(str);
    if (matchNum != null) {
      final num = int.tryParse(matchNum.group(1)!);
      if (num != null) {
        if (num >= 2 && num <= 7) return num - 1; // 2 -> Thứ Hai (1), 7 -> Thứ Bảy (6)
        if (num == 8 || num == 1) return 7; // 8 hoặc 1 theo chuẩn CN -> 7
      }
    }
    return null;
  }

  /// Chuẩn hóa giờ về định dạng "HH:mm"
  static String? _parseTime(dynamic raw) {
    if (raw == null) return null;
    final str = raw.toString().trim();
    if (str.isEmpty) return null;

    // Khớp dạng "08:00", "8:00", "08:00:00", "08h30", "8h", "8-30"
    final regex = RegExp(r'(\d{1,2})[:hH\-](\d{2})');
    final match = regex.firstMatch(str);
    if (match != null) {
      final h = int.tryParse(match.group(1)!);
      final m = int.tryParse(match.group(2)!);
      if (h != null && m != null && h >= 0 && h <= 23 && m >= 0 && m <= 59) {
        return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
      }
    }

    // Khớp dạng "8h", "14h"
    final hourOnly = RegExp(r'^(\d{1,2})\s*[hH]$').firstMatch(str);
    if (hourOnly != null) {
      final h = int.tryParse(hourOnly.group(1)!);
      if (h != null && h >= 0 && h <= 23) {
        return '${h.toString().padLeft(2, '0')}:00';
      }
    }

    // Khớp dạng số thập phân Excel (fraction of day, e.g. 0.333333 -> 08:00)
    final d = double.tryParse(str);
    if (d != null && d >= 0 && d < 1.0) {
      final totalMin = (d * 24 * 60).round();
      final h = (totalMin ~/ 60).clamp(0, 23);
      final m = (totalMin % 60).clamp(0, 59);
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }

    return null;
  }

  /// Tách chuỗi thời gian gộp (ví dụ "08:00 - 09:30" hoặc "08h00 - 11h30")
  static (String?, String?) _splitCombinedTime(String combined) {
    final parts = combined.split(RegExp(r'\s*[-–~đến]\s*'));
    if (parts.length >= 2) {
      return (_parseTime(parts[0]), _parseTime(parts[1]));
    }
    return (null, null);
  }

  static bool _isStartTimeBeforeEndTime(String start, String end) {
    final sParts = start.split(':').map(int.parse).toList();
    final eParts = end.split(':').map(int.parse).toList();
    final sMin = sParts[0] * 60 + sParts[1];
    final eMin = eParts[0] * 60 + eParts[1];
    return sMin < eMin;
  }

  static Subject? _findMatchingSubject(String name, List<Subject> subjects) {
    final target = name.trim().toLowerCase();
    for (final s in subjects) {
      if (s.name.trim().toLowerCase() == target) {
        return s;
      }
    }
    // Khớp gần (chứa toàn bộ từ)
    for (final s in subjects) {
      final sLower = s.name.trim().toLowerCase();
      if (sLower.contains(target) || target.contains(sLower)) {
        return s;
      }
    }
    return null;
  }

  static ClassSchedule? _findOverlappingSchedule({
    required int dayOfWeek,
    required String startTime,
    required String endTime,
    required List<ClassSchedule> existingSchedules,
  }) {
    final sParts = startTime.split(':').map(int.parse).toList();
    final eParts = endTime.split(':').map(int.parse).toList();
    final startMin = sParts[0] * 60 + sParts[1];
    final endMin = eParts[0] * 60 + eParts[1];

    for (final ex in existingSchedules) {
      if (ex.dayOfWeek == dayOfWeek && ex.isActive) {
        if (startMin < ex.endMinutesSinceMidnight && ex.startMinutesSinceMidnight < endMin) {
          return ex;
        }
      }
    }
    return null;
  }

  static String? _extractCellValue(List<dynamic> row, int? colIndex) {
    if (colIndex == null || colIndex < 0 || colIndex >= row.length) {
      return null;
    }
    final val = row[colIndex];
    if (val == null) return null;
    return val.toString();
  }

  static bool _isRowEmpty(List<dynamic> row) {
    return row.every((c) => c == null || c.toString().trim().isEmpty);
  }

  /// Tạo chuỗi nội dung CSV mẫu để người dùng tải hoặc tham khảo
  static String generateSampleCsv() {
    return '''Môn học,Thứ,Giờ bắt đầu,Giờ kết thúc,Phòng học,Ghi chú
Toán cao cấp,Thứ Hai,08:00,09:30,A1-204,Giải tích 1
Lập trình Di động,Thứ Tư,13:30,16:00,Lab 3,Flutter & Dart
Cơ sở dữ liệu,Thứ Sáu,09:45,11:15,B2-101,Thực hành SQL
Tiếng Anh chuyên ngành,Thứ Bảy,07:30,09:00,Online,Zoom ID 123
''';
  }
}

class _ColumnIndices {
  final int subjectCol;
  final int dayCol;
  final int? startCol;
  final int? endCol;
  final int? combinedTimeCol;
  final int? locationCol;
  final int? notesCol;

  const _ColumnIndices({
    required this.subjectCol,
    required this.dayCol,
    this.startCol,
    this.endCol,
    this.combinedTimeCol,
    this.locationCol,
    this.notesCol,
  });
}

class _HeaderDetectionResult {
  final int rowIndex;
  final _ColumnIndices columnIndices;

  const _HeaderDetectionResult({
    required this.rowIndex,
    required this.columnIndices,
  });
}

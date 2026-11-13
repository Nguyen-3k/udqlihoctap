import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/class_schedule.dart';
import '../models/subject.dart';
import '../models/timetable_import_model.dart';
import 'ocr/ocr_recognizer_platform.dart';

/// Dữ liệu hình ảnh thời khóa biểu được chọn từ thiết bị
class TimetableImage {
  final String name;
  final Uint8List bytes;
  final String? path;

  const TimetableImage({
    required this.name,
    required this.bytes,
    this.path,
  });

  double get sizeInKb => bytes.lengthInBytes / 1024.0;
  double get sizeInMb => sizeInKb / 1024.0;
}

/// Dòng chữ trong một khối chữ OCR kèm tọa độ
class OcrTextLine {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;

  const OcrTextLine({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });
}

/// Khối chữ OCR kèm tọa độ Bounding Box phục vụ phân tích ma trận/bảng
class OcrTextBlock {
  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final List<OcrTextLine> lines;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => left + width / 2;
  double get centerY => top + height / 2;

  const OcrTextBlock({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.lines = const [],
  });
}

/// Trạng thái của tiến trình nhận diện OCR
enum OcrEngineStatus {
  /// Chưa xử lý (ảnh mới được chọn)
  idle,

  /// Đang trong quá trình quét và nhận diện ảnh
  processing,

  /// Chưa hỗ trợ nhận diện (ví dụ trên nền tảng Web Preview)
  unsupported,

  /// Đã nhận diện thành công
  success,

  /// Có lỗi trong quá trình xử lý
  error,
}

/// Kết quả đầu ra từ bộ nhận diện văn bản OCR
class OcrRecognitionResult {
  final String rawText;
  final List<String> textBlocks;
  final List<OcrTextBlock> structuredBlocks;
  final bool isSuccess;
  final String? errorMessage;
  final OcrEngineStatus status;

  const OcrRecognitionResult({
    required this.rawText,
    this.textBlocks = const [],
    this.structuredBlocks = const [],
    required this.isSuccess,
    this.errorMessage,
    required this.status,
  });

  /// Khởi tạo trạng thái chưa hỗ trợ nền tảng
  const OcrRecognitionResult.unsupported({
    String message =
        'Google ML Kit On-Device OCR chỉ khả dụng trên thiết bị di động (Android / iOS).',
  })  : rawText = '',
        textBlocks = const [],
        structuredBlocks = const [],
        isSuccess = false,
        errorMessage = message,
        status = OcrEngineStatus.unsupported;

  /// Khởi tạo lỗi
  const OcrRecognitionResult.error(String message)
      : rawText = '',
        textBlocks = const [],
        structuredBlocks = const [],
        isSuccess = false,
        errorMessage = message,
        status = OcrEngineStatus.error;
}

/// Nguồn cấp ảnh: Camera trực tiếp hoặc Thư viện ảnh thiết bị
enum TimetableImageSource {
  camera,
  gallery,
}

// ============================================================================
// 1. GIAO DIỆN CHỌN VÀ QUẢN LÝ ẢNH (IMAGE PICKER ABSTRACTION)
// ============================================================================

abstract class TimetableImagePicker {
  /// Mở trình chọn ảnh từ thiết bị qua Camera hoặc Thư viện ảnh
  Future<TimetableImage?> pickImage({
    TimetableImageSource source = TimetableImageSource.gallery,
  });
}

/// Cài đặt chọn ảnh và chụp ảnh từ thiết bị qua ImagePicker & FilePicker fallback
class DeviceTimetableImagePicker implements TimetableImagePicker {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  Future<TimetableImage?> pickImage({
    TimetableImageSource source = TimetableImageSource.gallery,
  }) async {
    try {
      final imgSource = source == TimetableImageSource.camera
          ? ImageSource.camera
          : ImageSource.gallery;

      final xFile = await _imagePicker.pickImage(
        source: imgSource,
        imageQuality: 95,
      );

      if (xFile != null) {
        final bytes = await xFile.readAsBytes();
        if (bytes.isNotEmpty) {
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          final fallbackName = source == TimetableImageSource.camera
              ? 'camera_$timestamp.jpg'
              : 'gallery_$timestamp.jpg';

          return TimetableImage(
            name: xFile.name.isNotEmpty ? xFile.name : fallbackName,
            bytes: bytes,
            path: xFile.path,
          );
        }
      }
    } catch (_) {
      // Khi gặp lỗi với ImagePicker (ví dụ trên môi trường test hoặc thiết bị đặc thù),
      // tiếp tục thử fallback với FilePicker nếu đang chọn từ thư viện.
    }

    if (source == TimetableImageSource.gallery) {
      try {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png'],
        );

        if (result.isEmpty) return null;

        final file = result.first;
        Uint8List? bytes;
        try {
          bytes = await file.readAsBytes();
        } catch (_) {}

        if ((bytes == null || bytes.isEmpty) && !kIsWeb && file.path != null) {
          final f = io.File(file.path!);
          if (await f.exists()) {
            bytes = await f.readAsBytes();
          }
        }

        if (bytes != null && bytes.isNotEmpty) {
          return TimetableImage(
            name: file.name,
            bytes: bytes,
            path: file.path,
          );
        }
      } catch (_) {}
    }

    return null;
  }
}

// ============================================================================
// 2. GIAO DIỆN NHẬN DIỆN VĂN BẢN (TEXT RECOGNIZER ABSTRACTION)
// ============================================================================

abstract class ImageTextRecognizer {
  /// Tên định danh của bộ nhận diện OCR
  String get engineName;

  /// Động cơ OCR có khả dụng trên thiết bị hiện tại không
  bool get isAvailable;

  /// Nhận diện văn bản từ hình ảnh
  Future<OcrRecognitionResult> recognizeText(TimetableImage image);
}

// ============================================================================
// 3. GIAO DIỆN PHÂN TÍCH VĂN BẢN THỜI KHÓA BIỂU (PARSER ABSTRACTION)
// ============================================================================

abstract class ImageTimetableTextParser {
  /// Phân tích các khối văn bản thô và bounding box từ OCR thành danh sách các mục thời khóa biểu
  List<ImportedScheduleItem> parseTextToSchedules({
    required String rawText,
    required List<String> textBlocks,
    List<OcrTextBlock> structuredBlocks = const [],
    required List<Subject> existingSubjects,
    required List<ClassSchedule> existingSchedules,
  });
}

/// Trình phân tích văn bản thời khóa biểu thông minh kết hợp cả hai cơ chế:
/// 1. Nhóm theo Bounding Box không gian (Spatial Grid/Matrix clustering)
/// 2. Phân tích cụm dòng văn bản và Regex chuyên sâu (Card/List parsing)
class PatternBasedTimetableTextParser implements ImageTimetableTextParser {
  // Regex nhận diện khung giờ học chuẩn (ví dụ: "07:00 - 09:30", "7h30 - 9h45", "13:30-15:00")
  static final RegExp _clockTimeRangeRegex = RegExp(
    r'(\d{1,2}[:hH]\d{0,2})\s*[-~–—/đến]+\s*(\d{1,2}[:hH]\d{0,2})',
  );

  // Regex nhận diện tiết học (ví dụ: "Tiết 1-3", "Tiết 4 - 6", "tiet 7-9", "T 1-3")
  static final RegExp _lessonPeriodRegex = RegExp(
    r'(?:Tiết|Tiet|T\.)\s*(\d{1,2})\s*[-~–—/đến]+\s*(\d{1,2})',
    caseSensitive: false,
  );

  static final RegExp _teacherRegex = RegExp(
    r'(?:GV|Giảng\s*viên|Giang\s*vien|ThS|TS|PGS|GS|Thầy|Cô)[:\.\s]+([^\n,;]+)',
    caseSensitive: false,
  );

  static final RegExp _roomRegex = RegExp(
    r'(?:Phòng|Phong|P\.|Room|Lab|Giảng\s*đường)[:\.\s]*([A-Za-z0-9\-_]+)',
    caseSensitive: false,
  );

  @override
  List<ImportedScheduleItem> parseTextToSchedules({
    required String rawText,
    required List<String> textBlocks,
    List<OcrTextBlock> structuredBlocks = const [],
    required List<Subject> existingSubjects,
    required List<ClassSchedule> existingSchedules,
  }) {
    if (rawText.trim().isEmpty && textBlocks.isEmpty && structuredBlocks.isEmpty) {
      return const [];
    }

    // Ưu tiên 1: Thử phân tích dạng Bảng Ma trận (Grid Matrix) nếu có Bounding Box
    if (structuredBlocks.length >= 3) {
      final gridResult = _parseSpatialGrid(
        blocks: structuredBlocks,
        existingSubjects: existingSubjects,
        existingSchedules: existingSchedules,
      );
      if (gridResult.isNotEmpty) {
        return gridResult;
      }
    }

    // Ưu tiên 2: Phân tích dạng danh sách / cụm thẻ (Card/List blocks)
    return _parseSequentialBlocks(
      rawText: rawText,
      textBlocks: textBlocks,
      structuredBlocks: structuredBlocks,
      existingSubjects: existingSubjects,
      existingSchedules: existingSchedules,
    );
  }

  // --- 1. PHÂN TÍCH THEO TỌA ĐỘ BOUNDING BOX (SPATIAL GRID CLUSTERING) ---

  List<ImportedScheduleItem> _parseSpatialGrid({
    required List<OcrTextBlock> blocks,
    required List<Subject> existingSubjects,
    required List<ClassSchedule> existingSchedules,
  }) {
    // A. Tìm các cột tiêu đề Thứ (Day columns)
    final List<_DayColumn> dayColumns = [];
    for (final b in blocks) {
      final day = _detectDayOfWeek(b.text);
      if (day != null && !_containsTime(b.text)) {
        dayColumns.add(_DayColumn(dayOfWeek: day, block: b));
      }
    }

    // Cần tối thiểu 2 cột Thứ để xác định cấu trúc bảng ma trận
    if (dayColumns.length < 2) return [];

    // Sắp xếp các cột Thứ theo trục hoành X từ trái sang phải
    dayColumns.sort((a, b) => a.block.left.compareTo(b.block.left));

    // B. Tìm các hàng tiêu đề Giờ/Tiết (Time rows)
    final List<_TimeRow> timeRows = [];
    for (final b in blocks) {
      final timeMatch = _clockTimeRangeRegex.firstMatch(b.text);
      final periodMatch = _lessonPeriodRegex.firstMatch(b.text);

      if (timeMatch != null || periodMatch != null) {
        String? start;
        String? end;
        String? periodNote;

        if (timeMatch != null) {
          start = _normalizeTime(timeMatch.group(1));
          end = _normalizeTime(timeMatch.group(2));
        }
        if (periodMatch != null) {
          periodNote = 'Tiết ${periodMatch.group(1)}-${periodMatch.group(2)}';
        }

        timeRows.add(
          _TimeRow(
            startTime: start,
            endTime: end,
            periodText: periodNote,
            block: b,
          ),
        );
      }
    }

    if (timeRows.isEmpty) return [];

    // Sắp xếp các hàng Thời gian theo trục tung Y từ trên xuống dưới
    timeRows.sort((a, b) => a.block.top.compareTo(b.block.top));

    // C. Gom các khối nội dung vào ô giao thoa (Day column X, Time row Y)
    final List<ImportedScheduleItem> items = [];
    final headerBlockTexts = {
      ...dayColumns.map((c) => c.block.text),
      ...timeRows.map((r) => r.block.text),
    };

    final contentBlocks =
        blocks.where((b) => !headerBlockTexts.contains(b.text)).toList();

    int rowIndex = 1;

    for (final col in dayColumns) {
      // Xác định biên giới hạn của cột Thứ
      final colLeft = col.block.left - 25;
      final colRight = col.block.right + 25;

      for (final row in timeRows) {
        // Xác định biên giới hạn của hàng Thời gian
        final rowTop = row.block.top - 20;
        final rowBottom = row.block.bottom + 45;

        // Tìm các khối chữ rơi vào ô (col, row)
        final cellBlocks = contentBlocks.where((b) {
          final inX = b.centerX >= colLeft && b.centerX <= colRight;
          final inY = b.centerY >= rowTop && b.centerY <= rowBottom;
          return inX && inY;
        }).toList();

        if (cellBlocks.isEmpty) continue;

        // Gộp nội dung trong ô
        final cellText = cellBlocks.map((b) => b.text.trim()).join('\n');
        if (cellText.trim().isEmpty) continue;

        final item = _buildScheduleItemFromText(
          text: cellText,
          forcedDay: col.dayOfWeek,
          forcedStart: row.startTime,
          forcedEnd: row.endTime,
          extraPeriodNote: row.periodText,
          rowIndex: rowIndex++,
          existingSubjects: existingSubjects,
          existingSchedules: existingSchedules,
        );

        if (item != null) {
          items.add(item);
        }
      }
    }

    return items;
  }

  // --- 2. PHÂN TÍCH TUẦN TỰ THEO CỤM KHỐI (SEQUENTIAL CLUSTERS) ---

  List<ImportedScheduleItem> _parseSequentialBlocks({
    required String rawText,
    required List<String> textBlocks,
    required List<OcrTextBlock> structuredBlocks,
    required List<Subject> existingSubjects,
    required List<ClassSchedule> existingSchedules,
  }) {
    final List<ImportedScheduleItem> result = [];
    final lines = rawText.isNotEmpty
        ? rawText.split('\n')
        : textBlocks;

    int rowIndex = 1;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final item = _buildScheduleItemFromText(
        text: trimmed,
        rowIndex: rowIndex++,
        existingSubjects: existingSubjects,
        existingSchedules: existingSchedules,
      );

      if (item != null) {
        result.add(item);
      }
    }

    return result;
  }

  // --- 3. BÓC TÁCH CÁC TRƯỜNG THÔNG TIN TỪ MỘT ĐOẠN VĂN BẢN ---

  ImportedScheduleItem? _buildScheduleItemFromText({
    required String text,
    int? forcedDay,
    String? forcedStart,
    String? forcedEnd,
    String? extraPeriodNote,
    required int rowIndex,
    required List<Subject> existingSubjects,
    required List<ClassSchedule> existingSchedules,
  }) {
    // 1. Thứ trong tuần
    final dayOfWeek = forcedDay ?? _detectDayOfWeek(text);

    // 2. Khung giờ học
    String? startTime = forcedStart;
    String? endTime = forcedEnd;

    final timeMatch = _clockTimeRangeRegex.firstMatch(text);
    if (timeMatch != null && (startTime == null || endTime == null)) {
      startTime = _normalizeTime(timeMatch.group(1));
      endTime = _normalizeTime(timeMatch.group(2));
    }

    // 3. Tiết học (Lesson period) - Không nhầm với giờ đồng hồ
    String? periodNote = extraPeriodNote;
    final periodMatch = _lessonPeriodRegex.firstMatch(text);
    if (periodMatch != null && periodNote == null) {
      periodNote = 'Tiết ${periodMatch.group(1)}-${periodMatch.group(2)}';
    }

    // 4. Giảng viên
    String teacher = '';
    final teacherMatch = _teacherRegex.firstMatch(text);
    if (teacherMatch != null) {
      teacher = teacherMatch.group(1)?.trim() ?? '';
    }

    // 5. Phòng học
    String location = '';
    final roomMatch = _roomRegex.firstMatch(text);
    if (roomMatch != null) {
      location = roomMatch.group(1)?.trim() ?? '';
    }

    // 6. Tên môn học
    String rawSubject = '';
    String? matchedId;
    String matchedName = '';
    bool isNewSubject = true;

    for (final sub in existingSubjects) {
      if (text.toLowerCase().contains(sub.name.toLowerCase())) {
        rawSubject = sub.name;
        matchedId = sub.id;
        matchedName = sub.name;
        isNewSubject = false;
        break;
      }
    }

    if (rawSubject.isEmpty) {
      // Làm sạch các dòng để tìm tên môn học
      final textLines = text.split('\n');
      for (final l in textLines) {
        final cl = l.trim();
        if (cl.isNotEmpty &&
            !_containsDayOfWeek(cl) &&
            !_containsTime(cl) &&
            !_teacherRegex.hasMatch(cl) &&
            !_roomRegex.hasMatch(cl)) {
          rawSubject = cl;
          matchedName = cl;
          break;
        }
      }
      if (rawSubject.isEmpty) {
        rawSubject = textLines.first.trim();
        matchedName = rawSubject;
      }
    }

    // 7. Ghi chú tổng hợp
    String notes = periodNote ?? '';

    // 8. Đánh giá trạng thái và tính hợp lệ
    ImportItemStatus status = ImportItemStatus.valid;
    String? errorMsg;
    String? warningMsg;
    ClassSchedule? overlapping;

    // QUY TẮC AN TOÀN: Nếu thiếu thứ hoặc thiếu giờ đồng hồ thì đánh dấu lỗi để người dùng xác nhận
    if (dayOfWeek == null) {
      status = ImportItemStatus.errorMissingField;
      errorMsg = 'Chưa nhận diện được Thứ trong tuần';
    } else if (startTime == null || endTime == null) {
      status = ImportItemStatus.errorMissingField;
      errorMsg = periodNote != null
          ? 'Chưa có giờ cụ thể ($periodNote) - Vui lòng chọn giờ học'
          : 'Thiếu giờ bắt đầu / kết thúc';
    } else {
      // Kiểm tra xem giờ bắt đầu có trước giờ kết thúc không
      final startMin = _minutesFromTimeString(startTime);
      final endMin = _minutesFromTimeString(endTime);
      if (startMin >= endMin) {
        status = ImportItemStatus.errorInvalidTime;
        errorMsg = 'Giờ bắt đầu phải trước giờ kết thúc ($startTime - $endTime)';
      } else {
        overlapping = _findOverlapping(
          existingSchedules,
          dayOfWeek,
          startTime,
          endTime,
        );
        if (overlapping != null) {
          status = ImportItemStatus.warningOverlap;
          warningMsg =
              'Trùng giờ với ${overlapping.subjectName} (${overlapping.timeRangeText})';
        } else if (isNewSubject) {
          status = ImportItemStatus.newSubject;
        }
      }
    }

    return ImportedScheduleItem(
      rowIndex: rowIndex,
      rawSubjectName: rawSubject,
      matchedSubjectId: matchedId,
      matchedSubjectName: matchedName,
      isNewSubject: isNewSubject,
      dayOfWeek: dayOfWeek,
      startTime: startTime,
      endTime: endTime,
      location: location,
      teacher: teacher,
      notes: notes,
      isSelected: !status.hasError,
      status: status,
      errorMessage: errorMsg,
      warningMessage: warningMsg,
      overlappingSchedule: overlapping,
    );
  }

  // --- CÁC HÀM TRỢ GIÚP PHÂN TÍCH THỨ & GIỜ ---

  int? _detectDayOfWeek(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('chủ nhật') || lower.contains('cn') || lower.contains('sunday') || lower.contains('sun')) {
      return 7;
    }
    if (lower.contains('thứ hai') || lower.contains('thứ 2') || lower.contains('t2') || lower.contains('monday') || lower.contains('mon')) {
      return 1;
    }
    if (lower.contains('thứ ba') || lower.contains('thứ 3') || lower.contains('t3') || lower.contains('tuesday') || lower.contains('tue')) {
      return 2;
    }
    if (lower.contains('thứ tư') || lower.contains('thứ 4') || lower.contains('t4') || lower.contains('wednesday') || lower.contains('wed')) {
      return 3;
    }
    if (lower.contains('thứ năm') || lower.contains('thứ 5') || lower.contains('t5') || lower.contains('thursday') || lower.contains('thu')) {
      return 4;
    }
    if (lower.contains('thứ sáu') || lower.contains('thứ 6') || lower.contains('t6') || lower.contains('friday') || lower.contains('fri')) {
      return 5;
    }
    if (lower.contains('thứ bảy') || lower.contains('thứ 7') || lower.contains('t7') || lower.contains('saturday') || lower.contains('sat')) {
      return 6;
    }
    return null;
  }

  bool _containsDayOfWeek(String text) {
    return _detectDayOfWeek(text) != null;
  }

  bool _containsTime(String text) {
    return _clockTimeRangeRegex.hasMatch(text) || _lessonPeriodRegex.hasMatch(text);
  }

  String? _normalizeTime(String? input) {
    if (input == null) return null;
    final cleaned = input.replaceAll('h', ':').replaceAll('H', ':').trim();
    final parts = cleaned.split(':');
    if (parts.isEmpty) return null;
    final hour = int.tryParse(parts[0]);
    if (hour == null || hour < 0 || hour > 23) return null;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  int _minutesFromTimeString(String time) {
    final parts = time.split(':');
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return h * 60 + m;
  }

  ClassSchedule? _findOverlapping(
    List<ClassSchedule> existing,
    int dayOfWeek,
    String start,
    String end,
  ) {
    final startMin = _minutesFromTimeString(start);
    final endMin = _minutesFromTimeString(end);

    for (final s in existing) {
      if (s.dayOfWeek == dayOfWeek && s.isActive) {
        if (startMin < s.endMinutesSinceMidnight &&
            s.startMinutesSinceMidnight < endMin) {
          return s;
        }
      }
    }
    return null;
  }
}

class _DayColumn {
  final int dayOfWeek;
  final OcrTextBlock block;
  const _DayColumn({required this.dayOfWeek, required this.block});
}

class _TimeRow {
  final String? startTime;
  final String? endTime;
  final String? periodText;
  final OcrTextBlock block;
  const _TimeRow({
    this.startTime,
    this.endTime,
    this.periodText,
    required this.block,
  });
}

// ============================================================================
// 4. BỘ ĐIỀU PHỐI QUY TRÌNH NHẬP ẢNH (COORDINATOR)
// ============================================================================

class ImageTimetableCoordinator {
  final TimetableImagePicker imagePicker;
  final ImageTextRecognizer textRecognizer;
  final ImageTimetableTextParser textParser;

  ImageTimetableCoordinator({
    TimetableImagePicker? imagePicker,
    ImageTextRecognizer? textRecognizer,
    ImageTimetableTextParser? textParser,
  })  : imagePicker = imagePicker ?? DeviceTimetableImagePicker(),
        textRecognizer = textRecognizer ?? GoogleMlKitTextRecognizer(),
        textParser = textParser ?? PatternBasedTimetableTextParser();
}

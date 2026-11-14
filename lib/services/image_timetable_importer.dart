import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../models/class_schedule.dart';
import '../models/subject.dart';
import '../models/timetable_import_model.dart';
import 'class_period_time_mapper.dart';
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

  String get mimeType {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }
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
/// 2. Phân tích cụm khối văn bản và Regex chuyên sâu (Card/List parsing)
class PatternBasedTimetableTextParser implements ImageTimetableTextParser {
  // Regex nhận diện khung giờ học chuẩn (ví dụ: "07:00 - 09:30", "7h30 - 9h45", "13:30-15:00")
  static final RegExp _clockTimeRangeRegex = RegExp(
    r'(\d{1,2}[:hH]\d{1,2})\s*[-~–—/đến]+\s*(\d{1,2}[:hH]\d{1,2})',
  );

  // Regex nhận diện tiết học chuẩn (ví dụ: "Tiết 1-3", "Tiết 4 - 6", "tiet 7-9", "T 1-3")
  static final RegExp _lessonPeriodRegex = RegExp(
    r'(?:Tiết|Tiet|T\.)\s*(\d{1,2})\s*[-~–—/đến]+\s*(\d{1,2})',
    caseSensitive: false,
  );

  // Regex nhận diện tiết học trong dấu ngoặc (ví dụ: "(1-4)", "(7-10)")
  static final RegExp _parenthesizedPeriodRegex = RegExp(
    r'\(\s*(\d{1,2})\s*[-~–—/đến]+\s*(\d{1,2})\s*\)',
  );

  static final RegExp _teacherRegex = RegExp(
    r'(?:GV|Giảng\s*viên|Giang\s*vien|ThS|TS|PGS|GS|Thầy|Cô)[:\.\s]+([^\n,;]+)',
    caseSensitive: false,
  );

  static final RegExp _roomRegex = RegExp(
    r'(?:Phòng|Phong|P\.|Room|Lab|Giảng\s*đường)[:\.\s]*([A-Za-z0-9\.\-_]+)',
    caseSensitive: false,
  );

  static final RegExp _onlineRegex = RegExp(
    r'(?:PM|Phần\s*mềm|Hình\s*thức|Meet|Zoom|Teams)[:\.\s]+([^\n]+)',
    caseSensitive: false,
  );

  static final RegExp _hpRegex = RegExp(
    r'(?:HP|Học\s*phần|Tên\s*HP|Môn\s*học|Môn)\s*[:\.\-]\s*([^\n\(\)]+)',
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

    // Ưu tiên 2: Phân tích dạng danh sách / cụm khối tuần tự (Card/List blocks)
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
    // 1. Phân vùng các bảng theo tuần (nếu có nhiều bảng xếp chồng theo trục Y)
    final sections = _partitionIntoTableSections(blocks);
    if (sections.isEmpty) return [];

    final List<ImportedScheduleItem> allItems = [];
    int rowIndex = 1;

    for (final section in sections) {
      final sectionItems = _parseSingleTableSection(
        sectionBlocks: section,
        existingSubjects: existingSubjects,
        existingSchedules: existingSchedules,
        startRowIndex: rowIndex,
      );
      allItems.addAll(sectionItems);
      rowIndex += sectionItems.length;
    }

    _detectIntraBatchConflicts(allItems);
    return allItems;
  }

  /// Phân vùng các khối OCR thành từng bảng tuần riêng biệt dựa vào các hàng tiêu đề thứ
  List<List<OcrTextBlock>> _partitionIntoTableSections(List<OcrTextBlock> blocks) {
    if (blocks.isEmpty) return [];

    final List<OcrTextBlock> dayHeaderBlocks = [];
    for (final b in blocks) {
      if (_isDayHeaderBlock(b)) {
        dayHeaderBlocks.add(b);
      }
    }

    if (dayHeaderBlocks.length < 2) {
      return [blocks];
    }

    // Sắp xếp các tiêu đề thứ theo trục Y từ trên xuống dưới
    dayHeaderBlocks.sort((a, b) => a.top.compareTo(b.top));

    // Nhóm các tiêu đề thứ có tọa độ Y gần nhau thành từng hàng tiêu đề (Day Header Row)
    final List<List<OcrTextBlock>> headerRows = [];
    List<OcrTextBlock> currentRow = [dayHeaderBlocks.first];

    for (int i = 1; i < dayHeaderBlocks.length; i++) {
      final prev = currentRow.last;
      final curr = dayHeaderBlocks[i];
      final yDiff = (curr.centerY - prev.centerY).abs();
      final threshold = (prev.height > 0 ? prev.height * 1.5 : 35.0).clamp(25.0, 60.0);

      if (yDiff <= threshold) {
        currentRow.add(curr);
      } else {
        if (currentRow.length >= 2) {
          headerRows.add(currentRow);
        }
        currentRow = [curr];
      }
    }
    if (currentRow.length >= 2) {
      headerRows.add(currentRow);
    }

    if (headerRows.length <= 1) {
      return [blocks];
    }

    // Có nhiều bảng tuần xếp chồng (Multi-week tables) -> Tính các ranh giới cắt Y
    final List<double> splitY = [];
    for (int k = 0; k < headerRows.length - 1; k++) {
      final rowK = headerRows[k];
      final rowNext = headerRows[k + 1];
      final maxBottomK = rowK.map((b) => b.bottom).reduce((a, b) => a > b ? a : b);
      final minTopNext = rowNext.map((b) => b.top).reduce((a, b) => a < b ? a : b);
      splitY.add((maxBottomK + minTopNext) / 2);
    }

    final List<List<OcrTextBlock>> resultSections =
        List.generate(headerRows.length, (_) => []);

    for (final b in blocks) {
      int targetSec = 0;
      for (int k = 0; k < splitY.length; k++) {
        if (b.centerY >= splitY[k]) {
          targetSec = k + 1;
        }
      }
      resultSections[targetSec].add(b);
    }

    return resultSections;
  }

  /// Phân tích một bảng tuần đơn lẻ
  List<ImportedScheduleItem> _parseSingleTableSection({
    required List<OcrTextBlock> sectionBlocks,
    required List<Subject> existingSubjects,
    required List<ClassSchedule> existingSchedules,
    required int startRowIndex,
  }) {
    // 1. Tìm các cột tiêu đề thứ trong bảng này
    final List<_DayColumn> dayColumns = [];
    final Set<int> seenDays = {};

    for (final b in sectionBlocks) {
      if (_isDayHeaderBlock(b)) {
        final d = _detectDayOfWeek(b.text);
        if (d != null && !seenDays.contains(d)) {
          seenDays.add(d);
          dayColumns.add(_DayColumn(dayOfWeek: d, block: b));
        }
      }
    }

    if (dayColumns.length < 2) return [];

    // Sắp xếp các cột thứ theo trục hoành X từ trái sang phải
    dayColumns.sort((a, b) => a.block.left.compareTo(b.block.left));

    // Tính ranh giới tương đối thích ứng (Adaptive Midpoint Boundaries) cho các cột
    final List<_ColumnBounds> colBounds = [];
    for (int i = 0; i < dayColumns.length; i++) {
      final curr = dayColumns[i];
      double leftB;
      double rightB;

      if (i == 0) {
        leftB = curr.block.left - curr.block.width * 0.4;
      } else {
        final prev = dayColumns[i - 1];
        leftB = (prev.block.right + curr.block.left) / 2;
      }

      if (i == dayColumns.length - 1) {
        rightB = curr.block.right + curr.block.width * 0.4;
      } else {
        final next = dayColumns[i + 1];
        rightB = (curr.block.right + next.block.left) / 2;
      }

      colBounds.add(_ColumnBounds(
        dayOfWeek: curr.dayOfWeek,
        headerBlock: curr.block,
        leftBound: leftB,
        rightBound: rightB,
      ));
    }

    // 2. Tìm các hàng tiêu đề Buổi / Ca (Session Rows) ví dụ: "Sáng", "Chiều", "Tối"
    final List<_SessionRow> sessionRows = [];
    for (final b in sectionBlocks) {
      final s = _detectSessionName(b.text);
      if (s != null) {
        sessionRows.add(_SessionRow(sessionName: s, block: b));
      }
    }

    sessionRows.sort((a, b) => a.block.top.compareTo(b.block.top));

    final Set<OcrTextBlock> headerBlocks = {
      ...dayColumns.map((c) => c.block),
      ...sessionRows.map((r) => r.block),
    };

    final contentBlocks = sectionBlocks
        .where((b) => !headerBlocks.contains(b) && !_isNoiseOrHeader(b.text))
        .toList();

    final List<ImportedScheduleItem> items = [];
    int rowIndex = startRowIndex;

    if (sessionRows.isNotEmpty) {
      // Tính ranh giới tương đối thích ứng (Adaptive Y Boundaries) cho các hàng buổi
      final List<_RowBounds> rowBounds = [];
      for (int j = 0; j < sessionRows.length; j++) {
        final curr = sessionRows[j];
        double topB;
        double bottomB;

        if (j == 0) {
          final maxDayHeaderBottom = dayColumns
              .map((c) => c.block.bottom)
              .reduce((a, b) => a > b ? a : b);
          topB = maxDayHeaderBottom;
        } else {
          final prev = sessionRows[j - 1];
          topB = (prev.block.bottom + curr.block.top) / 2;
        }

        if (j == sessionRows.length - 1) {
          bottomB = curr.block.bottom + curr.block.height * 5;
        } else {
          final next = sessionRows[j + 1];
          bottomB = (curr.block.bottom + next.block.top) / 2;
        }

        rowBounds.add(_RowBounds(
          sessionName: curr.sessionName,
          headerBlock: curr.block,
          topBound: topB,
          bottomBound: bottomB,
        ));
      }

      // Gom nội dung vào từng ô giao thoa (Column X, Row Y)
      for (final col in colBounds) {
        for (final row in rowBounds) {
          final cellBlocks = contentBlocks.where((b) {
            final inX = b.centerX >= col.leftBound && b.centerX < col.rightBound;
            final inY = b.centerY >= row.topBound && b.centerY < row.bottomBound;
            return inX && inY;
          }).toList();

          if (cellBlocks.isEmpty) continue;

          cellBlocks.sort((a, b) => a.top.compareTo(b.top));
          final cellText = cellBlocks.map((b) => b.text.trim()).join('\n');

          final item = _parseCourseCellText(
            text: cellText,
            forcedDay: col.dayOfWeek,
            sessionHint: row.sessionName,
            rowIndex: rowIndex,
            existingSubjects: existingSubjects,
            existingSchedules: existingSchedules,
          );

          if (item != null) {
            items.add(item);
            rowIndex++;
          }
        }
      }
    } else {
      // Nếu không có các khối hàng "Sáng", "Chiều", "Tối" riêng lẻ
      // Gom contentBlocks theo từng cột thứ, rồi nhóm cụm theo khoảng cách Y
      for (final col in colBounds) {
        final colBlocks = contentBlocks.where((b) {
          return b.centerX >= col.leftBound &&
              b.centerX < col.rightBound &&
              b.centerY > col.headerBlock.bottom;
        }).toList();

        if (colBlocks.isEmpty) continue;
        colBlocks.sort((a, b) => a.top.compareTo(b.top));

        final cellGroups = _clusterBlocksVertically(colBlocks);
        for (final group in cellGroups) {
          final cellText = group.map((b) => b.text.trim()).join('\n');
          final item = _parseCourseCellText(
            text: cellText,
            forcedDay: col.dayOfWeek,
            rowIndex: rowIndex,
            existingSubjects: existingSubjects,
            existingSchedules: existingSchedules,
          );
          if (item != null) {
            items.add(item);
            rowIndex++;
          }
        }
      }
    }

    return items;
  }

  // --- 2. PHÂN TÍCH TUẦN TỰ THEO CỤM KHỐI (SEQUENTIAL CLUSTERS FALLBACK) ---

  List<ImportedScheduleItem> _parseSequentialBlocks({
    required String rawText,
    required List<String> textBlocks,
    required List<OcrTextBlock> structuredBlocks,
    required List<Subject> existingSubjects,
    required List<ClassSchedule> existingSchedules,
  }) {
    final List<ImportedScheduleItem> result = [];

    final blocks = textBlocks.isNotEmpty
        ? textBlocks
        : (structuredBlocks.isNotEmpty
            ? structuredBlocks.map((b) => b.text).toList()
            : rawText.split(RegExp(r'\n{2,}')));

    final chunks = <String>[];
    for (final b in blocks) {
      final trimmed = b.trim();
      if (trimmed.isEmpty) continue;
      if (_isNoiseOrHeader(trimmed)) continue;

      // Nếu khối này chứa nhiều HP:, tách theo HP:
      if (RegExp(r'(?:^|\n)(?:HP|Học\s*phần)[:\.\s]+', caseSensitive: false)
              .allMatches(trimmed)
              .length >
          1) {
        final subChunks = trimmed.split(RegExp(
            r'(?=(?:^|\n)(?:HP|Học\s*phần)[:\.\s]+)',
            caseSensitive: false));
        for (final sc in subChunks) {
          if (sc.trim().isNotEmpty && !_isNoiseOrHeader(sc.trim())) {
            chunks.add(sc.trim());
          }
        }
      } else {
        chunks.add(trimmed);
      }
    }

    int rowIndex = 1;
    for (final chunk in chunks) {
      final item = _parseCourseCellText(
        text: chunk,
        rowIndex: rowIndex,
        existingSubjects: existingSubjects,
        existingSchedules: existingSchedules,
      );
      if (item != null) {
        result.add(item);
        rowIndex++;
      }
    }

    _detectIntraBatchConflicts(result);
    return result;
  }

  // --- 3. BÓC TÁCH CÁC TRƯỜNG THÔNG TIN TỪ MỘT Ô HỌC PHẦN (COURSE CELL) ---

  ImportedScheduleItem? _parseCourseCellText({
    required String text,
    int? forcedDay,
    String? forcedStart,
    String? forcedEnd,
    String? sessionHint,
    required int rowIndex,
    required List<Subject> existingSubjects,
    required List<ClassSchedule> existingSchedules,
  }) {
    if (text.trim().isEmpty) return null;
    if (_isNoiseOrHeader(text)) return null;

    // 1. Thứ trong tuần
    final dayOfWeek = forcedDay ?? _detectDayOfWeek(text);

    // 2. Tìm thông tin tiết học (Period) ví dụ: "(1-4)", "Tiết 1-4", "(7-10)"
    int? pStart;
    int? pEnd;
    String? periodText;

    final parenMatch = _parenthesizedPeriodRegex.firstMatch(text);
    if (parenMatch != null) {
      pStart = int.tryParse(parenMatch.group(1)!);
      pEnd = int.tryParse(parenMatch.group(2)!);
      periodText = 'Tiết ${parenMatch.group(1)}-${parenMatch.group(2)}';
    } else {
      final periodMatch = _lessonPeriodRegex.firstMatch(text);
      if (periodMatch != null) {
        pStart = int.tryParse(periodMatch.group(1)!);
        pEnd = int.tryParse(periodMatch.group(2)!);
        periodText = 'Tiết ${periodMatch.group(1)}-${periodMatch.group(2)}';
      }
    }

    // 3. Khung giờ học
    String? startTime = forcedStart;
    String? endTime = forcedEnd;

    // Thử trích xuất giờ đồng hồ nếu có trong text
    final timeMatch = _clockTimeRangeRegex.firstMatch(text);
    if (timeMatch != null) {
      final s = _normalizeTime(timeMatch.group(1));
      final e = _normalizeTime(timeMatch.group(2));
      if (s != null && e != null) {
        startTime ??= s;
        endTime ??= e;
      }
    }

    // Nếu chưa có giờ đồng hồ nhưng có tiết học, thực hiện mapping giờ chuẩn đại học
    if ((startTime == null || endTime == null) && pStart != null && pEnd != null) {
      final mapped = _mapPeriodsToTime(pStart, pEnd, sessionHint: sessionHint);
      if (mapped != null) {
        startTime = mapped.start;
        endTime = mapped.end;
      }
    }

    // 4. Giảng viên
    String teacher = '';
    final teacherMatch = _teacherRegex.firstMatch(text);
    if (teacherMatch != null) {
      teacher = teacherMatch.group(1)?.trim() ?? '';
      teacher = teacher
          .split(RegExp(r'(?:Phòng|Phong|P\.|PM|Room|Meet|Zoom)', caseSensitive: false))
          .first
          .trim();
    }

    // 5. Phòng học
    String location = '';
    final roomMatch = _roomRegex.firstMatch(text);
    if (roomMatch != null) {
      location = roomMatch.group(1)?.trim() ?? '';
    }

    // 6. Thông tin học trực tuyến (PM: Google Meet, ...)
    String? onlineInfo;
    final onlineMatch = _onlineRegex.firstMatch(text);
    if (onlineMatch != null) {
      onlineInfo = onlineMatch.group(0)?.trim();
    }

    // 7. Tên môn học
    String rawSubject = '';
    String? matchedId;
    String matchedName = '';
    bool isNewSubject = true;

    // Ưu tiên dòng có HP: hoặc Học phần:
    final hpMatch = _hpRegex.firstMatch(text);
    if (hpMatch != null) {
      rawSubject = hpMatch.group(1)?.trim() ?? '';
    }

    // Kiểm tra khớp với môn học có sẵn
    if (rawSubject.isNotEmpty) {
      for (final sub in existingSubjects) {
        if (sub.name.trim().toLowerCase() == rawSubject.trim().toLowerCase()) {
          matchedId = sub.id;
          matchedName = sub.name;
          isNewSubject = false;
          break;
        }
      }
    } else {
      for (final sub in existingSubjects) {
        if (text.toLowerCase().contains(sub.name.toLowerCase())) {
          rawSubject = sub.name;
          matchedId = sub.id;
          matchedName = sub.name;
          isNewSubject = false;
          break;
        }
      }
    }

    // Nếu chưa tìm thấy, trích xuất dòng đầu tiên không phải header/metadata
    if (rawSubject.isEmpty) {
      final lines = text.split('\n');
      for (final l in lines) {
        final cl = l.trim();
        if (cl.isEmpty) continue;
        if (_isNoiseOrHeader(cl)) continue;
        if (_isMetadataLine(cl)) continue;
        rawSubject = cl;
        break;
      }
    }

    rawSubject = _cleanSubjectName(rawSubject);
    if (matchedName.isEmpty) {
      matchedName = rawSubject;
    }

    // Kiểm tra tính hợp lệ của tên môn (từ chối từ khóa rác hoặc tiêu đề bảng)
    if (rawSubject.isEmpty || isProhibitedSubjectName(rawSubject)) {
      return null;
    }

    // Phải có ít nhất 1 thuộc tính thời khóa biểu (thứ, giờ, tiết, giảng viên, phòng, hoặc là môn có sẵn)
    final hasAnyTimetableInfo = dayOfWeek != null ||
        startTime != null ||
        endTime != null ||
        pStart != null ||
        teacher.isNotEmpty ||
        location.isNotEmpty ||
        !isNewSubject;
    if (!hasAnyTimetableInfo) {
      return null;
    }

    // 8. Ghi chú tổng hợp
    final notesParts = <String>[];
    if (periodText != null) notesParts.add(periodText);
    if (onlineInfo != null) notesParts.add(onlineInfo);
    final notes = notesParts.join('; ');

    // 9. Đánh giá trạng thái và tính hợp lệ
    ImportItemStatus status = ImportItemStatus.valid;
    String? errorMsg;
    String? warningMsg;
    ClassSchedule? overlapping;

    if (dayOfWeek == null) {
      status = ImportItemStatus.errorMissingField;
      errorMsg = 'Chưa nhận diện được Thứ trong tuần';
    } else if (startTime == null || endTime == null) {
      status = ImportItemStatus.errorMissingField;
      errorMsg = periodText != null
          ? 'Chưa có giờ cụ thể ($periodText) - Vui lòng chọn giờ học'
          : 'Thiếu giờ bắt đầu / kết thúc';
    } else if (!isValidTimeString(startTime) || !isValidTimeString(endTime)) {
      status = ImportItemStatus.errorInvalidTime;
      errorMsg = 'Định dạng giờ không hợp lệ ($startTime - $endTime)';
    } else {
      final startMin = timeStringToMinutes(startTime)!;
      final endMin = timeStringToMinutes(endTime)!;
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

  // --- 4. CÁC HÀM TIỆN ÍCH HỖ TRỢ XỬ LÝ DỮ LIỆU ---

  bool _isNoiseOrHeader(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return true;

    // Không chứa bất kỳ chữ cái Unicode nào (chỉ toàn số, dấu câu, ký hiệu)
    if (!RegExp(r'\p{L}', unicode: true).hasMatch(clean)) {
      return true;
    }

    final lower = clean.toLowerCase();

    // Dải ngày hoặc tiêu đề thời khóa biểu
    if (lower.contains('thời khóa biểu') ||
        lower.contains('từ ngày') ||
        lower.contains('đến ngày') ||
        RegExp(r'^tuần\s*\d+', caseSensitive: false).hasMatch(clean)) {
      return true;
    }

    // Tiêu đề ngày trong tuần đứng riêng
    if (RegExp(
      r'^(?:thứ\s*[2-7]|thứ\s*(?:hai|ba|tư|năm|sáu|bảy)|chủ\s*nhật|t[2-7]|cn|mon(?:day)?|tue(?:sday)?|wed(?:nesday)?|thu(?:rsday)?|fri(?:day)?|sat(?:urday)?|sun(?:day)?)(?:\s*[\(\[]?\s*\d{1,2}[/-]\d{1,2}[\)\]]?)?$',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }

    // Tiêu đề cột/hàng buổi học hoặc nhãn siêu dữ liệu đứng riêng
    const noiseWords = {
      'buổi',
      'sáng',
      'chiều',
      'tối',
      'tiết',
      'stt',
      'ca',
      'ca học',
      'học kỳ',
      'năm học',
      'hp',
      'mã hp',
      'tên hp',
      'học phần',
      'môn',
      'môn học',
      'giảng viên',
      'gv',
      'phòng',
      'phòng học',
      'hình thức',
      'ghi chú',
      'lớp',
      'lớp học phần',
    };
    if (noiseWords.contains(lower)) {
      return true;
    }

    if (RegExp(r'^[-—–_\|\s]+$').hasMatch(clean)) {
      return true;
    }

    return false;
  }

  bool _isDayHeaderBlock(OcrTextBlock b) {
    final text = b.text.trim();
    if (text.isEmpty) return false;
    if (_hpRegex.hasMatch(text) ||
        _teacherRegex.hasMatch(text) ||
        _roomRegex.hasMatch(text) ||
        _clockTimeRangeRegex.hasMatch(text) ||
        _lessonPeriodRegex.hasMatch(text) ||
        _parenthesizedPeriodRegex.hasMatch(text)) {
      return false;
    }
    return _detectDayOfWeek(text) != null;
  }

  String? _detectSessionName(String text) {
    final lower = text.trim().toLowerCase();
    if (RegExp(r'^(?:buổi\s*)?sáng$').hasMatch(lower)) return 'Sáng';
    if (RegExp(r'^(?:buổi\s*)?chiều$').hasMatch(lower)) return 'Chiều';
    if (RegExp(r'^(?:buổi\s*)?tối$').hasMatch(lower)) return 'Tối';
    return null;
  }

  List<List<OcrTextBlock>> _clusterBlocksVertically(List<OcrTextBlock> blocks) {
    if (blocks.isEmpty) return [];
    final List<List<OcrTextBlock>> clusters = [];
    List<OcrTextBlock> currentCluster = [blocks.first];

    for (int i = 1; i < blocks.length; i++) {
      final prev = currentCluster.last;
      final curr = blocks[i];
      final gap = curr.top - prev.bottom;
      final isNewCourseStart = RegExp(r'^(?:HP|Học\s*phần)[:\.\s]+', caseSensitive: false)
          .hasMatch(curr.text.trim());

      if (isNewCourseStart || gap > 40) {
        clusters.add(currentCluster);
        currentCluster = [curr];
      } else {
        currentCluster.add(curr);
      }
    }
    clusters.add(currentCluster);
    return clusters;
  }

  int? _detectDayOfWeek(String text) {
    final lower = text.toLowerCase().trim();
    if (lower.isEmpty) return null;

    final tokens = lower
        .split(RegExp(r'[^\p{L}\p{N}]+', unicode: true))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    for (int i = 0; i < tokens.length; i++) {
      final t = tokens[i];

      // Chủ nhật: "chủ" + "nhật" hoặc "cn" hoặc "sun" / "sunday"
      if (t == 'cn' || t == 'sun' || t == 'sunday') return 7;
      if (t == 'chủ' && i + 1 < tokens.length && tokens[i + 1] == 'nhật') return 7;
      if (t == 'chu' && i + 1 < tokens.length && tokens[i + 1] == 'nhat') return 7;

      // Thứ hai / Thứ 2 / T2 / Mon / Monday
      if (t == 't2' || t == 'mon' || t == 'monday') return 1;
      if ((t == 'thứ' || t == 'thu') && i + 1 < tokens.length) {
        final next = tokens[i + 1];
        if (next == '2' || next == 'hai') return 1;
        if (next == '3' || next == 'ba') return 2;
        if (next == '4' || next == 'tư' || next == 'tu') return 3;
        if (next == '5' || next == 'năm' || next == 'nam') return 4;
        if (next == '6' || next == 'sáu' || next == 'sau') return 5;
        if (next == '7' || next == 'bảy' || next == 'bay') return 6;
      }

      // Thứ ba / T3 / Tue / Tuesday
      if (t == 't3' || t == 'tue' || t == 'tuesday') return 2;

      // Thứ tư / T4 / Wed / Wednesday
      if (t == 't4' || t == 'wed' || t == 'wednesday') return 3;

      // Thứ năm / T5 / Thu / Thursday (lưu ý: chỉ khi token đứng riêng là "thu" hoặc "t5" hoặc "thursday")
      if (t == 't5' || t == 'thursday' || t == 'thu') return 4;

      // Thứ sáu / T6 / Fri / Friday
      if (t == 't6' || t == 'fri' || t == 'friday') return 5;

      // Thứ bảy / T7 / Sat / Saturday
      if (t == 't7' || t == 'sat' || t == 'saturday') return 6;
    }

    return null;
  }

  String? _normalizeTime(String? input) {
    if (input == null) return null;
    final cleaned = input.replaceAll('h', ':').replaceAll('H', ':').trim();
    final match = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(cleaned);
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || hour < 0 || hour > 23) return null;
    if (minute == null || minute < 0 || minute > 59) return null;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  _MappedTime? _mapPeriodsToTime(int pStart, int pEnd, {String? sessionHint}) {
    if (pStart <= 0 || pEnd <= 0 || pStart > pEnd) return null;

    final hint = sessionHint?.toLowerCase() ?? '';

    // Nếu sessionHint chỉ định rõ 'chiều' nhưng tiết được ghi theo ca sáng (1..4), quy đổi sang 7..10
    int effStart = pStart;
    int effEnd = pEnd;
    if (hint.contains('chiều') && pStart <= 4 && pEnd <= 4) {
      effStart = pStart + 6;
      effEnd = pEnd + 6;
    }

    // Sử dụng bảng quy đổi giờ học chính thức từ ClassPeriodTimeMapper (Phase 6D.2)
    final mapping = ClassPeriodTimeMapper.mapPeriodsToTime(effStart, effEnd);
    if (mapping != null) {
      return _MappedTime(mapping.startTime, mapping.endTime);
    }

    // Không tự bịa giờ cho các tiết chưa có cấu hình chính thức (ví dụ tiết 5, 6 hoặc ngoài bảng)
    return null;
  }

  String _cleanSubjectName(String raw) {
    var s = raw.trim();
    s = s.replaceAll(
        RegExp(r'^(?:(?:HP|Học\s*phần|Tên\s*HP|Mã\s*HP|Môn\s*học|Môn)\s*[:\.\-]\s*|HP\s+)',
            caseSensitive: false),
        '').trim();
    s = s.replaceAll(RegExp(r'^[A-Za-z0-9\._\-]{3,10}\s*[-–—:]\s*'), '').trim();
    s = s.replaceAll(RegExp(r'^[\[\(\{"\x27]+|[\]\)\}"\x27]+$'), '').trim();
    return s;
  }

  bool _isMetadataLine(String line) {
    if (_clockTimeRangeRegex.hasMatch(line)) return true;
    if (_lessonPeriodRegex.hasMatch(line)) return true;
    if (_parenthesizedPeriodRegex.hasMatch(line)) return true;
    if (_teacherRegex.hasMatch(line)) return true;
    if (_roomRegex.hasMatch(line)) return true;
    if (_onlineRegex.hasMatch(line)) return true;
    if (_detectDayOfWeek(line) != null) return true;
    return false;
  }

  void _detectIntraBatchConflicts(List<ImportedScheduleItem> items) {
    for (int i = 0; i < items.length; i++) {
      final a = items[i];
      if (a.hasError || a.dayOfWeek == null || a.startTime == null || a.endTime == null) {
        continue;
      }
      final aStart = timeStringToMinutes(a.startTime);
      final aEnd = timeStringToMinutes(a.endTime);
      if (aStart == null || aEnd == null || aStart >= aEnd) continue;

      for (int j = i + 1; j < items.length; j++) {
        final b = items[j];
        if (b.hasError || b.dayOfWeek == null || b.startTime == null || b.endTime == null) {
          continue;
        }
        if (a.dayOfWeek != b.dayOfWeek) continue;

        final bStart = timeStringToMinutes(b.startTime);
        final bEnd = timeStringToMinutes(b.endTime);
        if (bStart == null || bEnd == null || bStart >= bEnd) continue;

        if (aStart < bEnd && bStart < aEnd) {
          b.status = ImportItemStatus.warningOverlap;
          b.warningMessage =
              'Trùng giờ với ${a.matchedSubjectName} (${a.startTime} - ${a.endTime}) trong cùng file';
          if (a.status != ImportItemStatus.warningOverlap) {
            a.status = ImportItemStatus.warningOverlap;
            a.warningMessage =
                'Trùng giờ với ${b.matchedSubjectName} (${b.startTime} - ${b.endTime}) trong cùng file';
          }
        }
      }
    }
  }

  ClassSchedule? _findOverlapping(
    List<ClassSchedule> existing,
    int dayOfWeek,
    String start,
    String end,
  ) {
    final startMin = timeStringToMinutes(start);
    final endMin = timeStringToMinutes(end);
    if (startMin == null || endMin == null || startMin >= endMin) return null;

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

class _ColumnBounds {
  final int dayOfWeek;
  final OcrTextBlock headerBlock;
  final double leftBound;
  final double rightBound;
  const _ColumnBounds({
    required this.dayOfWeek,
    required this.headerBlock,
    required this.leftBound,
    required this.rightBound,
  });
}

class _SessionRow {
  final String sessionName;
  final OcrTextBlock block;
  const _SessionRow({required this.sessionName, required this.block});
}

class _RowBounds {
  final String sessionName;
  final OcrTextBlock headerBlock;
  final double topBound;
  final double bottomBound;
  const _RowBounds({
    required this.sessionName,
    required this.headerBlock,
    required this.topBound,
    required this.bottomBound,
  });
}

class _MappedTime {
  final String start;
  final String end;
  const _MappedTime(this.start, this.end);
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

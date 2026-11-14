import '../models/class_schedule.dart';
import '../models/class_schedule_occurrence.dart';
import '../models/subject.dart';
import '../services/class_period_time_mapper.dart';

/// Trạng thái xác thực của một dòng thời khóa biểu được nhập từ file
enum ImportItemStatus {
  /// Dữ liệu hợp lệ, môn học đã khớp sẵn
  valid,

  /// Hợp lệ nhưng môn học chưa có trong danh mục (sẽ tự động tạo mới khi nhập)
  newSubject,

  /// Cảnh báo: Trùng khung giờ với một lịch học đã tồn tại
  warningOverlap,

  /// Lỗi: Thiếu trường bắt buộc (Tên môn, Thứ, hoặc Giờ)
  errorMissingField,

  /// Lỗi: Giờ học không hợp lệ (ví dụ: giờ bắt đầu >= giờ kết thúc)
  errorInvalidTime,
}

/// Tiện ích kiểm tra trạng thái lỗi của dòng nhập
extension ImportItemStatusExtension on ImportItemStatus {
  bool get hasError =>
      this == ImportItemStatus.errorMissingField ||
      this == ImportItemStatus.errorInvalidTime;
}

/// Kiểm tra xem chuỗi thời gian có đúng định dạng HH:mm với giờ 0..23 và phút 0..59 không
bool isValidTimeString(String? time) {
  if (time == null) return false;
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time.trim());
  if (match == null) return false;
  final h = int.tryParse(match.group(1)!);
  final m = int.tryParse(match.group(2)!);
  if (h == null || h < 0 || h > 23) return false;
  if (m == null || m < 0 || m > 59) return false;
  return true;
}

/// Đổi chuỗi thời gian HH:mm sang số phút tính từ 00:00 (hoặc null nếu không hợp lệ)
int? timeStringToMinutes(String? time) {
  if (!isValidTimeString(time)) return null;
  final parts = time!.trim().split(':');
  final h = int.parse(parts[0]);
  final m = int.parse(parts[1]);
  return h * 60 + m;
}

/// Kiểm tra xem một chuỗi tên có phải là từ khóa bị cấm / tiêu đề bảng / từ nhiễu không
bool isProhibitedSubjectName(String name) {
  final clean = name.trim().toLowerCase();
  if (clean.isEmpty) return true;

  // Tiêu đề ngày trong tuần
  const prohibitedDays = {
    'thứ',
    'thứ hai',
    'thứ 2',
    'thứ ba',
    'thứ 3',
    'thứ tư',
    'thứ 4',
    'thứ năm',
    'thứ 5',
    'thứ sáu',
    'thứ 6',
    'thứ bảy',
    'thứ 7',
    'chủ nhật',
    't2',
    't3',
    't4',
    't5',
    't6',
    't7',
    'cn',
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun',
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  };
  if (prohibitedDays.contains(clean)) return true;

  // Tiêu đề bảng / buổi học / siêu dữ liệu
  const prohibitedHeaders = {
    'buổi',
    'sáng',
    'chiều',
    'tối',
    'tiết',
    'stt',
    'hp',
    'học phần',
    'mã hp',
    'tên hp',
    'môn học',
    'môn',
    'giảng viên',
    'gv',
    'phòng',
    'phòng học',
    'hình thức',
    'thời khóa biểu',
    'lịch học',
    'tuần',
    'ngày',
  };
  if (prohibitedHeaders.contains(clean)) return true;

  // Tiêu đề tuần: "tuần 1", "tuần 11", ...
  if (clean.startsWith('tuần ') ||
      clean.startsWith('tuần:') ||
      RegExp(r'^tuần\s*\d+').hasMatch(clean)) {
    return true;
  }

  // Dải ngày: "từ ngày ... đến ngày ..."
  if (clean.startsWith('từ ngày') || clean.contains('đến ngày')) return true;

  return false;
}

/// Mô hình đại diện cho một mục thời khóa biểu được đọc và chuẩn hóa từ file
class ImportedScheduleItem {
  /// Số thứ tự dòng trong file gốc (bắt đầu từ 2 đối với file có header)
  final int rowIndex;

  /// Tên môn học đọc được từ file
  final String rawSubjectName;

  /// ID môn học đã liên kết (null nếu là môn mới)
  String? matchedSubjectId;

  /// Tên môn học hiển thị (có thể liên kết với môn có sẵn hoặc tạo mới)
  String matchedSubjectName;

  /// Đánh dấu môn học này cần tạo mới trong SubjectRepository
  bool isNewSubject;

  /// Thứ trong tuần (1 = Thứ Hai, ..., 7 = Chủ Nhật)
  final int? dayOfWeek;

  /// Ngày học cụ thể định dạng YYYY-MM-DD (Phase 6D)
  final String? classDate;

  /// Tiết bắt đầu và kết thúc (Phase 6D)
  final int? startPeriod;
  final int? endPeriod;

  /// Giờ bắt đầu ("HH:mm")
  final String? startTime;

  /// Giờ kết thúc ("HH:mm")
  final String? endTime;

  /// Địa điểm / phòng học
  final String location;

  /// Giảng viên phụ trách (Phase 6B)
  String teacher;

  /// Ghi chú
  final String notes;

  /// Độ tin cậy AI (0.0 .. 1.0)
  final double? confidence;

  /// Cần người dùng xem xét lại
  final bool needsReview;

  /// Lý do cần xem xét lại
  final String? reviewReason;

  /// Người dùng có chọn nhập mục này không
  bool isSelected;

  /// Trạng thái xác thực
  ImportItemStatus status;

  /// Thông báo lỗi chi tiết (nếu có)
  String? errorMessage;

  /// Thông báo cảnh báo (nếu có, ví dụ: trùng lịch)
  String? warningMessage;

  /// Đối tượng lịch học bị trùng giờ (nếu có)
  ClassSchedule? overlappingSchedule;

  ImportedScheduleItem({
    required this.rowIndex,
    required this.rawSubjectName,
    this.matchedSubjectId,
    required this.matchedSubjectName,
    this.isNewSubject = false,
    this.dayOfWeek,
    this.classDate,
    this.startPeriod,
    this.endPeriod,
    this.startTime,
    this.endTime,
    this.location = '',
    this.teacher = '',
    this.notes = '',
    this.confidence,
    this.needsReview = false,
    this.reviewReason,
    this.isSelected = true,
    this.status = ImportItemStatus.valid,
    this.errorMessage,
    this.warningMessage,
    this.overlappingSchedule,
  });

  /// Tạo bản sao có cập nhật các trường
  ImportedScheduleItem copyWith({
    int? rowIndex,
    String? rawSubjectName,
    String? matchedSubjectId,
    String? matchedSubjectName,
    bool? isNewSubject,
    int? dayOfWeek,
    String? classDate,
    int? startPeriod,
    int? endPeriod,
    String? startTime,
    String? endTime,
    String? location,
    String? teacher,
    String? notes,
    double? confidence,
    bool? needsReview,
    String? reviewReason,
    bool? isSelected,
    ImportItemStatus? status,
    String? errorMessage,
    String? warningMessage,
    ClassSchedule? overlappingSchedule,
  }) {
    return ImportedScheduleItem(
      rowIndex: rowIndex ?? this.rowIndex,
      rawSubjectName: rawSubjectName ?? this.rawSubjectName,
      matchedSubjectId: matchedSubjectId ?? this.matchedSubjectId,
      matchedSubjectName: matchedSubjectName ?? this.matchedSubjectName,
      isNewSubject: isNewSubject ?? this.isNewSubject,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      classDate: classDate ?? this.classDate,
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      teacher: teacher ?? this.teacher,
      notes: notes ?? this.notes,
      confidence: confidence ?? this.confidence,
      needsReview: needsReview ?? this.needsReview,
      reviewReason: reviewReason ?? this.reviewReason,
      isSelected: isSelected ?? this.isSelected,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      warningMessage: warningMessage ?? this.warningMessage,
      overlappingSchedule: overlappingSchedule ?? this.overlappingSchedule,
    );
  }

  /// Kiểm tra xem dòng này có lỗi chặn nhập hay không
  bool get hasError =>
      status == ImportItemStatus.errorMissingField ||
      status == ImportItemStatus.errorInvalidTime;

  /// Kiểm tra xem dòng này có thể lưu thành ClassSchedule hợp lệ hay không
  bool get isValidForSave {
    if (hasError) return false;
    int? effectiveDay = dayOfWeek;
    if (effectiveDay == null && classDate != null) {
      final dt = DateTime.tryParse(classDate!);
      if (dt != null) effectiveDay = dt.weekday;
    }
    if (effectiveDay == null || effectiveDay < 1 || effectiveDay > 7) return false;
    if (startTime == null || endTime == null) return false;
    if (!isValidTimeString(startTime) || !isValidTimeString(endTime)) return false;
    final startMin = timeStringToMinutes(startTime)!;
    final endMin = timeStringToMinutes(endTime)!;
    if (startMin >= endMin) return false;
    final trimmedName = matchedSubjectName.trim();
    if (trimmedName.isEmpty || isProhibitedSubjectName(trimmedName)) return false;
    return true;
  }

  /// Kiểm tra xem dòng này có thể lưu thành ClassScheduleOccurrence hợp lệ hay không
  bool get isValidForOccurrenceSave {
    if (hasError) return false;
    if (classDate == null || DateTime.tryParse(classDate!) == null) return false;
    if (startTime == null || endTime == null) return false;
    if (!isValidTimeString(startTime) || !isValidTimeString(endTime)) return false;
    final startMin = timeStringToMinutes(startTime)!;
    final endMin = timeStringToMinutes(endTime)!;
    if (startMin >= endMin) return false;
    final trimmedName = matchedSubjectName.trim();
    if (trimmedName.isEmpty || isProhibitedSubjectName(trimmedName)) return false;
    return true;
  }

  /// Tên thứ tiếng Việt hiển thị
  String get dayOfWeekText {
    int? effectiveDay = dayOfWeek;
    if (effectiveDay == null && classDate != null) {
      final dt = DateTime.tryParse(classDate!);
      if (dt != null) effectiveDay = dt.weekday;
    }
    if (effectiveDay == null) return 'Chưa rõ thứ';
    switch (effectiveDay) {
      case 1:
        return 'Thứ Hai';
      case 2:
        return 'Thứ Ba';
      case 3:
        return 'Thứ Tư';
      case 4:
        return 'Thứ Năm';
      case 5:
        return 'Thứ Sáu';
      case 6:
        return 'Thứ Bảy';
      case 7:
        return 'Chủ Nhật';
      default:
        return 'Thứ $effectiveDay';
    }
  }

  /// Khung giờ hiển thị ("HH:mm - HH:mm")
  String get timeRangeText {
    if (startTime == null && endTime == null) return 'Chưa rõ giờ';
    return '${startTime ?? '??'}' ' - ' '${endTime ?? '??'}';
  }

  /// Thời lượng học thực tế (phút) - Tự động loại bỏ thời gian nghỉ giải lao nếu có thông tin số tiết
  int get actualStudyMinutes {
    final mapped = ClassPeriodTimeMapper.getActualStudyMinutes(startPeriod, endPeriod);
    if (mapped != null) return mapped;
    if (startTime != null && endTime != null) {
      final s = timeStringToMinutes(startTime);
      final e = timeStringToMinutes(endTime);
      if (s != null && e != null && e > s) return e - s;
    }
    return 0;
  }

  /// Chuỗi hiển thị khoảng tiết học nếu có (ví dụ: "Tiết 1-4")
  String? get periodRangeText {
    if (startPeriod != null && endPeriod != null && startPeriod! > 0) {
      return 'Tiết $startPeriod-$endPeriod';
    }
    return null;
  }

  /// Chuyển đổi sang `ClassSchedule` để lưu vào cơ sở dữ liệu
  ClassSchedule toClassSchedule({required String targetSubjectId}) {
    if (!isValidForSave) {
      throw StateError(
        'Không thể chuyển đổi mục thời khóa biểu không hợp lệ sang ClassSchedule: '
        'môn="$matchedSubjectName", thứ=$dayOfWeek, ngày=$classDate, giờ="$startTime - $endTime", trạng thái=$status',
      );
    }
    int? effectiveDay = dayOfWeek;
    if (effectiveDay == null && classDate != null) {
      final dt = DateTime.tryParse(classDate!);
      if (dt != null) effectiveDay = dt.weekday;
    }
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final generatedId = 'sched_imp_${timestamp}_$rowIndex';

    return ClassSchedule(
      id: generatedId,
      subjectId: targetSubjectId,
      subjectName: matchedSubjectName.trim(),
      dayOfWeek: effectiveDay ?? 1,
      startTime: startTime!,
      endTime: endTime!,
      location: location.trim(),
      teacher: teacher.trim(),
      notes: notes.trim(),
      isActive: true,
      repeatWeekly: true,
    );
  }

  /// Chuyển đổi sang `ClassScheduleOccurrence` để lưu vào cơ sở dữ liệu (Phase 6D)
  ClassScheduleOccurrence toOccurrence({required String targetSubjectId}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final generatedId = 'occ_imp_${timestamp}_$rowIndex';

    return ClassScheduleOccurrence(
      id: generatedId,
      scheduleId: null,
      subjectId: targetSubjectId,
      subjectName: matchedSubjectName.trim(),
      classDate: classDate ?? DateTime.now().toIso8601String().substring(0, 10),
      startTime: startTime ?? '08:00',
      endTime: endTime ?? '09:30',
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      teacher: teacher.trim(),
      location: location.trim(),
      notes: notes.trim(),
      status: 'scheduled',
      source: 'image_import',
      createdAt: DateTime.now().toIso8601String(),
      updatedAt: DateTime.now().toIso8601String(),
    );
  }
}

/// Kết quả phân tích toàn bộ file nhập
class TimetableParseResult {
  final String fileName;
  final int totalRowsRead;
  final List<ImportedScheduleItem> items;
  final List<String> warnings;
  final String? fatalError;

  const TimetableParseResult({
    required this.fileName,
    required this.totalRowsRead,
    required this.items,
    this.warnings = const [],
    this.fatalError,
  });

  bool get isSuccess => fatalError == null && items.isNotEmpty;
  int get validCount => items.where((i) => !i.hasError).length;
  int get errorCount => items.where((i) => i.hasError).length;
  int get selectedCount => items.where((i) => i.isSelected && !i.hasError).length;
}

/// Tóm tắt sau khi thực thi nhập vào cơ sở dữ liệu
class TimetableImportSummary {
  final int importedCount;
  final int skippedCount;
  final int errorCount;
  final int createdSubjectsCount;
  final List<Subject> createdSubjects;

  const TimetableImportSummary({
    required this.importedCount,
    required this.skippedCount,
    required this.errorCount,
    required this.createdSubjectsCount,
    this.createdSubjects = const [],
  });
}

import '../models/class_schedule.dart';
import '../models/subject.dart';

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
    this.startTime,
    this.endTime,
    this.location = '',
    this.teacher = '',
    this.notes = '',
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
    String? startTime,
    String? endTime,
    String? location,
    String? teacher,
    String? notes,
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
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      teacher: teacher ?? this.teacher,
      notes: notes ?? this.notes,
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
  bool get isValidForSave =>
      !hasError &&
      dayOfWeek != null &&
      startTime != null &&
      endTime != null &&
      matchedSubjectName.trim().isNotEmpty;

  /// Tên thứ tiếng Việt hiển thị
  String get dayOfWeekText {
    if (dayOfWeek == null) return 'Chưa rõ thứ';
    switch (dayOfWeek!) {
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
        return 'Thứ $dayOfWeek';
    }
  }

  /// Khung giờ hiển thị ("HH:mm - HH:mm")
  String get timeRangeText {
    if (startTime == null && endTime == null) return 'Chưa rõ giờ';
    return '${startTime ?? '??'}' ' - ' '${endTime ?? '??'}';
  }

  /// Chuyển đổi sang `ClassSchedule` để lưu vào cơ sở dữ liệu
  ClassSchedule toClassSchedule({required String targetSubjectId}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final generatedId = 'sched_imp_${timestamp}_$rowIndex';

    return ClassSchedule(
      id: generatedId,
      subjectId: targetSubjectId,
      subjectName: matchedSubjectName.trim(),
      dayOfWeek: dayOfWeek ?? 1,
      startTime: startTime ?? '08:00',
      endTime: endTime ?? '09:30',
      location: location.trim(),
      teacher: teacher.trim(),
      notes: notes.trim(),
      isActive: true,
      repeatWeekly: true,
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

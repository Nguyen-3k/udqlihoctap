import 'class_schedule.dart';
import 'class_schedule_occurrence.dart';
import '../services/class_period_time_mapper.dart';

/// Đại diện cho một buổi học trích xuất từ Gemini Vision AI
class AiTimetableClass {
  final String subject;
  final String? classDate; // Định dạng "YYYY-MM-DD"
  final int? weekday; // 1 = Thứ Hai ... 7 = Chủ Nhật
  final String? session; // 'morning', 'afternoon', 'evening'
  final int? startPeriod;
  final int? endPeriod;
  final String? startTime; // "HH:mm" nếu có
  final String? endTime; // "HH:mm" nếu có
  final String? teacher;
  final String? location;
  final String? format; // 'offline', 'online', 'hybrid'
  final String? notes;
  final double confidence; // 0.0 .. 1.0
  final bool needsReview;
  final List<String> reviewReasons;

  // Trường hỗ trợ người dùng chỉnh sửa trong UI
  final bool isSelected;
  final String? matchedSubjectId;
  final String customSubjectName;

  const AiTimetableClass({
    required this.subject,
    this.classDate,
    this.weekday,
    this.session,
    this.startPeriod,
    this.endPeriod,
    this.startTime,
    this.endTime,
    this.teacher,
    this.location,
    this.format,
    this.notes,
    this.confidence = 0.9,
    this.needsReview = false,
    this.reviewReasons = const [],
    this.isSelected = true,
    this.matchedSubjectId,
    this.customSubjectName = '',
  });

  String get effectiveSubjectName {
    final custom = customSubjectName.trim();
    if (custom.isNotEmpty) return custom;
    return subject.trim();
  }

  String get subjectName => effectiveSubjectName;
  int? get dayOfWeek => weekday;
  String? get reviewReason =>
      reviewReasons.isNotEmpty ? reviewReasons.join('; ') : null;

  bool get hasSpecificDate =>
      classDate != null &&
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(classDate!.trim());

  bool get hasTime =>
      startTime != null &&
      endTime != null &&
      startTime!.trim().isNotEmpty &&
      endTime!.trim().isNotEmpty;

  String get weekdayText {
    if (weekday == null || weekday! < 1 || weekday! > 7) {
      return 'Chưa rõ thứ';
    }
    switch (weekday!) {
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
        return 'Thứ $weekday';
    }
  }

  String get sessionText {
    switch (session?.toLowerCase()) {
      case 'morning':
        return 'Sáng';
      case 'afternoon':
        return 'Chiều';
      case 'evening':
        return 'Tối';
      default:
        return 'Chưa rõ buổi';
    }
  }

  String get periodText {
    if (startPeriod != null && endPeriod != null && startPeriod! > 0) {
      return 'Tiết $startPeriod-$endPeriod';
    }
    return '';
  }

  String get timeOrPeriodText {
    if (hasTime) {
      return '$startTime - $endTime${periodText.isNotEmpty ? ' ($periodText)' : ''}';
    }
    if (periodText.isNotEmpty) {
      return periodText;
    }
    return 'Chưa có giờ cụ thể';
  }

  String get dateDisplay {
    if (!hasSpecificDate) return 'Chưa có ngày';
    try {
      final parts = classDate!.split('-');
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    } catch (_) {
      return classDate!;
    }
  }

  AiTimetableClass copyWith({
    String? subject,
    String? classDate,
    int? weekday,
    String? session,
    int? startPeriod,
    int? endPeriod,
    String? startTime,
    String? endTime,
    String? teacher,
    String? location,
    String? format,
    String? notes,
    double? confidence,
    bool? needsReview,
    List<String>? reviewReasons,
    bool? isSelected,
    String? matchedSubjectId,
    String? customSubjectName,
  }) {
    return AiTimetableClass(
      subject: subject ?? this.subject,
      classDate: classDate ?? this.classDate,
      weekday: weekday ?? this.weekday,
      session: session ?? this.session,
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      teacher: teacher ?? this.teacher,
      location: location ?? this.location,
      format: format ?? this.format,
      notes: notes ?? this.notes,
      confidence: confidence ?? this.confidence,
      needsReview: needsReview ?? this.needsReview,
      reviewReasons: reviewReasons ?? this.reviewReasons,
      isSelected: isSelected ?? this.isSelected,
      matchedSubjectId: matchedSubjectId ?? this.matchedSubjectId,
      customSubjectName: customSubjectName ?? this.customSubjectName,
    );
  }

  factory AiTimetableClass.fromJson(Map<String, dynamic> json) {
    int? parsePeriod(dynamic val) {
      if (val == null) return null;
      if (val is num && val > 0) return val.toInt();
      if (val is String) {
        final p = int.tryParse(val.trim());
        if (p != null && p > 0) return p;
      }
      return null;
    }

    String? parseString(dynamic val) {
      if (val == null) return null;
      final str = val.toString().trim();
      return str.isNotEmpty ? str : null;
    }

    final rawSubject = json['subject']?.toString().trim() ?? '';
    final rawDate = parseString(json['classDate']);
    final rawWeekday = (json['weekday'] as num?)?.toInt();
    final effectiveWeekday =
        (rawWeekday != null && rawWeekday >= 1 && rawWeekday <= 7)
            ? rawWeekday
            : null;

    final rawConfidence = (json['confidence'] as num?)?.toDouble() ?? 0.9;
    final clampedConfidence = rawConfidence.clamp(0.0, 1.0);

    final reasonsList = <String>[];
    if (json['reviewReasons'] is List) {
      for (final r in json['reviewReasons'] as List) {
        if (r != null && r.toString().trim().isNotEmpty) {
          reasonsList.add(r.toString().trim());
        }
      }
    }

    return AiTimetableClass(
      subject: rawSubject,
      classDate: rawDate,
      weekday: effectiveWeekday,
      session: parseString(json['session']),
      startPeriod: parsePeriod(json['startPeriod']),
      endPeriod: parsePeriod(json['endPeriod']),
      startTime: parseString(json['startTime']),
      endTime: parseString(json['endTime']),
      teacher: parseString(json['teacher']),
      location: parseString(json['location']),
      format: parseString(json['format']),
      notes: parseString(json['notes']),
      confidence: clampedConfidence,
      needsReview: json['needsReview'] == true,
      reviewReasons: reasonsList,
    );
  }

  /// Chuyển đổi thành ClassScheduleOccurrence (Lịch học theo ngày cụ thể)
  ClassScheduleOccurrence toOccurrence({
    required String targetSubjectId,
    String fallbackStartTime = '08:00',
    String fallbackEndTime = '09:30',
  }) {
    final now = DateTime.now();
    final timestamp = now.millisecondsSinceEpoch;
    final generatedId = 'occ_ai_${timestamp}_${uniqueIndex++}';

    // Ngày học bắt buộc phải có
    final resolvedDate = hasSpecificDate
        ? classDate!
        : '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // Quy đổi giờ học: Ưu tiên giờ rõ ràng, nếu thiếu dùng ClassPeriodTimeMapper từ số tiết
    final mapped = ClassPeriodTimeMapper.mapPeriodsToTime(startPeriod, endPeriod);
    final effectiveStart = hasTime ? startTime! : (mapped?.startTime ?? fallbackStartTime);
    final effectiveEnd = hasTime ? endTime! : (mapped?.endTime ?? fallbackEndTime);

    return ClassScheduleOccurrence(
      id: generatedId,
      scheduleId: null, // Buổi học riêng theo ngày từ import AI
      subjectId: targetSubjectId,
      subjectName: effectiveSubjectName,
      classDate: resolvedDate,
      startTime: effectiveStart,
      endTime: effectiveEnd,
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      teacher: teacher?.trim() ?? '',
      location: location?.trim() ?? '',
      notes: notes?.trim() ?? '',
      status: 'scheduled',
      source: 'image_import',
      createdAt: now.toIso8601String(),
      updatedAt: now.toIso8601String(),
    );
  }

  /// Chuyển đổi thành ClassSchedule (Thời khóa biểu cố định theo tuần)
  ClassSchedule toClassSchedule({
    required String targetSubjectId,
    String fallbackStartTime = '08:00',
    String fallbackEndTime = '09:30',
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final generatedId = 'sched_ai_${timestamp}_${uniqueIndex++}';

    // Quy đổi giờ học: Ưu tiên giờ rõ ràng, nếu thiếu dùng ClassPeriodTimeMapper từ số tiết
    final mapped = ClassPeriodTimeMapper.mapPeriodsToTime(startPeriod, endPeriod);
    final effectiveStart = hasTime ? startTime! : (mapped?.startTime ?? fallbackStartTime);
    final effectiveEnd = hasTime ? endTime! : (mapped?.endTime ?? fallbackEndTime);

    return ClassSchedule(
      id: generatedId,
      subjectId: targetSubjectId,
      subjectName: effectiveSubjectName,
      dayOfWeek: weekday ?? 1,
      startTime: effectiveStart,
      endTime: effectiveEnd,
      location: location?.trim() ?? '',
      teacher: teacher?.trim() ?? '',
      notes: notes?.trim() ?? '',
      isActive: true,
      repeatWeekly: true,
    );
  }

  static int uniqueIndex = 0;
}

/// Bảng thời khóa biểu cho một tuần
class AiTimetableWeek {
  final String? startDate;
  final String? endDate;
  final int? weekNumber;
  final List<AiTimetableClass> classes;

  const AiTimetableWeek({
    this.startDate,
    this.endDate,
    this.weekNumber,
    required this.classes,
  });

  factory AiTimetableWeek.fromJson(Map<String, dynamic> json) {
    final rawClasses = json['classes'] is List ? json['classes'] as List : [];
    final list = <AiTimetableClass>[];
    for (final item in rawClasses) {
      if (item is Map<String, dynamic>) {
        list.add(AiTimetableClass.fromJson(item));
      } else if (item is Map) {
        list.add(AiTimetableClass.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    return AiTimetableWeek(
      startDate: json['startDate']?.toString().trim(),
      endDate: json['endDate']?.toString().trim(),
      weekNumber: (json['weekNumber'] as num?)?.toInt(),
      classes: list,
    );
  }
}

/// Kết quả phân tích toàn bộ ảnh từ Gemini Vision
class AiTimetableResult {
  final bool success;
  final String message;
  final List<AiTimetableWeek> weeks;
  final List<String> warnings;
  final int totalDetected;
  final int validCount;
  final int needsReviewCount;
  final int ignoredCount;

  const AiTimetableResult({
    required this.success,
    required this.message,
    required this.weeks,
    this.warnings = const [],
    this.totalDetected = 0,
    this.validCount = 0,
    this.needsReviewCount = 0,
    this.ignoredCount = 0,
  });

  /// Danh sách tất cả các buổi học được phát hiện từ mọi tuần
  List<AiTimetableClass> get allClasses {
    final list = <AiTimetableClass>[];
    for (final w in weeks) {
      list.addAll(w.classes);
    }
    return list;
  }

  /// Alias tiện lợi tương đương allClasses
  List<AiTimetableClass> get classes => allClasses;

  /// Thông báo lỗi nếu thất bại
  String? get errorMessage => success
      ? null
      : (message.isNotEmpty
          ? message
          : (warnings.isNotEmpty ? warnings.first : 'Lỗi không xác định'));

  factory AiTimetableResult.fromJson(Map<String, dynamic> json) {
    final rawWeeks = json['weeks'] is List ? json['weeks'] as List : [];
    final weeksList = <AiTimetableWeek>[];
    for (final w in rawWeeks) {
      if (w is Map<String, dynamic>) {
        weeksList.add(AiTimetableWeek.fromJson(w));
      } else if (w is Map) {
        weeksList.add(AiTimetableWeek.fromJson(Map<String, dynamic>.from(w)));
      }
    }

    final rawWarnings =
        json['warnings'] is List ? json['warnings'] as List : [];
    final warningsList = rawWarnings.map((e) => e.toString()).toList();

    final summary = json['summary'] is Map ? json['summary'] as Map : {};
    final total = (summary['totalDetected'] as num?)?.toInt() ?? 0;
    final valid = (summary['validCount'] as num?)?.toInt() ?? 0;
    final needsReview = (summary['needsReviewCount'] as num?)?.toInt() ?? 0;
    final ignored = (summary['ignoredCount'] as num?)?.toInt() ?? 0;

    final resolvedMessage = json['message']?.toString() ??
        json['error']?.toString() ??
        '';

    final isSuccess = json['success'] == true && json['error'] == null;

    return AiTimetableResult(
      success: isSuccess,
      message: resolvedMessage,
      weeks: weeksList,
      warnings: warningsList,
      totalDetected: total,
      validCount: valid,
      needsReviewCount: needsReview,
      ignoredCount: ignored,
    );
  }

  factory AiTimetableResult.error(String message) {
    return AiTimetableResult(
      success: false,
      message: message,
      weeks: const [],
      warnings: [message],
    );
  }
}

import 'package:flutter/foundation.dart';
import '../services/class_period_time_mapper.dart';

/// Đại diện cho một buổi học diễn ra vào một ngày cụ thể (Phase 6D).
/// Phục vụ:
/// 1. Lịch học riêng theo ngày (nhập từ ảnh thời khóa biểu nhiều tuần).
/// 2. Điều chỉnh thông tin (giờ, phòng, giảng viên) của một buổi học cố định (`scheduleId` != null).
/// 3. Hủy một buổi học cụ thể (`status == 'cancelled'`).
@immutable
class ClassScheduleOccurrence {
  final String id;
  final String? scheduleId; // null = Buổi học riêng lẻ theo ngày; non-null = Ghi đè lịch cố định
  final String subjectId;
  final String subjectName;
  final String classDate; // Định dạng "YYYY-MM-DD"
  final String startTime; // Định dạng "HH:mm" (24h)
  final String endTime; // Định dạng "HH:mm" (24h)
  final int? startPeriod;
  final int? endPeriod;
  final String teacher;
  final String location;
  final String notes;
  final String status; // 'scheduled' (hoạt động) hoặc 'cancelled' (bị hủy)
  final String source; // 'image_import', 'manual', 'override'
  final String createdAt;
  final String updatedAt;

  const ClassScheduleOccurrence({
    required this.id,
    this.scheduleId,
    required this.subjectId,
    required this.subjectName,
    required this.classDate,
    required this.startTime,
    required this.endTime,
    this.startPeriod,
    this.endPeriod,
    this.teacher = '',
    this.location = '',
    this.notes = '',
    this.status = 'scheduled',
    this.source = 'image_import',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isCancelled => status.toLowerCase() == 'cancelled';
  bool get isScheduled => !isCancelled;

  int get startHour {
    final parts = startTime.split(':');
    return parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
  }

  int get startMinute {
    final parts = startTime.split(':');
    return parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  }

  int get endHour {
    final parts = endTime.split(':');
    return parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
  }

  int get endMinute {
    final parts = endTime.split(':');
    return parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  }

  int get startMinutesSinceMidnight => startHour * 60 + startMinute;
  int get endMinutesSinceMidnight => endHour * 60 + endMinute;

  String get timeRangeText => '$startTime - $endTime';

  /// Thời lượng học thực tế (phút) - Tự động loại bỏ thời gian nghỉ giải lao nếu có thông tin số tiết
  int get actualStudyMinutes {
    final mapped = ClassPeriodTimeMapper.getActualStudyMinutes(startPeriod, endPeriod);
    if (mapped != null) return mapped;
    return (endMinutesSinceMidnight - startMinutesSinceMidnight).clamp(0, 1440);
  }

  /// Chuỗi hiển thị khoảng tiết học nếu có (ví dụ: "Tiết 1-4")
  String? get periodRangeText {
    if (startPeriod != null && endPeriod != null && startPeriod! > 0) {
      return 'Tiết $startPeriod-$endPeriod';
    }
    return null;
  }

  DateTime? get dateParsed {
    try {
      return DateTime.parse(classDate);
    } catch (_) {
      return null;
    }
  }

  String get dateDisplay {
    try {
      final parts = classDate.split('-');
      if (parts.length == 3) {
        return '${parts[2]}/${parts[1]}/${parts[0]}';
      }
    } catch (_) {}
    return classDate;
  }

  ClassScheduleOccurrence copyWith({
    String? id,
    String? scheduleId,
    String? subjectId,
    String? subjectName,
    String? classDate,
    String? startTime,
    String? endTime,
    int? startPeriod,
    int? endPeriod,
    String? teacher,
    String? location,
    String? notes,
    String? status,
    String? source,
    String? createdAt,
    String? updatedAt,
  }) {
    return ClassScheduleOccurrence(
      id: id ?? this.id,
      scheduleId: scheduleId ?? this.scheduleId,
      subjectId: subjectId ?? this.subjectId,
      subjectName: subjectName ?? this.subjectName,
      classDate: classDate ?? this.classDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      startPeriod: startPeriod ?? this.startPeriod,
      endPeriod: endPeriod ?? this.endPeriod,
      teacher: teacher ?? this.teacher,
      location: location ?? this.location,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      source: source ?? this.source,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'schedule_id': scheduleId,
      'subject_id': subjectId,
      'subject_name': subjectName,
      'class_date': classDate,
      'start_time': startTime,
      'end_time': endTime,
      'start_period': startPeriod,
      'end_period': endPeriod,
      'teacher': teacher,
      'location': location,
      'notes': notes,
      'status': status,
      'source': source,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory ClassScheduleOccurrence.fromMap(Map<String, dynamic> map) {
    return ClassScheduleOccurrence(
      id: map['id']?.toString() ?? '',
      scheduleId: map['schedule_id']?.toString(),
      subjectId: map['subject_id']?.toString() ?? '',
      subjectName: map['subject_name']?.toString() ?? 'Môn học',
      classDate: map['class_date']?.toString() ?? '',
      startTime: map['start_time']?.toString() ?? '08:00',
      endTime: map['end_time']?.toString() ?? '09:30',
      startPeriod: (map['start_period'] as num?)?.toInt(),
      endPeriod: (map['end_period'] as num?)?.toInt(),
      teacher: map['teacher']?.toString() ?? '',
      location: map['location']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      status: map['status']?.toString() ?? 'scheduled',
      source: map['source']?.toString() ?? 'image_import',
      createdAt: map['created_at']?.toString() ?? DateTime.now().toIso8601String(),
      updatedAt: map['updated_at']?.toString() ?? DateTime.now().toIso8601String(),
    );
  }
}

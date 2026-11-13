import 'package:flutter/foundation.dart';
import 'alarm_state.dart';

/// Đại diện cho một lịch học cố định theo tuần trong ExamPilot (Phase 4.3).
/// Mỗi lịch học gắn với một môn học cụ thể (`subjectId`), thứ trong tuần (1..7),
/// giờ bắt đầu, giờ kết thúc, địa điểm và ghi chú tùy chọn.
@immutable
class ClassSchedule {
  final String id;
  final String subjectId;
  final String subjectName;
  final int dayOfWeek; // 1 = Thứ Hai, 7 = Chủ Nhật (DateTime.monday .. DateTime.sunday)
  final String startTime; // Định dạng "HH:mm" (24h), ví dụ: "08:00"
  final String endTime; // Định dạng "HH:mm" (24h), ví dụ: "09:30"
  final String location; // Tùy chọn (ví dụ: "Phòng B204")
  final String teacher; // Giảng viên phụ trách (tùy chọn)
  final String notes; // Ghi chú tùy chọn
  final bool isActive; // Trạng thái bật/tắt lịch học
  final bool repeatWeekly; // Có lặp lại hàng tuần hay không

  const ClassSchedule({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.location = '',
    this.teacher = '',
    this.notes = '',
    this.isActive = true,
    this.repeatWeekly = true,
  });

  /// Giờ và phút bắt đầu
  int get startHour {
    final parts = startTime.split(':');
    return parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
  }

  int get startMinute {
    final parts = startTime.split(':');
    return parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  }

  /// Giờ và phút kết thúc
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

  /// Kiểm tra tính hợp lệ: giờ bắt đầu phải nhỏ hơn giờ kết thúc
  bool get isValidTime =>
      startMinutesSinceMidnight < endMinutesSinceMidnight;

  /// Chuỗi hiển thị khoảng thời gian: "08:00 - 09:30"
  String get timeRangeText => '$startTime - $endTime';

  /// Tên thứ trong tuần hiển thị bằng Tiếng Việt
  String get dayOfWeekText {
    switch (dayOfWeek) {
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

  /// Tên viết tắt thứ trong tuần (T2, T3, ..., CN)
  String get dayOfWeekShortText {
    switch (dayOfWeek) {
      case 1:
        return 'T2';
      case 2:
        return 'T3';
      case 3:
        return 'T4';
      case 4:
        return 'T5';
      case 5:
        return 'T6';
      case 6:
        return 'T7';
      case 7:
        return 'CN';
      default:
        return 'T$dayOfWeek';
    }
  }

  /// Kiểm tra trùng thời gian với một lịch học khác trên cùng thứ trong tuần
  bool overlapsWith(ClassSchedule other) {
    if (dayOfWeek != other.dayOfWeek) return false;
    if (id == other.id) return false;
    // Giao nhau giữa 2 khoảng thời gian [start, end)
    return startMinutesSinceMidnight < other.endMinutesSinceMidnight &&
        other.startMinutesSinceMidnight < endMinutesSinceMidnight;
  }

  /// Tạo các buổi học thực tế (`ScheduledStudySlot`) sắp tới trong khoảng `daysAhead` ngày
  /// tính từ thời điểm địa phương `fromTime`.
  List<ScheduledStudySlot> generateUpcomingSlots({
    DateTime? fromTime,
    int daysAhead = 14,
  }) {
    if (!isActive) return const [];
    final now = fromTime ?? DateTime.now();
    final results = <ScheduledStudySlot>[];

    for (int dayOffset = 0; dayOffset < daysAhead; dayOffset++) {
      final date = DateTime(now.year, now.month, now.day + dayOffset);
      if (date.weekday == dayOfWeek) {
        final slotStart = DateTime(
          date.year,
          date.month,
          date.day,
          startHour,
          startMinute,
        );

        if (slotStart.isAfter(now)) {
          final dateStr =
              '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
          results.add(
            ScheduledStudySlot(
              id: '${id}_$dateStr',
              subjectId: subjectId,
              subjectName: subjectName,
              taskTitle: location.isNotEmpty ? 'Tại $location' : null,
              startAtUtc: slotStart.toUtc(),
              isCancelled: !isActive,
            ),
          );

          if (!repeatWeekly) {
            break; // Nếu không lặp lại hàng tuần, chỉ tạo một lần xuất hiện gần nhất
          }
        }
      }
    }

    return results;
  }

  ClassSchedule copyWith({
    String? id,
    String? subjectId,
    String? subjectName,
    int? dayOfWeek,
    String? startTime,
    String? endTime,
    String? location,
    String? teacher,
    String? notes,
    bool? isActive,
    bool? repeatWeekly,
  }) {
    return ClassSchedule(
      id: id ?? this.id,
      subjectId: subjectId ?? this.subjectId,
      subjectName: subjectName ?? this.subjectName,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      location: location ?? this.location,
      teacher: teacher ?? this.teacher,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      repeatWeekly: repeatWeekly ?? this.repeatWeekly,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject_id': subjectId,
      'subject_name': subjectName,
      'day_of_week': dayOfWeek,
      'start_time': startTime,
      'end_time': endTime,
      'location': location,
      'teacher': teacher,
      'notes': notes,
      'is_active': isActive ? 1 : 0,
      'repeat_weekly': repeatWeekly ? 1 : 0,
    };
  }

  factory ClassSchedule.fromMap(Map<String, dynamic> map) {
    return ClassSchedule(
      id: map['id']?.toString() ?? '',
      subjectId: map['subject_id']?.toString() ?? '',
      subjectName: map['subject_name']?.toString() ?? 'Môn học',
      dayOfWeek: (map['day_of_week'] as num?)?.toInt() ?? 1,
      startTime: map['start_time']?.toString() ?? '08:00',
      endTime: map['end_time']?.toString() ?? '09:30',
      location: map['location']?.toString() ?? '',
      teacher: map['teacher']?.toString() ?? '',
      notes: map['notes']?.toString() ?? '',
      isActive: map['is_active'] == 1 || map['is_active'] == true,
      repeatWeekly: map['repeat_weekly'] == null ||
          map['repeat_weekly'] == 1 ||
          map['repeat_weekly'] == true,
    );
  }
}

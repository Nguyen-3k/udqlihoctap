import 'package:flutter/foundation.dart';
import '../models/alarm_state.dart';
import '../models/class_schedule.dart';
import '../models/class_schedule_occurrence.dart';
import 'class_period_time_mapper.dart';

/// Buổi học đã được hợp nhất từ Lịch cố định và Lịch riêng theo ngày (Phase 6D).
@immutable
class ResolvedScheduleItem {
  final String id;
  final String subjectId;
  final String subjectName;
  final String classDate; // "YYYY-MM-DD"
  final String startTime;
  final String endTime;
  final int? startPeriod;
  final int? endPeriod;
  final String location;
  final String teacher;
  final String notes;
  final bool isOccurrence; // True nếu là lịch riêng theo ngày hoặc lịch điều chỉnh
  final bool isOverride; // True nếu là lịch điều chỉnh thay thế một lịch cố định
  final bool isCancelled; // True nếu buổi học này bị hủy
  final String? originalScheduleId;
  final String? occurrenceId;
  final String source;

  const ResolvedScheduleItem({
    required this.id,
    required this.subjectId,
    required this.subjectName,
    required this.classDate,
    required this.startTime,
    required this.endTime,
    this.startPeriod,
    this.endPeriod,
    this.location = '',
    this.teacher = '',
    this.notes = '',
    this.isOccurrence = false,
    this.isOverride = false,
    this.isCancelled = false,
    this.originalScheduleId,
    this.occurrenceId,
    this.source = 'fixed_schedule',
  });

  String get timeRangeText => '$startTime - $endTime';

  /// Tổng số phút học thực tế (loại bỏ thời gian giải lao 30 phút nếu có)
  int get actualStudyMinutes {
    final fromPeriod =
        ClassPeriodTimeMapper.getActualStudyMinutes(startPeriod, endPeriod);
    if (fromPeriod != null) return fromPeriod;
    final sMin = startHour * 60 + startMinute;
    final parts = endTime.split(':');
    final eHour = parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
    final eMin = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final total = (eHour * 60 + eMin) - sMin;
    return total > 0 ? total : 0;
  }

  /// Chuỗi hiển thị khoảng tiết học nếu có (ví dụ: "Tiết 1-4")
  String? get periodRangeText {
    if (startPeriod != null && endPeriod != null && startPeriod! > 0) {
      return 'Tiết $startPeriod-$endPeriod';
    }
    return null;
  }

  int get startHour {
    final parts = startTime.split(':');
    return parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 0) : 0;
  }

  int get startMinute {
    final parts = startTime.split(':');
    return parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  }

  int get startMinutesSinceMidnight => startHour * 60 + startMinute;
}

/// Bộ giải quyết lịch học tập trung (ClassScheduleResolver).
/// Hợp nhất:
/// 1. Lịch cố định hàng tuần (`ClassSchedule`).
/// 2. Lịch học riêng theo ngày (`ClassScheduleOccurrence` với `scheduleId == null`).
/// 3. Lịch điều chỉnh một buổi cụ thể (`ClassScheduleOccurrence` với `scheduleId != null`).
/// 4. Lịch bị hủy một buổi cụ thể (`ClassScheduleOccurrence` với `status == 'cancelled'`).
class ClassScheduleResolver {
  const ClassScheduleResolver();

  /// Tổng hợp danh sách các buổi học cho một ngày cụ thể
  List<ResolvedScheduleItem> resolveForDate({
    required List<ClassSchedule> fixedSchedules,
    required List<ClassScheduleOccurrence> occurrences,
    required DateTime date,
  }) {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final weekday = date.weekday;

    final results = <ResolvedScheduleItem>[];

    // 1. Duyệt các lịch học cố định của thứ này
    final activeSchedulesForDay =
        fixedSchedules.where((s) => s.isActive && s.dayOfWeek == weekday);

    for (final schedule in activeSchedulesForDay) {
      // Tìm xem có bản ghi occurrence nào điều chỉnh hoặc hủy buổi này không
      ClassScheduleOccurrence? matchOcc;
      for (final occ in occurrences) {
        if (occ.scheduleId == schedule.id && occ.classDate == dateStr) {
          matchOcc = occ;
          break;
        }
      }

      if (matchOcc != null) {
        if (matchOcc.isCancelled) {
          // Buổi học bị hủy: Không đưa vào danh sách hiển thị
          continue;
        } else {
          // Buổi học bị điều chỉnh (Override): Dùng thông tin từ Occurrence
          results.add(
            ResolvedScheduleItem(
              id: 'resolved_override_${matchOcc.id}',
              subjectId: matchOcc.subjectId,
              subjectName: matchOcc.subjectName,
              classDate: dateStr,
              startTime: matchOcc.startTime,
              endTime: matchOcc.endTime,
              startPeriod: matchOcc.startPeriod,
              endPeriod: matchOcc.endPeriod,
              location: matchOcc.location,
              teacher: matchOcc.teacher,
              notes: matchOcc.notes,
              isOccurrence: true,
              isOverride: true,
              isCancelled: false,
              originalScheduleId: schedule.id,
              occurrenceId: matchOcc.id,
              source: matchOcc.source,
            ),
          );
        }
      } else {
        // Buổi học cố định diễn ra bình thường
        results.add(
          ResolvedScheduleItem(
            id: 'resolved_sched_${schedule.id}_$dateStr',
            subjectId: schedule.subjectId,
            subjectName: schedule.subjectName,
            classDate: dateStr,
            startTime: schedule.startTime,
            endTime: schedule.endTime,
            location: schedule.location,
            teacher: schedule.teacher,
            notes: schedule.notes,
            isOccurrence: false,
            isOverride: false,
            isCancelled: false,
            originalScheduleId: schedule.id,
            source: 'fixed_schedule',
          ),
        );
      }
    }

    // 2. Duyệt các lịch riêng lẻ theo ngày (scheduleId == null) của ngày này
    final standaloneOccurrences = occurrences.where((occ) =>
        occ.scheduleId == null &&
        occ.classDate == dateStr &&
        occ.isScheduled);

    for (final occ in standaloneOccurrences) {
      results.add(
        ResolvedScheduleItem(
          id: 'resolved_standalone_${occ.id}',
          subjectId: occ.subjectId,
          subjectName: occ.subjectName,
          classDate: dateStr,
          startTime: occ.startTime,
          endTime: occ.endTime,
          startPeriod: occ.startPeriod,
          endPeriod: occ.endPeriod,
          location: occ.location,
          teacher: occ.teacher,
          notes: occ.notes,
          isOccurrence: true,
          isOverride: false,
          isCancelled: false,
          occurrenceId: occ.id,
          source: occ.source,
        ),
      );
    }

    // Sắp xếp theo giờ bắt đầu
    results.sort(
        (a, b) => a.startMinutesSinceMidnight.compareTo(b.startMinutesSinceMidnight));

    return results;
  }

  /// Tạo danh sách các slot học tập sắp tới (`ScheduledStudySlot`) cho hệ thống Thông báo & Báo thức
  List<ScheduledStudySlot> resolveSlots({
    required List<ClassSchedule> fixedSchedules,
    required List<ClassScheduleOccurrence> occurrences,
    DateTime? fromDate,
    DateTime? fromTime,
    int daysAhead = 14,
  }) {
    final now = fromDate ?? fromTime ?? DateTime.now();
    final slots = <ScheduledStudySlot>[];

    for (int dayOffset = 0; dayOffset < daysAhead; dayOffset++) {
      final date = DateTime(now.year, now.month, now.day + dayOffset);
      final resolvedItems = resolveForDate(
        fixedSchedules: fixedSchedules,
        occurrences: occurrences,
        date: date,
      );

      for (final item in resolvedItems) {
        if (item.isCancelled) continue;

        final slotStartLocal = DateTime(
          date.year,
          date.month,
          date.day,
          item.startHour,
          item.startMinute,
        );

        if (slotStartLocal.isAfter(now)) {
          final slotId = item.isOccurrence
              ? 'occ_${item.occurrenceId ?? item.id}'
              : 'slot_${item.originalScheduleId}_${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';

          slots.add(
            ScheduledStudySlot(
              id: slotId,
              subjectId: item.subjectId,
              subjectName: item.subjectName,
              taskTitle:
                  item.location.isNotEmpty ? 'Tại ${item.location}' : null,
              startAtUtc: slotStartLocal.toUtc(),
              isCancelled: false,
            ),
          );
        }
      }
    }

    slots.sort((a, b) => a.startAtUtc.compareTo(b.startAtUtc));
    return slots;
  }
}

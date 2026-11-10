import '../models/study_activity.dart';
import '../models/study_streak.dart';
import '../models/study_task.dart';
import '../models/subject.dart';

/// Khoảng thời gian thống kê.
enum StatisticsPeriod {
  last7Days('7 ngày qua'),
  last30Days('30 ngày qua'),
  allTime('Tất cả thời gian');

  final String label;
  const StatisticsPeriod(this.label);
}

/// Số liệu hoạt động học tập theo một ngày cụ thể (cho biểu đồ tuần).
class DailyStudyMetric {
  final DateTime date;
  final String dateKey; // YYYY-MM-DD
  final String weekdayLabel; // T2, T3...
  final String dateLabel; // 09/11
  final int completedTasks;
  final int actualMinutes;

  const DailyStudyMetric({
    required this.date,
    required this.dateKey,
    required this.weekdayLabel,
    required this.dateLabel,
    required this.completedTasks,
    required this.actualMinutes,
  });
}

/// Thống kê chi tiết theo từng môn học.
/// Phân biệt rõ tiến độ hiện tại của môn học và hoạt động học tập trong kỳ.
class SubjectStudyMetric {
  final Subject subject;
  final int totalTasks; // Tổng số công việc hiện tại của môn
  final int currentCompletedTasks; // Số công việc hiện đang hoàn thành của môn
  final double
  completionRate; // Tiến độ hiện tại của môn (currentCompletedTasks / totalTasks)
  final int
  periodCompletedTasks; // Số công việc hoàn thành trong kỳ (từ study_activities)
  final int
  actualMinutes; // Thời lượng học thực tế trong kỳ (từ study_activities)

  const SubjectStudyMetric({
    required this.subject,
    required this.totalTasks,
    required this.currentCompletedTasks,
    required this.completionRate,
    required this.periodCompletedTasks,
    required this.actualMinutes,
  });

  /// Getter tương thích ngược cho các màn hình hoặc bài kiểm thử cũ
  int get completedTasks => currentCompletedTasks;
}

/// Kết quả tính toán tổng hợp toàn bộ số liệu thống kê.
/// Tách biệt rõ ràng số liệu trạng thái công việc hiện tại và lịch sử hoạt động học tập.
class StudyStatistics {
  final StatisticsPeriod period;

  // 1. Trạng thái công việc hiện tại (danh mục nhiệm vụ)
  final int totalTasks;
  final int currentCompletedTasks;
  final int pendingTasks;
  final double currentCompletionRate;

  // 2. Lịch sử hoạt động học tập thực tế trong kỳ (từ study_activities)
  final int periodCompletedTasks;
  final int totalActualMinutes;
  final int totalSubjects;
  final List<DailyStudyMetric> weeklyMetrics;
  final List<SubjectStudyMetric> subjectMetrics;

  const StudyStatistics({
    required this.period,
    required this.totalTasks,
    required this.currentCompletedTasks,
    required this.pendingTasks,
    required this.currentCompletionRate,
    required this.periodCompletedTasks,
    required this.totalActualMinutes,
    required this.totalSubjects,
    required this.weeklyMetrics,
    required this.subjectMetrics,
  });

  /// Getter tương thích ngược:
  /// - Khi xem "Tất cả thời gian": trả về số công việc hoàn thành hiện tại
  /// - Khi xem 7 ngày / 30 ngày: trả về số công việc đã hoàn thành trong kỳ từ activities
  int get completedTasks => period == StatisticsPeriod.allTime
      ? currentCompletedTasks
      : periodCompletedTasks;

  /// Tỷ lệ hoàn thành công việc hiện tại
  double get completionRate => currentCompletionRate;

  /// Kiểm tra xem tuần này có hoạt động học tập nào không.
  bool get hasWeeklyData =>
      weeklyMetrics.any((d) => d.completedTasks > 0 || d.actualMinutes > 0);
}

/// Bộ tính toán thống kê độc lập, tách biệt hoàn toàn khỏi Widget UI.
/// Tuân thủ nghiêm ngặt nguyên tắc:
/// - Không dùng deadline hay ngày tạo để suy diễn sinh viên đã học.
/// - Lịch sử học tập hoàn toàn dựa vào study_activities.
/// - Không xóa lịch sử học tập khi bỏ tích hoàn thành task.
class StudyStatisticsCalculator {
  /// Tính toán số liệu thống kê hoàn chỉnh theo bộ lọc khoảng thời gian.
  static StudyStatistics calculate({
    required List<StudyTask> tasks,
    required List<Subject> subjects,
    required List<StudyActivity> activities,
    required StatisticsPeriod period,
    DateTime? now,
  }) {
    final current = now ?? DateTime.now();
    final localNow = current.toLocal();
    final startOfToday = DateTime(localNow.year, localNow.month, localNow.day);
    final endOfToday = DateTime(
      localNow.year,
      localNow.month,
      localNow.day,
      23,
      59,
      59,
      999,
    );

    // Xác định mốc thời gian lọc (chuẩn hóa đầu ngày và cuối ngày địa phương)
    DateTime? filterStartDate;
    if (period == StatisticsPeriod.last7Days) {
      filterStartDate = startOfToday.subtract(const Duration(days: 6));
    } else if (period == StatisticsPeriod.last30Days) {
      filterStartDate = startOfToday.subtract(const Duration(days: 29));
    }

    // 1. Lọc danh sách hoạt động học tập thực tế theo khoảng thời gian
    // Sử dụng study_activities làm nguồn dữ liệu chính cho các chỉ số lịch sử
    final filteredActivities = activities.where((a) {
      if (filterStartDate == null) return true;
      final localCompleted = a.completedAt.toLocal();
      return !localCompleted.isBefore(filterStartDate) &&
          !localCompleted.isAfter(endOfToday);
    }).toList();

    // 2. Số lượng công việc hoàn thành trong kỳ (dùng taskId duy nhất chống cộng trùng)
    final periodCompletedTaskIds = filteredActivities
        .map((a) => a.taskId)
        .toSet();
    int periodCompletedTasks = periodCompletedTaskIds.length;

    // 3. Công việc hiện tại (danh mục nhiệm vụ)
    // Các chỉ số trạng thái công việc hiện tại độc lập với bộ lọc thời gian để không làm sai lệch bản chất
    final totalTasks = tasks.length;
    final currentCompletedTasks = tasks.where((t) => t.isCompleted).length;
    final pendingTasks = totalTasks > currentCompletedTasks
        ? totalTasks - currentCompletedTasks
        : 0;
    final currentCompletionRate = totalTasks > 0
        ? (currentCompletedTasks / totalTasks)
        : 0.0;

    // 4. Tổng thời lượng học thực tế (từ các hoạt động trong kỳ)
    int totalActualMinutes = filteredActivities.fold<int>(
      0,
      (sum, a) => sum + a.actualMinutes,
    );

    // Fallback an toàn cho allTime: nếu có công việc hoàn thành trong tasks chưa có activity (dữ liệu mock/cũ)
    if (period == StatisticsPeriod.allTime) {
      final extraCompleted = tasks.where(
        (t) => t.isCompleted && !periodCompletedTaskIds.contains(t.id),
      );
      periodCompletedTasks += extraCompleted.length;
      totalActualMinutes += extraCompleted.fold<int>(
        0,
        (sum, t) => sum + (t.actualMinutes ?? 0),
      );
    }

    // 5. Tính toán biểu đồ 7 ngày của tuần hiện tại (Thứ 2 đến Chủ nhật)
    final weeklyMetrics = _calculateWeeklyMetrics(
      activities: activities,
      now: current,
    );

    // 6. Tính toán thống kê theo từng môn học
    final subjectMetrics = _calculateSubjectMetrics(
      tasks: tasks,
      subjects: subjects,
      filteredActivities: filteredActivities,
      allActivities: activities,
      period: period,
    );

    return StudyStatistics(
      period: period,
      totalTasks: totalTasks,
      currentCompletedTasks: currentCompletedTasks,
      pendingTasks: pendingTasks,
      currentCompletionRate: currentCompletionRate,
      periodCompletedTasks: periodCompletedTasks,
      totalActualMinutes: totalActualMinutes,
      totalSubjects: subjects.length,
      weeklyMetrics: weeklyMetrics,
      subjectMetrics: subjectMetrics,
    );
  }

  /// Tính toán dữ liệu 7 ngày theo tuần hiện tại (theo giờ địa phương, T2 -> CN).
  /// Tuyệt đối không lấy deadline làm hoạt động học. Chỉ tính hoạt động khi có activity hoàn thành.
  static List<DailyStudyMetric> _calculateWeeklyMetrics({
    required List<StudyActivity> activities,
    required DateTime now,
  }) {
    final localNow = now.toLocal();
    final monday = localNow.subtract(Duration(days: localNow.weekday - 1));
    final startOfMonday = DateTime(monday.year, monday.month, monday.day);

    const weekdayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

    return List.generate(7, (i) {
      final day = startOfMonday.add(Duration(days: i));
      final dateKey = StudyStreak.formatDateKey(day);
      final weekdayLabel = weekdayLabels[day.weekday - 1];
      final dateLabel =
          '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';

      // Lọc các hoạt động diễn ra trong ngày này (theo giờ địa phương)
      final dayActivities = activities.where((a) {
        if (a.dateKey.isNotEmpty) {
          return a.dateKey == dateKey;
        }
        return StudyStreak.formatDateKey(a.completedAt) == dateKey;
      }).toList();

      // Số nhiệm vụ hoàn thành trong ngày (loại trừ trùng lặp taskId)
      final completedCount = dayActivities.map((a) => a.taskId).toSet().length;

      // Tổng thời lượng học thực tế trong ngày
      final actualMinutes = dayActivities.fold<int>(
        0,
        (sum, a) => sum + a.actualMinutes,
      );

      return DailyStudyMetric(
        date: day,
        dateKey: dateKey,
        weekdayLabel: weekdayLabel,
        dateLabel: dateLabel,
        completedTasks: completedCount,
        actualMinutes: actualMinutes,
      );
    });
  }

  /// Tính toán thống kê theo từng môn học, liên kết chặt chẽ qua subjectId.
  static List<SubjectStudyMetric> _calculateSubjectMetrics({
    required List<StudyTask> tasks,
    required List<Subject> subjects,
    required List<StudyActivity> filteredActivities,
    required List<StudyActivity> allActivities,
    required StatisticsPeriod period,
  }) {
    return subjects.map((sub) {
      // 1. Nhiệm vụ thuộc môn qua subjectId
      final subTasks = tasks.where((t) => t.subjectId == sub.id).toList();
      final total = subTasks.length;
      final currentCompleted = subTasks.where((t) => t.isCompleted).length;
      final rate = total > 0 ? (currentCompleted / total) : 0.0;

      // 2. Hoạt động của môn học trong khoảng thời gian được lọc
      final subTaskIds = subTasks.map((t) => t.id).toSet();
      final subFilteredActivities = filteredActivities.where(
        (a) =>
            a.subjectId == sub.id ||
            (a.subjectId == null && subTaskIds.contains(a.taskId)),
      );

      final periodCompletedCount = subFilteredActivities
          .map((a) => a.taskId)
          .toSet()
          .length;

      var subMinutes = subFilteredActivities.fold<int>(
        0,
        (sum, a) => sum + a.actualMinutes,
      );

      // Fallback an toàn cho allTime
      if (period == StatisticsPeriod.allTime) {
        final extraMinutes = subTasks
            .where(
              (t) =>
                  t.isCompleted &&
                  (t.actualMinutes ?? 0) > 0 &&
                  !allActivities.any((a) => a.taskId == t.id),
            )
            .fold<int>(0, (sum, t) => sum + (t.actualMinutes ?? 0));
        subMinutes += extraMinutes;
      }

      return SubjectStudyMetric(
        subject: sub,
        totalTasks: total,
        currentCompletedTasks: currentCompleted,
        completionRate: rate,
        periodCompletedTasks: periodCompletedCount,
        actualMinutes: subMinutes,
      );
    }).toList();
  }
}

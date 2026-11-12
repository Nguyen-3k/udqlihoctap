import 'package:flutter/material.dart';
import '../models/study_session.dart';
import '../models/study_streak.dart';
import '../models/study_task.dart';
import '../models/user_profile.dart';
import '../services/study_timer_engine.dart';
import '../theme/app_colors.dart';
import '../widgets/info_card.dart';
import '../widgets/overview_timer_card.dart';
import '../widgets/task_card.dart';
import '../widgets/weekly_goal_summary_card.dart';

/// Màn hình Tổng quan (Dashboard) nâng cấp toàn diện trong Giai đoạn 3:
/// - Lời chào & Ngày hiện tại chuẩn tiếng Việt.
/// - Thẻ Study Streak nổi bật: Chuỗi ngày liên tiếp, Kỷ lục cá nhân, Ngọn lửa và Lịch hoạt động trong tuần.
/// - Tiến độ học tập hôm nay (chỉ tính công việc có hạn trong ngày hiện tại theo giờ địa phương).
/// - Danh sách công việc cần làm hôm nay.
/// - Danh sách công việc quá hạn (cảnh báo riêng biệt, không gộp với sắp đến hạn).
/// - Danh sách công việc sắp đến hạn trong tương lai gần.
/// - Lối tắt nhanh sang tab Kế hoạch và Môn học.
class OverviewScreen extends StatelessWidget {
  final List<StudyTask> tasks;
  final StudyStreak studyStreak;
  final int legacyActiveDatesCount;
  final UserProfile userProfile;
  final List<StudySession> sessions;
  final StudyTimerEngine? timerEngine;
  final VoidCallback? onOpenTimer;
  final ValueChanged<StudyTask> onToggleComplete;
  final ValueChanged<StudyTask> onTapTask;
  final ValueChanged<StudyTask> onEditTask;
  final ValueChanged<StudyTask> onDeleteTask;
  final VoidCallback onAddTask;
  final VoidCallback onGoToPlan;
  final VoidCallback? onGoToSubjects;
  final VoidCallback? onGoToProfile;

  const OverviewScreen({
    super.key,
    required this.tasks,
    required this.studyStreak,
    this.legacyActiveDatesCount = 0,
    this.userProfile = const UserProfile(),
    this.sessions = const [],
    this.timerEngine,
    this.onOpenTimer,
    required this.onToggleComplete,
    required this.onTapTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onAddTask,
    required this.onGoToPlan,
    this.onGoToSubjects,
    this.onGoToProfile,
  });

  static bool _isSameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  String _formatGreeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Chào buổi sáng! 🌅';
    if (hour < 18) return 'Chào buổi chiều! ☀️';
    return 'Chào buổi tối! 🌙';
  }

  String _formatVietnameseDate(DateTime dt) {
    const weekdays = [
      'Thứ Hai',
      'Thứ Ba',
      'Thứ Tư',
      'Thứ Năm',
      'Thứ Sáu',
      'Thứ Bảy',
      'Chủ Nhật',
    ];
    final weekdayStr = weekdays[dt.weekday - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    return '$weekdayStr, ngày $day/$month/$year';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

    // 1. Phân loại công việc hôm nay (theo giờ địa phương)
    final todayTasks = tasks
        .where((t) => t.deadline != null && _isSameDay(t.deadline!, now))
        .toList();
    final todayTotal = todayTasks.length;
    final todayCompleted = todayTasks.where((t) => t.isCompleted).length;
    final todayRemaining = todayTotal - todayCompleted;
    final todayProgress = todayTotal > 0 ? (todayCompleted / todayTotal) : 0.0;
    final todayPercent = (todayProgress * 100).toInt();
    final todayPendingTasks = todayTasks.where((t) => !t.isCompleted).toList();

    // 2. Phân loại công việc quá hạn (chưa xong và hạn nộp trước hôm nay)
    final overdueTasks =
        tasks
            .where(
              (t) =>
                  !t.isCompleted &&
                  t.deadline != null &&
                  t.deadline!.isBefore(startOfToday) &&
                  !_isSameDay(t.deadline!, now),
            )
            .toList()
          ..sort((a, b) => a.deadline!.compareTo(b.deadline!));

    // 3. Phân loại công việc sắp đến hạn (chưa xong và hạn nộp sau hôm nay)
    final upcomingTasks =
        tasks
            .where(
              (t) =>
                  !t.isCompleted &&
                  t.deadline != null &&
                  t.deadline!.isAfter(endOfToday),
            )
            .toList()
          ..sort((a, b) => a.deadline!.compareTo(b.deadline!));

    return SingleChildScrollView(
      padding: const EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 88),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A. Lời chào & Ngày hiện tại
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatGreeting(now),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _formatVietnameseDate(now),
                style: TextStyle(
                  color: context.textSecondaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // B. Thẻ Study Streak – Chuỗi ngày học liên tiếp
          _buildStudyStreakCard(now),

          const SizedBox(height: 14),

          // B1. Điểm truy cập nhanh Study Timer (Phase 3)
          OverviewTimerCard(timerEngine: timerEngine, onOpenTimer: onOpenTimer),

          const SizedBox(height: 14),

          // B2. Tóm tắt Mục tiêu học tuần này (theo dữ liệu Timer G8.8 Phase 1)
          WeeklyGoalSummaryCard(
            profile: userProfile,
            sessions: sessions,
            now: now,
            onTapConfigure: onGoToProfile,
          ),

          const SizedBox(height: 16),

          // C. Tiến độ học tập hôm nay
          _buildTodayProgressCard(
            context,
            todayTotal: todayTotal,
            todayCompleted: todayCompleted,
            todayRemaining: todayRemaining,
            todayProgress: todayProgress,
            todayPercent: todayPercent,
          ),

          // D. Công việc quá hạn (nếu có) – Ưu tiên hiển thị trước công việc hôm nay
          if (overdueTasks.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.error,
                  size: 20,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Công việc quá hạn (${overdueTasks.length})',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.error,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: context.isDark
                    ? const Color(0xFF450A0A)
                    : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: context.isDark
                      ? const Color(0xFF991B1B)
                      : const Color(0xFFFCA5A5),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Có ${overdueTasks.length} bài tập đã quá hạn nộp. Hãy ưu tiên hoàn thành ngay!',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.isDark
                            ? const Color(0xFFFCA5A5)
                            : AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ...overdueTasks.map(
              (task) => TaskCard(
                task: task,
                onToggleComplete: (_) => onToggleComplete(task),
                onTap: () => onTapTask(task),
                onEdit: () => onEditTask(task),
                onDelete: () => onDeleteTask(task),
              ),
            ),
          ],

          // E. Công việc cần làm hôm nay
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Cần làm hôm nay ($todayRemaining)',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (todayTasks.isNotEmpty)
                TextButton(
                  onPressed: onGoToPlan,
                  child: const Text('Xem kế hoạch'),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (todayPendingTasks.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      todayTotal > 0
                          ? Icons.check_circle_outline_rounded
                          : Icons.event_available_rounded,
                      size: 38,
                      color: todayTotal > 0
                          ? AppColors.statusCompleted
                          : AppColors.primary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      todayTotal > 0
                          ? 'Đã hoàn thành toàn bộ công việc hôm nay! 🎉'
                          : 'Không có công việc nào đến hạn hôm nay.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      todayTotal > 0
                          ? 'Bạn đã làm rất tốt! Hãy tiếp tục duy trì nhé.'
                          : 'Xem các việc sắp tới hoặc tạo thêm bài tập mới để học trước.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ...todayPendingTasks.map(
              (task) => TaskCard(
                task: task,
                onToggleComplete: (_) => onToggleComplete(task),
                onTap: () => onTapTask(task),
                onEdit: () => onEditTask(task),
                onDelete: () => onDeleteTask(task),
              ),
            ),

          // F. Công việc sắp đến hạn
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Sắp đến hạn (${upcomingTasks.length})',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onGoToPlan,
                child: const Text('Xem tất cả'),
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (upcomingTasks.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Center(
                child: Text(
                  'Không có công việc nào sắp đến hạn trong những ngày tới.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                  ),
                ),
              ),
            )
          else
            ...upcomingTasks
                .take(3)
                .map(
                  (task) => TaskCard(
                    task: task,
                    onToggleComplete: (_) => onToggleComplete(task),
                    onTap: () => onTapTask(task),
                    onEdit: () => onEditTask(task),
                    onDelete: () => onDeleteTask(task),
                  ),
                ),

          // G. Lối tắt đến Kế hoạch và Môn học
          const SizedBox(height: 22),
          Text(
            'Lối tắt nhanh',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 10),
          InfoCard(
            icon: Icons.calendar_month_rounded,
            iconColor: AppColors.primary,
            title: 'Xem toàn bộ Kế hoạch học tập',
            subtitle:
                'Tìm kiếm thời gian thực, lọc theo môn học và sắp xếp bài tập theo độ ưu tiên.',
            onTap: onGoToPlan,
          ),
          if (onGoToSubjects != null)
            InfoCard(
              icon: Icons.menu_book_rounded,
              iconColor: const Color(0xFF0284C7),
              title: 'Quản lý theo Môn học',
              subtitle:
                  'Xem chi tiết tiến độ hoàn thành, bài tập và phân loại từng môn học.',
              onTap: onGoToSubjects,
            ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // --- THẺ STUDY STREAK NỔI BẬT ---

  Widget _buildStudyStreakCard(DateTime now) {
    final hasTodayActivity = studyStreak.hasActivityOn(now);
    final streakDays = studyStreak.currentStreak;
    final bestStreak = studyStreak.longestStreak;

    // Tính 7 ngày trong tuần hiện tại (từ Thứ 2 đến Chủ nhật)
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final weekDays = List.generate(7, (i) => monday.add(Duration(days: i)));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: streakDays > 0
              ? const [Color(0xFFEA580C), Color(0xFFF97316)]
              : const [Color(0xFF3B5BDB), Color(0xFF4C6EF5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color:
                (streakDays > 0 ? const Color(0xFFEA580C) : AppColors.primary)
                    .withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dòng tiêu đề streak & Kỷ lục
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$streakDays ngày liên tiếp',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Kỷ lục cá nhân: $bestStreak ngày',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasTodayActivity
                          ? Icons.check_circle_rounded
                          : Icons.hourglass_top_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasTodayActivity ? 'Đã đạt' : 'Chưa học',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Lời nhắc nhở động viên (theo quy tắc Study Streak >= 15 phút Đồng hồ)
          Text(
            hasTodayActivity
                ? 'Tuyệt vời! Bạn đã học ít nhất 15 phút bằng Đồng hồ hôm nay để tiếp tục chuỗi 🔥'
                : (streakDays > 0
                      ? 'Học ít nhất 15 phút bằng Đồng hồ hôm nay để nâng chuỗi lên ${streakDays + 1} ngày!'
                      : 'Bắt đầu chuỗi học mới bằng cách hoàn thành 15 phút học với Đồng hồ!'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              height: 1.35,
            ),
          ),

          if (legacyActiveDatesCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Lịch sử $legacyActiveDatesCount ngày theo quy tắc cũ vẫn được bảo toàn nguyên vẹn trong Thống kê.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 11,
                height: 1.3,
              ),
            ),
          ],

          const SizedBox(height: 16),
          const Divider(height: 1, color: Colors.white24),
          const SizedBox(height: 12),

          // Lịch hoạt động trong tuần (Thứ 2 đến Chủ nhật)
          Row(
            children: weekDays.map((day) {
              final isToday = _isSameDay(day, now);
              final hasActivity = studyStreak.hasActivityOn(day);
              const weekdayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
              final label = weekdayLabels[day.weekday - 1];

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: isToday ? Colors.white : Colors.white70,
                        fontSize: 11,
                        fontWeight: isToday
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: hasActivity
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: isToday
                            ? Border.all(color: Colors.white, width: 2)
                            : null,
                      ),
                      child: Center(
                        child: hasActivity
                            ? Icon(
                                Icons.local_fire_department_rounded,
                                color: streakDays > 0
                                    ? const Color(0xFFEA580C)
                                    : AppColors.primary,
                                size: 16,
                              )
                            : Text(
                                '${day.day}',
                                style: TextStyle(
                                  color: isToday
                                      ? Colors.white
                                      : Colors.white60,
                                  fontSize: 11,
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // --- THẺ TIẾN ĐỘ HỌC TẬP HÔM NAY ---

  Widget _buildTodayProgressCard(
    BuildContext context, {
    required int todayTotal,
    required int todayCompleted,
    required int todayRemaining,
    required double todayProgress,
    required int todayPercent,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.today_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Tiến độ mục tiêu hôm nay',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              if (todayTotal > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$todayPercent%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (todayTotal == 0)
            Text(
              'Hôm nay không có hạn bài tập nào! Bạn có thể xem các công việc sắp tới hoặc tạo thêm việc mới.',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
                height: 1.35,
              ),
            )
          else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: todayProgress,
                minHeight: 8,
                backgroundColor: context.surfaceMutedColor,
                color: todayCompleted == todayTotal
                    ? AppColors.statusCompleted
                    : AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    todayCompleted == todayTotal
                        ? 'Đã hoàn thành $todayCompleted/$todayTotal việc (100%) 🎉'
                        : 'Đã hoàn thành $todayCompleted/$todayTotal việc',
                    style: TextStyle(
                      fontSize: 12,
                      color: todayCompleted == todayTotal
                          ? AppColors.statusCompleted
                          : context.textSecondaryColor,
                      fontWeight: todayCompleted == todayTotal
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (todayRemaining > 0) ...[
                  const SizedBox(width: 6),
                  Text(
                    'Còn $todayRemaining việc',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

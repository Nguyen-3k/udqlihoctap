import 'package:flutter/material.dart';
import '../models/study_session.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';

/// Thẻ tóm tắt Mục tiêu học tập tuần trên màn hình Tổng quan (G8.8 Phase 1).
/// Chỉ tổng hợp thời lượng học thực tế trong tuần hiện tại (Thứ Hai -> Chủ Nhật)
/// từ các `StudySession` đã hoàn thành (`completed`), KHÔNG lấy số task hoàn thành
/// hoặc `actualMinutes` nhập tay cũ làm thời gian Timer.
class WeeklyGoalSummaryCard extends StatelessWidget {
  final UserProfile profile;
  final List<StudySession> sessions;
  final DateTime? now;
  final VoidCallback? onTapConfigure;

  const WeeklyGoalSummaryCard({
    super.key,
    required this.profile,
    this.sessions = const [],
    this.now,
    this.onTapConfigure,
  });

  static String _formatCalendarDateKey(int year, int month, int day) {
    final normalized = DateTime(year, month, day);
    final y = normalized.year.toString().padLeft(4, '0');
    final m = normalized.month.toString().padLeft(2, '0');
    final d = normalized.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Trả về cặp `(mondayKey, sundayKey)` của tuần lịch địa phương chứa `referenceNow`
  /// bằng phép dịch ngày lịch thuần túy (không dùng millisecond/24h delta).
  static (String, String) getCurrentWeekDateRange(DateTime referenceNow) {
    final local = referenceNow.toLocal();
    final daysSinceMonday = local.weekday - DateTime.monday;
    final monday = DateTime(
      local.year,
      local.month,
      local.day - daysSinceMonday,
    );
    final mondayKey = _formatCalendarDateKey(
      monday.year,
      monday.month,
      monday.day,
    );
    final sundayKey = _formatCalendarDateKey(
      monday.year,
      monday.month,
      monday.day + 6,
    );
    return (mondayKey, sundayKey);
  }

  /// Tính tổng số giây học hợp lệ từ Timer (`completed`) trong tuần hiện tại.
  static int calculateWeeklyTimerSeconds(
    List<StudySession> sessions, {
    DateTime? now,
  }) {
    final reference = now ?? DateTime.now();
    final (mondayKey, sundayKey) = getCurrentWeekDateRange(reference);
    return StudySession.sumCompletedSecondsInDateRange(
      sessions,
      mondayKey,
      sundayKey,
    );
  }

  static String _formatHoursNumber(double hours) {
    if (hours <= 0) return '0';
    if (hours.truncateToDouble() == hours) {
      return hours.toInt().toString();
    }
    return hours.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final totalSeconds = calculateWeeklyTimerSeconds(sessions, now: now);
    final totalMinutes = totalSeconds ~/ 60;
    final actualHours = totalSeconds / 3600.0;
    final targetHours = profile.weeklyTargetHours;

    final progressRate = targetHours <= 0
        ? 0.0
        : (actualHours / targetHours).clamp(0.0, 1.0);
    final percent = (progressRate * 100).round();
    final isAchieved = targetHours > 0 && actualHours >= targetHours;

    final actualHoursStr = _formatHoursNumber(actualHours);
    final targetHoursStr = _formatHoursNumber(targetHours);

    return Container(
      key: const ValueKey('weekly_goal_summary_card'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Biểu tượng + Tiêu đề + Phần trăm / Nút cấu hình
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(
                      Icons.track_changes_rounded,
                      color: isAchieved ? AppColors.success : AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Mục tiêu học tuần này',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: isAchieved
                          ? AppColors.success.withValues(alpha: 0.14)
                          : AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      totalSeconds == 0 ? '0 giờ' : '$percent%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isAchieved
                            ? AppColors.success
                            : AppColors.primary,
                      ),
                    ),
                  ),
                  if (onTapConfigure != null) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      key: const ValueKey('weekly_goal_configure_button'),
                      onTap: onTapConfigure,
                      borderRadius: BorderRadius.circular(8),
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.tune_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Nhãn chỉ số thời lượng Timer tuần
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Thời gian học (Đồng hồ)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  totalSeconds == 0
                      ? '0 / $targetHoursStr giờ'
                      : (totalMinutes < 60
                            ? '$actualHoursStr / $targetHoursStr giờ ($totalMinutes phút)'
                            : '$actualHoursStr / $targetHoursStr giờ'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: isAchieved ? AppColors.success : AppColors.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Thanh tiến độ
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: progressRate,
              minHeight: 8,
              backgroundColor: context.surfaceMutedColor,
              color: isAchieved ? AppColors.success : AppColors.primary,
            ),
          ),

          const SizedBox(height: 10),

          // Trạng thái 0 giải thích ngắn gọn hoặc tóm tắt mục tiêu tuần
          if (totalSeconds == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.surfaceMutedColor.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 15,
                    color: context.textSecondaryColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Chưa có phiên học từ Đồng hồ trong tuần này. Thời gian sẽ được ghi nhận khi sử dụng Study Timer ở giai đoạn tiếp theo.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Row(
              children: [
                Icon(
                  isAchieved
                      ? Icons.check_circle_outline_rounded
                      : Icons.timer_rounded,
                  size: 14,
                  color: isAchieved
                      ? AppColors.success
                      : context.textSecondaryColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isAchieved
                        ? 'Tuyệt vời! Bạn đã đạt mục tiêu thời gian tuần ($targetHoursStr giờ).'
                        : 'Đã ghi nhận $totalMinutes phút học từ Đồng hồ trong tuần này.',
                    style: TextStyle(
                      fontSize: 12,
                      color: isAchieved
                          ? AppColors.success
                          : context.textSecondaryColor,
                      fontWeight: isAchieved
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),

          if (profile.weeklyTargetTasks > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Mục tiêu đặt sẵn: $targetHoursStr giờ • ${profile.weeklyTargetTasks} công việc/tuần',
              style: TextStyle(fontSize: 11, color: context.textSecondaryColor),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/task_priority.dart';
import '../models/task_status.dart';
import '../theme/app_colors.dart';
import '../widgets/info_card.dart';

/// Màn hình Thống kê học tập.
/// Tổng hợp số liệu tiến độ, thời lượng thực tế và phân bổ mức độ ưu tiên.
class StatisticsScreen extends StatelessWidget {
  final List<StudyTask> tasks;

  const StatisticsScreen({super.key, required this.tasks});

  @override
  Widget build(BuildContext context) {
    final total = tasks.length;
    final completed = tasks.where((t) => t.isCompleted).length;
    final inProgress = tasks
        .where((t) => t.status == TaskStatus.inProgress)
        .length;
    final todo = tasks.where((t) => t.status == TaskStatus.todo).length;

    final percent = total == 0 ? 0.0 : completed / total;

    // Tổng thời gian dự kiến
    final totalMinutes = tasks.fold<int>(
      0,
      (sum, t) => sum + t.estimatedMinutes,
    );
    final completedMinutes = tasks
        .where((t) => t.isCompleted)
        .fold<int>(0, (sum, t) => sum + t.estimatedMinutes);

    // Thống kê theo mức ưu tiên
    final highPriority = tasks
        .where((t) => t.priority == TaskPriority.high)
        .length;
    final mediumPriority = tasks
        .where((t) => t.priority == TaskPriority.medium)
        .length;
    final lowPriority = tasks
        .where((t) => t.priority == TaskPriority.low)
        .length;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        const Text(
          'Thống kê học tập',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tổng hợp tiến độ và thời gian học thực tế',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        const SizedBox(height: 16),

        // Thẻ tổng quan hoàn thành
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tỷ lệ hoàn thành nhiệm vụ',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '${(percent * 100).round()}%',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: percent,
                minHeight: 10,
                borderRadius: BorderRadius.circular(10),
                backgroundColor: AppColors.primaryContainer,
                color: AppColors.primary,
              ),
              const SizedBox(height: 12),
              Text(
                '$completed / $total công việc đã hoàn thành',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Lưới 3 cột: Chưa làm, Đang làm, Đã xong
        Row(
          children: [
            Expanded(
              child: _buildMetricBox(
                label: 'Chưa làm',
                count: todo,
                color: AppColors.statusTodo,
                icon: Icons.radio_button_unchecked_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricBox(
                label: 'Đang làm',
                count: inProgress,
                color: AppColors.statusInProgress,
                icon: Icons.timelapse_rounded,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricBox(
                label: 'Đã xong',
                count: completed,
                color: AppColors.statusCompleted,
                icon: Icons.check_circle_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Thống kê thời gian
        InfoCard(
          icon: Icons.hourglass_top_rounded,
          iconColor: AppColors.primary,
          title: 'Thời lượng học tập',
          subtitle:
              'Đã hoàn thành: $completedMinutes phút\nTổng thời lượng lên lịch: $totalMinutes phút (~${(totalMinutes / 60).toStringAsFixed(1)} giờ)',
        ),

        // Phân loại mức độ ưu tiên
        InfoCard(
          icon: Icons.flag_rounded,
          iconColor: AppColors.priorityMedium,
          title: 'Phân loại mức độ ưu tiên',
          subtitle:
              'Cao: $highPriority • Trung bình: $mediumPriority • Thấp: $lowPriority',
        ),

        const InfoCard(
          icon: Icons.info_outline_rounded,
          iconColor: AppColors.primary,
          title: 'Dữ liệu thời gian thực',
          subtitle:
              'Tất cả số liệu thống kê được tính toán trực tiếp từ các công việc trong danh sách hiện tại.',
        ),
      ],
    );
  }

  Widget _buildMetricBox({
    required String label,
    required int count,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

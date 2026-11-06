import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../theme/app_colors.dart';
import '../widgets/info_card.dart';
import '../widgets/task_card.dart';

/// Màn hình Tổng quan (Dashboard) của ExamPilot.
/// Tối ưu thông tin trên màn hình di động: Thẻ tiến độ gradient, việc cần học tiếp theo và giới thiệu mục tiêu.
class OverviewScreen extends StatelessWidget {
  final List<StudyTask> tasks;
  final ValueChanged<StudyTask> onToggleComplete;
  final ValueChanged<StudyTask> onTapTask;
  final ValueChanged<StudyTask> onEditTask;
  final ValueChanged<StudyTask> onDeleteTask;
  final VoidCallback onAddTask;
  final VoidCallback onGoToPlan;

  const OverviewScreen({
    super.key,
    required this.tasks,
    required this.onToggleComplete,
    required this.onTapTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onAddTask,
    required this.onGoToPlan,
  });

  @override
  Widget build(BuildContext context) {
    final completedCount = tasks.where((t) => t.isCompleted).length;
    final totalCount = tasks.length;
    final progress = totalCount == 0 ? 0.0 : completedCount / totalCount;

    // Lấy tối đa 3 công việc chưa hoàn thành để làm việc ưu tiên hôm nay
    final pendingTasks = tasks.where((t) => !t.isCompleted).take(3).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        // Lời chào đầu ngày
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Xin chào bạn! 👋',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Theo dõi tiến độ học tập mỗi ngày',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: IconButton(
                onPressed: onAddTask,
                icon: const Icon(Icons.add, color: AppColors.primary),
                tooltip: 'Thêm công việc mới',
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Thẻ tiến độ hôm nay (Gradient Hero Card)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3B5BDB), Color(0xFF4C6EF5)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.22),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tiến độ học tập hiện tại',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$completedCount / $totalCount hoàn thành',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      totalCount == 0
                          ? 'Chưa có công việc nào'
                          : (completedCount == totalCount
                                ? 'Tuyệt vời! Bạn đã hoàn thành hết mục tiêu 🎉'
                                : 'Cố gắng hoàn thành các bài học còn lại nhé!'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              SizedBox(
                width: 76,
                height: 76,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const CircularProgressIndicator(
                      value: 1,
                      color: Colors.white24,
                      strokeWidth: 7,
                    ),
                    CircularProgressIndicator(
                      value: progress,
                      color: Colors.white,
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Tiêu đề phần công việc ưu tiên
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Cần học tiếp theo',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            TextButton(onPressed: onGoToPlan, child: const Text('Xem tất cả')),
          ],
        ),
        const SizedBox(height: 6),

        if (pendingTasks.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    totalCount == 0
                        ? Icons.playlist_add_rounded
                        : Icons.celebration_rounded,
                    size: 40,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    totalCount == 0
                        ? 'Chưa có nhiệm vụ học tập nào.'
                        : 'Tất cả nhiệm vụ đã được hoàn thành!',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Nhấn nút bên dưới để tạo công việc mới.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: onAddTask,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Thêm nhiệm vụ'),
                  ),
                ],
              ),
            ),
          )
        else
          ...pendingTasks.map(
            (task) => TaskCard(
              task: task,
              onToggleComplete: (_) => onToggleComplete(task),
              onTap: () => onTapTask(task),
              onEdit: () => onEditTask(task),
              onDelete: () => onDeleteTask(task),
            ),
          ),

        const SizedBox(height: 20),
        // Thông tin giới thiệu & ghi chú kiến trúc
        const Text(
          'Mục tiêu của ExamPilot',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        const InfoCard(
          icon: Icons.event_note_rounded,
          title: 'Lập kế hoạch cá nhân',
          subtitle:
              'Phân bổ môn học, thời lượng dự kiến và mức độ ưu tiên hợp lý.',
        ),
        const InfoCard(
          icon: Icons.track_changes_rounded,
          title: 'Đánh giá & Ghi chú khó hiểu',
          subtitle: 'Ghi lại các khái niệm chưa nắm vững sau mỗi buổi học.',
        ),
        const InfoCard(
          icon: Icons.storage_rounded,
          iconColor: AppColors.primary,
          title: 'Lưu trữ cục bộ SQLite',
          subtitle:
              'Dữ liệu công việc được lưu bền vững trên thiết bị, bảo toàn sau khi đóng ứng dụng.',
        ),
      ],
    );
  }
}

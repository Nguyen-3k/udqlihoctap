import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../theme/app_colors.dart';
import '../widgets/task_card.dart';

/// Màn hình Chi tiết Môn học:
/// - Hiển thị tên môn, mô tả, tổng số nhiệm vụ, số việc đã xong và chưa xong.
/// - Lọc và chỉ hiển thị các nhiệm vụ thuộc môn học hiện tại.
/// - Cho phép thêm nhiệm vụ mới với môn học được chọn sẵn.
/// - Nhấn vào nhiệm vụ để mở chi tiết, hỗ trợ sửa, xóa, đổi trạng thái tức thì.
class SubjectDetailScreen extends StatelessWidget {
  final Subject subject;
  final List<Subject> allSubjects;
  final List<StudyTask> tasks;
  final ValueChanged<StudyTask> onToggleComplete;
  final ValueChanged<StudyTask> onTapTask;
  final ValueChanged<StudyTask> onEditTask;
  final ValueChanged<StudyTask> onDeleteTask;
  final VoidCallback onAddTaskForThisSubject;
  final VoidCallback onEditSubject;
  final VoidCallback onDeleteSubject;

  const SubjectDetailScreen({
    super.key,
    required this.subject,
    required this.allSubjects,
    required this.tasks,
    required this.onToggleComplete,
    required this.onTapTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onAddTaskForThisSubject,
    required this.onEditSubject,
    required this.onDeleteSubject,
  });

  @override
  Widget build(BuildContext context) {
    // Chỉ lấy các nhiệm vụ liên kết với môn học này theo subjectId (hoặc fallback tên môn)
    final subjectTasks = tasks
        .where(
          (t) =>
              t.subjectId == subject.id ||
              (t.subjectId.isEmpty && t.subject == subject.name),
        )
        .toList();

    final totalCount = subjectTasks.length;
    final completedCount = subjectTasks.where((t) => t.isCompleted).length;
    final uncompletedCount = totalCount - completedCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          subject.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Chỉnh sửa môn học',
            onPressed: onEditSubject,
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
            ),
            tooltip: 'Xóa môn học',
            onPressed: onDeleteSubject,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Thẻ thông tin môn học
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: subject.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(subject.icon, color: subject.color, size: 26),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subject.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subject.description.isNotEmpty
                            ? subject.description
                            : 'Chưa có mô tả cho môn học này.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Lưới thống kê nhiệm vụ của môn: Tổng số, Đã xong, Chưa xong
          Row(
            children: [
              Expanded(
                child: _buildMetricItem(
                  label: 'Tổng nhiệm vụ',
                  count: totalCount,
                  color: AppColors.primary,
                  icon: Icons.list_alt_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricItem(
                  label: 'Đã hoàn thành',
                  count: completedCount,
                  color: AppColors.statusCompleted,
                  icon: Icons.check_circle_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricItem(
                  label: 'Chưa hoàn thành',
                  count: uncompletedCount,
                  color: AppColors.statusInProgress,
                  icon: Icons.timelapse_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Tiêu đề danh sách nhiệm vụ
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Nhiệm vụ của môn ($totalCount)',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              TextButton.icon(
                onPressed: onAddTaskForThisSubject,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm nhiệm vụ'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Danh sách nhiệm vụ thuộc môn
          if (subjectTasks.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.assignment_outlined,
                      size: 44,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Môn "${subject.name}" chưa có nhiệm vụ nào.',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tạo nhiệm vụ đầu tiên để bắt đầu theo dõi tiến độ môn học.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onAddTaskForThisSubject,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Thêm nhiệm vụ ngay'),
                    ),
                  ],
                ),
              ),
            )
          else
            ...subjectTasks.map(
              (task) => TaskCard(
                task: task,
                onToggleComplete: (_) => onToggleComplete(task),
                onTap: () => onTapTask(task),
                onEdit: () => onEditTask(task),
                onDelete: () => onDeleteTask(task),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAddTaskForThisSubject,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add, size: 20),
        label: const Text(
          'Thêm việc môn này',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildMetricItem({
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
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

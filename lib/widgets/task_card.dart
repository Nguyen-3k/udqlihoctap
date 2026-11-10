import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/task_status.dart';
import '../theme/app_colors.dart';

/// Thẻ hiển thị một công việc học tập theo hệ thống thiết kế ExamPilot.
/// Hỗ trợ mục tiêu chạm chuẩn 48dp, thanh màu ưu tiên tinh tế, hệ thống thẻ nhãn phân cấp,
/// hiển thị trạng thái mức độ hiểu bài và hộp thoại xác nhận xóa an toàn.
class TaskCard extends StatelessWidget {
  final StudyTask task;
  final ValueChanged<bool?> onToggleComplete;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onToggleComplete,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  String _formatDate(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Xác nhận xóa',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: dialogContext.textPrimaryColor,
          ),
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa công việc "${task.title}" không?',
          style: TextStyle(
            fontSize: 14,
            color: dialogContext.textSecondaryColor,
            height: 1.4,
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              onDelete();
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCompleted = task.isCompleted;
    final accentColor = isCompleted
        ? AppColors.statusCompleted
        : task.priority.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted ? context.borderSubtleColor : context.borderColor,
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thanh viền màu thể hiện mức ưu tiên ở mép trái (4.5px)
              Container(width: 4.5, color: accentColor),

              // Nội dung thẻ
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Checkbox đánh dấu hoàn thành nhanh (Chuẩn touch target 44-48dp)
                            SizedBox(
                              width: 44,
                              height: 44,
                              child: Center(
                                child: Checkbox(
                                  value: isCompleted,
                                  activeColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  onChanged: onToggleComplete,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),

                            // Tiêu đề và nhãn môn học / ưu tiên / mức độ hiểu
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      task.title,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        decoration: isCompleted
                                            ? TextDecoration.lineThrough
                                            : null,
                                        color: isCompleted
                                            ? AppColors.textMuted
                                            : context.textPrimaryColor,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 8),

                                    // Nhóm nhãn thông tin (Badges)
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        // Chip Môn học
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                context.primaryContainerColor,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            task.subject,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: context
                                                  .onPrimaryContainerColor,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),

                                        // Badge Mức ưu tiên
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                task.priority.backgroundColor,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            border: Border.all(
                                              color: task.priority.borderColor,
                                              width: 0.8,
                                            ),
                                          ),
                                          child: Text(
                                            'Ưu tiên: ${task.priority.label}',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: task.priority.color,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),

                                        // Badge Trạng thái Đang làm
                                        if (task.status ==
                                            TaskStatus.inProgress)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color:
                                                  AppColors.statusInProgressBg,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.timelapse_rounded,
                                                  size: 13,
                                                  color: AppColors
                                                      .statusInProgress,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Đang làm',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors
                                                        .statusInProgress,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                        // Badge Mức độ hiểu bài
                                        if (task.understandingLevel != null)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: task
                                                  .understandingLevel!
                                                  .backgroundColor,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: task
                                                    .understandingLevel!
                                                    .borderColor,
                                                width: 0.8,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  task.understandingLevel!.icon,
                                                  size: 13,
                                                  color: task
                                                      .understandingLevel!
                                                      .color,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  task
                                                      .understandingLevel!
                                                      .label,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: task
                                                        .understandingLevel!
                                                        .color,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else if (isCompleted)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: context.surfaceMutedColor,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: context.borderColor,
                                                width: 0.8,
                                              ),
                                            ),
                                            child: const Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.help_outline_rounded,
                                                  size: 13,
                                                  color: AppColors.textMuted,
                                                ),
                                                SizedBox(width: 4),
                                                Text(
                                                  'Chưa đánh giá',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: AppColors.textMuted,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Nút mở menu thao tác nhanh (Có xác nhận xóa an toàn)
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.more_vert_rounded,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    onEdit();
                                  } else if (value == 'delete') {
                                    _confirmDelete(context);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.edit_outlined,
                                          size: 18,
                                          color: AppColors.textPrimary,
                                        ),
                                        SizedBox(width: 8),
                                        Text('Chỉnh sửa'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.delete_outline_rounded,
                                          color: AppColors.error,
                                          size: 18,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Xóa',
                                          style: TextStyle(
                                            color: AppColors.error,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),
                        const Divider(
                          height: 1,
                          thickness: 0.8,
                          color: AppColors.borderSubtle,
                        ),
                        const SizedBox(height: 8),

                        // Thông tin chân thẻ: Hạn chót, thời lượng, ghi chú
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Hạn: ${_formatDate(task.deadline)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 14),
                            const Icon(
                              Icons.timelapse_rounded,
                              size: 14,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${task.estimatedMinutes} phút',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (task.notes.trim().isNotEmpty) ...[
                              const Spacer(),
                              const Icon(
                                Icons.note_alt_outlined,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'Có ghi chú',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../theme/app_colors.dart';

/// Modal hiển thị thông tin chi tiết một công việc học tập.
/// Thiết kế chuẩn Material 3 với bo góc 24dp, các thẻ thuộc tính rõ ràng,
/// hiển thị đầy đủ mức độ hiểu bài, ghi chú ôn tập và các nút thao tác 44-48dp.
class TaskDetailSheet extends StatelessWidget {
  final StudyTask task;
  final VoidCallback onToggleComplete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onAssess;
  final VoidCallback? onStartTimer;
  final int? accumulatedStudySeconds;
  final VoidCallback? onStartStudy;
  final VoidCallback? onReschedule;

  static const int minStudySecondsToComplete = 900; // 15 phút

  const TaskDetailSheet({
    super.key,
    required this.task,
    required this.onToggleComplete,
    required this.onEdit,
    required this.onDelete,
    this.onAssess,
    this.onStartTimer,
    this.accumulatedStudySeconds,
    this.onStartStudy,
    this.onReschedule,
  });

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year lúc $hour:$minute';
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
              Navigator.of(context).pop(); // Đóng modal chi tiết
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
    final understanding = task.understandingLevel;
    final hasTracking = accumulatedStudySeconds != null;
    final currentStudySeconds = accumulatedStudySeconds ?? 0;
    final currentStudyMinutes = currentStudySeconds ~/ 60;
    final isStudyEligible =
        isCompleted ||
        !hasTracking ||
        currentStudySeconds >= minStudySecondsToComplete;

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.borderColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),

            // Tiêu đề & Môn học
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                          color: isCompleted
                              ? AppColors.textMuted
                              : context.textPrimaryColor,
                          decoration: isCompleted
                              ? TextDecoration.lineThrough
                              : null,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3.5,
                        ),
                        decoration: BoxDecoration(
                          color: context.primaryContainerColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          task.subject,
                          style: TextStyle(
                            color: context.isDark
                                ? AppColors.primaryLight
                                : AppColors.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: context.textSecondaryColor,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Divider(height: 1, color: context.borderColor),
            const SizedBox(height: 16),

            // Khối cảnh báo và thao tác cho công việc quá hạn (Phase 4.2 - Học bù & Chuyển lịch)
            if (task.isOverdue) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.priorityHighBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.priorityHighBorder,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: AppColors.error,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Công việc đã quá hạn hoàn thành',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: AppColors.error,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Hạn nộp cũ: ${_formatDateTime(task.deadline!)}. Bạn có thể Học bù ngay với Study Timer hoặc Chuyển lịch sang thời điểm mới.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            key: const ValueKey('task_detail_makeup_button'),
                            onPressed: () {
                              Navigator.of(context).pop();
                              (onStartStudy ?? onStartTimer)?.call();
                            },
                            icon: const Icon(
                              Icons.history_edu_rounded,
                              size: 16,
                            ),
                            label: const Text('Học bù ngay'),
                          ),
                        ),
                        if (onReschedule != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              key: const ValueKey(
                                'task_detail_reschedule_button',
                              ),
                              onPressed: () {
                                Navigator.of(context).pop();
                                onReschedule!();
                              },
                              icon: const Icon(
                                Icons.edit_calendar_rounded,
                                size: 16,
                              ),
                              label: const Text('Chuyển lịch'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Lưới thuộc tính: Hạn chót, thời lượng, ưu tiên, trạng thái
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildDetailItem(
                  context,
                  icon: Icons.calendar_today_rounded,
                  label: 'Hạn hoàn thành',
                  value: task.deadline != null
                      ? _formatDateTime(task.deadline!)
                      : 'Không có hạn chót',
                  color: AppColors.primary,
                ),
                _buildDetailItem(
                  context,
                  icon: Icons.timelapse_rounded,
                  label: 'Thời lượng dự kiến',
                  value: '${task.estimatedMinutes} phút',
                  color: AppColors.statusInProgress,
                ),
                if (task.actualMinutes != null && task.actualMinutes! > 0)
                  _buildDetailItem(
                    context,
                    icon: Icons.timer_rounded,
                    label: 'Thời lượng thực tế',
                    value: '${task.actualMinutes} phút',
                    color: AppColors.statusCompleted,
                  ),
                _buildDetailItem(
                  context,
                  icon: Icons.flag_rounded,
                  label: 'Mức ưu tiên',
                  value: task.priority.label,
                  color: task.priority.color,
                ),
                _buildDetailItem(
                  context,
                  icon: task.status.icon,
                  label: 'Trạng thái',
                  value: task.status.label,
                  color: task.status.color,
                ),
                if (hasTracking)
                  _buildDetailItem(
                    context,
                    icon: Icons.timer_outlined,
                    label: 'Thời gian đã học',
                    value: '$currentStudyMinutes phút',
                    color: isStudyEligible
                        ? AppColors.statusCompleted
                        : AppColors.statusInProgress,
                  ),
              ],
            ),

            const SizedBox(height: 18),

            // Thẻ tiến độ học thực tế tối thiểu 15 phút (Phase 4.2)
            if (hasTracking && !isCompleted) ...[
              Container(
                key: const ValueKey('task_detail_study_time_progress_card'),
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isStudyEligible
                      ? AppColors.statusCompleted.withValues(alpha: 0.08)
                      : AppColors.statusInProgress.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isStudyEligible
                        ? AppColors.statusCompleted.withValues(alpha: 0.35)
                        : AppColors.statusInProgress.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isStudyEligible
                              ? Icons.check_circle_outline_rounded
                              : Icons.timelapse_rounded,
                          color: isStudyEligible
                              ? AppColors.statusCompleted
                              : AppColors.statusInProgress,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isStudyEligible
                                ? '$currentStudyMinutes/15 phút: đủ điều kiện hoàn thành'
                                : '$currentStudyMinutes/15 phút: chưa đủ điều kiện',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isStudyEligible
                                  ? AppColors.statusCompleted
                                  : AppColors.statusInProgress,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value:
                            (currentStudySeconds /
                                    minStudySecondsToComplete.toDouble())
                                .clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: context.surfaceMutedColor,
                        color: isStudyEligible
                            ? AppColors.statusCompleted
                            : AppColors.statusInProgress,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isStudyEligible
                          ? 'Công việc đã đạt mốc 15 phút học thực tế đã xác nhận. Bạn có thể chủ động đánh dấu hoàn thành.'
                          : 'Theo quy định sản phẩm, cần tích lũy tối thiểu 15 phút học thực tế đã xác nhận liên kết với công việc này trước khi cho phép hoàn thành.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
            ],

            // Mục Tự đánh giá mức độ hiểu bài
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Mức độ hiểu bài',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondaryColor,
                  ),
                ),
                if (onAssess != null)
                  InkWell(
                    onTap: () {
                      Navigator.of(context).pop();
                      onAssess!();
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            understanding != null
                                ? Icons.edit_note_rounded
                                : Icons.add_circle_outline_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            understanding != null
                                ? 'Sửa đánh giá'
                                : 'Đánh giá ngay',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),

            if (understanding != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: understanding.backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: understanding.borderColor,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          understanding.icon,
                          size: 20,
                          color: understanding.color,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          understanding.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: understanding.color,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Đã tự đánh giá',
                            style: TextStyle(
                              fontSize: 11,
                              color: understanding.color,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      understanding.description,
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                    if (task.reviewNotes != null &&
                        task.reviewNotes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Divider(height: 1, color: context.borderSubtleColor),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.rate_review_outlined,
                            size: 15,
                            color: context.textSecondaryColor,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ghi chú ôn tập: ${task.reviewNotes}',
                              style: TextStyle(
                                fontSize: 13,
                                color: context.textPrimaryColor,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.surfaceMutedColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.help_outline_rounded,
                      size: 20,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Chưa đánh giá mức độ hiểu bài. Nhấn Đánh giá ngay để lưu nhận xét tự học.',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 18),

            // Ghi chú ban đầu của bài học
            Text(
              'Ghi chú bài học / Khái niệm khó hiểu',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.surfaceMutedColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Text(
                task.notes.trim().isNotEmpty
                    ? task.notes
                    : 'Chưa có ghi chú cho công việc này. Bạn có thể nhấn Chỉnh sửa để thêm ghi chú kiến thức khó hiểu.',
                style: TextStyle(
                  color: task.notes.trim().isNotEmpty
                      ? context.textPrimaryColor
                      : AppColors.textMuted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),

            const SizedBox(height: 18),

            if (onStartTimer != null) ...[
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.tonalIcon(
                  key: const ValueKey('task_detail_start_timer_button'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    onStartTimer!();
                  },
                  icon: const Icon(Icons.timer_outlined, size: 19),
                  label: const Text('Học công việc này với Study Timer'),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Thanh nút thao tác
            Row(
              children: [
                // Nút xóa
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error, width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () => _confirmDelete(context),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Xóa'),
                  ),
                ),
                const SizedBox(width: 8),

                // Nút sửa
                SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                      onEdit();
                    },
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Sửa'),
                  ),
                ),
                const Spacer(),

                // Nút hoàn thành / hoàn tác
                SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: !isStudyEligible
                          ? context.surfaceMutedColor
                          : (isCompleted
                                ? AppColors.priorityMedium
                                : AppColors.primary),
                      foregroundColor: !isStudyEligible
                          ? AppColors.textMuted
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onPressed: isStudyEligible
                        ? () {
                            onToggleComplete();
                            Navigator.of(context).pop();
                          }
                        : null,
                    icon: Icon(
                      isCompleted
                          ? Icons.undo_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 18,
                    ),
                    label: Text(
                      isCompleted
                          ? 'Chưa hoàn thành'
                          : (!isStudyEligible
                                ? 'Chưa đủ 15 phút'
                                : 'Đã hoàn thành'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      width: 156,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.surfaceMutedColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.borderColor, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.textPrimaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

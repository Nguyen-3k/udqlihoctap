import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/understanding_level.dart';
import '../theme/app_colors.dart';

/// Hộp thoại cho phép sinh viên tự đánh giá mức độ hiểu bài sau khi hoàn thành nhiệm vụ.
/// Thiết kế chuẩn Material 3, thao tác nhanh, không ép buộc (có nút "Để sau"),
/// và ghi chú ôn tập tách biệt, không ghi đè ghi chú ban đầu.
class TaskAssessmentDialog extends StatefulWidget {
  final StudyTask task;
  final void Function(UnderstandingLevel? level, String? reviewNotes)? onSave;
  final void Function(
    UnderstandingLevel? level,
    String? reviewNotes,
    int? actualMinutes,
  )?
  onSaveWithDuration;

  const TaskAssessmentDialog({
    super.key,
    required this.task,
    this.onSave,
    this.onSaveWithDuration,
  }) : assert(
         onSave != null || onSaveWithDuration != null,
         'Cần cung cấp onSave hoặc onSaveWithDuration',
       );

  @override
  State<TaskAssessmentDialog> createState() => _TaskAssessmentDialogState();
}

class _TaskAssessmentDialogState extends State<TaskAssessmentDialog> {
  late UnderstandingLevel? _selectedLevel;
  late final TextEditingController _reviewNotesController;
  late final TextEditingController _actualMinutesController;

  @override
  void initState() {
    super.initState();
    _selectedLevel = widget.task.understandingLevel;
    _reviewNotesController = TextEditingController(
      text: widget.task.reviewNotes ?? '',
    );
    _actualMinutesController = TextEditingController(
      text: widget.task.actualMinutes != null
          ? widget.task.actualMinutes.toString()
          : '',
    );
  }

  @override
  void dispose() {
    _reviewNotesController.dispose();
    _actualMinutesController.dispose();
    super.dispose();
  }

  void _submit() {
    final reviewText = _reviewNotesController.text.trim();
    final actualMins = int.tryParse(_actualMinutesController.text.trim());
    final notes = reviewText.isNotEmpty ? reviewText : null;
    if (widget.onSaveWithDuration != null) {
      widget.onSaveWithDuration!(_selectedLevel, notes, actualMins);
    } else if (widget.onSave != null) {
      widget.onSave!(_selectedLevel, notes);
    }
    Navigator.of(context).pop();
  }

  void _clearAssessment() {
    if (widget.onSaveWithDuration != null) {
      widget.onSaveWithDuration!(null, null, null);
    } else if (widget.onSave != null) {
      widget.onSave!(null, null);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isAlreadyAssessed = widget.task.isAssessed;

    return Dialog(
      backgroundColor: context.surfaceColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: screenHeight * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.primaryContainerColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.psychology_alt_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Đánh giá mức độ hiểu bài',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimaryColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondaryColor,
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

              const SizedBox(height: 12),
              Divider(height: 1, color: context.borderColor),
              const SizedBox(height: 14),

              // Nội dung cuộn
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      'Sau khi học xong, bạn tự đánh giá mức độ nắm vững bài này ra sao?',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 3 tùy chọn mức độ
                    ...UnderstandingLevel.values.map((level) {
                      final isSelected = _selectedLevel == level;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedLevel = isSelected ? null : level;
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? level.backgroundColor
                                  : context.surfaceMutedColor,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? level.color
                                    : context.borderColor,
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: level.color.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    level.icon,
                                    color: level.color,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        level.label,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected
                                              ? level.color
                                              : context.textPrimaryColor,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        level.description,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: context.textSecondaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? level.color
                                          : AppColors.textMuted,
                                      width: isSelected ? 6 : 1.5,
                                    ),
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 12),

                    // Trường ghi chú ôn tập / phản hồi
                    Text(
                      'Ghi chú ôn tập & củng cố kiến thức (tùy chọn)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('assessment_review_notes'),
                      controller: _reviewNotesController,
                      maxLines: 3,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.textPrimaryColor,
                      ),
                      decoration: const InputDecoration(
                        hintText:
                            'Ví dụ: Chưa hiểu kỹ định lý Fermat, cần làm thêm 5 bài tập phân dạng...',
                        prefixIcon: Icon(Icons.rate_review_outlined, size: 20),
                        alignLabelWithHint: true,
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Trường ghi nhận thời lượng học thực tế (G4)
                    Text(
                      'Thời lượng học thực tế (phút) - Tùy chọn',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('assessment_actual_minutes'),
                      controller: _actualMinutesController,
                      keyboardType: TextInputType.number,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.textPrimaryColor,
                      ),
                      decoration: const InputDecoration(
                        hintText:
                            'Ví dụ: 45 (để trống nếu không muốn ghi nhận)',
                        prefixIcon: Icon(Icons.timer_outlined, size: 20),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Thông báo bảo toàn ghi chú gốc
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: context.primaryContainerColor.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 14,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Ghi chú này được lưu riêng và không ghi đè ghi chú công việc ban đầu.',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.isDark
                                    ? AppColors.primaryLight
                                    : AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),
              Divider(height: 1, color: context.borderColor),
              const SizedBox(height: 14),

              // Footer actions
              Row(
                children: [
                  if (isAlreadyAssessed)
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      onPressed: _clearAssessment,
                      child: const Text('Xóa đánh giá'),
                    ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Để sau'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Lưu đánh giá'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

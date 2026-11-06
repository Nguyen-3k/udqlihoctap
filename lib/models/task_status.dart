import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Trạng thái của công việc học tập.
enum TaskStatus {
  todo(
    'Chưa làm',
    Icons.radio_button_unchecked_rounded,
    AppColors.statusTodo,
    AppColors.statusTodoBg,
  ),
  inProgress(
    'Đang làm',
    Icons.timelapse_rounded,
    AppColors.statusInProgress,
    AppColors.statusInProgressBg,
  ),
  completed(
    'Hoàn thành',
    Icons.check_circle_rounded,
    AppColors.statusCompleted,
    AppColors.statusCompletedBg,
  );

  final String label;
  final IconData icon;
  final Color color;
  final Color backgroundColor;

  const TaskStatus(this.label, this.icon, this.color, this.backgroundColor);
}

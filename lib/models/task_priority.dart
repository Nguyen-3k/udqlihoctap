import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Mức độ ưu tiên của công việc học tập.
enum TaskPriority {
  low(
    'Thấp',
    AppColors.priorityLow,
    AppColors.priorityLowBg,
    AppColors.priorityLowBorder,
  ),
  medium(
    'Trung bình',
    AppColors.priorityMedium,
    AppColors.priorityMediumBg,
    AppColors.priorityMediumBorder,
  ),
  high(
    'Cao',
    AppColors.priorityHigh,
    AppColors.priorityHighBg,
    AppColors.priorityHighBorder,
  );

  final String label;
  final Color color;
  final Color backgroundColor;
  final Color borderColor;

  const TaskPriority(
    this.label,
    this.color,
    this.backgroundColor,
    this.borderColor,
  );
}

import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';

/// Hộp thoại thiết lập và chỉnh sửa Mục tiêu học tập hàng tuần.
class GoalsEditDialog extends StatefulWidget {
  final UserProfile profile;
  final void Function(double hours, int tasks) onSave;

  const GoalsEditDialog({
    super.key,
    required this.profile,
    required this.onSave,
  });

  @override
  State<GoalsEditDialog> createState() => _GoalsEditDialogState();
}

class _GoalsEditDialogState extends State<GoalsEditDialog> {
  late double _targetHours;
  late int _targetTasks;

  @override
  void initState() {
    super.initState();
    _targetHours = widget.profile.weeklyTargetHours.clamp(1.0, 60.0);
    _targetTasks = widget.profile.weeklyTargetTasks.clamp(1, 40);
  }

  void _handleSave() {
    widget.onSave(_targetHours, _targetTasks);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tiêu đề
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.track_changes_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Thiết lập mục tiêu tuần',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Mục tiêu được áp dụng cho mỗi tuần (từ Thứ Hai đến Chủ Nhật). Bạn có thể điều chỉnh bất kỳ lúc nào mà không làm ảnh hưởng đến dữ liệu đã học.',
                style: TextStyle(
                  fontSize: 13,
                  color: context.textSecondaryColor,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),

              // Mục tiêu 1: Thời lượng học tuần (giờ)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Thời lượng học mỗi tuần:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: context.primaryContainerColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${_targetHours.toStringAsFixed(_targetHours.truncateToDouble() == _targetHours ? 0 : 1)} giờ',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.isDark
                            ? AppColors.primaryLight
                            : AppColors.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _targetHours,
                min: 1.0,
                max: 60.0,
                divisions: 59,
                label: '${_targetHours.toInt()}h',
                onChanged: (val) {
                  setState(() => _targetHours = val.roundToDouble());
                },
              ),
              const SizedBox(height: 16),

              // Mục tiêu 2: Số công việc hoàn thành mỗi tuần
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Số việc hoàn thành mỗi tuần:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: context.primaryContainerColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_targetTasks việc',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: context.isDark
                            ? AppColors.primaryLight
                            : AppColors.primary,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
              Slider(
                value: _targetTasks.toDouble(),
                min: 1.0,
                max: 40.0,
                divisions: 39,
                label: '$_targetTasks việc',
                onChanged: (val) {
                  setState(() => _targetTasks = val.round());
                },
              ),
              const SizedBox(height: 24),

              // Nút thao tác
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const ValueKey('goals_save_button'),
                    onPressed: _handleSave,
                    child: const Text('Lưu mục tiêu'),
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

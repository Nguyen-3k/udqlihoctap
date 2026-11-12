import 'package:flutter/material.dart';

import '../models/alarm_state.dart';
import '../services/alarm_state_manager.dart';
import '../theme/app_colors.dart';

/// Biểu ngữ tương tác khi có báo thức ở trạng thái `Ringing`.
/// Người dùng bắt buộc chọn Tắt, Nhắc lại 5p (nếu chưa snooze) hoặc Vào học ngay.
class ActiveAlarmBanner extends StatelessWidget {
  final AlarmStateManager alarmStateManager;

  const ActiveAlarmBanner({super.key, required this.alarmStateManager});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: alarmStateManager,
      builder: (context, _) {
        final AlarmRecord? alarm = alarmStateManager.activeRingingAlarm;
        if (alarm == null) return const SizedBox.shrink();

        return Container(
          key: const ValueKey('active_alarm_banner'),
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: context.isDark
                ? const Color(0xFF451A03)
                : AppColors.priorityMediumBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.priorityMedium.withValues(alpha: 0.7),
              width: 1.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.alarm_on_rounded,
                    color: AppColors.priorityMedium,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Báo thức học tập: ${alarm.title}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              if (alarm.taskTitle != null && alarm.taskTitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  alarm.taskTitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                alarm.snoozeCount > 0
                    ? 'Đang reo lại sau khi Nhắc lại (đã dùng 1/1 lần Nhắc lại).'
                    : 'Báo thức lặp cho tới khi bạn chọn Tắt, Nhắc lại 5 phút hoặc Vào học.',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('active_alarm_start_button'),
                    onPressed: () =>
                        alarmStateManager.startFromAlarm(alarm.alarmKey),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: const Text('Vào học ngay'),
                  ),
                  if (alarm.canSnooze)
                    OutlinedButton.icon(
                      key: const ValueKey('active_alarm_snooze_button'),
                      onPressed: () =>
                          alarmStateManager.snoozeAlarm(alarm.alarmKey),
                      icon: const Icon(Icons.snooze_rounded, size: 18),
                      label: const Text('Nhắc lại 5p'),
                    ),
                  TextButton.icon(
                    key: const ValueKey('active_alarm_dismiss_button'),
                    onPressed: () =>
                        alarmStateManager.dismissAlarm(alarm.alarmKey),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.error,
                    ),
                    icon: const Icon(Icons.alarm_off_rounded, size: 18),
                    label: const Text('Tắt báo thức'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

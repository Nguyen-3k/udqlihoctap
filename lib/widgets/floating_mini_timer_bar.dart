import 'package:flutter/material.dart';

import '../models/study_session.dart';
import '../services/study_timer_engine.dart';
import '../theme/app_colors.dart';
import 'study_timer_formatters.dart';

/// Thanh Mini Timer nổi phía trên Bottom Navigation khi chuyển sang tab khác.
/// Chỉ đọc trực tiếp trạng thái từ Singleton [StudyTimerEngine], không tạo bộ đếm độc lập.
/// Ẩn hoàn toàn khi Idle, Completed, Cancelled hoặc InterruptedPending.
class FloatingMiniTimerBar extends StatelessWidget {
  final StudyTimerEngine timerEngine;
  final VoidCallback onTap;

  const FloatingMiniTimerBar({
    super.key,
    required this.timerEngine,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([timerEngine, timerEngine.uiTickListenable]),
      builder: (context, _) {
        final session = timerEngine.activeSession;
        if (session == null ||
            session.status == StudySessionStatus.interruptedPending ||
            session.status == StudySessionStatus.completed ||
            session.status == StudySessionStatus.cancelled) {
          return const SizedBox.shrink();
        }

        final isBreak = session.status == StudySessionStatus.inBreak;
        final isPaused = session.status == StudySessionStatus.paused;
        final displaySeconds = isBreak
            ? timerEngine.getCurrentActiveBreakSeconds()
            : timerEngine.getCurrentElapsedSeconds();
        final statusText = sessionStatusLabel(session.status);
        final statusColor = sessionStatusColor(session.status);

        return Material(
          key: const ValueKey('floating_mini_timer_bar'),
          color: context.surfaceColor,
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: context.isDark
                    ? statusColor.withValues(alpha: 0.16)
                    : statusColor.withValues(alpha: 0.08),
                border: Border(
                  top: BorderSide(
                    color: statusColor.withValues(alpha: 0.35),
                    width: 1,
                  ),
                ),
              ),
              child: SafeArea(
                top: false,
                bottom: false,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isBreak
                            ? Icons.coffee_rounded
                            : (isPaused
                                  ? Icons.pause_rounded
                                  : Icons.timer_rounded),
                        size: 18,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  session.subjectNameSnapshot,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: context.textPrimaryColor,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: statusColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (session.taskTitleSnapshot != null &&
                              session.taskTitleSnapshot!.trim().isNotEmpty)
                            Text(
                              session.taskTitleSnapshot!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.textSecondaryColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatTimerDuration(displaySeconds),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: context.textSecondaryColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

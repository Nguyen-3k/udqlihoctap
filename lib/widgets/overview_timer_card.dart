import 'package:flutter/material.dart';

import '../models/study_session.dart';
import '../services/study_timer_engine.dart';
import '../theme/app_colors.dart';
import 'study_timer_formatters.dart';

/// Thẻ truy cập Study Timer trên màn hình Tổng quan (OverviewScreen).
/// Đọc trực tiếp từ Singleton [StudyTimerEngine], tuyệt đối không tự đếm thời gian riêng.
class OverviewTimerCard extends StatelessWidget {
  final StudyTimerEngine? timerEngine;
  final VoidCallback? onOpenTimer;

  const OverviewTimerCard({super.key, this.timerEngine, this.onOpenTimer});

  @override
  Widget build(BuildContext context) {
    final engine = timerEngine;
    if (engine == null) {
      return _buildCard(
        context,
        status: null,
        session: null,
        displayTime: null,
      );
    }

    return ListenableBuilder(
      listenable: Listenable.merge([engine, engine.uiTickListenable]),
      builder: (context, _) {
        final session = engine.activeSession;
        final status = session?.status;
        final String? formatted;
        if (session == null ||
            status == StudySessionStatus.interruptedPending) {
          formatted = null;
        } else if (status == StudySessionStatus.inBreak) {
          formatted = formatTimerDuration(
            engine.getCurrentActiveBreakSeconds(),
          );
        } else {
          formatted = formatTimerDuration(engine.getCurrentElapsedSeconds());
        }
        return _buildCard(
          context,
          status: status,
          session: session,
          displayTime: formatted,
        );
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required StudySessionStatus? status,
    required StudySession? session,
    required String? displayTime,
  }) {
    final isIdle = session == null;
    final isBreak = status == StudySessionStatus.inBreak;
    final isPaused = status == StudySessionStatus.paused;
    final isPending = status == StudySessionStatus.interruptedPending;
    final accentColor = isIdle ? AppColors.primary : sessionStatusColor(status);

    final String titleText;
    final String subtitleText;
    final String actionLabel;

    if (isIdle) {
      titleText = 'Đồng hồ học tập';
      subtitleText = 'Theo dõi thời gian thực tế theo môn học hoặc công việc';
      actionLabel = 'Bắt đầu học';
    } else if (isPending) {
      titleText = 'Phiên học đang chờ khôi phục';
      subtitleText =
          '${session.subjectNameSnapshot} • Cần bạn xác nhận thời gian';
      actionLabel = 'Xác nhận';
    } else if (isBreak) {
      titleText = 'Đang nghỉ giải lao';
      subtitleText =
          '${session.subjectNameSnapshot} • Đang nghỉ ($displayTime)';
      actionLabel = 'Mở đồng hồ';
    } else if (isPaused) {
      titleText = 'Đã tạm dừng';
      subtitleText = '${session.subjectNameSnapshot} • Đã học $displayTime';
      actionLabel = 'Tiếp tục';
    } else {
      titleText = 'Đang học tập';
      subtitleText = '${session.subjectNameSnapshot} • $displayTime';
      actionLabel = 'Mở đồng hồ';
    }

    return Container(
      key: const ValueKey('overview_timer_entry_card'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isIdle
              ? context.borderColor
              : accentColor.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isBreak
                  ? Icons.coffee_rounded
                  : (isPaused
                        ? Icons.pause_circle_outline_rounded
                        : (isPending
                              ? Icons.warning_amber_rounded
                              : Icons.timer_rounded)),
              color: accentColor,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isIdle ? context.textSecondaryColor : accentColor,
                    fontWeight: isIdle ? FontWeight.normal : FontWeight.w600,
                    fontFeatures: displayTime != null
                        ? const [FontFeature.tabularFigures()]
                        : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: FilledButton(
              key: const ValueKey('overview_start_timer_button'),
              onPressed: onOpenTimer,
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/study_timer_engine.dart';
import '../theme/app_colors.dart';
import 'study_timer_formatters.dart';

/// Hộp thoại phục hồi phiên học bị gián đoạn (`interrupted_pending`) tuân thủ Quyết định D3:
/// - Không cho phép đóng để vô tình bỏ qua phiên đang chờ xác nhận (`barrierDismissible: false`, `PopScope(canPop: false)`).
/// - Phân tách rõ thời gian đã xác minh và khoảng gián đoạn chưa xác minh.
/// - Mặc định thời gian xác nhận bổ sung bằng 0; không tự điền tối đa hay tự động hoàn thành.
class StudyRecoveryDialog extends StatefulWidget {
  final StudyTimerEngine timerEngine;
  final VoidCallback? onResolved;

  const StudyRecoveryDialog({
    super.key,
    required this.timerEngine,
    this.onResolved,
  });

  @override
  State<StudyRecoveryDialog> createState() => _StudyRecoveryDialogState();
}

class _StudyRecoveryDialogState extends State<StudyRecoveryDialog> {
  final TextEditingController _extraMinutesController = TextEditingController(
    text: '0',
  );
  RecoveryContext? _cachedContext;
  int _selectedExtraMinutes = 0;
  bool _showConfirmPanel = false;
  bool _isSubmitting = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _cachedContext = _resolveContext();
  }

  @override
  void dispose() {
    _extraMinutesController.dispose();
    super.dispose();
  }

  RecoveryContext? _resolveContext() {
    final existing = widget.timerEngine.recoveryContext;
    if (existing != null) {
      _cachedContext = existing;
      return existing;
    }

    final s = widget.timerEngine.activeSession;
    if (s == null) {
      return _cachedContext;
    }
    final nowUtc = DateTime.now().toUtc();
    final diffSec = nowUtc.difference(s.lastHeartbeatAt).inSeconds;
    final safeGap = diffSec < 0 ? 0 : diffSec;
    final built = RecoveryContext(
      session: s,
      interruptedFromStatus: null,
      detectedAtUtc: nowUtc,
      verifiedStudySeconds: s.verifiedStudySeconds,
      verifiedBreakSeconds: s.accumulatedBreakSeconds,
      rawWallGapSeconds: safeGap,
      unverifiedGapSeconds: safeGap,
      maxConfirmableExtraSeconds: safeGap,
      isStaleOver8Hours: safeGap > 8 * 3600,
      isClockMovedBackward: diffSec < 0,
    );
    _cachedContext = built;
    return built;
  }

  Future<void> _handleAction(
    StudyRecoveryAction action, {
    int? confirmedExtraSeconds,
  }) async {
    if (_isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _validationError = null;
    });

    try {
      await widget.timerEngine.recoverInterruptedSession(
        action: action,
        confirmedExtraSeconds: confirmedExtraSeconds,
      );
      if (!mounted) return;
      Navigator.of(context).pop(action);
      widget.onResolved?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _validationError = 'Không thể lưu phục hồi phiên học: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctx = _resolveContext();
    if (ctx == null) {
      return const SizedBox.shrink();
    }
    final session = ctx.session;
    final maxExtraMinutes = ctx.maxConfirmableExtraSeconds ~/ 60;
    final rawGapMinutes = ctx.unverifiedGapSeconds ~/ 60;

    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('study_recovery_dialog'),
        backgroundColor: context.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.priorityMediumBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.history_toggle_off_rounded,
                color: AppColors.priorityMedium,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Phục hồi phiên học gián đoạn',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimaryColor,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thông tin môn học / công việc & mốc bắt đầu
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.surfaceMutedColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.borderColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.subjectNameSnapshot,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    if (session.taskTitleSnapshot != null &&
                        session.taskTitleSnapshot!.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Công việc: ${session.taskTitleSnapshot}',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Bắt đầu lúc: ${formatSessionLocalTimestamp(session.startedAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Số liệu thời gian đã xác minh vs chưa xác minh
              _buildMetricRow(
                context,
                icon: Icons.verified_rounded,
                iconColor: AppColors.success,
                label: 'Thời gian học đã xác minh',
                value: formatVietnameseDurationSummary(
                  ctx.verifiedStudySeconds,
                ),
              ),
              if (ctx.verifiedBreakSeconds > 0) ...[
                const SizedBox(height: 6),
                _buildMetricRow(
                  context,
                  icon: Icons.coffee_outlined,
                  iconColor: AppColors.statusInProgress,
                  label: 'Thời gian nghỉ đã ghi nhận',
                  value: formatVietnameseDurationSummary(
                    ctx.verifiedBreakSeconds,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              _buildMetricRow(
                context,
                icon: Icons.schedule_rounded,
                iconColor: AppColors.priorityMedium,
                label: 'Khoảng gián đoạn chưa xác minh',
                value: ctx.unverifiedGapSeconds > 0
                    ? '${formatVietnameseDurationSummary(ctx.unverifiedGapSeconds)} (chưa tính)'
                    : '0 giây (gián đoạn khi không đếm giờ học)',
              ),

              // Cảnh báo > 8 giờ hoặc bất thường đồng hồ hệ thống
              if (ctx.isStaleOver8Hours ||
                  ctx.hasAbnormalClock ||
                  ctx.warningReason != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (ctx.isStaleOver8Hours || ctx.hasAbnormalClock)
                        ? AppColors.priorityHighBg
                        : AppColors.priorityMediumBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: (ctx.isStaleOver8Hours || ctx.hasAbnormalClock)
                          ? AppColors.priorityHighBorder
                          : AppColors.priorityMediumBorder,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: (ctx.isStaleOver8Hours || ctx.hasAbnormalClock)
                            ? AppColors.error
                            : AppColors.priorityMedium,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _buildWarningCopy(ctx),
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color:
                                (ctx.isStaleOver8Hours || ctx.hasAbnormalClock)
                                ? AppColors.error
                                : AppColors.priorityMedium,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Bảng xác nhận thời gian bổ sung cho Lựa chọn B
              if (_showConfirmPanel) ...[
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: context.surfaceMutedColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Xác nhận thời gian học trong khoảng gián đoạn (tùy chọn)',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Đây là khoảng thời gian chưa được hệ thống xác minh (mặc định: 0 phút bổ sung).',
                        style: TextStyle(
                          fontSize: 12,
                          color: context.textSecondaryColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (maxExtraMinutes > 0) ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: const ValueKey(
                                  'recovery_extra_minutes_field',
                                ),
                                controller: _extraMinutesController,
                                enabled: !_isSubmitting,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                decoration: InputDecoration(
                                  labelText:
                                      'Số phút bổ sung (0 - $maxExtraMinutes)',
                                  isDense: true,
                                  suffixText: 'phút',
                                ),
                                onChanged: (raw) {
                                  final parsed = int.tryParse(raw.trim()) ?? 0;
                                  setState(() {
                                    if (parsed < 0 ||
                                        parsed > maxExtraMinutes) {
                                      _validationError =
                                          'Không thể xác nhận vượt quá $maxExtraMinutes phút trong khoảng gián đoạn.';
                                    } else {
                                      _validationError = null;
                                      _selectedExtraMinutes = parsed;
                                    }
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                        if (rawGapMinutes > maxExtraMinutes) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Hệ thống chỉ cho phép xác nhận thêm tối đa $maxExtraMinutes phút hợp lệ để bảo vệ tính toàn vẹn dữ liệu.',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                        Slider(
                          key: const ValueKey('recovery_extra_minutes_slider'),
                          value: _selectedExtraMinutes
                              .clamp(0, maxExtraMinutes)
                              .toDouble(),
                          min: 0,
                          max: maxExtraMinutes.toDouble(),
                          divisions: maxExtraMinutes,
                          label: '$_selectedExtraMinutes phút',
                          onChanged: _isSubmitting
                              ? null
                              : (val) {
                                  final rounded = val.round();
                                  setState(() {
                                    _selectedExtraMinutes = rounded;
                                    _extraMinutesController.text = '$rounded';
                                    _validationError = null;
                                  });
                                },
                        ),
                      ] else
                        Text(
                          'Không có khoảng thời gian bổ sung hợp lệ cho phiên này. Xác nhận sẽ lưu nguyên ${formatVietnameseDurationSummary(ctx.verifiedStudySeconds)} đã chốt.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        'Tổng thời gian sẽ lưu: ${formatVietnameseDurationSummary(ctx.verifiedStudySeconds + _selectedExtraMinutes * 60)}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_validationError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _validationError!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // Ba nút lựa chọn rõ ràng, dễ bấm (>= 44-48dp)
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  key: const ValueKey('recovery_choice_continue'),
                  onPressed: _isSubmitting
                      ? null
                      : () =>
                            _handleAction(StudyRecoveryAction.continueStudying),
                  icon: const Icon(Icons.play_arrow_rounded, size: 20),
                  label: const Text('Tiếp tục học'),
                ),
              ),
              const SizedBox(height: 8),

              if (!_showConfirmPanel)
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.tonalIcon(
                    key: const ValueKey('recovery_choice_confirm_open'),
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() => _showConfirmPanel = true),
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Kết thúc và xác nhận thời gian'),
                  ),
                )
              else
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: FilledButton.icon(
                    key: const ValueKey('recovery_choice_confirm_submit'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: (_isSubmitting || _validationError != null)
                        ? null
                        : () {
                            final parsed =
                                int.tryParse(
                                  _extraMinutesController.text.trim(),
                                ) ??
                                _selectedExtraMinutes;
                            if (parsed < 0 || parsed > maxExtraMinutes) {
                              setState(() {
                                _validationError =
                                    'Không thể xác nhận vượt quá $maxExtraMinutes phút trong khoảng gián đoạn.';
                              });
                              return;
                            }
                            _handleAction(
                              StudyRecoveryAction.completeAndConfirm,
                              confirmedExtraSeconds: parsed * 60,
                            );
                          },
                    icon: const Icon(Icons.verified_outlined, size: 20),
                    label: const Text('Xác nhận & Hoàn thành'),
                  ),
                ),

              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton.icon(
                  key: const ValueKey('recovery_choice_cancel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                  onPressed: _isSubmitting
                      ? null
                      : () => _handleAction(StudyRecoveryAction.cancel),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Hủy phiên'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _buildWarningCopy(RecoveryContext ctx) {
    final reasons = <String>[];
    if (ctx.isStaleOver8Hours) {
      reasons.add('Phiên học đã gián đoạn hơn 8 giờ kể từ lần lưu cuối.');
    }
    if (ctx.isClockMovedBackward) {
      reasons.add('Đồng hồ hệ thống có dấu hiệu bị lùi thời gian.');
    }
    if (ctx.isClockJumpedForward) {
      reasons.add('Đồng hồ hệ thống tăng đột biến so với thời gian thực.');
    }
    if (reasons.isEmpty && ctx.warningReason != null) {
      reasons.add(ctx.warningReason!);
    }
    return reasons.join(' ');
  }

  Widget _buildMetricRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 17, color: iconColor),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimaryColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

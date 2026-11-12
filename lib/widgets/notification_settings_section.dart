import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../services/audio_playback_gateway.dart';
import '../services/notification_permission_service.dart';
import '../services/sound_catalog.dart';
import '../theme/app_colors.dart';
import 'alarm_sound_selector.dart';
import 'break_sound_selector.dart';

/// Callback cập nhật toàn bộ tùy chọn thông báo và âm thanh trong `UserProfile`.
typedef UpdateNotificationPrefsCallback =
    void Function({
      String? alarmSoundId,
      String? breakSoundId,
      int? preReminderMinutes,
      bool? notifyPreStudy,
      bool? notifyAlarmOnTime,
      bool? notifySessionStart,
      bool? notifyBreakStart,
      bool? notifyBreakEnd,
    });

/// Khối cài đặt Thông báo, Báo thức, Quyền hệ thống và Nghe thử âm thanh
/// trong màn hình Cá nhân (`ProfileScreen`).
class NotificationSettingsSection extends StatefulWidget {
  final UserProfile profile;
  final ValueChanged<bool> onUpdateReminderEnabled;
  final UpdateNotificationPrefsCallback? onUpdateNotificationPrefs;
  final NotificationPermissionStatus permissionStatus;
  final Future<void> Function()? onRequestNotificationPermission;
  final Future<void> Function()? onRequestExactAlarmPermission;
  final Future<void> Function()? onOpenSystemSettings;
  final AudioPlaybackGateway? audioGateway;
  final bool hasValidScheduleSource;
  final bool initiallyExpanded;

  const NotificationSettingsSection({
    super.key,
    required this.profile,
    required this.onUpdateReminderEnabled,
    this.onUpdateNotificationPrefs,
    this.permissionStatus = const NotificationPermissionStatus.unknown(),
    this.onRequestNotificationPermission,
    this.onRequestExactAlarmPermission,
    this.onOpenSystemSettings,
    this.audioGateway,
    this.hasValidScheduleSource = false,
    this.initiallyExpanded = false,
  });

  @override
  State<NotificationSettingsSection> createState() =>
      _NotificationSettingsSectionState();
}

class _NotificationSettingsSectionState
    extends State<NotificationSettingsSection> {
  static const List<int> _preReminderChoices = [5, 10, 15, 30];
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  void _stopPreviewOnExit() {
    final gateway = widget.audioGateway;
    if (gateway == null || !gateway.isPreviewPlaying) return;
    scheduleMicrotask(() {
      unawaited(gateway.stopPreview());
    });
  }

  @override
  void deactivate() {
    _stopPreviewOnExit();
    super.deactivate();
  }

  @override
  void dispose() {
    _stopPreviewOnExit();
    super.dispose();
  }

  void _updatePrefs({
    String? alarmSoundId,
    String? breakSoundId,
    int? preReminderMinutes,
    bool? notifyPreStudy,
    bool? notifyAlarmOnTime,
    bool? notifySessionStart,
    bool? notifyBreakStart,
    bool? notifyBreakEnd,
  }) {
    widget.onUpdateNotificationPrefs?.call(
      alarmSoundId: alarmSoundId,
      breakSoundId: breakSoundId,
      preReminderMinutes: preReminderMinutes,
      notifyPreStudy: notifyPreStudy,
      notifyAlarmOnTime: notifyAlarmOnTime,
      notifySessionStart: notifySessionStart,
      notifyBreakStart: notifyBreakStart,
      notifyBreakEnd: notifyBreakEnd,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final masterOn = p.reminderEnabled;
    final hasSystemPerm = widget.permissionStatus.notificationsGranted;
    final String masterSubtitle;
    if (!masterOn) {
      masterSubtitle =
          'Đang tắt thông báo tổng. Khi bật, ứng dụng sẽ kiểm tra quyền thông báo hệ thống của bạn.';
    } else if (!hasSystemPerm) {
      masterSubtitle =
          'Đã lưu mong muốn bật trong hồ sơ, nhưng hệ thống CHƯA cấp quyền thông báo. Vui lòng cấp quyền bên dưới để thông báo hoạt động.';
    } else {
      masterSubtitle =
          'Đang bật thông báo phiên học & nghỉ giữa giờ. Khi tắt, mọi lịch nhắc chờ sẽ bị hủy nhưng dữ liệu học tập vẫn giữ nguyên.';
    }

    return Material(
      key: const ValueKey('notification_settings_section'),
      color: context.surfaceColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const ValueKey('reminder_switch'),
            title: Text(
              'Bật thông báo',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: context.textPrimaryColor,
              ),
            ),
            subtitle: Text(
              masterSubtitle,
              style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
            ),
            secondary: const Icon(
              Icons.notifications_active_outlined,
              color: AppColors.primary,
            ),
            value: masterOn,
            onChanged: widget.onUpdateReminderEnabled,
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPermissionStatusCard(context),
                const SizedBox(height: 10),
                if (!widget.hasValidScheduleSource) ...[
                  _buildScheduleSourceInfoBanner(context),
                  const SizedBox(height: 10),
                ],
                Material(
                  color: context.surfaceMutedColor.withValues(alpha: 0.65),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: context.borderColor),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    key: const ValueKey('notification_details_toggle'),
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 2,
                    ),
                    leading: const Icon(
                      Icons.tune_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    title: Text(
                      'Tùy chỉnh loại thông báo & Âm thanh',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    subtitle: Text(
                      'Nhắc trước ${p.preReminderMinutes}p • Chuông: ${SoundCatalog.alarmById(p.alarmSoundId).label} • Nghỉ: ${SoundCatalog.breakById(p.breakSoundId).label}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.textSecondaryColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: context.textSecondaryColor,
                    ),
                    onTap: () {
                      final next = !_isExpanded;
                      if (!next) {
                        unawaited(widget.audioGateway?.stopPreview());
                      }
                      setState(() => _isExpanded = next);
                    },
                  ),
                ),

                if (_isExpanded) ...[
                  const SizedBox(height: 12),
                  Divider(color: context.borderColor, height: 1),
                  const SizedBox(height: 12),

                  Text(
                    'Loại thông báo',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _buildSubToggle(
                    context,
                    tileKey: const ValueKey('switch_notify_pre_study'),
                    title: 'Nhắc trước giờ học',
                    subtitle: 'Nhắc trước khi đến giờ học theo thời khóa biểu.',
                    value: p.notifyPreStudy,
                    enabled: masterOn,
                    onChanged: (val) => _updatePrefs(notifyPreStudy: val),
                  ),
                  _buildSubToggle(
                    context,
                    tileKey: const ValueKey('switch_notify_alarm_on_time'),
                    title: 'Báo thức đúng giờ',
                    subtitle: 'Phát chuông lặp đến khi bạn Tắt hoặc Nhắc lại.',
                    value: p.notifyAlarmOnTime,
                    enabled: masterOn,
                    onChanged: (val) => _updatePrefs(notifyAlarmOnTime: val),
                  ),
                  _buildSubToggle(
                    context,
                    tileKey: const ValueKey('switch_notify_session_start'),
                    title: 'Thông báo bắt đầu phiên học',
                    subtitle:
                        'Hiện thông báo xác nhận khi bắt đầu Study Timer.',
                    value: p.notifySessionStart,
                    enabled: masterOn,
                    onChanged: (val) => _updatePrefs(notifySessionStart: val),
                  ),
                  _buildSubToggle(
                    context,
                    tileKey: const ValueKey('switch_notify_break_start'),
                    title: 'Thông báo bắt đầu nghỉ',
                    subtitle:
                        'Thông báo khi bạn chuyển phiên học sang chế độ nghỉ.',
                    value: p.notifyBreakStart,
                    enabled: masterOn,
                    onChanged: (val) => _updatePrefs(notifyBreakStart: val),
                  ),
                  _buildSubToggle(
                    context,
                    tileKey: const ValueKey('switch_notify_break_end'),
                    title: 'Thông báo kết thúc nghỉ',
                    subtitle:
                        'Nhắc khi hết thời gian nghỉ dự kiến (không tự chuyển Timer).',
                    value: p.notifyBreakEnd,
                    enabled: masterOn,
                    onChanged: (val) => _updatePrefs(notifyBreakEnd: val),
                  ),

                  const SizedBox(height: 10),
                  Divider(color: context.borderColor, height: 1),
                  const SizedBox(height: 12),

                  Text(
                    'Thời gian nhắc trước giờ học',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _preReminderChoices.map((mins) {
                      final selected = p.preReminderMinutes == mins;
                      return ChoiceChip(
                        key: ValueKey('pre_reminder_$mins'),
                        label: Text('$mins phút'),
                        selected: selected,
                        onSelected: masterOn
                            ? (_) => _updatePrefs(preReminderMinutes: mins)
                            : null,
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 14),
                  Divider(color: context.borderColor, height: 1),
                  const SizedBox(height: 12),

                  if (!SoundCatalog.hasAnyCustomBundledAssets) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: context.surfaceMutedColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        'Âm thanh hiện dùng âm thông báo/báo thức mặc định của hệ thống do chưa gắn bộ tệp âm thanh tùy chỉnh riêng.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.textSecondaryColor,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],

                  AlarmSoundSelector(
                    selectedSoundId: p.alarmSoundId,
                    audioGateway: widget.audioGateway,
                    enabled: true,
                    onSelected: (soundId) =>
                        _updatePrefs(alarmSoundId: soundId),
                  ),
                  const SizedBox(height: 16),
                  BreakSoundSelector(
                    selectedSoundId: p.breakSoundId,
                    audioGateway: widget.audioGateway,
                    enabled: true,
                    onSelected: (soundId) =>
                        _updatePrefs(breakSoundId: soundId),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionStatusCard(BuildContext context) {
    final perm = widget.permissionStatus;
    final isWeb = perm.isWebPlatform || kIsWeb;

    if (isWeb) {
      final statusText = switch (perm.webPermissionState) {
        'granted' => 'Đã cấp quyền thông báo trình duyệt',
        'denied' =>
          'Chưa được phép (đang bị chặn trong cài đặt trang web của trình duyệt)',
        'unsupported' => 'Trình duyệt hiện tại không hỗ trợ Notification API',
        _ => 'Chưa cấp quyền thông báo trình duyệt',
      };

      return Container(
        key: const ValueKey('permission_status_card'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.surfaceMutedColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  perm.notificationsGranted
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  size: 18,
                  color: perm.notificationsGranted
                      ? AppColors.success
                      : AppColors.priorityMedium,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimaryColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Giới hạn nền tảng Web: thông báo và âm thanh chỉ chạy khi tab đang mở, trình duyệt có thể chặn tự phát âm thanh và không bảo đảm đánh thức nền như Android.',
              style: TextStyle(
                fontSize: 11.5,
                color: context.textSecondaryColor,
                height: 1.35,
              ),
            ),
            if (!perm.notificationsGranted &&
                perm.webPermissionState != 'unsupported' &&
                !perm.isWebDeniedPermanently &&
                widget.onRequestNotificationPermission != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('request_notification_permission_button'),
                onPressed: () => widget.onRequestNotificationPermission!(),
                icon: const Icon(Icons.notifications_outlined, size: 16),
                label: const Text('Yêu cầu quyền thông báo'),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('permission_status_card'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.surfaceMutedColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPermissionRow(
            context,
            granted: perm.notificationsGranted,
            grantedText: 'Đã cấp quyền thông báo',
            deniedText: 'Chưa cấp quyền thông báo',
          ),
          const SizedBox(height: 6),
          _buildPermissionRow(
            context,
            granted: perm.exactAlarmsGranted,
            grantedText: 'Đã cấp quyền báo thức chính xác',
            deniedText:
                'Chưa cấp quyền báo thức chính xác (Android có thể trì hoãn khi Doze)',
          ),
          if (perm.batteryOptimizationIgnored == false) ...[
            const SizedBox(height: 6),
            Text(
              'Lưu ý OEM: Một số hãng (Xiaomi, Oppo, Vivo) có thể hạn chế báo thức nền nếu tắt Tự khởi chạy; ứng dụng vẫn giữ dữ liệu an toàn qua Recovery.',
              style: TextStyle(
                fontSize: 11,
                color: context.textSecondaryColor,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (!perm.notificationsGranted &&
                  widget.onRequestNotificationPermission != null)
                OutlinedButton.icon(
                  key: const ValueKey('request_notification_permission_button'),
                  onPressed: () => widget.onRequestNotificationPermission!(),
                  icon: const Icon(Icons.notifications_outlined, size: 16),
                  label: const Text('Cấp quyền thông báo'),
                ),
              if (!perm.exactAlarmsGranted &&
                  widget.onRequestExactAlarmPermission != null)
                OutlinedButton.icon(
                  key: const ValueKey('request_exact_alarm_permission_button'),
                  onPressed: () => widget.onRequestExactAlarmPermission!(),
                  icon: const Icon(Icons.alarm_add_outlined, size: 16),
                  label: const Text('Cấp quyền báo thức chính xác'),
                ),
              if (widget.onOpenSystemSettings != null)
                TextButton.icon(
                  key: const ValueKey('open_system_settings_button'),
                  onPressed: () => widget.onOpenSystemSettings!(),
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text('Mở cài đặt hệ thống'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionRow(
    BuildContext context, {
    required bool granted,
    required String grantedText,
    required String deniedText,
  }) {
    return Row(
      children: [
        Icon(
          granted ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
          size: 16,
          color: granted ? AppColors.success : AppColors.priorityMedium,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            granted ? grantedText : deniedText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: context.textPrimaryColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScheduleSourceInfoBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.primaryContainerColor.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.event_note_outlined,
            size: 16,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Nhắc trước giờ học và Báo thức đúng giờ đang chờ nguồn Thời khóa biểu chính thức (ScheduledSession). Hạn công việc (Task deadline) không được dùng làm lịch báo thức.',
              style: TextStyle(
                fontSize: 11.5,
                color: context.textSecondaryColor,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubToggle(
    BuildContext context, {
    required Key tileKey,
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      key: tileKey,
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: enabled
              ? context.textPrimaryColor
              : context.textSecondaryColor,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11.5, color: context.textSecondaryColor),
      ),
      value: value,
      onChanged: enabled ? onChanged : null,
    );
  }
}

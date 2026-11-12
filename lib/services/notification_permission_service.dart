import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'web_notification_bridge.dart';

/// Ảnh chụp trạng thái quyền thông báo, báo thức chính xác và nền tảng hiện tại.
@immutable
class NotificationPermissionStatus {
  final bool notificationsGranted;
  final bool exactAlarmsGranted;
  final bool isWebPlatform;
  final String webPermissionState;
  final bool? batteryOptimizationIgnored;

  const NotificationPermissionStatus({
    required this.notificationsGranted,
    required this.exactAlarmsGranted,
    this.isWebPlatform = false,
    this.webPermissionState = 'default',
    this.batteryOptimizationIgnored,
  });

  const NotificationPermissionStatus.unknown()
    : notificationsGranted = false,
      exactAlarmsGranted = false,
      isWebPlatform = false,
      webPermissionState = 'default',
      batteryOptimizationIgnored = null;

  bool get isWebDeniedPermanently =>
      isWebPlatform && webPermissionState == 'denied';

  bool get isWebSupported =>
      !isWebPlatform || webPermissionState != 'unsupported';
}

/// Giao diện trừu tượng kiểm tra và yêu cầu quyền hệ thống cho thông báo và báo thức.
abstract class NotificationPermissionService {
  Future<NotificationPermissionStatus> checkStatus();
  Future<bool> requestNotificationPermission();
  Future<bool> requestExactAlarmPermission();
  Future<bool> openSystemNotificationSettings();
}

/// Triển khai kiểm tra/xin quyền thật cho Android 13+/14+ và Web Browser Notification API.
/// Không bao giờ xin quyền tự động lúc mới mở app; chỉ gọi khi người dùng bật tính năng.
class PlatformNotificationPermissionService
    implements NotificationPermissionService {
  static const MethodChannel _alarmChannel = MethodChannel(
    'com.example.exampilot/alarm_service',
  );

  final FlutterLocalNotificationsPlugin _plugin;

  PlatformNotificationPermissionService({
    FlutterLocalNotificationsPlugin? plugin,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<NotificationPermissionStatus> checkStatus() async {
    if (kIsWeb) {
      final perm = WebNotificationBridge.permissionState;
      return NotificationPermissionStatus(
        notificationsGranted: perm == 'granted',
        exactAlarmsGranted: false,
        isWebPlatform: true,
        webPermissionState: perm,
      );
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return const NotificationPermissionStatus(
        notificationsGranted: true,
        exactAlarmsGranted: true,
      );
    }

    bool notificationsEnabled = false;
    bool exactAlarmsEnabled = false;
    bool? batteryIgnored;

    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      notificationsEnabled =
          await androidImpl?.areNotificationsEnabled() ?? false;
      exactAlarmsEnabled =
          await androidImpl?.canScheduleExactNotifications() ?? false;
    } catch (_) {}

    if (!exactAlarmsEnabled) {
      try {
        exactAlarmsEnabled =
            await _alarmChannel.invokeMethod<bool>('canScheduleExactAlarms') ??
            false;
      } catch (_) {}
    }

    try {
      batteryIgnored = await _alarmChannel.invokeMethod<bool>(
        'isBatteryOptimizationIgnored',
      );
    } catch (_) {}

    return NotificationPermissionStatus(
      notificationsGranted: notificationsEnabled,
      exactAlarmsGranted: exactAlarmsEnabled,
      batteryOptimizationIgnored: batteryIgnored,
    );
  }

  @override
  Future<bool> requestNotificationPermission() async {
    if (kIsWeb) {
      return WebNotificationBridge.requestPermission();
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidImpl?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestExactAlarmPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }

    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidImpl?.requestExactAlarmsPermission();
      if (granted != null) {
        return granted;
      }
      await _alarmChannel.invokeMethod<bool>('openExactAlarmSettings');
      return await androidImpl?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> openSystemNotificationSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await androidImpl?.openAppNotificationSettings() ?? false;
    } catch (_) {
      return false;
    }
  }
}

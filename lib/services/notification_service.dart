import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/notification_type.dart';
import '../models/user_profile.dart';
import 'web_notification_bridge.dart';

/// Kết quả khi thao tác với Notification hệ thống (lỗi luôn được cô lập, không làm sập Timer).
class NotificationDispatchResult {
  final bool succeeded;
  final bool usedExactSchedule;
  final String? failureReason;

  const NotificationDispatchResult({
    required this.succeeded,
    this.usedExactSchedule = false,
    this.failureReason,
  });

  static const NotificationDispatchResult ok = NotificationDispatchResult(
    succeeded: true,
  );
}

/// Giao diện trừu tượng quản lý hiển thị, lên lịch và hủy thông báo cục bộ.
abstract class NotificationService {
  Future<void> initialize({
    void Function(String? payload, String? actionId)? onResponse,
  });

  Future<NotificationDispatchResult> showImmediate({
    required int id,
    required AppNotificationType type,
    required UserProfile profile,
    required String title,
    required String body,
    String? payload,
    bool ongoing = false,
  });

  Future<NotificationDispatchResult> scheduleAt({
    required int id,
    required DateTime scheduledAtUtc,
    required AppNotificationType type,
    required UserProfile profile,
    required String title,
    required String body,
    String? payload,
    bool allowExact = true,
  });

  Future<void> cancel(int id);
  Future<void> cancelAll();
  Future<List<int>> getPendingNotificationIds();
}

/// Triển khai thực tế qua `flutter_local_notifications` (Android + Web fallback an toàn).
class PlatformNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _channelsCreated = false;
  bool _timezonesInitialized = false;
  void Function(String? payload, String? actionId)? _onResponse;

  PlatformNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  @override
  Future<void> initialize({
    void Function(String? payload, String? actionId)? onResponse,
  }) async {
    _onResponse = onResponse ?? _onResponse;
    if (_initialized) return;

    if (!_timezonesInitialized) {
      try {
        tzdata.initializeTimeZones();
        _timezonesInitialized = true;
      } catch (_) {}
    }

    if (kIsWeb || defaultTargetPlatform == TargetPlatform.android) {
      try {
        const androidSettings = AndroidInitializationSettings(
          '@mipmap/ic_launcher',
        );
        final settings = InitializationSettings(
          android: defaultTargetPlatform == TargetPlatform.android && !kIsWeb
              ? androidSettings
              : null,
          web: kIsWeb ? const WebInitializationSettings() : null,
        );
        await _plugin.initialize(
          settings: settings,
          onDidReceiveNotificationResponse: (response) {
            _onResponse?.call(response.payload, response.actionId);
          },
        );
        _initialized = true;
      } catch (e) {
        debugPrint('Không thể khởi tạo plugin thông báo: $e');
      }
    } else {
      _initialized = true;
    }

    await _ensureFixedAndroidChannels();
  }

  Future<void> _ensureFixedAndroidChannels() async {
    if (_channelsCreated ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (androidImpl == null) return;
      for (final spec in NotificationChannelRegistry.allFixedChannels) {
        await androidImpl.createNotificationChannel(spec.toAndroidChannel());
      }
      _channelsCreated = true;
    } catch (e) {
      debugPrint('Lỗi tạo Android Notification Channels: $e');
    }
  }

  @override
  Future<NotificationDispatchResult> showImmediate({
    required int id,
    required AppNotificationType type,
    required UserProfile profile,
    required String title,
    required String body,
    String? payload,
    bool ongoing = false,
  }) async {
    await initialize();

    if (kIsWeb) {
      if (!WebNotificationBridge.isSupported) {
        return const NotificationDispatchResult(
          succeeded: false,
          failureReason: 'Trình duyệt không hỗ trợ Notification API.',
        );
      }
      if (WebNotificationBridge.permissionState != 'granted') {
        return const NotificationDispatchResult(
          succeeded: false,
          failureReason: 'Trình duyệt chưa cấp quyền thông báo.',
        );
      }
      try {
        await _plugin.show(
          id: id,
          title: title,
          body: body,
          payload: payload,
          notificationDetails: NotificationDetails(
            web: WebNotificationDetails(
              isSilent: _isSilentForType(type, profile),
            ),
          ),
        );
        return NotificationDispatchResult.ok;
      } catch (_) {
        // Khi Flutter Web chạy local preview chưa đăng ký Service Worker riêng của plugin,
        // fallback trực tiếp sang Web Notification API khi tab đang mở.
        final shown = WebNotificationBridge.showNotification(
          title: title,
          body: body,
          tag: 'exampilot_$id',
        );
        return NotificationDispatchResult(
          succeeded: shown,
          failureReason: shown ? null : 'Không thể hiển thị Web Notification.',
        );
      }
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return NotificationDispatchResult.ok;
    }

    try {
      final details = _buildAndroidDetails(type, profile, ongoing: ongoing);
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: details),
        payload: payload,
      );
      return NotificationDispatchResult.ok;
    } catch (e) {
      debugPrint('Lỗi hiển thị thông báo: $e');
      return NotificationDispatchResult(
        succeeded: false,
        failureReason: e.toString(),
      );
    }
  }

  @override
  Future<NotificationDispatchResult> scheduleAt({
    required int id,
    required DateTime scheduledAtUtc,
    required AppNotificationType type,
    required UserProfile profile,
    required String title,
    required String body,
    String? payload,
    bool allowExact = true,
  }) async {
    await initialize();

    if (kIsWeb) {
      // flutter_local_notifications_web không hỗ trợ zonedSchedule ở nền trình duyệt.
      return const NotificationDispatchResult(
        succeeded: false,
        failureReason:
            'Web không hỗ trợ lập lịch thông báo chạy nền khi đóng tab.',
      );
    }

    if (defaultTargetPlatform != TargetPlatform.android) {
      return NotificationDispatchResult(
        succeeded: true,
        usedExactSchedule: allowExact,
      );
    }

    try {
      final androidImpl = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final canExact =
          allowExact &&
          (await androidImpl?.canScheduleExactNotifications() ?? false);
      final mode = canExact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
      final tzTarget = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.UTC,
        scheduledAtUtc.toUtc().millisecondsSinceEpoch,
      );
      final details = _buildAndroidDetails(type, profile);

      // Chống trùng: hủy thông báo cùng id nếu tồn tại trước khi đặt lịch mới
      await _plugin.cancel(id: id);
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: tzTarget,
        notificationDetails: NotificationDetails(android: details),
        androidScheduleMode: mode,
        title: title,
        body: body,
        payload: payload,
      );

      return NotificationDispatchResult(
        succeeded: true,
        usedExactSchedule: canExact,
      );
    } catch (e) {
      debugPrint('Lỗi lập lịch thông báo Android: $e');
      return NotificationDispatchResult(
        succeeded: false,
        failureReason: e.toString(),
      );
    }
  }

  @override
  Future<void> cancel(int id) async {
    try {
      if (!_initialized) return;
      await _plugin.cancel(id: id);
    } catch (_) {}
  }

  @override
  Future<void> cancelAll() async {
    try {
      if (!_initialized) return;
      await _plugin.cancelAllPendingNotifications();
      await _plugin.cancelAll();
    } catch (_) {}
  }

  @override
  Future<List<int>> getPendingNotificationIds() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    try {
      final pending = await _plugin.pendingNotificationRequests();
      return pending.map((p) => p.id).toList();
    } catch (_) {
      return const [];
    }
  }

  bool _isSilentForType(AppNotificationType type, UserProfile profile) {
    switch (type) {
      case AppNotificationType.alarmOnTime:
        return profile.alarmSoundId == 'none';
      case AppNotificationType.breakStart:
      case AppNotificationType.breakEnd:
        return profile.breakSoundId == 'none';
      case AppNotificationType.sessionStart:
      case AppNotificationType.sessionOngoing:
        return true;
      case AppNotificationType.sessionCompleted:
      case AppNotificationType.preStudy:
        return false;
    }
  }

  AndroidNotificationDetails _buildAndroidDetails(
    AppNotificationType type,
    UserProfile profile, {
    bool ongoing = false,
  }) {
    final spec = NotificationChannelRegistry.resolveFor(type, profile);
    return AndroidNotificationDetails(
      spec.id,
      spec.name,
      channelDescription: spec.description,
      importance: spec.importance,
      priority: spec.importance == Importance.max
          ? Priority.max
          : (spec.importance == Importance.high
                ? Priority.high
                : (spec.importance == Importance.low
                      ? Priority.low
                      : Priority.defaultPriority)),
      playSound: spec.playSound,
      enableVibration: spec.enableVibration,
      audioAttributesUsage: spec.audioAttributesUsage,
      ongoing: ongoing,
      autoCancel: !ongoing,
      onlyAlertOnce:
          type == AppNotificationType.sessionStart ||
          type == AppNotificationType.sessionOngoing ||
          ongoing,
      category: type == AppNotificationType.alarmOnTime
          ? AndroidNotificationCategory.alarm
          : (ongoing
                ? AndroidNotificationCategory.progress
                : AndroidNotificationCategory.reminder),
    );
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/alarm_state.dart';

/// Giao diện cầu nối giữa `AlarmStateManager` (Dart) và hệ thống đánh thức báo thức nền tảng
/// (Android AlarmManager + ForegroundService hoặc bộ hẹn giờ tab-only trên Web Preview).
abstract class AlarmPlatformBridge {
  bool get supportsBackgroundAlarm;

  void attachListeners({
    required ValueChanged<AlarmRecord> onNativeAlarmUpdated,
    required ValueChanged<String?> onNativeLaunchStartRequested,
  });

  Future<bool> scheduleAlarm(AlarmRecord record);
  Future<void> startRingingForeground(AlarmRecord record);
  Future<void> stopRingingForeground();
  Future<void> syncAlarmRecord(AlarmRecord record);
  Future<void> cancelAlarm(AlarmRecord record);
  Future<void> cancelAllAlarms();
  Future<List<AlarmRecord>> getStoredNativeAlarms();
  Future<({String action, String? alarmKey})?> consumePendingLaunchAction();
  void dispose();
}

/// Triển khai nền tảng thật:
/// - Android: `MethodChannel('com.example.exampilot/alarm_service')` nối với `AlarmSchedulerNative`
///   và `AlarmForegroundService` để reo chuông lặp ngay cả khi app xuống nền / tắt màn hình.
/// - Web: chỉ hỗ trợ hẹn giờ trong lúc tab đang mở (`Timer`), KHÔNG hỗ trợ khi đã đóng tab.
class PlatformAlarmBridge implements AlarmPlatformBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.example.exampilot/alarm_service',
  );

  final Map<String, Timer> _webTabTimers = {};
  ValueChanged<AlarmRecord>? _onNativeAlarmUpdated;
  ValueChanged<String?>? _onNativeLaunchStartRequested;
  bool _channelBound = false;

  @override
  bool get supportsBackgroundAlarm =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void attachListeners({
    required ValueChanged<AlarmRecord> onNativeAlarmUpdated,
    required ValueChanged<String?> onNativeLaunchStartRequested,
  }) {
    _onNativeAlarmUpdated = onNativeAlarmUpdated;
    _onNativeLaunchStartRequested = onNativeLaunchStartRequested;
    if (_channelBound || kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _channelBound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onNativeAlarmUpdated' && call.arguments is Map) {
        final record = AlarmRecord.fromNativeMap(
          Map<dynamic, dynamic>.from(call.arguments as Map),
        );
        _onNativeAlarmUpdated?.call(record);
      } else if (call.method == 'onNativeAlarmLaunchAction' &&
          call.arguments is Map) {
        final map = Map<dynamic, dynamic>.from(call.arguments as Map);
        if (map['action']?.toString() == 'start') {
          _onNativeLaunchStartRequested?.call(map['alarmKey']?.toString());
        }
      }
    });
  }

  @override
  Future<bool> scheduleAlarm(AlarmRecord record) async {
    if (kIsWeb) {
      _scheduleWebTabTimer(record);
      return false;
    }
    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }
    try {
      debugPrint(
        '[ExamPilotAlarm] 1c. Flutter: PlatformAlarmBridge invoking scheduleAlarm on MethodChannel with key=${record.alarmKey}, alarmId=${record.alarmId}, effectiveTrigger=${record.effectiveTriggerAtUtc}',
      );
      final exact = await _channel.invokeMethod<bool>(
        'scheduleAlarm',
        record.toNativeMap(),
      );
      debugPrint(
        '[ExamPilotAlarm] 1c-res. Flutter: MethodChannel scheduleAlarm response exact=$exact',
      );
      return exact ?? false;
    } catch (e) {
      debugPrint('[ExamPilotAlarm] Lỗi scheduleAlarm native Android: $e');
      return false;
    }
  }

  void _scheduleWebTabTimer(AlarmRecord record) {
    _webTabTimers.remove(record.alarmKey)?.cancel();
    if (!record.isPendingTrigger) return;
    final delay = record.effectiveTriggerAtUtc.difference(
      DateTime.now().toUtc(),
    );
    if (delay.isNegative) return;

    _webTabTimers[record.alarmKey] = Timer(delay, () {
      _webTabTimers.remove(record.alarmKey);
      _onNativeAlarmUpdated?.call(
        record.copyWith(
          status: AlarmStatus.ringing,
          updatedAtUtc: DateTime.now().toUtc(),
        ),
      );
    });
  }

  @override
  Future<void> startRingingForeground(AlarmRecord record) async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod(
          'startRingingService',
          record.toNativeMap(),
        );
      } catch (e) {
        debugPrint('Lỗi bật AlarmForegroundService: $e');
      }
    }
  }

  @override
  Future<void> stopRingingForeground() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('stopRingingService');
      } catch (_) {}
    }
  }

  @override
  Future<void> syncAlarmRecord(AlarmRecord record) async {
    if (kIsWeb) {
      if (record.isTerminal) {
        _webTabTimers.remove(record.alarmKey)?.cancel();
      }
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('syncAlarmRecord', record.toNativeMap());
    } catch (_) {}
  }

  @override
  Future<void> cancelAlarm(AlarmRecord record) async {
    if (kIsWeb) {
      _webTabTimers.remove(record.alarmKey)?.cancel();
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('cancelAlarm', {
        'alarmKey': record.alarmKey,
        'alarmId': record.alarmId,
      });
    } catch (_) {}
  }

  @override
  Future<void> cancelAllAlarms() async {
    for (final timer in _webTabTimers.values) {
      timer.cancel();
    }
    _webTabTimers.clear();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _channel.invokeMethod('cancelAllAlarms');
      } catch (_) {}
    }
  }

  @override
  Future<List<AlarmRecord>> getStoredNativeAlarms() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    try {
      final raw = await _channel.invokeListMethod<dynamic>('getStoredAlarms');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((m) => AlarmRecord.fromNativeMap(Map<dynamic, dynamic>.from(m)))
          .where((r) => r.alarmKey.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<({String action, String? alarmKey})?>
  consumePendingLaunchAction() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final raw = await _channel.invokeMapMethod<dynamic, dynamic>(
        'consumePendingLaunchAction',
      );
      if (raw == null) return null;
      final action = raw['action']?.toString();
      if (action == null || action.isEmpty) return null;
      return (action: action, alarmKey: raw['alarmKey']?.toString());
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    for (final timer in _webTabTimers.values) {
      timer.cancel();
    }
    _webTabTimers.clear();
    _onNativeAlarmUpdated = null;
    _onNativeLaunchStartRequested = null;
  }
}

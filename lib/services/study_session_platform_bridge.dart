import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Giao diện trừu tượng điều khiển Foreground Service phiên học trên Android (Phase 4.1).
/// Trên Web và các nền tảng khác, cầu nối này tự động no-op an toàn mà không phát sinh lỗi.
abstract class StudySessionPlatformBridge {
  Future<void> startOrUpdateOngoingSession({
    required String sessionId,
    required int notificationId,
    required String title,
    required String content,
    String? subText,
  });

  Future<void> stopOngoingSession();
}

/// Triển khai thực tế qua MethodChannel trên Android native.
class NativeStudySessionBridge implements StudySessionPlatformBridge {
  static const MethodChannel _channel = MethodChannel(
    'com.example.exampilot/study_session_service',
  );

  @override
  Future<void> startOrUpdateOngoingSession({
    required String sessionId,
    required int notificationId,
    required String title,
    required String content,
    String? subText,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('startOrUpdateOngoingSession', {
        'sessionId': sessionId,
        'notificationId': notificationId,
        'title': title,
        'content': content,
        'subText': subText,
      });
    } on MissingPluginException {
      // Bỏ qua khi chạy trong môi trường test / preview không có native handler
    } catch (e) {
      debugPrint('Lỗi gọi native StudySessionService (đã bỏ qua): $e');
    }
  }

  @override
  Future<void> stopOngoingSession() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('stopOngoingSession');
    } on MissingPluginException {
      // Bỏ qua khi chạy trong môi trường test / preview không có native handler
    } catch (e) {
      debugPrint('Lỗi dừng native StudySessionService (đã bỏ qua): $e');
    }
  }
}

/// Fake bridge cho môi trường kiểm thử không cần gọi MethodChannel thật.
class FakeStudySessionBridge implements StudySessionPlatformBridge {
  final List<Map<String, dynamic>> calls = [];
  bool isStopped = false;

  @override
  Future<void> startOrUpdateOngoingSession({
    required String sessionId,
    required int notificationId,
    required String title,
    required String content,
    String? subText,
  }) async {
    isStopped = false;
    calls.add({
      'action': 'startOrUpdate',
      'sessionId': sessionId,
      'notificationId': notificationId,
      'title': title,
      'content': content,
      'subText': subText,
    });
  }

  @override
  Future<void> stopOngoingSession() async {
    isStopped = true;
    calls.add({'action': 'stop'});
  }
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'audio_playback_platform.dart';
import 'sound_catalog.dart';

/// Giao diện trừu tượng quản lý phát nghe thử và âm báo thức/nhắc nghỉ.
/// Bảo đảm tối đa một âm thanh nghe thử được phát tại một thời điểm,
/// tự dừng khi đổi lựa chọn hoặc đóng màn hình.
abstract class AudioPlaybackGateway extends ChangeNotifier {
  String? get currentPreviewSoundId;
  SoundGroup? get currentPreviewGroup;
  bool get isPreviewPlaying;
  bool get isAlarmLoopPlaying;
  String? get activeAlarmSoundId;

  Future<void> playPreview(String soundId, {required SoundGroup group});
  Future<void> stopPreview();
  Future<void> playOneShotCue(String soundId, {required SoundGroup group});
  Future<void> startAlarmLoop(String soundId);
  Future<void> stopAlarmLoop();
}

/// Triển khai đa nền tảng thật:
/// - Android: gọi MethodChannel tới Kotlin SoundPreviewManager / RingtoneManager.
/// - Web Preview: phát qua Web Audio API khi trình duyệt cho phép.
class PlatformAudioPlaybackGateway extends AudioPlaybackGateway {
  static const MethodChannel _audioChannel = MethodChannel(
    'com.example.exampilot/alarm_audio',
  );

  final WebSoundPreviewPlayer _webPlayer = WebSoundPreviewPlayer();
  String? _currentPreviewSoundId;
  SoundGroup? _currentPreviewGroup;
  bool _isAlarmLoopPlaying = false;
  String? _activeAlarmSoundId;
  bool _channelInitialized = false;
  bool _disposed = false;

  PlatformAudioPlaybackGateway() {
    _ensureChannelBound();
  }

  void _ensureChannelBound() {
    if (_channelInitialized || kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    _channelInitialized = true;
    _audioChannel.setMethodCallHandler((call) async {
      if (call.method == 'onPreviewCompleted') {
        final completedId = call.arguments?.toString();
        if (completedId == null || completedId == _currentPreviewSoundId) {
          _currentPreviewSoundId = null;
          _currentPreviewGroup = null;
          _notifySafely();
        }
      }
    });
  }

  @override
  String? get currentPreviewSoundId => _currentPreviewSoundId;

  @override
  SoundGroup? get currentPreviewGroup => _currentPreviewGroup;

  @override
  bool get isPreviewPlaying => _currentPreviewSoundId != null;

  @override
  bool get isAlarmLoopPlaying => _isAlarmLoopPlaying;

  @override
  String? get activeAlarmSoundId => _activeAlarmSoundId;

  @override
  Future<void> playPreview(String soundId, {required SoundGroup group}) async {
    await stopPreview();
    if (_disposed || soundId == 'none') return;

    _currentPreviewSoundId = soundId;
    _currentPreviewGroup = group;
    _notifySafely();

    if (kIsWeb) {
      await _webPlayer.playSystemTone(
        isAlarmGroup: group == SoundGroup.alarm,
        loop: false,
        onEnded: () {
          if (_currentPreviewSoundId == soundId) {
            _currentPreviewSoundId = null;
            _currentPreviewGroup = null;
            _notifySafely();
          }
        },
      );
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _audioChannel.invokeMethod('playPreview', {
          'soundId': soundId,
          'isAlarmGroup': group == SoundGroup.alarm,
        });
      } catch (_) {
        _currentPreviewSoundId = null;
        _currentPreviewGroup = null;
        _notifySafely();
      }
      return;
    }

    // Môi trường không có thiết bị âm thanh native (như unit test desktop) giữ trạng thái logic
    // cho tới khi người dùng dừng hoặc hết thời lượng mô phỏng.
  }

  @override
  Future<void> stopPreview() async {
    final hadPreview = _currentPreviewSoundId != null;
    _currentPreviewSoundId = null;
    _currentPreviewGroup = null;

    if (kIsWeb) {
      _webPlayer.stop();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _audioChannel.invokeMethod('stopPreview');
      } catch (_) {}
    }

    if (hadPreview) {
      _notifySafely();
    }
  }

  @override
  Future<void> playOneShotCue(
    String soundId, {
    required SoundGroup group,
  }) async {
    if (_disposed || soundId == 'none') return;
    if (kIsWeb) {
      await _webPlayer.playSystemTone(
        isAlarmGroup: group == SoundGroup.alarm,
        loop: false,
      );
    }
    // Trên Android, Notification Channel tương ứng trực tiếp phát âm thanh hệ thống
    // nên không gọi playPreview đè lên trạng thái UI.
  }

  @override
  Future<void> startAlarmLoop(String soundId) async {
    if (_disposed) return;
    await stopPreview();
    _isAlarmLoopPlaying = soundId != 'none';
    _activeAlarmSoundId = soundId;
    _notifySafely();

    if (kIsWeb && soundId != 'none') {
      await _webPlayer.playSystemTone(isAlarmGroup: true, loop: true);
    }
  }

  @override
  Future<void> stopAlarmLoop() async {
    final wasLooping = _isAlarmLoopPlaying || _activeAlarmSoundId != null;
    _isAlarmLoopPlaying = false;
    _activeAlarmSoundId = null;
    if (kIsWeb) {
      _webPlayer.stop();
    }
    if (wasLooping) {
      _notifySafely();
    }
  }

  void _notifySafely() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    if (kIsWeb) {
      _webPlayer.dispose();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      unawaited(_audioChannel.invokeMethod('stopPreview').catchError((_) {}));
    }
    super.dispose();
  }
}

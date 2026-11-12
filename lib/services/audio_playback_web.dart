import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Bộ phát âm thanh trên Web Preview bằng Web Audio API (chỉ chạy khi tab đang mở
/// và trình duyệt cho phép sau thao tác người dùng).
class WebSoundPreviewPlayer {
  web.AudioContext? _audioContext;
  final List<web.OscillatorNode> _oscillators = [];
  Timer? _autoStopTimer;

  Future<void> playSystemTone({
    required bool isAlarmGroup,
    required bool loop,
    void Function()? onEnded,
  }) async {
    stop();
    try {
      final ctx = web.AudioContext();
      _audioContext = ctx;
      if (ctx.state == 'suspended') {
        await ctx.resume().toDart;
      }

      final freqs = isAlarmGroup
          ? const [587.33, 783.99, 987.77]
          : const [523.25, 659.25];
      final noteGap = isAlarmGroup ? 0.28 : 0.32;
      final now = ctx.currentTime;

      for (var i = 0; i < freqs.length; i++) {
        final osc = ctx.createOscillator();
        final gain = ctx.createGain();
        osc.type = isAlarmGroup ? 'triangle' : 'sine';
        osc.frequency.setValueAtTime(freqs[i], now + i * noteGap);

        gain.gain.setValueAtTime(0.0001, now + i * noteGap);
        gain.gain.exponentialRampToValueAtTime(
          isAlarmGroup ? 0.16 : 0.12,
          now + i * noteGap + 0.03,
        );
        gain.gain.exponentialRampToValueAtTime(
          0.0001,
          now + i * noteGap + 0.35,
        );

        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.start(now + i * noteGap);
        osc.stop(now + i * noteGap + 0.38);
        _oscillators.add(osc);
      }

      final totalMs = ((freqs.length * noteGap + 0.45) * 1000).round();
      if (loop) {
        _autoStopTimer = Timer.periodic(Duration(milliseconds: totalMs + 600), (
          _,
        ) {
          unawaited(playSystemTone(isAlarmGroup: isAlarmGroup, loop: true));
        });
      } else {
        _autoStopTimer = Timer(Duration(milliseconds: totalMs), () {
          stop();
          onEnded?.call();
        });
      }
    } catch (_) {
      stop();
      onEnded?.call();
    }
  }

  void stop() {
    _autoStopTimer?.cancel();
    _autoStopTimer = null;
    for (final osc in _oscillators) {
      try {
        osc.stop();
        osc.disconnect();
      } catch (_) {}
    }
    _oscillators.clear();
    try {
      _audioContext?.close();
    } catch (_) {}
    _audioContext = null;
  }

  void dispose() {
    stop();
  }
}

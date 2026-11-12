import 'package:flutter/material.dart';

import '../services/audio_playback_gateway.dart';
import '../services/sound_catalog.dart';
import '../theme/app_colors.dart';

/// Điều khiển nghe thử và dừng âm thanh (bảo đảm chỉ phát 1 âm tại một thời điểm).
class SoundPreviewControl extends StatelessWidget {
  final SoundOption option;
  final AudioPlaybackGateway? audioGateway;
  final VoidCallback? onError;

  const SoundPreviewControl({
    super.key,
    required this.option,
    this.audioGateway,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    if (option.isSilent) {
      return Text(
        'Im lặng',
        style: TextStyle(
          fontSize: 12,
          color: context.textSecondaryColor,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final gateway = audioGateway;
    if (gateway == null) {
      return OutlinedButton.icon(
        key: ValueKey('sound_preview_btn_${option.id}'),
        onPressed: null,
        icon: const Icon(Icons.volume_up_outlined, size: 16),
        label: const Text('Nghe thử'),
      );
    }

    return AnimatedBuilder(
      animation: gateway,
      builder: (context, _) {
        final isPlayingThis =
            gateway.isPreviewPlaying &&
            gateway.currentPreviewSoundId == option.id;

        if (isPlayingThis) {
          return FilledButton.tonalIcon(
            key: ValueKey('sound_stop_btn_${option.id}'),
            onPressed: () => gateway.stopPreview(),
            style: FilledButton.styleFrom(
              foregroundColor: AppColors.error,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: const Size(0, 36),
            ),
            icon: const Icon(Icons.stop_rounded, size: 18),
            label: const Text('Dừng'),
          );
        }

        return OutlinedButton.icon(
          key: ValueKey('sound_preview_btn_${option.id}'),
          onPressed: () async {
            try {
              await gateway.playPreview(option.id, group: option.group);
            } catch (_) {
              onError?.call();
            }
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            minimumSize: const Size(0, 36),
          ),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Nghe thử'),
        );
      },
    );
  }
}

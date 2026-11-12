import 'package:flutter/material.dart';

import '../services/audio_playback_gateway.dart';
import '../services/sound_catalog.dart';
import '../theme/app_colors.dart';
import 'sound_preview_control.dart';

/// Khu vực chọn và nghe thử âm thanh báo thức (`alarm_sound_id`).
class AlarmSoundSelector extends StatelessWidget {
  final String selectedSoundId;
  final ValueChanged<String> onSelected;
  final AudioPlaybackGateway? audioGateway;
  final bool enabled;

  const AlarmSoundSelector({
    super.key,
    required this.selectedSoundId,
    required this.onSelected,
    this.audioGateway,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final current = SoundCatalog.alarmById(selectedSoundId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.alarm_rounded, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Âm thanh báo thức: ${current.label}',
                key: const ValueKey('selected_alarm_sound_label'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.textPrimaryColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...SoundCatalog.alarmOptions.map((option) {
          final isSelected = option.id == current.id;
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: isSelected
                  ? context.primaryContainerColor.withValues(alpha: 0.45)
                  : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.5)
                      : context.borderColor,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                key: ValueKey('alarm_sound_option_${option.id}'),
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: isSelected
                      ? AppColors.primary
                      : context.textSecondaryColor,
                ),
                title: Text(
                  option.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: context.textPrimaryColor,
                  ),
                ),
                subtitle: Text(
                  option.description,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.textSecondaryColor,
                  ),
                ),
                trailing: SoundPreviewControl(
                  option: option,
                  audioGateway: audioGateway,
                ),
                onTap: enabled
                    ? () async {
                        if (option.isSilent) {
                          await audioGateway?.stopPreview();
                        }
                        onSelected(option.id);
                      }
                    : null,
              ),
            ),
          );
        }),
      ],
    );
  }
}

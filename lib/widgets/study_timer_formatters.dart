import 'package:flutter/material.dart';
import '../models/study_session.dart';
import '../models/user_profile.dart';
import '../theme/app_colors.dart';

/// Định dạng giây sang chuỗi `MM:SS` (dưới 1 giờ) hoặc `HH:MM:SS` (từ 1 giờ trở lên).
String formatTimerDuration(int totalSeconds) {
  final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final seconds = safeSeconds % 60;

  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  if (hours > 0) {
    final hh = hours.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }
  return '$mm:$ss';
}

/// Định dạng giây sang chuỗi `HH:MM:SS` cố định (ví dụ 00:25:36)
/// dùng riêng cho tiêu đề và nội dung thông báo liên tục của Study Notification.
String formatNotificationDuration(int totalSeconds) {
  final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final seconds = safeSeconds % 60;

  final hh = hours.toString().padLeft(2, '0');
  final mm = minutes.toString().padLeft(2, '0');
  final ss = seconds.toString().padLeft(2, '0');
  return '$hh:$mm:$ss';
}

/// Định dạng thời lượng tiếng Việt dễ đọc dùng trong thông tin phụ và Recovery Dialog.
String formatVietnameseDurationSummary(int totalSeconds) {
  final safeSeconds = totalSeconds < 0 ? 0 : totalSeconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final seconds = safeSeconds % 60;

  final parts = <String>[];
  if (hours > 0) parts.add('$hours giờ');
  if (minutes > 0) parts.add('$minutes phút');
  if (seconds > 0 || parts.isEmpty) parts.add('$seconds giây');
  return parts.join(' ');
}

/// Định dạng DateTime UTC sang ngày giờ địa phương `dd/MM/yyyy lúc HH:mm`.
String formatSessionLocalTimestamp(DateTime utcDateTime) {
  final local = utcDateTime.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  final y = local.year;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$d/$m/$y lúc $hh:$mm';
}

/// Đại diện một cấu hình chu kỳ học/nghỉ chuẩn của ExamPilot.
class StudyBreakPreset {
  final String id;
  final String label;
  final StudySessionMode sessionMode;
  final int studyMinutes;
  final int breakMinutes;

  const StudyBreakPreset({
    required this.id,
    required this.label,
    required this.sessionMode,
    required this.studyMinutes,
    required this.breakMinutes,
  });

  static const List<StudyBreakPreset> standardPresets = [
    StudyBreakPreset(
      id: 'pomodoro_25_5',
      label: 'Pomodoro',
      sessionMode: StudySessionMode.pomodoro25_5,
      studyMinutes: 25,
      breakMinutes: 5,
    ),
    StudyBreakPreset(
      id: 'deep_50_10',
      label: 'Tập trung sâu',
      sessionMode: StudySessionMode.deep50_10,
      studyMinutes: 50,
      breakMinutes: 10,
    ),
    StudyBreakPreset(
      id: 'long_90_15',
      label: 'Học dài',
      sessionMode: StudySessionMode.long90_15,
      studyMinutes: 90,
      breakMinutes: 15,
    ),
  ];

  static StudyBreakPreset customFromProfile(UserProfile profile) {
    return StudyBreakPreset(
      id: 'custom',
      label: 'Tùy chỉnh',
      sessionMode: StudySessionMode.custom,
      studyMinutes: profile.customStudyMinutes,
      breakMinutes: profile.customBreakMinutes,
    );
  }

  static StudyBreakPreset resolveDefaultFromProfile(UserProfile profile) {
    for (final p in standardPresets) {
      if (p.id == profile.breakPresetId) {
        return p;
      }
    }
    return standardPresets.first;
  }
}

/// Trả về nhãn tiếng Việt chuẩn cho trạng thái phiên học.
String sessionStatusLabel(StudySessionStatus? status) {
  switch (status) {
    case StudySessionStatus.running:
      return 'Đang học';
    case StudySessionStatus.paused:
      return 'Đã tạm dừng';
    case StudySessionStatus.inBreak:
      return 'Đang nghỉ';
    case StudySessionStatus.interruptedPending:
      return 'Chờ xác nhận';
    case StudySessionStatus.completed:
      return 'Đã hoàn thành';
    case StudySessionStatus.cancelled:
      return 'Đã hủy';
    case null:
      return 'Sẵn sàng';
  }
}

/// Trả về màu sắc đại diện nhất quán với thiết kế ExamPilot cho trạng thái phiên.
Color sessionStatusColor(StudySessionStatus? status) {
  switch (status) {
    case StudySessionStatus.running:
      return AppColors.primary;
    case StudySessionStatus.paused:
      return AppColors.priorityMedium;
    case StudySessionStatus.inBreak:
      return AppColors.success;
    case StudySessionStatus.interruptedPending:
      return AppColors.error;
    case StudySessionStatus.completed:
      return AppColors.statusCompleted;
    case StudySessionStatus.cancelled:
      return AppColors.textMuted;
    case null:
      return AppColors.textSecondary;
  }
}

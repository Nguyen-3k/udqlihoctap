import 'package:flutter/foundation.dart';

/// Định nghĩa khung giờ chuẩn cho một tiết học đơn lẻ (Phase 6D.2).
@immutable
class ClassPeriodDefinition {
  /// Số thứ tự tiết học (1..4 cho ca sáng, 7..10 cho ca chiều)
  final int period;

  /// Giờ bắt đầu ("HH:mm")
  final String startTime;

  /// Giờ kết thúc ("HH:mm")
  final String endTime;

  /// Phút bắt đầu tính từ 00:00
  final int startMinutes;

  /// Phút kết thúc tính từ 00:00
  final int endMinutes;

  /// Thời lượng học thực tế của 1 tiết (chuẩn 45 phút)
  final int durationMinutes;

  const ClassPeriodDefinition({
    required this.period,
    required this.startTime,
    required this.endTime,
    required this.startMinutes,
    required this.endMinutes,
    this.durationMinutes = 45,
  });
}

/// Kết quả quy đổi khoảng tiết học (startPeriod -> endPeriod) sang giờ thực tế.
@immutable
class PeriodTimeMappingResult {
  /// Tiết bắt đầu (giữ nguyên gốc)
  final int startPeriod;

  /// Tiết kết thúc (giữ nguyên gốc)
  final int endPeriod;

  /// Giờ bắt đầu của tiết đầu tiên ("HH:mm")
  final String startTime;

  /// Giờ kết thúc của tiết cuối cùng ("HH:mm")
  final String endTime;

  /// Thời lượng học thực tế (phút) - KHÔNG bao gồm thời gian nghỉ giải lao
  final int actualStudyMinutes;

  /// Tổng khoảng thời gian từ lúc bắt đầu đến kết thúc (phút) - bao gồm cả giải lao
  final int totalSpanMinutes;

  /// Có thời gian nghỉ giải lao ở giữa ca không
  final bool hasBreak;

  /// Số phút nghỉ giải lao (30 phút nếu có, 0 nếu không)
  final int breakMinutes;

  const PeriodTimeMappingResult({
    required this.startPeriod,
    required this.endPeriod,
    required this.startTime,
    required this.endTime,
    required this.actualStudyMinutes,
    required this.totalSpanMinutes,
    this.hasBreak = false,
    this.breakMinutes = 0,
  });

  /// Chuỗi hiển thị khoảng giờ học
  String get timeRangeText => '$startTime - $endTime';

  /// Chuỗi hiển thị tiết học
  String get periodRangeText => 'Tiết $startPeriod-$endPeriod';

  @override
  String toString() =>
      'PeriodTimeMappingResult(Tiết $startPeriod-$endPeriod -> $timeRangeText, '
      'thực học: ${actualStudyMinutes}p, tổng: ${totalSpanMinutes}p)';
}

/// Thành phần quy đổi thời gian tập trung trong toàn bộ ứng dụng ExamPilot (Phase 6D.2).
///
/// Bảng khung giờ học chính thức:
/// **Ca sáng:**
/// - Tiết 1: 07:00–07:45 (45 phút)
/// - Tiết 2: 07:45–08:30 (45 phút)
/// - *Nghỉ giải lao: 08:30–09:00 (30 phút)*
/// - Tiết 3: 09:00–09:45 (45 phút)
/// - Tiết 4: 09:45–10:30 (45 phút)
///
/// **Ca chiều:**
/// - Tiết 7: 13:30–14:15 (45 phút)
/// - Tiết 8: 14:15–15:00 (45 phút)
/// - *Nghỉ giải lao: 15:00–15:30 (30 phút)*
/// - Tiết 9: 15:30–16:15 (45 phút)
/// - Tiết 10: 16:15–17:00 (45 phút)
///
/// Tiết 5 và 6 không có cấu hình. Không tự suy đoán hoặc sinh giờ cho các tiết chưa có cấu hình.
class ClassPeriodTimeMapper {
  /// Bảng tra cứu thông tin chi tiết từng tiết học được cấu hình chính thức
  static const Map<int, ClassPeriodDefinition> officialPeriods = {
    // Ca sáng
    1: ClassPeriodDefinition(
      period: 1,
      startTime: '07:00',
      endTime: '07:45',
      startMinutes: 7 * 60, // 420
      endMinutes: 7 * 60 + 45, // 465
    ),
    2: ClassPeriodDefinition(
      period: 2,
      startTime: '07:45',
      endTime: '08:30',
      startMinutes: 7 * 60 + 45, // 465
      endMinutes: 8 * 60 + 30, // 510
    ),
    3: ClassPeriodDefinition(
      period: 3,
      startTime: '09:00',
      endTime: '09:45',
      startMinutes: 9 * 60, // 540
      endMinutes: 9 * 60 + 45, // 585
    ),
    4: ClassPeriodDefinition(
      period: 4,
      startTime: '09:45',
      endTime: '10:30',
      startMinutes: 9 * 60 + 45, // 585
      endMinutes: 10 * 60 + 30, // 630
    ),

    // Ca chiều
    7: ClassPeriodDefinition(
      period: 7,
      startTime: '13:30',
      endTime: '14:15',
      startMinutes: 13 * 60 + 30, // 810
      endMinutes: 14 * 60 + 15, // 855
    ),
    8: ClassPeriodDefinition(
      period: 8,
      startTime: '14:15',
      endTime: '15:00',
      startMinutes: 14 * 60 + 15, // 855
      endMinutes: 15 * 60, // 900
    ),
    9: ClassPeriodDefinition(
      period: 9,
      startTime: '15:30',
      endTime: '16:15',
      startMinutes: 15 * 60 + 30, // 930
      endMinutes: 16 * 60 + 15, // 975
    ),
    10: ClassPeriodDefinition(
      period: 10,
      startTime: '16:15',
      endTime: '17:00',
      startMinutes: 16 * 60 + 15, // 975
      endMinutes: 17 * 60, // 1020
    ),
  };

  /// Tập hợp các tiết ca sáng hợp lệ (1, 2, 3, 4)
  static const Set<int> morningPeriods = {1, 2, 3, 4};

  /// Tập hợp các tiết ca chiều hợp lệ (7, 8, 9, 10)
  static const Set<int> afternoonPeriods = {7, 8, 9, 10};

  /// Kiểm tra xem một tiết học có nằm trong bảng quy đổi chính thức hay không
  static bool isConfiguredPeriod(int? period) {
    if (period == null) return false;
    return officialPeriods.containsKey(period);
  }

  /// Quy đổi khoảng tiết học (`startPeriod` -> `endPeriod`) sang khung giờ thực tế.
  ///
  /// Quy tắc:
  /// - `startPeriod` và `endPeriod` phải hợp lệ và `startPeriod <= endPeriod`.
  /// - Tất cả các tiết trong khoảng `[startPeriod, endPeriod]` phải nằm trọn vẹn
  ///   trong Ca sáng (1..4) hoặc Ca chiều (7..10).
  /// - Nếu gặp tiết 5, 6 hoặc tiết nằm ngoài bảng quy đổi -> trả về `null`.
  /// - Nếu khoảng tiết vắt qua cả ca sáng và ca chiều (ví dụ 4 đến 7) -> trả về `null`.
  /// - Giờ bắt đầu lấy từ `startPeriod`, giờ kết thúc lấy từ `endPeriod`.
  /// - Thời lượng học thực tế = `(số tiết) * 45` phút (loại bỏ thời gian nghỉ giải lao).
  static PeriodTimeMappingResult? mapPeriodsToTime(
    int? startPeriod,
    int? endPeriod,
  ) {
    if (startPeriod == null || endPeriod == null) return null;
    if (startPeriod <= 0 || endPeriod <= 0) return null;
    if (startPeriod > endPeriod) return null;

    // Kiểm tra xem khoảng tiết có thuộc trọn vẹn Ca sáng (1..4) hay không
    final isMorning = startPeriod >= 1 && endPeriod <= 4;
    // Kiểm tra xem khoảng tiết có thuộc trọn vẹn Ca chiều (7..10) hay không
    final isAfternoon = startPeriod >= 7 && endPeriod <= 10;

    if (!isMorning && !isAfternoon) {
      // Khoảng tiết chứa tiết 5, 6, hoặc vắt qua sáng - chiều, hoặc ngoài phạm vi
      return null;
    }

    // Đảm bảo tất cả các tiết trong khoảng đều có cấu hình
    for (int p = startPeriod; p <= endPeriod; p++) {
      if (!officialPeriods.containsKey(p)) {
        return null;
      }
    }

    final startDef = officialPeriods[startPeriod]!;
    final endDef = officialPeriods[endPeriod]!;

    final periodCount = endPeriod - startPeriod + 1;
    final actualStudyMinutes = periodCount * 45;
    final totalSpanMinutes = endDef.endMinutes - startDef.startMinutes;

    // Kiểm tra có chứa khoảng nghỉ giải lao hay không:
    // Ca sáng: nghỉ giữa tiết 2 (kết thúc 08:30) và tiết 3 (bắt đầu 09:00) -> có break nếu start <= 2 và end >= 3
    // Ca chiều: nghỉ giữa tiết 8 (kết thúc 15:00) và tiết 9 (bắt đầu 15:30) -> có break nếu start <= 8 và end >= 9
    final hasMorningBreak = isMorning && startPeriod <= 2 && endPeriod >= 3;
    final hasAfternoonBreak = isAfternoon && startPeriod <= 8 && endPeriod >= 9;
    final hasBreak = hasMorningBreak || hasAfternoonBreak;
    final breakMinutes = hasBreak ? 30 : 0;

    return PeriodTimeMappingResult(
      startPeriod: startPeriod,
      endPeriod: endPeriod,
      startTime: startDef.startTime,
      endTime: endDef.endTime,
      actualStudyMinutes: actualStudyMinutes,
      totalSpanMinutes: totalSpanMinutes,
      hasBreak: hasBreak,
      breakMinutes: breakMinutes,
    );
  }

  /// Tính thời lượng học thực tế (số phút) từ `startPeriod` và `endPeriod`.
  /// Loại trừ hoàn toàn 30 phút nghỉ giải lao ở giữa ca (nếu có).
  /// Trả về `null` nếu tiết học chưa được cấu hình hoặc không hợp lệ.
  static int? getActualStudyMinutes(int? startPeriod, int? endPeriod) {
    final result = mapPeriodsToTime(startPeriod, endPeriod);
    return result?.actualStudyMinutes;
  }
}

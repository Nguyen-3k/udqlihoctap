import 'study_session.dart';

/// Đại diện cho chuỗi ngày học tập liên tiếp (Study Streak) của sinh viên.
/// Tính toán dựa trên ngày lịch địa phương thuần túy `(year, month, day)` theo quy tắc G8.8.4:
/// - Cần đạt tối thiểu `900` giây (15 phút) học thực tế đã xác nhận từ `study_sessions` (`completed`) mỗi ngày.
/// - Áp dụng Pure Calendar-Day Stepping để miễn nhiễm với DST (ngày 23h/25h) và đổi múi giờ.
class StudyStreak {
  /// Ngưỡng tối thiểu mỗi ngày địa phương để nhận +1 ngày Streak (15 phút = 900 giây).
  static const int minDailySecondsForStreak = 900;

  /// Số ngày học liên tiếp hiện tại.
  final int currentStreak;

  /// Kỷ lục chuỗi ngày học liên tiếp dài nhất từng đạt được.
  final int longestStreak;

  /// Tập hợp các ngày đạt chuẩn Streak (định dạng `YYYY-MM-DD` theo giờ địa phương).
  final Set<String> activeDates;

  const StudyStreak({
    required this.currentStreak,
    required this.longestStreak,
    required this.activeDates,
  });

  /// Kiểm tra xem một ngày cụ thể có đạt điều kiện Streak hay không.
  bool hasActivityOn(DateTime date) {
    final key = formatDateKey(date);
    return activeDates.contains(key);
  }

  /// Kiểm tra năm nhuận theo lịch Gregorian.
  static bool isLeapYear(int year) {
    return (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0);
  }

  /// Số ngày thực tế của một tháng trong năm.
  static int daysInMonth(int year, int month) {
    switch (month) {
      case 1:
      case 3:
      case 5:
      case 7:
      case 8:
      case 10:
      case 12:
        return 31;
      case 4:
      case 6:
      case 9:
      case 11:
        return 30;
      case 2:
        return isLeapYear(year) ? 29 : 28;
      default:
        throw ArgumentError.value(month, 'month', 'Tháng phải nằm trong 1..12');
    }
  }

  /// Định dạng bộ `(year, month, day)` thành khóa `YYYY-MM-DD`.
  static String formatCalendarTuple(int year, int month, int day) {
    final y = year.toString().padLeft(4, '0');
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Định dạng ngày sang khóa chuẩn `YYYY-MM-DD` theo giờ địa phương.
  static String formatDateKey(DateTime dt) {
    final local = dt.toLocal();
    return formatCalendarTuple(local.year, local.month, local.day);
  }

  /// Bước lùi đúng 1 ngày lịch trên bộ `(year, month, day)` (không dùng `Duration`).
  static (int, int, int) previousCalendarDay(int year, int month, int day) {
    if (day > 1) {
      return (year, month, day - 1);
    }
    if (month > 1) {
      final prevMonth = month - 1;
      return (year, prevMonth, daysInMonth(year, prevMonth));
    }
    return (year - 1, 12, 31);
  }

  /// Bước tiến đúng 1 ngày lịch trên bộ `(year, month, day)` (không dùng `Duration`).
  static (int, int, int) nextCalendarDay(int year, int month, int day) {
    final maxDays = daysInMonth(year, month);
    if (day < maxDays) {
      return (year, month, day + 1);
    }
    if (month < 12) {
      return (year, month + 1, 1);
    }
    return (year + 1, 1, 1);
  }

  /// Phân tích an toàn khóa `YYYY-MM-DD` thành bộ `(year, month, day)` hợp lệ trên lịch Gregorian.
  static (int, int, int)? tryParseCalendarTuple(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return null;
    if (month < 1 || month > 12 || day < 1) return null;
    if (day > daysInMonth(year, month)) return null;
    return (year, month, day);
  }

  /// Chuyển đổi khóa YYYY-MM-DD ngược lại đối tượng DateTime địa phương.
  static DateTime parseDateKey(String key) {
    final parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  /// Cộng dồn tổng giây học thực tế từ các phiên `completed` theo từng ngày địa phương `study_date`.
  /// Không cộng phiên chưa hoàn thành, phiên bị hủy, phiên chờ Recovery hoặc thời gian nghỉ.
  static Map<String, int> sumCompletedSecondsByDate(
    List<StudySession> sessions,
  ) {
    final totals = <String, int>{};
    for (final session in sessions) {
      if (session.status != StudySessionStatus.completed) continue;
      if (tryParseCalendarTuple(session.studyDate) == null) continue;
      totals[session.studyDate] =
          (totals[session.studyDate] ?? 0) + session.verifiedStudySeconds;
    }
    return totals;
  }

  /// Tính toán Study Streak chính thức từ danh sách `StudySession` (quy tắc >= 900s/ngày).
  /// Học ngoài lịch hoặc nhiều phiên cộng dồn trong cùng ngày đều hợp lệ; tối đa +1 ngày Streak/ngày.
  factory StudyStreak.fromSessions(
    List<StudySession> sessions, {
    DateTime? now,
    int minimumDailySeconds = minDailySecondsForStreak,
  }) {
    final dailyTotals = sumCompletedSecondsByDate(sessions);
    final qualifiedDates = <String>{};
    dailyTotals.forEach((dateKey, seconds) {
      if (seconds >= minimumDailySeconds) {
        qualifiedDates.add(dateKey);
      }
    });
    return StudyStreak.fromActiveDates(qualifiedDates, now: now);
  }

  /// Tính toán Study Streak từ tập các khóa ngày đạt chuẩn bằng Pure Calendar-Day Stepping.
  factory StudyStreak.fromActiveDates(
    Set<String> activeDates, {
    DateTime? now,
  }) {
    final currentLocal = (now ?? DateTime.now()).toLocal();
    final todayTuple = (
      currentLocal.year,
      currentLocal.month,
      currentLocal.day,
    );
    final todayKey = formatCalendarTuple(
      todayTuple.$1,
      todayTuple.$2,
      todayTuple.$3,
    );
    final yesterdayTuple = previousCalendarDay(
      todayTuple.$1,
      todayTuple.$2,
      todayTuple.$3,
    );
    final yesterdayKey = formatCalendarTuple(
      yesterdayTuple.$1,
      yesterdayTuple.$2,
      yesterdayTuple.$3,
    );

    final normalizedDates = <String>{};
    final validTuples = <(int, int, int)>[];
    for (final rawKey in activeDates) {
      final tuple = tryParseCalendarTuple(rawKey);
      if (tuple == null) continue;
      final canonicalKey = formatCalendarTuple(tuple.$1, tuple.$2, tuple.$3);
      if (normalizedDates.add(canonicalKey)) {
        validTuples.add(tuple);
      }
    }

    // 1. Tính currentStreak bằng bước lùi ngày lịch thuần túy
    int currentStreak = 0;
    if (normalizedDates.contains(todayKey)) {
      currentStreak = 1;
      var cursor = previousCalendarDay(
        todayTuple.$1,
        todayTuple.$2,
        todayTuple.$3,
      );
      while (normalizedDates.contains(
        formatCalendarTuple(cursor.$1, cursor.$2, cursor.$3),
      )) {
        currentStreak++;
        cursor = previousCalendarDay(cursor.$1, cursor.$2, cursor.$3);
      }
    } else if (normalizedDates.contains(yesterdayKey)) {
      currentStreak = 1;
      var cursor = previousCalendarDay(
        yesterdayTuple.$1,
        yesterdayTuple.$2,
        yesterdayTuple.$3,
      );
      while (normalizedDates.contains(
        formatCalendarTuple(cursor.$1, cursor.$2, cursor.$3),
      )) {
        currentStreak++;
        cursor = previousCalendarDay(cursor.$1, cursor.$2, cursor.$3);
      }
    }

    // 2. Tính longestStreak bằng sắp xếp và kiểm tra nextCalendarDay trực tiếp
    int maxStreak = 0;
    if (validTuples.isNotEmpty) {
      validTuples.sort((a, b) {
        if (a.$1 != b.$1) return a.$1.compareTo(b.$1);
        if (a.$2 != b.$2) return a.$2.compareTo(b.$2);
        return a.$3.compareTo(b.$3);
      });

      int currentRun = 0;
      (int, int, int)? prevTuple;
      for (final tuple in validTuples) {
        if (prevTuple == null) {
          currentRun = 1;
        } else {
          final expectedNext = nextCalendarDay(
            prevTuple.$1,
            prevTuple.$2,
            prevTuple.$3,
          );
          if (expectedNext == tuple) {
            currentRun++;
          } else {
            currentRun = 1;
          }
        }
        if (currentRun > maxStreak) {
          maxStreak = currentRun;
        }
        prevTuple = tuple;
      }
    }

    if (currentStreak > maxStreak) {
      maxStreak = currentStreak;
    }

    return StudyStreak(
      currentStreak: currentStreak,
      longestStreak: maxStreak,
      activeDates: normalizedDates,
    );
  }
}

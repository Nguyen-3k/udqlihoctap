/// Đại diện cho chuỗi ngày học tập liên tiếp (Study Streak) của sinh viên.
/// Tính toán dựa trên ngày địa phương (local date), đảm bảo tính nhất quán và kỷ lục không bị giảm.
class StudyStreak {
  /// Số ngày học liên tiếp hiện tại.
  final int currentStreak;

  /// Kỷ lục chuỗi ngày học liên tiếp dài nhất từng đạt được.
  final int longestStreak;

  /// Tập hợp các ngày đã có hoạt động học tập (định dạng YYYY-MM-DD theo giờ địa phương).
  final Set<String> activeDates;

  const StudyStreak({
    required this.currentStreak,
    required this.longestStreak,
    required this.activeDates,
  });

  /// Kiểm tra xem một ngày cụ thể có hoạt động hoàn thành bài học không.
  bool hasActivityOn(DateTime date) {
    final key = formatDateKey(date);
    return activeDates.contains(key);
  }

  /// Định dạng ngày sang khóa chuẩn YYYY-MM-DD theo giờ địa phương.
  static String formatDateKey(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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

  /// Tính toán Study Streak từ danh sách các ngày hoạt động thực tế.
  factory StudyStreak.fromActiveDates(
    Set<String> activeDates, {
    DateTime? now,
  }) {
    final currentNow = now ?? DateTime.now();
    final today = DateTime(currentNow.year, currentNow.month, currentNow.day);
    final todayKey = formatDateKey(today);
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayKey = formatDateKey(yesterday);

    // 1. Tính currentStreak (chuỗi hiện tại)
    int currentStreak = 0;
    if (activeDates.contains(todayKey)) {
      // Đã có hoạt động hôm nay -> tính lùi từ hôm nay
      currentStreak = 1;
      var checkDate = today.subtract(const Duration(days: 1));
      while (activeDates.contains(formatDateKey(checkDate))) {
        currentStreak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      }
    } else if (activeDates.contains(yesterdayKey)) {
      // Hôm nay chưa có hoạt động nhưng hôm qua có -> chuỗi vẫn được bảo lưu từ hôm qua
      currentStreak = 1;
      var checkDate = today.subtract(const Duration(days: 2));
      while (activeDates.contains(formatDateKey(checkDate))) {
        currentStreak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      }
    } else {
      // Cả hôm nay và hôm qua đều không có hoạt động -> chuỗi hiện tại bằng 0
      currentStreak = 0;
    }

    // 2. Tính longestStreak (chuỗi dài nhất lịch sử)
    int maxStreak = 0;
    if (activeDates.isNotEmpty) {
      final sortedDates = activeDates.map(parseDateKey).toList()..sort();
      int currentRun = 0;
      DateTime? prevDate;

      for (final d in sortedDates) {
        if (prevDate == null) {
          currentRun = 1;
        } else {
          final diff = d.difference(prevDate).inDays;
          if (diff == 1) {
            currentRun++;
          } else if (diff > 1) {
            currentRun = 1;
          }
        }
        if (currentRun > maxStreak) {
          maxStreak = currentRun;
        }
        prevDate = d;
      }
    }

    if (currentStreak > maxStreak) {
      maxStreak = currentStreak;
    }

    return StudyStreak(
      currentStreak: currentStreak,
      longestStreak: maxStreak,
      activeDates: activeDates,
    );
  }
}

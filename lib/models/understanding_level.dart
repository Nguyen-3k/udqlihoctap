import 'package:flutter/material.dart';

/// Đại diện cho mức độ hiểu bài sau khi sinh viên hoàn thành công việc học tập.
enum UnderstandingLevel {
  /// 1. Chưa hiểu (Cần học lại)
  notUnderstood,

  /// 2. Hiểu một phần (Cần củng cố thêm)
  partiallyUnderstood,

  /// 3. Đã nắm vững (Đã hiểu tốt)
  mastered;

  /// Nhãn hiển thị bằng tiếng Việt.
  String get label {
    switch (this) {
      case UnderstandingLevel.notUnderstood:
        return 'Chưa hiểu';
      case UnderstandingLevel.partiallyUnderstood:
        return 'Hiểu một phần';
      case UnderstandingLevel.mastered:
        return 'Đã nắm vững';
    }
  }

  /// Mô tả gợi ý cho mức độ hiểu.
  String get description {
    switch (this) {
      case UnderstandingLevel.notUnderstood:
        return 'Chưa nắm rõ nội dung, cần xem lại lý thuyết hoặc hỏi giảng viên';
      case UnderstandingLevel.partiallyUnderstood:
        return 'Đã nắm khái niệm cơ bản nhưng cần luyện thêm bài tập';
      case UnderstandingLevel.mastered:
        return 'Đã hiểu rõ bản chất và có thể tự tin làm bài thi / bài tập';
    }
  }

  /// Biểu tượng cảm xúc trực quan.
  IconData get icon {
    switch (this) {
      case UnderstandingLevel.notUnderstood:
        return Icons.sentiment_dissatisfied_rounded;
      case UnderstandingLevel.partiallyUnderstood:
        return Icons.sentiment_neutral_rounded;
      case UnderstandingLevel.mastered:
        return Icons.sentiment_very_satisfied_rounded;
    }
  }

  /// Màu sắc đại diện.
  Color get color {
    switch (this) {
      case UnderstandingLevel.notUnderstood:
        return const Color(0xFFDC2626); // Đỏ cam
      case UnderstandingLevel.partiallyUnderstood:
        return const Color(0xFFD97706); // Hổ phách / Vàng cam
      case UnderstandingLevel.mastered:
        return const Color(0xFF16A34A); // Xanh lá
    }
  }

  /// Màu nền nhẹ nhàng (Badge/Container background).
  Color get backgroundColor {
    switch (this) {
      case UnderstandingLevel.notUnderstood:
        return const Color(0xFFFEE2E2);
      case UnderstandingLevel.partiallyUnderstood:
        return const Color(0xFFFEF3C7);
      case UnderstandingLevel.mastered:
        return const Color(0xFFDCFCE7);
    }
  }

  /// Màu viền nhẹ.
  Color get borderColor {
    switch (this) {
      case UnderstandingLevel.notUnderstood:
        return const Color(0xFFFCA5A5);
      case UnderstandingLevel.partiallyUnderstood:
        return const Color(0xFFFCD34D);
      case UnderstandingLevel.mastered:
        return const Color(0xFF86EFAC);
    }
  }
}

import 'package:flutter/material.dart';

/// Bảng mã màu chuẩn của ExamPilot tuân theo hệ thống thiết kế hiện đại (Design System).
/// Phù hợp ứng dụng giáo dục / năng suất cá nhân (Education & Productivity).
class AppColors {
  AppColors._();

  // Màu thương hiệu chủ đạo (Royal Indigo)
  static const Color primary = Color(0xFF3B5BDB);
  static const Color primaryHover = Color(0xFF364FC7);
  static const Color primaryContainer = Color(0xFFEEF2FF);
  static const Color onPrimaryContainer = Color(0xFF2B44B8);

  // Màu nền & bề mặt (Slate Neutral System)
  static const Color background = Color(
    0xFFF8FAFC,
  ); // Nền xám dịu mắt chống mỏi
  static const Color surface = Color(
    0xFFFFFFFF,
  ); // Thẻ và modal màu trắng tinh khiết
  static const Color surfaceMuted = Color(0xFFF1F5F9); // Nền phụ, ô nhập liệu
  static const Color border = Color(
    0xFFE2E8F0,
  ); // Viền mảnh tinh tế, độ tương phản cao
  static const Color borderSubtle = Color(0xFFEEF2F6); // Viền ngăn cách nhẹ

  // Màu chữ (Typography)
  static const Color textPrimary = Color(
    0xFF0F172A,
  ); // Tiêu đề chính, văn bản chính
  static const Color textSecondary = Color(0xFF475569); // Nội dung phụ, nhãn
  static const Color textMuted = Color(
    0xFF94A3B8,
  ); // Chữ mờ, placeholder, biểu tượng mờ

  // Màu mức độ ưu tiên (Priority Levels)
  static const Color priorityHigh = Color(0xFFDC2626); // Đỏ ưu tiên cao
  static const Color priorityHighBg = Color(0xFFFEF2F2);
  static const Color priorityHighBorder = Color(0xFFFECACA);

  static const Color priorityMedium = Color(
    0xFFD97706,
  ); // Cam hổ phách vừa phải
  static const Color priorityMediumBg = Color(0xFFFFFBEB);
  static const Color priorityMediumBorder = Color(0xFFFDE68A);

  static const Color priorityLow = Color(0xFF16A34A); // Xanh lá ưu tiên thấp
  static const Color priorityLowBg = Color(0xFFF0FDF4);
  static const Color priorityLowBorder = Color(0xFFBBF7D0);

  // Màu trạng thái công việc (Task Status)
  static const Color statusTodo = Color(0xFF64748B); // Slate xám
  static const Color statusTodoBg = Color(0xFFF1F5F9);

  static const Color statusInProgress = Color(0xFF0284C7); // Sky blue
  static const Color statusInProgressBg = Color(0xFFE0F2FE);

  static const Color statusCompleted = Color(0xFF16A34A); // Emerald green
  static const Color statusCompletedBg = Color(0xFFDCFCE7);

  // Màu chức năng phụ (Error, Success, Warning)
  static const Color error = Color(0xFFDC2626);
  static const Color errorContainer = Color(0xFFFEE2E2);
  static const Color success = Color(0xFF16A34A);
}

import 'package:flutter/material.dart';

/// Đại diện cho môn học trong ExamPilot.
class Subject {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  const Subject({
    required this.id,
    required this.name,
    required this.description,
    this.icon = Icons.menu_book_rounded,
    this.color = const Color(0xFF3B5BDB),
  });

  /// Chuyển đổi môn học sang Map để lưu trữ trong SQLite.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'icon_code': icon.codePoint,
      'color_value': color.toARGB32(),
    };
  }

  /// Khởi tạo môn học từ Map đọc ra từ SQLite.
  factory Subject.fromMap(Map<String, dynamic> map) {
    final iconCode = (map['icon_code'] as num?)?.toInt();
    final colorVal = (map['color_value'] as num?)?.toInt();

    return Subject(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      description: map['description']?.toString() ?? '',
      icon: _resolveIcon(iconCode),
      color: colorVal != null ? Color(colorVal) : const Color(0xFF3B5BDB),
    );
  }

  static IconData _resolveIcon(int? codePoint) {
    if (codePoint == null) return Icons.menu_book_rounded;
    const availableIcons = [
      Icons.menu_book_rounded,
      Icons.code_rounded,
      Icons.functions_rounded,
      Icons.storage_rounded,
      Icons.language_rounded,
      Icons.science_rounded,
      Icons.school_rounded,
      Icons.lightbulb_outline_rounded,
    ];
    for (final icon in availableIcons) {
      if (icon.codePoint == codePoint) return icon;
    }
    return Icons.menu_book_rounded;
  }

  /// Tạo bản sao môn học có cập nhật các trường.
  Subject copyWith({
    String? id,
    String? name,
    String? description,
    IconData? icon,
    Color? color,
  }) {
    return Subject(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      icon: icon ?? this.icon,
      color: color ?? this.color,
    );
  }
}

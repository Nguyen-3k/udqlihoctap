import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/subject.dart';

/// Repository quản lý dữ liệu môn học (Subject).
/// - Trên Android: Đọc/ghi bền vững vào bảng `subjects` trong SQLite.
/// - Trên Web / Chrome: Sử dụng bộ nhớ tạm (In-memory Web Preview), không gọi sqflite.
class SubjectRepository {
  final DatabaseHelper? _dbHelper;
  final bool _isWebPreviewForced;
  final List<Subject> _webSubjects = [];
  bool _webInitialized = false;

  SubjectRepository({DatabaseHelper? dbHelper, bool useWebPreview = false})
    : _isWebPreviewForced = useWebPreview,
      _dbHelper = useWebPreview
          ? null
          : (dbHelper ?? (kIsWeb ? null : DatabaseHelper.instance)) {
    if (isWebPreview) {
      _initWebPreviewSubjects();
    }
  }

  /// Kiểm tra xem repository có đang hoạt động ở chế độ Web Preview hay không.
  bool get isWebPreview => _isWebPreviewForced || (kIsWeb && _dbHelper == null);

  /// Khởi tạo các môn học mẫu ban đầu cho phiên làm việc Web Preview.
  void _initWebPreviewSubjects() {
    if (_webInitialized) return;
    _webSubjects.addAll(getDefaultSubjects());
    _webInitialized = true;
  }

  /// Danh mục 4 môn học mặc định ban đầu.
  static List<Subject> getDefaultSubjects() {
    return const [
      Subject(
        id: 'subj_1',
        name: 'Toán cao cấp',
        description: 'Đạo hàm, tích phân và đại số tuyến tính',
        icon: Icons.functions_rounded,
        color: Color(0xFF3B5BDB),
      ),
      Subject(
        id: 'subj_2',
        name: 'Lập trình Web',
        description: 'HTML, CSS, JavaScript và kiến trúc Web',
        icon: Icons.code_rounded,
        color: Color(0xFF0284C7),
      ),
      Subject(
        id: 'subj_3',
        name: 'Cơ sở dữ liệu',
        description: 'Mô hình quan hệ, SQL và chuẩn hóa dữ liệu',
        icon: Icons.storage_rounded,
        color: Color(0xFFD97706),
      ),
      Subject(
        id: 'subj_4',
        name: 'Tiếng Anh',
        description: 'Từ vựng chuyên ngành CNTT và ngữ pháp',
        icon: Icons.language_rounded,
        color: Color(0xFFE11D48),
      ),
    ];
  }

  /// Lấy toàn bộ danh sách môn học.
  Future<List<Subject>> getAllSubjects() async {
    if (isWebPreview) {
      return List<Subject>.from(_webSubjects);
    }

    try {
      final db = await _dbHelper!.database;
      final maps = await db.query(
        DatabaseHelper.tableSubjects,
        orderBy: '${DatabaseHelper.columnSubjectName} ASC',
      );
      return maps.map((m) => Subject.fromMap(m)).toList();
    } catch (e) {
      throw Exception('Không thể tải danh sách môn học từ cơ sở dữ liệu: $e');
    }
  }

  /// Thêm một môn học mới.
  Future<void> insertSubject(Subject subject) async {
    if (isWebPreview) {
      _webSubjects.removeWhere((s) => s.id == subject.id);
      _webSubjects.add(subject);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.insert(
        DatabaseHelper.tableSubjects,
        subject.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      throw Exception('Không thể thêm môn học vào cơ sở dữ liệu: $e');
    }
  }

  /// Cập nhật thông tin một môn học đã có.
  Future<void> updateSubject(Subject subject) async {
    if (isWebPreview) {
      final index = _webSubjects.indexWhere((s) => s.id == subject.id);
      if (index != -1) {
        _webSubjects[index] = subject;
      } else {
        _webSubjects.add(subject);
      }
      return;
    }

    try {
      final db = await _dbHelper!.database;
      final count = await db.update(
        DatabaseHelper.tableSubjects,
        subject.toMap(),
        where: '${DatabaseHelper.columnSubjectId} = ?',
        whereArgs: [subject.id],
      );
      if (count == 0) {
        throw Exception(
          'Không tìm thấy môn học với id ${subject.id} để cập nhật',
        );
      }
    } catch (e) {
      throw Exception('Không thể cập nhật môn học trong cơ sở dữ liệu: $e');
    }
  }

  /// Xóa môn học khỏi cơ sở dữ liệu theo id.
  Future<void> deleteSubject(String subjectId) async {
    if (isWebPreview) {
      _webSubjects.removeWhere((s) => s.id == subjectId);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.delete(
        DatabaseHelper.tableSubjects,
        where: '${DatabaseHelper.columnSubjectId} = ?',
        whereArgs: [subjectId],
      );
    } catch (e) {
      throw Exception('Không thể xóa môn học khỏi cơ sở dữ liệu: $e');
    }
  }

  /// Khôi phục danh sách môn học mặc định.
  Future<void> resetDefaultSubjects(List<Subject> subjects) async {
    if (isWebPreview) {
      _webSubjects.clear();
      _webSubjects.addAll(subjects);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.transaction((txn) async {
        await txn.delete(DatabaseHelper.tableSubjects);
        for (final s in subjects) {
          await txn.insert(
            DatabaseHelper.tableSubjects,
            s.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (e) {
      throw Exception('Không thể khôi phục môn học mẫu: $e');
    }
  }
}

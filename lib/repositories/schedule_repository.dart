import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/class_schedule.dart';
import '../services/web_storage.dart';

/// Repository quản lý dữ liệu Lịch học cố định theo tuần (`class_schedules`).
/// - Trên Android / Thiết bị di động: Thao tác qua SQLite bảng `class_schedules`.
/// - Trên Web / Trình duyệt Chrome: Lưu trữ qua `WebScheduleStorage`.
class ScheduleRepository {
  final DatabaseHelper? _dbHelper;
  final bool _isWebPreviewForced;
  final List<ClassSchedule> _webSchedules = [];
  bool _webInitialized = false;

  ScheduleRepository({DatabaseHelper? dbHelper, bool useWebPreview = false})
      : _isWebPreviewForced = useWebPreview,
        _dbHelper = useWebPreview
            ? null
            : (dbHelper ?? (kIsWeb ? null : DatabaseHelper.instance)) {
    if (isWebPreview) {
      _initWebPreviewSchedules();
    }
  }

  bool get isWebPreview => _isWebPreviewForced || (kIsWeb && _dbHelper == null);

  void _initWebPreviewSchedules() {
    if (_webInitialized) return;
    _webSchedules.addAll(WebScheduleStorage.loadSchedules());
    _webInitialized = true;
  }

  /// Lấy toàn bộ danh sách lịch học (sắp xếp theo thứ trong tuần, rồi đến giờ bắt đầu)
  Future<List<ClassSchedule>> getAllSchedules() async {
    if (isWebPreview) {
      final list = List<ClassSchedule>.from(_webSchedules);
      _sortSchedules(list);
      return list;
    }

    try {
      final db = await _dbHelper!.database;
      final maps = await db.query(
        DatabaseHelper.tableClassSchedules,
        orderBy:
            '${DatabaseHelper.columnScheduleDayOfWeek} ASC, ${DatabaseHelper.columnScheduleStartTime} ASC',
      );
      return maps.map((m) => ClassSchedule.fromMap(m)).toList();
    } catch (e) {
      if (e.toString().contains('no such table')) {
        return const [];
      }
      rethrow;
    }
  }

  /// Lấy các lịch học đang ở trạng thái hoạt động (isActive = true)
  Future<List<ClassSchedule>> getActiveSchedules() async {
    if (isWebPreview) {
      final list = _webSchedules.where((s) => s.isActive).toList();
      _sortSchedules(list);
      return list;
    }

    try {
      final db = await _dbHelper!.database;
      final maps = await db.query(
        DatabaseHelper.tableClassSchedules,
        where: '${DatabaseHelper.columnScheduleIsActive} = 1',
        orderBy:
            '${DatabaseHelper.columnScheduleDayOfWeek} ASC, ${DatabaseHelper.columnScheduleStartTime} ASC',
      );
      return maps.map((m) => ClassSchedule.fromMap(m)).toList();
    } catch (e) {
      if (e.toString().contains('no such table')) {
        return const [];
      }
      rethrow;
    }
  }

  /// Tìm lịch học theo ID
  Future<ClassSchedule?> getScheduleById(String id) async {
    if (isWebPreview) {
      for (final s in _webSchedules) {
        if (s.id == id) return s;
      }
      return null;
    }

    final db = await _dbHelper!.database;
    final maps = await db.query(
      DatabaseHelper.tableClassSchedules,
      where: '${DatabaseHelper.columnScheduleId} = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return ClassSchedule.fromMap(maps.first);
    }
    return null;
  }

  /// Thêm mới một lịch học
  Future<void> insertSchedule(ClassSchedule schedule) async {
    if (isWebPreview) {
      _webSchedules.removeWhere((s) => s.id == schedule.id);
      _webSchedules.add(schedule);
      WebScheduleStorage.saveSchedules(_webSchedules);
      return;
    }

    final db = await _dbHelper!.database;
    await db.insert(
      DatabaseHelper.tableClassSchedules,
      schedule.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Thêm hàng loạt lịch học (Batch insert sử dụng transaction/batch)
  Future<void> insertSchedulesBatch(List<ClassSchedule> schedules) async {
    if (schedules.isEmpty) return;
    if (isWebPreview) {
      final existingIds = schedules.map((s) => s.id).toSet();
      _webSchedules.removeWhere((s) => existingIds.contains(s.id));
      _webSchedules.addAll(schedules);
      WebScheduleStorage.saveSchedules(_webSchedules);
      return;
    }

    final db = await _dbHelper!.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final s in schedules) {
        batch.insert(
          DatabaseHelper.tableClassSchedules,
          s.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Cập nhật một lịch học hiện có
  Future<void> updateSchedule(ClassSchedule schedule) async {
    if (isWebPreview) {
      final index = _webSchedules.indexWhere((s) => s.id == schedule.id);
      if (index != -1) {
        _webSchedules[index] = schedule;
        WebScheduleStorage.saveSchedules(_webSchedules);
      }
      return;
    }

    final db = await _dbHelper!.database;
    await db.update(
      DatabaseHelper.tableClassSchedules,
      schedule.toMap(),
      where: '${DatabaseHelper.columnScheduleId} = ?',
      whereArgs: [schedule.id],
    );
  }

  /// Xóa lịch học theo ID
  Future<void> deleteSchedule(String id) async {
    if (isWebPreview) {
      _webSchedules.removeWhere((s) => s.id == id);
      WebScheduleStorage.saveSchedules(_webSchedules);
      return;
    }

    final db = await _dbHelper!.database;
    await db.delete(
      DatabaseHelper.tableClassSchedules,
      where: '${DatabaseHelper.columnScheduleId} = ?',
      whereArgs: [id],
    );
  }

  /// Bật hoặc tắt trạng thái hoạt động của lịch học
  Future<void> toggleScheduleActive(String id, bool isActive) async {
    if (isWebPreview) {
      final index = _webSchedules.indexWhere((s) => s.id == id);
      if (index != -1) {
        _webSchedules[index] = _webSchedules[index].copyWith(isActive: isActive);
        WebScheduleStorage.saveSchedules(_webSchedules);
      }
      return;
    }

    final db = await _dbHelper!.database;
    await db.update(
      DatabaseHelper.tableClassSchedules,
      {DatabaseHelper.columnScheduleIsActive: isActive ? 1 : 0},
      where: '${DatabaseHelper.columnScheduleId} = ?',
      whereArgs: [id],
    );
  }

  /// Xóa toàn bộ lịch học (phục vụ reset hoặc khôi phục)
  Future<void> clearAllSchedules() async {
    if (isWebPreview) {
      _webSchedules.clear();
      WebScheduleStorage.clearSchedules();
      return;
    }

    final db = await _dbHelper!.database;
    await db.delete(DatabaseHelper.tableClassSchedules);
  }

  /// Đặt lại toàn bộ danh sách lịch học (phục vụ restore từ bản sao lưu)
  Future<void> resetDefaultSchedules(List<ClassSchedule> schedules) async {
    if (isWebPreview) {
      _webSchedules
        ..clear()
        ..addAll(schedules);
      WebScheduleStorage.saveSchedules(_webSchedules);
      return;
    }

    final db = await _dbHelper!.database;
    final batch = db.batch();
    batch.delete(DatabaseHelper.tableClassSchedules);
    for (final s in schedules) {
      batch.insert(
        DatabaseHelper.tableClassSchedules,
        s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  void _sortSchedules(List<ClassSchedule> list) {
    list.sort((a, b) {
      final dayComp = a.dayOfWeek.compareTo(b.dayOfWeek);
      if (dayComp != 0) return dayComp;
      return a.startMinutesSinceMidnight.compareTo(b.startMinutesSinceMidnight);
    });
  }
}

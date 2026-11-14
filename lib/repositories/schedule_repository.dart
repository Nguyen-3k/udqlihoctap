import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/class_schedule.dart';
import '../models/class_schedule_occurrence.dart';
import '../models/subject.dart';
import '../services/web_storage.dart';

/// Repository quản lý dữ liệu Lịch học cố định theo tuần (`class_schedules`).
/// - Trên Android / Thiết bị di động: Thao tác qua SQLite bảng `class_schedules`.
/// - Trên Web / Trình duyệt Chrome: Lưu trữ qua `WebScheduleStorage`.
class ScheduleRepository {
  final DatabaseHelper? _dbHelper;
  final bool _isWebPreviewForced;
  final List<ClassSchedule> _webSchedules = [];
  final List<ClassScheduleOccurrence> _webOccurrences = [];
  bool _webInitialized = false;

  ScheduleRepository({DatabaseHelper? dbHelper, bool useWebPreview = false})
      : _isWebPreviewForced = useWebPreview,
        _dbHelper = useWebPreview
            ? null
            : (dbHelper ?? (kIsWeb ? null : DatabaseHelper.instance)) {
    if (isWebPreview) {
      _initWebPreviewSchedules();
      _initWebPreviewOccurrences();
    }
  }

  bool get isWebPreview => _isWebPreviewForced || (kIsWeb && _dbHelper == null);

  void _initWebPreviewSchedules() {
    if (_webInitialized) return;
    _webSchedules.addAll(WebScheduleStorage.loadSchedules());
    _webInitialized = true;
  }

  void _initWebPreviewOccurrences() {
    _webOccurrences.clear();
    _webOccurrences.addAll(WebOccurrenceStorage.loadOccurrences());
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

  /// Thêm hàng loạt môn học mới và lịch học trong cùng một Transaction nguyên tử
  /// Nếu có lỗi xảy ra ở bất kỳ bước nào (môn học hoặc lịch học), toàn bộ thao tác sẽ bị rollback.
  Future<void> importSchedulesWithSubjectsBatch({
    required List<ClassSchedule> schedules,
    required List<Subject> newSubjects,
  }) async {
    if (schedules.isEmpty && newSubjects.isEmpty) return;

    if (isWebPreview) {
      final existingIds = schedules.map((s) => s.id).toSet();
      _webSchedules.removeWhere((s) => existingIds.contains(s.id));
      _webSchedules.addAll(schedules);
      WebScheduleStorage.saveSchedules(_webSchedules);
      return;
    }

    final db = await _dbHelper!.database;
    await db.transaction((txn) async {
      // 1. Chèn các môn học mới vào bảng subjects
      for (final subject in newSubjects) {
        await txn.insert(
          DatabaseHelper.tableSubjects,
          subject.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 2. Chèn các lịch học vào bảng class_schedules
      for (final schedule in schedules) {
        await txn.insert(
          DatabaseHelper.tableClassSchedules,
          schedule.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
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

  // ==========================================
  // QUẢN LÝ BUỔI HỌC THEO NGÀY (OCCURRENCES - PHASE 6D)
  // ==========================================

  /// Lấy toàn bộ danh sách buổi học theo ngày (sắp xếp theo classDate, rồi startTime)
  Future<List<ClassScheduleOccurrence>> getAllOccurrences() async {
    if (isWebPreview) {
      final list = List<ClassScheduleOccurrence>.from(_webOccurrences);
      _sortOccurrences(list);
      return list;
    }

    try {
      final db = await _dbHelper!.database;
      final maps = await db.query(
        DatabaseHelper.tableScheduleOccurrences,
        orderBy:
            '${DatabaseHelper.columnOccClassDate} ASC, ${DatabaseHelper.columnOccStartTime} ASC',
      );
      return maps.map((m) => ClassScheduleOccurrence.fromMap(m)).toList();
    } catch (e) {
      if (e.toString().contains('no such table')) {
        return const [];
      }
      rethrow;
    }
  }

  /// Lấy các buổi học trong một ngày cụ thể (YYYY-MM-DD)
  Future<List<ClassScheduleOccurrence>> getOccurrencesForDate(String date) async {
    if (isWebPreview) {
      final list = _webOccurrences.where((o) => o.classDate == date).toList();
      _sortOccurrences(list);
      return list;
    }

    try {
      final db = await _dbHelper!.database;
      final maps = await db.query(
        DatabaseHelper.tableScheduleOccurrences,
        where: '${DatabaseHelper.columnOccClassDate} = ?',
        whereArgs: [date],
        orderBy: '${DatabaseHelper.columnOccStartTime} ASC',
      );
      return maps.map((m) => ClassScheduleOccurrence.fromMap(m)).toList();
    } catch (e) {
      if (e.toString().contains('no such table')) {
        return const [];
      }
      rethrow;
    }
  }

  /// Lấy các buổi học trong khoảng ngày [startDate, endDate] (YYYY-MM-DD)
  Future<List<ClassScheduleOccurrence>> getOccurrencesInRange(
    String startDate,
    String endDate,
  ) async {
    if (isWebPreview) {
      final list = _webOccurrences.where((o) {
        return o.classDate.compareTo(startDate) >= 0 &&
            o.classDate.compareTo(endDate) <= 0;
      }).toList();
      _sortOccurrences(list);
      return list;
    }

    try {
      final db = await _dbHelper!.database;
      final maps = await db.query(
        DatabaseHelper.tableScheduleOccurrences,
        where:
            '${DatabaseHelper.columnOccClassDate} >= ? AND ${DatabaseHelper.columnOccClassDate} <= ?',
        whereArgs: [startDate, endDate],
        orderBy:
            '${DatabaseHelper.columnOccClassDate} ASC, ${DatabaseHelper.columnOccStartTime} ASC',
      );
      return maps.map((m) => ClassScheduleOccurrence.fromMap(m)).toList();
    } catch (e) {
      if (e.toString().contains('no such table')) {
        return const [];
      }
      rethrow;
    }
  }

  /// Thêm mới một buổi học theo ngày
  Future<void> insertOccurrence(ClassScheduleOccurrence occurrence) async {
    if (isWebPreview) {
      _webOccurrences.removeWhere((o) => o.id == occurrence.id);
      _webOccurrences.add(occurrence);
      WebOccurrenceStorage.saveOccurrences(_webOccurrences);
      return;
    }

    final db = await _dbHelper!.database;
    await db.insert(
      DatabaseHelper.tableScheduleOccurrences,
      occurrence.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Thêm hàng loạt buổi học theo ngày (Batch insert sử dụng transaction)
  Future<void> insertOccurrencesBatch(
    List<ClassScheduleOccurrence> occurrences,
  ) async {
    if (occurrences.isEmpty) return;
    if (isWebPreview) {
      final existingIds = occurrences.map((o) => o.id).toSet();
      _webOccurrences.removeWhere((o) => existingIds.contains(o.id));
      _webOccurrences.addAll(occurrences);
      WebOccurrenceStorage.saveOccurrences(_webOccurrences);
      return;
    }

    final db = await _dbHelper!.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final occ in occurrences) {
        batch.insert(
          DatabaseHelper.tableScheduleOccurrences,
          occ.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  /// Thêm hàng loạt môn học mới và buổi học theo ngày trong cùng một Transaction nguyên tử
  Future<void> importOccurrencesWithSubjectsBatch({
    required List<ClassScheduleOccurrence> occurrences,
    required List<Subject> newSubjects,
  }) async {
    if (occurrences.isEmpty && newSubjects.isEmpty) return;

    if (isWebPreview) {
      final existingIds = occurrences.map((o) => o.id).toSet();
      _webOccurrences.removeWhere((o) => existingIds.contains(o.id));
      _webOccurrences.addAll(occurrences);
      WebOccurrenceStorage.saveOccurrences(_webOccurrences);
      return;
    }

    final db = await _dbHelper!.database;
    await db.transaction((txn) async {
      // 1. Chèn môn học mới vào bảng subjects
      for (final subject in newSubjects) {
        await txn.insert(
          DatabaseHelper.tableSubjects,
          subject.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 2. Chèn các buổi học vào bảng class_schedule_occurrences
      for (final occ in occurrences) {
        await txn.insert(
          DatabaseHelper.tableScheduleOccurrences,
          occ.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Cập nhật một buổi học hiện có
  Future<void> updateOccurrence(ClassScheduleOccurrence occurrence) async {
    if (isWebPreview) {
      final index = _webOccurrences.indexWhere((o) => o.id == occurrence.id);
      if (index != -1) {
        _webOccurrences[index] = occurrence;
        WebOccurrenceStorage.saveOccurrences(_webOccurrences);
      }
      return;
    }

    final db = await _dbHelper!.database;
    await db.update(
      DatabaseHelper.tableScheduleOccurrences,
      occurrence.toMap(),
      where: '${DatabaseHelper.columnOccId} = ?',
      whereArgs: [occurrence.id],
    );
  }

  /// Xóa buổi học theo ID
  Future<void> deleteOccurrence(String id) async {
    if (isWebPreview) {
      _webOccurrences.removeWhere((o) => o.id == id);
      WebOccurrenceStorage.saveOccurrences(_webOccurrences);
      return;
    }

    final db = await _dbHelper!.database;
    await db.delete(
      DatabaseHelper.tableScheduleOccurrences,
      where: '${DatabaseHelper.columnOccId} = ?',
      whereArgs: [id],
    );
  }

  /// Xóa toàn bộ buổi học
  Future<void> clearAllOccurrences() async {
    if (isWebPreview) {
      _webOccurrences.clear();
      WebOccurrenceStorage.clearOccurrences();
      return;
    }

    final db = await _dbHelper!.database;
    await db.delete(DatabaseHelper.tableScheduleOccurrences);
  }

  /// Đặt lại toàn bộ danh sách buổi học (phục vụ restore)
  Future<void> resetDefaultOccurrences(
    List<ClassScheduleOccurrence> occurrences,
  ) async {
    if (isWebPreview) {
      _webOccurrences
        ..clear()
        ..addAll(occurrences);
      WebOccurrenceStorage.saveOccurrences(_webOccurrences);
      return;
    }

    final db = await _dbHelper!.database;
    final batch = db.batch();
    batch.delete(DatabaseHelper.tableScheduleOccurrences);
    for (final occ in occurrences) {
      batch.insert(
        DatabaseHelper.tableScheduleOccurrences,
        occ.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  void _sortOccurrences(List<ClassScheduleOccurrence> list) {
    list.sort((a, b) {
      final dateComp = a.classDate.compareTo(b.classDate);
      if (dateComp != 0) return dateComp;
      return a.startMinutesSinceMidnight.compareTo(b.startMinutesSinceMidnight);
    });
  }
}

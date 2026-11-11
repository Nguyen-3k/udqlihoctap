import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/study_activity.dart';
import '../models/study_streak.dart';
import '../models/study_task.dart';
import '../models/task_priority.dart';
import '../models/task_status.dart';
import '../models/understanding_level.dart';
import '../services/web_storage.dart';

/// Repository quản lý các thao tác dữ liệu công việc học tập và hoạt động Study Streak.
/// - Trên Android / Thiết bị di động: Sử dụng cơ sở dữ liệu SQLite (sqflite) bền vững.
/// - Trên Web / Trình duyệt Chrome: Tự động chuyển sang chế độ bộ nhớ tạm (In-memory Web Preview),
///   KHÔNG gọi sqflite/openDatabase, đảm bảo hiển thị giao diện mượt mà và không làm thay đổi dữ liệu Android.
class TaskRepository {
  final DatabaseHelper? _dbHelper;
  final bool _isWebPreviewForced;
  final List<StudyTask> _webTasks = [];
  final Set<String> _webActiveDates = {};
  final List<StudyActivity> _webActivities = [];
  bool _webInitialized = false;

  TaskRepository({DatabaseHelper? dbHelper, bool useWebPreview = false})
    : _isWebPreviewForced = useWebPreview,
      _dbHelper = useWebPreview
          ? null
          : (dbHelper ?? (kIsWeb ? null : DatabaseHelper.instance)) {
    if (isWebPreview) {
      _initWebPreviewTasks();
    }
  }

  /// Kiểm tra xem ứng dụng có đang chạy ở chế độ Web Preview hay không.
  bool get isWebPreview => _isWebPreviewForced || (kIsWeb && _dbHelper == null);

  /// Khởi tạo dữ liệu mẫu ban đầu cho chế độ xem trước trên Web và nạp lịch sử Streak.
  void _initWebPreviewTasks() {
    if (_webInitialized) return;
    final savedDates = WebStreakStorage.loadActiveDates();
    _webActiveDates.addAll(savedDates);
    final savedActivities = WebStreakStorage.loadActivities();
    _webActivities.addAll(savedActivities);
    if (_webActivities.isEmpty) {
      final now = DateTime.now();
      final dateKey = StudyStreak.formatDateKey(now);
      final initialAct = StudyActivity(
        id: 'act_sample_3',
        dateKey: dateKey,
        taskId: 'task_3',
        completedAt: now.subtract(const Duration(hours: 1)),
        actualMinutes: 30,
        subjectId: 'subj_2',
      );
      _webActivities.add(initialAct);
      WebStreakStorage.saveActivities(_webActivities);
      _webActiveDates.add(dateKey);
      WebStreakStorage.saveActiveDates(_webActiveDates);
    } else {
      for (final act in savedActivities) {
        if (act.dateKey.isNotEmpty) {
          _webActiveDates.add(act.dateKey);
        }
      }
    }
    final now = DateTime.now();
    _webTasks.addAll([
      StudyTask(
        id: 'task_1',
        title: 'Ôn tập chương 3 Đạo hàm',
        subjectId: 'subj_1',
        subject: 'Toán cao cấp',
        deadline: now.add(const Duration(hours: 4)),
        estimatedMinutes: 60,
        priority: TaskPriority.high,
        status: TaskStatus.inProgress,
        notes: 'Cần chú ý công thức đạo hàm hàm hợp và định lý Fermat.',
      ),
      StudyTask(
        id: 'task_2',
        title: 'Thực hành viết câu lệnh SQL JOIN',
        subjectId: 'subj_3',
        subject: 'Cơ sở dữ liệu',
        deadline: now.add(const Duration(days: 1)),
        estimatedMinutes: 45,
        priority: TaskPriority.medium,
        status: TaskStatus.todo,
        notes: 'Phân biệt rõ ràng giữa INNER JOIN và LEFT JOIN.',
      ),
      StudyTask(
        id: 'task_3',
        title: 'Đọc tài liệu CSS Flexbox & Grid',
        subjectId: 'subj_2',
        subject: 'Lập trình Web',
        deadline: now.subtract(const Duration(hours: 2)),
        estimatedMinutes: 30,
        actualMinutes: 30,
        priority: TaskPriority.low,
        status: TaskStatus.completed,
        notes: 'Đã nắm vững align-items và justify-content.',
        understandingLevel: UnderstandingLevel.mastered,
        reviewNotes: 'Đã áp dụng thành thạo CSS Flexbox vào bố cục dự án.',
      ),
    ]);
    _webInitialized = true;
  }

  /// Lấy danh sách toàn bộ công việc từ SQLite hoặc bộ nhớ Web, sắp xếp theo hạn hoàn thành tăng dần.
  Future<List<StudyTask>> getAllTasks() async {
    if (isWebPreview) {
      final sortedList = List<StudyTask>.from(_webTasks);
      sortedList.sort((a, b) {
        if (a.deadline == null && b.deadline == null) return 0;
        if (a.deadline == null) return 1;
        if (b.deadline == null) return -1;
        return a.deadline!.compareTo(b.deadline!);
      });
      return sortedList;
    }

    try {
      final db = await _dbHelper!.database;
      final maps = await db.query(
        DatabaseHelper.tableTasks,
        orderBy: '${DatabaseHelper.columnDeadline} ASC',
      );
      return maps.map((m) => StudyTask.fromMap(m)).toList();
    } catch (e) {
      throw Exception('Không thể tải danh sách công việc từ cơ sở dữ liệu: $e');
    }
  }

  /// Thêm một công việc mới.
  Future<void> insertTask(StudyTask task) async {
    if (isWebPreview) {
      _webTasks.removeWhere((t) => t.id == task.id);
      _webTasks.insert(0, task);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.insert(
        DatabaseHelper.tableTasks,
        task.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      if (e.toString().contains('actual_minutes')) {
        try {
          final db = await _dbHelper!.database;
          final fallbackMap = task.toMap()
            ..remove(DatabaseHelper.columnActualMinutes);
          await db.insert(
            DatabaseHelper.tableTasks,
            fallbackMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          return;
        } catch (_) {}
      }
      throw Exception('Không thể thêm công việc vào cơ sở dữ liệu: $e');
    }
  }

  /// Cập nhật một công việc đã có.
  Future<void> updateTask(StudyTask task) async {
    if (isWebPreview) {
      final index = _webTasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        _webTasks[index] = task;
      } else {
        _webTasks.insert(0, task);
      }
      return;
    }

    try {
      final db = await _dbHelper!.database;
      final count = await db.update(
        DatabaseHelper.tableTasks,
        task.toMap(),
        where: '${DatabaseHelper.columnId} = ?',
        whereArgs: [task.id],
      );
      if (count == 0) {
        throw Exception(
          'Không tìm thấy công việc với id ${task.id} để cập nhật',
        );
      }
    } catch (e) {
      if (e.toString().contains('actual_minutes')) {
        try {
          final db = await _dbHelper!.database;
          final fallbackMap = task.toMap()
            ..remove(DatabaseHelper.columnActualMinutes);
          final count = await db.update(
            DatabaseHelper.tableTasks,
            fallbackMap,
            where: '${DatabaseHelper.columnId} = ?',
            whereArgs: [task.id],
          );
          if (count > 0) return;
        } catch (_) {}
      }
      throw Exception('Không thể cập nhật công việc trong cơ sở dữ liệu: $e');
    }
  }

  /// Cập nhật riêng đánh giá mức độ hiểu bài, ghi chú ôn tập và thời lượng thực tế (G4).
  Future<void> updateTaskAssessment(
    String taskId,
    UnderstandingLevel? level,
    String? reviewNotes, [
    int? actualMinutes,
  ]) async {
    if (isWebPreview) {
      final index = _webTasks.indexWhere((t) => t.id == taskId);
      if (index != -1) {
        _webTasks[index].understandingLevel = level;
        _webTasks[index].reviewNotes = reviewNotes;
        if (actualMinutes != null) {
          _webTasks[index].actualMinutes = actualMinutes;
          // Cập nhật lại thời lượng trong activity tương ứng nếu có
          final actIdx = _webActivities.indexWhere((a) => a.taskId == taskId);
          if (actIdx != -1) {
            _webActivities[actIdx] = StudyActivity(
              id: _webActivities[actIdx].id,
              dateKey: _webActivities[actIdx].dateKey,
              taskId: taskId,
              completedAt: _webActivities[actIdx].completedAt,
              actualMinutes: actualMinutes,
              subjectId: _webActivities[actIdx].subjectId,
            );
            WebStreakStorage.saveActivities(_webActivities);
          }
        }
      } else {
        throw Exception(
          'Không tìm thấy công việc với id $taskId để cập nhật đánh giá',
        );
      }
      return;
    }

    try {
      final db = await _dbHelper!.database;
      final updateData = <String, dynamic>{
        DatabaseHelper.columnUnderstandingLevel: level?.name,
        DatabaseHelper.columnReviewNotes: reviewNotes,
      };
      if (actualMinutes != null) {
        updateData[DatabaseHelper.columnActualMinutes] = actualMinutes;
      }

      try {
        final count = await db.update(
          DatabaseHelper.tableTasks,
          updateData,
          where: '${DatabaseHelper.columnId} = ?',
          whereArgs: [taskId],
        );
        if (count == 0) {
          throw Exception(
            'Không tìm thấy công việc với id $taskId trong cơ sở dữ liệu để cập nhật đánh giá',
          );
        }
      } catch (e) {
        if (e.toString().contains('actual_minutes')) {
          final fallbackData = Map<String, dynamic>.from(updateData)
            ..remove(DatabaseHelper.columnActualMinutes);
          final count = await db.update(
            DatabaseHelper.tableTasks,
            fallbackData,
            where: '${DatabaseHelper.columnId} = ?',
            whereArgs: [taskId],
          );
          if (count == 0) {
            throw Exception(
              'Không tìm thấy công việc với id $taskId trong cơ sở dữ liệu để cập nhật đánh giá',
            );
          }
        } else {
          rethrow;
        }
      }

      // Cập nhật thời lượng thực tế trong bảng study_activities nếu có
      if (actualMinutes != null) {
        final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='${DatabaseHelper.tableActivities}'",
        );
        if (tableCheck.isNotEmpty) {
          await db.update(
            DatabaseHelper.tableActivities,
            {DatabaseHelper.columnActivityActualMinutes: actualMinutes},
            where: '${DatabaseHelper.columnActivityTaskId} = ?',
            whereArgs: [taskId],
          );
        }
      }
    } catch (e) {
      throw Exception('Không thể cập nhật đánh giá công việc: $e');
    }
  }

  /// Xóa công việc theo id.
  Future<void> deleteTask(String id) async {
    if (isWebPreview) {
      _webTasks.removeWhere((t) => t.id == id);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.delete(
        DatabaseHelper.tableTasks,
        where: '${DatabaseHelper.columnId} = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw Exception('Không thể xóa công việc khỏi cơ sở dữ liệu: $e');
    }
  }

  /// Cập nhật nhanh trạng thái công việc (chưa làm / đang làm / hoàn thành).
  /// Tự động ghi nhận hoạt động học tập khi hoàn thành để duy trì Study Streak và Thống kê.
  Future<void> updateTaskStatus(String id, TaskStatus newStatus) async {
    if (isWebPreview) {
      final index = _webTasks.indexWhere((t) => t.id == id);
      if (index != -1) {
        _webTasks[index].status = newStatus;
        if (newStatus == TaskStatus.completed) {
          final t = _webTasks[index];
          recordTaskCompletion(
            id,
            actualMinutes: t.actualMinutes,
            subjectId: t.subjectId,
          );
        }
      } else {
        throw Exception('Không tìm thấy công việc với id $id để cập nhật');
      }
      return;
    }

    try {
      final db = await _dbHelper!.database;
      final count = await db.update(
        DatabaseHelper.tableTasks,
        {DatabaseHelper.columnStatus: newStatus.name},
        where: '${DatabaseHelper.columnId} = ?',
        whereArgs: [id],
      );
      if (count == 0) {
        throw Exception(
          'Không tìm thấy công việc với id $id trong cơ sở dữ liệu để cập nhật trạng thái',
        );
      }

      // Tự động ghi nhận hoạt động học tập hôm nay khi hoàn thành công việc
      if (newStatus == TaskStatus.completed) {
        final taskMaps = await db.query(
          DatabaseHelper.tableTasks,
          where: '${DatabaseHelper.columnId} = ?',
          whereArgs: [id],
          limit: 1,
        );
        String? subId;
        int? actMins;
        if (taskMaps.isNotEmpty) {
          subId = taskMaps.first[DatabaseHelper.columnTaskSubjectId]
              ?.toString();
          actMins = (taskMaps.first[DatabaseHelper.columnActualMinutes] as num?)
              ?.toInt();
        }
        await recordTaskCompletion(
          id,
          actualMinutes: actMins,
          subjectId: subId,
        );
      }
    } catch (e) {
      throw Exception('Không thể cập nhật trạng thái công việc: $e');
    }
  }

  // --- QUẢN LÝ LỊCH SỬ HOẠT ĐỘNG HỌC TẬP (STUDY STREAK & THỐNG KÊ G4) ---

  /// Ghi nhận một sự kiện hoàn thành bài học vào ngày địa phương tương ứng.
  /// Đảm bảo không cộng trùng thời lượng hoặc tạo bản ghi trùng lặp khi đánh dấu hoàn thành lại.
  Future<void> recordTaskCompletion(
    String taskId, {
    DateTime? completedAt,
    int? actualMinutes,
    String? subjectId,
  }) async {
    final now = completedAt ?? DateTime.now();
    final dateKey = StudyStreak.formatDateKey(now);
    final minutes = actualMinutes ?? 0;

    // Tự động phân giải subjectId từ task nếu chưa được truyền vào
    String? resolvedSubjectId = subjectId;
    if (resolvedSubjectId == null && isWebPreview) {
      final t = _webTasks.where((t) => t.id == taskId).firstOrNull;
      resolvedSubjectId = t?.subjectId;
    }

    if (isWebPreview) {
      _webActiveDates.add(dateKey);

      // Tránh cộng trùng: nếu task này đã có hoạt động, cập nhật thời lượng thay vì thêm mới
      final existingIndex = _webActivities.indexWhere(
        (a) => a.taskId == taskId,
      );
      if (existingIndex != -1) {
        _webActivities[existingIndex] = StudyActivity(
          id: _webActivities[existingIndex].id,
          dateKey: _webActivities[existingIndex].dateKey,
          taskId: taskId,
          completedAt: _webActivities[existingIndex].completedAt,
          actualMinutes:
              actualMinutes ?? _webActivities[existingIndex].actualMinutes,
          subjectId:
              resolvedSubjectId ?? _webActivities[existingIndex].subjectId,
        );
      } else {
        final id = 'act_${now.millisecondsSinceEpoch}_$taskId';
        _webActivities.add(
          StudyActivity(
            id: id,
            dateKey: dateKey,
            taskId: taskId,
            completedAt: now,
            actualMinutes: minutes,
            subjectId: resolvedSubjectId,
          ),
        );
      }

      WebStreakStorage.saveActiveDates(_webActiveDates);
      WebStreakStorage.saveActivities(_webActivities);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      // Kiểm tra sự tồn tại của bảng study_activities trước khi chèn (an toàn tuyệt đối cho mock test)
      final tableCheck = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='${DatabaseHelper.tableActivities}'",
      );
      if (tableCheck.isEmpty) return;

      if (resolvedSubjectId == null) {
        try {
          final taskMaps = await db.query(
            DatabaseHelper.tableTasks,
            columns: [DatabaseHelper.columnTaskSubjectId],
            where: '${DatabaseHelper.columnId} = ?',
            whereArgs: [taskId],
            limit: 1,
          );
          if (taskMaps.isNotEmpty) {
            resolvedSubjectId = taskMaps
                .first[DatabaseHelper.columnTaskSubjectId]
                ?.toString();
          }
        } catch (_) {}
      }

      // Tránh cộng trùng trong SQLite: kiểm tra xem taskId đã có trong bảng chưa
      final existing = await db.query(
        DatabaseHelper.tableActivities,
        where: '${DatabaseHelper.columnActivityTaskId} = ?',
        whereArgs: [taskId],
      );

      if (existing.isNotEmpty) {
        final updateValues = <String, dynamic>{};
        if (actualMinutes != null) {
          updateValues[DatabaseHelper.columnActivityActualMinutes] =
              actualMinutes;
        }
        if (resolvedSubjectId != null) {
          updateValues[DatabaseHelper.columnActivitySubjectId] =
              resolvedSubjectId;
        }
        if (updateValues.isNotEmpty) {
          await db.update(
            DatabaseHelper.tableActivities,
            updateValues,
            where: '${DatabaseHelper.columnActivityTaskId} = ?',
            whereArgs: [taskId],
          );
        }
        return;
      }

      final id = 'act_${now.millisecondsSinceEpoch}_$taskId';
      try {
        await db.insert(DatabaseHelper.tableActivities, {
          DatabaseHelper.columnActivityId: id,
          DatabaseHelper.columnActivityDate: dateKey,
          DatabaseHelper.columnActivityTaskId: taskId,
          DatabaseHelper.columnActivityCompletedAt: now.toIso8601String(),
          DatabaseHelper.columnActivityActualMinutes: minutes,
          DatabaseHelper.columnActivitySubjectId: resolvedSubjectId,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {
        await db.insert(DatabaseHelper.tableActivities, {
          DatabaseHelper.columnActivityId: id,
          DatabaseHelper.columnActivityDate: dateKey,
          DatabaseHelper.columnActivityTaskId: taskId,
          DatabaseHelper.columnActivityCompletedAt: now.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    } catch (e) {
      debugPrint('Lỗi ghi nhận hoạt động học tập (Study Streak): $e');
    }
  }

  /// Lấy toàn bộ danh sách chi tiết các hoạt động học tập phục vụ tính toán Thống kê G4.
  Future<List<StudyActivity>> getAllActivities() async {
    if (isWebPreview) {
      if (_webActivities.isEmpty) {
        final saved = WebStreakStorage.loadActivities();
        _webActivities.addAll(saved);
      }
      return List<StudyActivity>.from(_webActivities);
    }

    try {
      final db = await _dbHelper!.database;
      final tableCheck = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='${DatabaseHelper.tableActivities}'",
      );
      if (tableCheck.isEmpty) return [];

      final maps = await db.query(
        DatabaseHelper.tableActivities,
        orderBy: '${DatabaseHelper.columnActivityCompletedAt} DESC',
      );
      return maps.map((m) => StudyActivity.fromMap(m)).toList();
    } catch (e) {
      debugPrint('Lỗi lấy danh sách hoạt động học tập: $e');
      return [];
    }
  }

  /// Lấy toàn bộ tập hợp các ngày (YYYY-MM-DD theo giờ địa phương) đã có hoạt động hoàn thành bài học.
  Future<Set<String>> getActiveStudyDates() async {
    if (isWebPreview) {
      if (_webActiveDates.isEmpty) {
        final saved = WebStreakStorage.loadActiveDates();
        _webActiveDates.addAll(saved);
      }
      return Set<String>.from(_webActiveDates);
    }

    try {
      final db = await _dbHelper!.database;
      final tableCheck = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='${DatabaseHelper.tableActivities}'",
      );
      if (tableCheck.isEmpty) return {};

      final maps = await db.rawQuery(
        'SELECT DISTINCT ${DatabaseHelper.columnActivityDate} FROM ${DatabaseHelper.tableActivities}',
      );
      return maps
          .map((m) => m[DatabaseHelper.columnActivityDate]?.toString() ?? '')
          .where((k) => k.isNotEmpty)
          .toSet();
    } catch (e) {
      debugPrint('Lỗi lấy danh sách ngày học tập: $e');
      return {};
    }
  }

  /// Xóa toàn bộ công việc và lịch sử hoạt động học tập (phục vụ dọn dẹp hoặc đặt lại dữ liệu học tập).
  Future<void> clearAllTasks() async {
    if (isWebPreview) {
      _webTasks.clear();
      _webActivities.clear();
      _webActiveDates.clear();
      WebStreakStorage.clearStudyActivitiesAndDates();
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.delete(DatabaseHelper.tableTasks);
      final tableCheck = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='${DatabaseHelper.tableActivities}'",
      );
      if (tableCheck.isNotEmpty) {
        await db.delete(DatabaseHelper.tableActivities);
      }
    } catch (e) {
      throw Exception('Không thể xóa toàn bộ công việc: $e');
    }
  }

  /// Xóa toàn bộ lịch sử hoạt động học tập và chuỗi ngày học (study_activities).
  Future<void> clearAllActivities() async {
    if (isWebPreview) {
      _webActivities.clear();
      _webActiveDates.clear();
      WebStreakStorage.clearStudyActivitiesAndDates();
      return;
    }

    try {
      final db = await _dbHelper!.database;
      final tableCheck = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='${DatabaseHelper.tableActivities}'",
      );
      if (tableCheck.isNotEmpty) {
        await db.delete(DatabaseHelper.tableActivities);
      }
    } catch (e) {
      throw Exception('Không thể xóa toàn bộ hoạt động học tập: $e');
    }
  }

  /// Cập nhật tên hiển thị của môn học cho tất cả các nhiệm vụ liên quan.
  Future<void> updateTasksSubjectName(
    String subjectId,
    String newSubjectName,
  ) async {
    if (isWebPreview) {
      for (final t in _webTasks) {
        if (t.subjectId == subjectId) {
          t.subject = newSubjectName;
        }
      }
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.update(
        DatabaseHelper.tableTasks,
        {DatabaseHelper.columnSubject: newSubjectName},
        where: '${DatabaseHelper.columnTaskSubjectId} = ?',
        whereArgs: [subjectId],
      );
    } catch (e) {
      throw Exception(
        'Không thể cập nhật tên môn học trong danh sách nhiệm vụ: $e',
      );
    }
  }

  /// Chuyển toàn bộ nhiệm vụ từ môn học cũ sang môn học mới (khi chuẩn bị xóa môn học).
  Future<void> migrateTasksSubject(
    String fromSubjectId,
    String toSubjectId,
    String toSubjectName,
  ) async {
    if (isWebPreview) {
      for (final t in _webTasks) {
        if (t.subjectId == fromSubjectId) {
          t.subjectId = toSubjectId;
          t.subject = toSubjectName;
        }
      }
      for (int i = 0; i < _webActivities.length; i++) {
        if (_webActivities[i].subjectId == fromSubjectId) {
          _webActivities[i] = StudyActivity(
            id: _webActivities[i].id,
            dateKey: _webActivities[i].dateKey,
            taskId: _webActivities[i].taskId,
            completedAt: _webActivities[i].completedAt,
            actualMinutes: _webActivities[i].actualMinutes,
            subjectId: toSubjectId,
          );
        }
      }
      WebStreakStorage.saveActivities(_webActivities);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.update(
        DatabaseHelper.tableTasks,
        {
          DatabaseHelper.columnTaskSubjectId: toSubjectId,
          DatabaseHelper.columnSubject: toSubjectName,
        },
        where: '${DatabaseHelper.columnTaskSubjectId} = ?',
        whereArgs: [fromSubjectId],
      );
      try {
        await db.update(
          DatabaseHelper.tableActivities,
          {DatabaseHelper.columnActivitySubjectId: toSubjectId},
          where: '${DatabaseHelper.columnActivitySubjectId} = ?',
          whereArgs: [fromSubjectId],
        );
      } catch (_) {}
    } catch (e) {
      throw Exception('Không thể chuyển nhiệm vụ sang môn học mới: $e');
    }
  }

  /// Khôi phục danh sách công việc mẫu.
  Future<void> resetSampleTasks(List<StudyTask> sampleTasks) async {
    if (isWebPreview) {
      _webTasks.clear();
      _webTasks.addAll(sampleTasks);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.transaction((txn) async {
        await txn.delete(DatabaseHelper.tableTasks);
        for (final task in sampleTasks) {
          await txn.insert(
            DatabaseHelper.tableTasks,
            task.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (e) {
      throw Exception('Không thể khôi phục dữ liệu mẫu: $e');
    }
  }
}

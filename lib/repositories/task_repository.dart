import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/study_task.dart';
import '../models/task_priority.dart';
import '../models/task_status.dart';

/// Repository quản lý các thao tác dữ liệu công việc học tập.
/// - Trên Android / Thiết bị di động: Sử dụng cơ sở dữ liệu SQLite (sqflite) bền vững.
/// - Trên Web / Trình duyệt Chrome: Tự động chuyển sang chế độ bộ nhớ tạm (In-memory Web Preview),
///   KHÔNG gọi sqflite/openDatabase, đảm bảo hiển thị giao diện mượt mà và không làm thay đổi dữ liệu Android.
class TaskRepository {
  final DatabaseHelper? _dbHelper;
  final bool _isWebPreviewForced;
  final List<StudyTask> _webTasks = [];
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

  /// Khởi tạo dữ liệu mẫu ban đầu cho chế độ xem trước trên Web.
  void _initWebPreviewTasks() {
    if (_webInitialized) return;
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
        priority: TaskPriority.low,
        status: TaskStatus.completed,
        notes: 'Đã nắm vững align-items và justify-content.',
      ),
    ]);
    _webInitialized = true;
  }

  /// Lấy danh sách toàn bộ công việc từ SQLite hoặc bộ nhớ Web, sắp xếp theo hạn hoàn thành tăng dần.
  Future<List<StudyTask>> getAllTasks() async {
    if (isWebPreview) {
      final sortedList = List<StudyTask>.from(_webTasks);
      sortedList.sort((a, b) => a.deadline.compareTo(b.deadline));
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
      throw Exception('Không thể cập nhật công việc trong cơ sở dữ liệu: $e');
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
  Future<void> updateTaskStatus(String id, TaskStatus newStatus) async {
    if (isWebPreview) {
      final index = _webTasks.indexWhere((t) => t.id == id);
      if (index != -1) {
        _webTasks[index].status = newStatus;
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
    } catch (e) {
      throw Exception('Không thể cập nhật trạng thái công việc: $e');
    }
  }

  /// Xóa toàn bộ công việc (phục vụ kiểm thử hoặc dọn dẹp dữ liệu).
  Future<void> clearAllTasks() async {
    if (isWebPreview) {
      _webTasks.clear();
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.delete(DatabaseHelper.tableTasks);
    } catch (e) {
      throw Exception('Không thể xóa toàn bộ công việc: $e');
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

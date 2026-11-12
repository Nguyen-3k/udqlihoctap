import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../models/study_session.dart';
import '../services/session_storage.dart';
import '../services/session_storage_codec.dart';

/// Repository quản lý lưu trữ dữ liệu Phiên học tập thực tế (`study_sessions`).
/// - Trên Android / SQLite: Thao tác qua bảng `study_sessions` với ràng buộc khóa ngoại `ON DELETE SET NULL`.
/// - Trên Web Preview: Thao tác qua `WebSessionStorage` (namespace riêng trong `localStorage`).
/// Repository thuần túy quản lý CRUD & truy vấn; không chứa logic Timer Engine,
/// Heartbeat, tính Streak hay cập nhật `actual_minutes`/`study_activities`.
class SessionRepository {
  final DatabaseHelper? _dbHelper;
  final bool _isWebPreviewForced;

  SessionRepository({DatabaseHelper? dbHelper, bool useWebPreview = false})
    : _isWebPreviewForced = useWebPreview,
      _dbHelper = useWebPreview
          ? null
          : (dbHelper ?? (kIsWeb ? null : DatabaseHelper.instance));

  bool get isWebPreview => _isWebPreviewForced || (kIsWeb && _dbHelper == null);

  static const String _defaultOrderBy =
      '${DatabaseHelper.columnSessionStartedAt} DESC, ${DatabaseHelper.columnSessionId} ASC';

  static const String _dateRangeOrderBy =
      '${DatabaseHelper.columnSessionStudyDate} DESC, '
      '${DatabaseHelper.columnSessionStartedAt} DESC, '
      '${DatabaseHelper.columnSessionId} ASC';

  Future<bool> _sessionsTableExists(Database db) async {
    final result = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [DatabaseHelper.tableSessions],
    );
    return result.isNotEmpty;
  }

  Future<List<StudySession>> _querySqlSessions({
    String? where,
    List<Object?>? whereArgs,
    String orderBy = _defaultOrderBy,
  }) async {
    final db = await _dbHelper!.database;
    if (!db.isOpen || !await _sessionsTableExists(db)) {
      return [];
    }

    final maps = await db.query(
      DatabaseHelper.tableSessions,
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
    );
    return maps.map((m) => StudySession.fromMap(m)).toList();
  }

  /// Tạo mới một phiên học tập trong CSDL hoặc WebStorage.
  Future<StudySession> createSession(StudySession session) async {
    session.validate();

    if (isWebPreview) {
      WebSessionStorage.createSession(session);
      return session;
    }

    try {
      final db = await _dbHelper!.database;
      await db.transaction((txn) async {
        await txn.insert(
          DatabaseHelper.tableSessions,
          session.toMap(),
          conflictAlgorithm: ConflictAlgorithm.abort,
        );
      });
      return session;
    } catch (e) {
      throw Exception('Không thể tạo phiên học mới trong cơ sở dữ liệu: $e');
    }
  }

  /// Lấy thông tin một phiên học theo ID (trả về null nếu không tìm thấy).
  Future<StudySession?> getSessionById(String id) async {
    if (isWebPreview) {
      return WebSessionStorage.loadSessionById(id);
    }

    try {
      final list = await _querySqlSessions(
        where: '${DatabaseHelper.columnSessionId} = ?',
        whereArgs: [id],
      );
      return list.isEmpty ? null : list.first;
    } catch (e) {
      throw Exception('Không thể truy vấn phiên học theo id $id: $e');
    }
  }

  /// Lấy toàn bộ danh sách phiên học (tùy chọn lọc theo trạng thái).
  Future<List<StudySession>> getAllSessions({
    StudySessionStatus? status,
  }) async {
    if (isWebPreview) {
      final all = WebSessionStorage.loadSessions();
      if (status == null) return all;
      return SessionStorageCodec.sortDeterministic(
        all.where((s) => s.status == status).toList(),
      );
    }

    try {
      return await _querySqlSessions(
        where: status != null
            ? '${DatabaseHelper.columnSessionStatus} = ?'
            : null,
        whereArgs: status != null ? [status.dbValue] : null,
      );
    } catch (e) {
      throw Exception('Không thể tải danh sách phiên học: $e');
    }
  }

  /// Lấy các phiên học đang hoạt động hoặc đang chờ xác nhận Recovery
  /// (`running`, `paused`, `in_break`, `interrupted_pending`).
  Future<List<StudySession>> getActiveOrPendingSessions() async {
    if (isWebPreview) {
      final active = WebSessionStorage.loadSessions()
          .where((s) => s.status.isActiveOrPending)
          .toList();
      return SessionStorageCodec.sortDeterministic(active);
    }

    try {
      final activeStatuses = [
        StudySessionStatus.running.dbValue,
        StudySessionStatus.paused.dbValue,
        StudySessionStatus.inBreak.dbValue,
        StudySessionStatus.interruptedPending.dbValue,
      ];
      final placeholders = List.filled(activeStatuses.length, '?').join(', ');
      return await _querySqlSessions(
        where: '${DatabaseHelper.columnSessionStatus} IN ($placeholders)',
        whereArgs: activeStatuses,
      );
    } catch (e) {
      throw Exception('Không thể truy vấn phiên học đang hoạt động/chờ: $e');
    }
  }

  /// Truy vấn an toàn các phiên học đang mở/chờ khôi phục khi khởi động lại ứng dụng.
  /// Các bản ghi hỏng nặng (timestamp/cấu trúc không hợp lệ) sẽ được cô lập ID (và đánh dấu cancelled trên SQLite)
  /// thay vì làm crash toàn bộ quá trình khởi động.
  Future<({List<StudySession> valid, List<String> corruptedIds})>
  getActiveOrPendingSessionsSafe({DateTime? fallbackEndedAtUtc}) async {
    final activeStatuses = [
      StudySessionStatus.running.dbValue,
      StudySessionStatus.paused.dbValue,
      StudySessionStatus.inBreak.dbValue,
      StudySessionStatus.interruptedPending.dbValue,
    ];

    if (isWebPreview) {
      return (
        valid: await getActiveOrPendingSessions(),
        corruptedIds: <String>[],
      );
    }

    try {
      final db = await _dbHelper!.database;
      if (!db.isOpen || !await _sessionsTableExists(db)) {
        return (valid: <StudySession>[], corruptedIds: <String>[]);
      }

      final placeholders = List.filled(activeStatuses.length, '?').join(', ');
      final rows = await db.query(
        DatabaseHelper.tableSessions,
        where: '${DatabaseHelper.columnSessionStatus} IN ($placeholders)',
        whereArgs: activeStatuses,
        orderBy: _defaultOrderBy,
      );

      final valid = <StudySession>[];
      final corruptedIds = <String>[];

      for (final row in rows) {
        try {
          valid.add(StudySession.fromMap(row));
        } catch (e) {
          final id = row[DatabaseHelper.columnSessionId]?.toString() ?? '';
          if (id.isNotEmpty) {
            corruptedIds.add(id);
          }
          debugPrint(
            'Phát hiện bản ghi study_sessions hỏng khi khôi phục ($id): $e',
          );
        }
      }

      if (corruptedIds.isNotEmpty) {
        final isolateAt = (fallbackEndedAtUtc ?? DateTime.now().toUtc())
            .toUtc()
            .toIso8601String();
        await db.transaction((txn) async {
          for (final badId in corruptedIds) {
            await txn.update(
              DatabaseHelper.tableSessions,
              {
                DatabaseHelper.columnSessionStatus:
                    StudySessionStatus.cancelled.dbValue,
                DatabaseHelper.columnSessionEndedAt: isolateAt,
              },
              where: '${DatabaseHelper.columnSessionId} = ?',
              whereArgs: [badId],
            );
          }
        });
      }

      return (valid: valid, corruptedIds: corruptedIds);
    } catch (e) {
      throw Exception('Không thể kiểm tra phiên học gián đoạn an toàn: $e');
    }
  }

  /// Truy vấn các phiên học trong khoảng ngày địa phương `[startDateKey, endDateKey]` (bao gồm 2 đầu).
  Future<List<StudySession>> getSessionsByDateRange(
    String startDateKey,
    String endDateKey, {
    StudySessionStatus? status,
  }) async {
    if (isWebPreview) {
      final filtered = WebSessionStorage.loadSessions().where((s) {
        if (s.studyDate.compareTo(startDateKey) < 0 ||
            s.studyDate.compareTo(endDateKey) > 0) {
          return false;
        }
        if (status != null && s.status != status) return false;
        return true;
      }).toList();
      filtered.sort((a, b) {
        final dateCmp = b.studyDate.compareTo(a.studyDate);
        if (dateCmp != 0) return dateCmp;
        final timeCmp = b.startedAt.compareTo(a.startedAt);
        if (timeCmp != 0) return timeCmp;
        return a.id.compareTo(b.id);
      });
      return filtered;
    }

    try {
      final conditions = <String>[
        '${DatabaseHelper.columnSessionStudyDate} >= ?',
        '${DatabaseHelper.columnSessionStudyDate} <= ?',
      ];
      final args = <Object?>[startDateKey, endDateKey];
      if (status != null) {
        conditions.add('${DatabaseHelper.columnSessionStatus} = ?');
        args.add(status.dbValue);
      }

      return await _querySqlSessions(
        where: conditions.join(' AND '),
        whereArgs: args,
        orderBy: _dateRangeOrderBy,
      );
    } catch (e) {
      throw Exception('Không thể truy vấn phiên học theo khoảng ngày: $e');
    }
  }

  /// Lấy danh sách phiên học theo mã môn học (`subjectId`).
  Future<List<StudySession>> getSessionsBySubject(
    String subjectId, {
    StudySessionStatus? status,
  }) async {
    if (isWebPreview) {
      final filtered = WebSessionStorage.loadSessions().where((s) {
        if (s.subjectId != subjectId) return false;
        if (status != null && s.status != status) return false;
        return true;
      }).toList();
      return SessionStorageCodec.sortDeterministic(filtered);
    }

    try {
      final conditions = <String>[
        '${DatabaseHelper.columnSessionSubjectId} = ?',
      ];
      final args = <Object?>[subjectId];
      if (status != null) {
        conditions.add('${DatabaseHelper.columnSessionStatus} = ?');
        args.add(status.dbValue);
      }

      return await _querySqlSessions(
        where: conditions.join(' AND '),
        whereArgs: args,
      );
    } catch (e) {
      throw Exception('Không thể truy vấn phiên học theo môn học: $e');
    }
  }

  /// Lấy danh sách phiên học theo mã công việc (`taskId`).
  Future<List<StudySession>> getSessionsByTask(
    String taskId, {
    StudySessionStatus? status,
  }) async {
    if (isWebPreview) {
      final filtered = WebSessionStorage.loadSessions().where((s) {
        if (s.taskId != taskId) return false;
        if (status != null && s.status != status) return false;
        return true;
      }).toList();
      return SessionStorageCodec.sortDeterministic(filtered);
    }

    try {
      final conditions = <String>['${DatabaseHelper.columnSessionTaskId} = ?'];
      final args = <Object?>[taskId];
      if (status != null) {
        conditions.add('${DatabaseHelper.columnSessionStatus} = ?');
        args.add(status.dbValue);
      }

      return await _querySqlSessions(
        where: conditions.join(' AND '),
        whereArgs: args,
      );
    } catch (e) {
      throw Exception('Không thể truy vấn phiên học theo công việc: $e');
    }
  }

  /// Cập nhật metadata hoặc trạng thái một phiên học đã tồn tại bên trong Transaction.
  Future<void> updateSession(StudySession session) async {
    session.validate();

    if (isWebPreview) {
      WebSessionStorage.updateSession(session);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      await db.transaction((txn) async {
        final count = await txn.update(
          DatabaseHelper.tableSessions,
          session.toMap(),
          where: '${DatabaseHelper.columnSessionId} = ?',
          whereArgs: [session.id],
        );
        if (count == 0) {
          throw Exception(
            'Không tìm thấy phiên học với id ${session.id} để cập nhật.',
          );
        }
      });
    } catch (e) {
      throw Exception('Không thể cập nhật phiên học trong cơ sở dữ liệu: $e');
    }
  }

  /// Xóa một phiên học theo ID (API quản lý dữ liệu tường minh).
  Future<void> deleteSession(String id) async {
    if (isWebPreview) {
      WebSessionStorage.deleteSession(id);
      return;
    }

    try {
      final db = await _dbHelper!.database;
      if (!db.isOpen || !await _sessionsTableExists(db)) return;
      await db.delete(
        DatabaseHelper.tableSessions,
        where: '${DatabaseHelper.columnSessionId} = ?',
        whereArgs: [id],
      );
    } catch (e) {
      throw Exception('Không thể xóa phiên học khỏi cơ sở dữ liệu: $e');
    }
  }

  /// Xóa toàn bộ phiên học (chỉ gọi khi người dùng đặt lại toàn bộ dữ liệu học tập).
  Future<void> clearAllSessions() async {
    if (isWebPreview) {
      WebSessionStorage.clearSessions();
      return;
    }

    try {
      final db = await _dbHelper!.database;
      if (!db.isOpen || !await _sessionsTableExists(db)) return;
      await db.transaction((txn) async {
        await txn.delete(DatabaseHelper.tableSessions);
      });
    } catch (e) {
      throw Exception('Không thể đặt lại danh sách phiên học: $e');
    }
  }

  /// Chuyển `subjectId` sang null trong WebStorage khi môn học bị xóa
  /// (trên SQLite việc này tự động thực thi bởi `ON DELETE SET NULL`),
  /// giữ nguyên toàn bộ `subjectNameSnapshot` và lịch sử phiên.
  Future<void> detachSubjectForWeb(String subjectId) async {
    if (!isWebPreview) return;
    final all = WebSessionStorage.loadSessions();
    var changed = false;
    final updated = all.map((s) {
      if (s.subjectId == subjectId) {
        changed = true;
        return s.copyWith(clearSubjectId: true);
      }
      return s;
    }).toList();
    if (changed) {
      WebSessionStorage.saveSessions(updated);
    }
  }

  /// Chuyển `taskId` sang null trong WebStorage khi công việc bị xóa
  /// (trên SQLite việc này tự động thực thi bởi `ON DELETE SET NULL`),
  /// giữ nguyên `taskTitleSnapshot` và lịch sử phiên.
  Future<void> detachTaskForWeb(String taskId) async {
    if (!isWebPreview) return;
    final all = WebSessionStorage.loadSessions();
    var changed = false;
    final updated = all.map((s) {
      if (s.taskId == taskId) {
        changed = true;
        return s.copyWith(clearTaskId: true);
      }
      return s;
    }).toList();
    if (changed) {
      WebSessionStorage.saveSessions(updated);
    }
  }
}

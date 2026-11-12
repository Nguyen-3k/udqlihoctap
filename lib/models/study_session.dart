/// Trạng thái vòng đời của một phiên học thực tế (`study_sessions`).
enum StudySessionStatus {
  running('running'),
  paused('paused'),
  inBreak('in_break'),
  interruptedPending('interrupted_pending'),
  completed('completed'),
  cancelled('cancelled');

  final String dbValue;
  const StudySessionStatus(this.dbValue);

  /// Kiểm tra xem phiên có đang mở hoặc chờ xác nhận khôi phục hay không.
  bool get isActiveOrPending =>
      this == StudySessionStatus.running ||
      this == StudySessionStatus.paused ||
      this == StudySessionStatus.inBreak ||
      this == StudySessionStatus.interruptedPending;

  /// Phân giải nghiêm ngặt giá trị từ CSDL/JSON; ném lỗi nếu trạng thái không hợp lệ.
  static StudySessionStatus fromDbValue(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      throw ArgumentError('Trạng thái phiên học không được rỗng.');
    }
    for (final status in StudySessionStatus.values) {
      if (status.dbValue == raw) {
        return status;
      }
    }
    throw ArgumentError('Trạng thái phiên học không hợp lệ: "$raw".');
  }
}

/// Chế độ đếm giờ hoặc chu kỳ nghỉ của phiên học.
enum StudySessionMode {
  stopwatch('stopwatch'),
  pomodoro25_5('pomodoro_25_5'),
  deep50_10('deep_50_10'),
  long90_15('long_90_15'),
  custom('custom');

  final String dbValue;
  const StudySessionMode(this.dbValue);

  static StudySessionMode fromDbValue(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return StudySessionMode.stopwatch;
    }
    for (final mode in StudySessionMode.values) {
      if (mode.dbValue == raw) {
        return mode;
      }
    }
    throw ArgumentError('Chế độ phiên học không hợp lệ: "$raw".');
  }
}

/// Đại diện cho một phiên học tập thực tế (`study_sessions`) theo Schema v7.
/// Model thuần túy bất biến: không tự chạy Timer, không tự cộng thời gian,
/// bảo toàn UTC timestamps và ngày lịch địa phương `studyDate`.
class StudySession {
  static final RegExp _dateKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final RegExp _timezoneSuffixPattern = RegExp(
    r'(?:Z|[+-]\d{2}:?\d{2})$',
    caseSensitive: false,
  );

  final String id;

  /// Khóa liên kết tới bảng `subjects`. Có thể null nếu môn học đã bị xóa (`ON DELETE SET NULL`).
  final String? subjectId;

  /// Tên môn học được chụp lại tại thời điểm diễn ra phiên học để bảo toàn lịch sử.
  final String subjectNameSnapshot;

  /// Mã màu ARGB của môn học tại thời điểm diễn ra phiên học (nullable).
  final int? subjectColorSnapshot;

  /// Khóa liên kết tới bảng `study_tasks`. Có thể null khi học tự do theo môn hoặc khi task đã xóa.
  final String? taskId;

  /// Tên công việc được chụp lại tại thời điểm học (nullable).
  final String? taskTitleSnapshot;

  /// Khóa liên kết tùy chọn tới buổi học dự kiến (`scheduled_sessions` trong G9.0).
  final String? scheduledSessionId;

  /// Các mốc thời gian luôn được chuẩn hóa lưu dưới dạng UTC.
  final DateTime startedAt;
  final DateTime? endedAt;
  final DateTime lastHeartbeatAt;
  final DateTime lastStateChangedAt;

  /// Ngày lịch địa phương lúc bắt đầu phiên (`YYYY-MM-DD`).
  /// Không suy diễn lại từ `startedAt.toUtc()` khi đọc để tránh sai lệch khi đổi múi giờ.
  final String studyDate;

  /// Thời lượng học và nghỉ đã chốt sổ (đơn vị: giây, luôn không âm).
  final int verifiedStudySeconds;
  final int accumulatedBreakSeconds;

  final StudySessionStatus status;
  final StudySessionMode sessionMode;
  final int plannedStudyMinutes;
  final int plannedBreakMinutes;
  final String notes;

  StudySession({
    required this.id,
    this.subjectId,
    required this.subjectNameSnapshot,
    this.subjectColorSnapshot,
    this.taskId,
    this.taskTitleSnapshot,
    this.scheduledSessionId,
    required DateTime startedAt,
    DateTime? endedAt,
    required DateTime lastHeartbeatAt,
    required DateTime lastStateChangedAt,
    required this.studyDate,
    this.verifiedStudySeconds = 0,
    this.accumulatedBreakSeconds = 0,
    required this.status,
    this.sessionMode = StudySessionMode.stopwatch,
    this.plannedStudyMinutes = 0,
    this.plannedBreakMinutes = 0,
    this.notes = '',
  }) : startedAt = startedAt.toUtc(),
       endedAt = endedAt?.toUtc(),
       lastHeartbeatAt = lastHeartbeatAt.toUtc(),
       lastStateChangedAt = lastStateChangedAt.toUtc() {
    validate();
  }

  /// Factory khởi tạo nhanh một phiên học mới chuẩn bị chạy.
  /// Tự động đóng dấu `studyDate` theo ngày lịch địa phương tại thời điểm `startedAt`
  /// và chuẩn hóa toàn bộ timestamp sang UTC.
  factory StudySession.createNew({
    required String id,
    required String? subjectId,
    required String subjectNameSnapshot,
    int? subjectColorSnapshot,
    String? taskId,
    String? taskTitleSnapshot,
    String? scheduledSessionId,
    DateTime? startedAt,
    StudySessionStatus status = StudySessionStatus.running,
    StudySessionMode sessionMode = StudySessionMode.stopwatch,
    int plannedStudyMinutes = 0,
    int plannedBreakMinutes = 0,
    String notes = '',
  }) {
    final startLocal = (startedAt ?? DateTime.now()).toLocal();
    final startUtc = startLocal.toUtc();
    final studyDate = formatLocalDateKey(startLocal);

    return StudySession(
      id: id,
      subjectId: subjectId,
      subjectNameSnapshot: subjectNameSnapshot,
      subjectColorSnapshot: subjectColorSnapshot,
      taskId: taskId,
      taskTitleSnapshot: taskTitleSnapshot,
      scheduledSessionId: scheduledSessionId,
      startedAt: startUtc,
      endedAt:
          status == StudySessionStatus.completed ||
              status == StudySessionStatus.cancelled
          ? startUtc
          : null,
      lastHeartbeatAt: startUtc,
      lastStateChangedAt: startUtc,
      studyDate: studyDate,
      verifiedStudySeconds: 0,
      accumulatedBreakSeconds: 0,
      status: status,
      sessionMode: sessionMode,
      plannedStudyMinutes: plannedStudyMinutes,
      plannedBreakMinutes: plannedBreakMinutes,
      notes: notes,
    );
  }

  /// Định dạng `DateTime` thành khóa ngày lịch địa phương `YYYY-MM-DD`.
  static String formatLocalDateKey(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Kiểm tra hợp lệ `YYYY-MM-DD` theo lịch thực tế (tránh ngày ảo như 2026-02-30).
  static bool isValidDateKey(String key) {
    if (!_dateKeyPattern.hasMatch(key)) return false;
    final parts = key.split('-');
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year == null || month == null || day == null) return false;
    if (month < 1 || month > 12 || day < 1) return false;
    final probe = DateTime(year, month, day);
    return probe.year == year && probe.month == month && probe.day == day;
  }

  /// Kiểm tra toàn bộ ràng buộc dữ liệu của phiên học.
  void validate() {
    if (id.trim().isEmpty) {
      throw ArgumentError('ID phiên học không được để trống.');
    }
    if (subjectNameSnapshot.trim().isEmpty) {
      throw ArgumentError('Tên môn học snapshot không được để trống.');
    }
    if (!isValidDateKey(studyDate)) {
      throw ArgumentError.value(
        studyDate,
        'studyDate',
        'Ngày học study_date phải có định dạng hợp lệ YYYY-MM-DD.',
      );
    }
    if (verifiedStudySeconds < 0) {
      throw ArgumentError.value(
        verifiedStudySeconds,
        'verifiedStudySeconds',
        'Thời lượng học đã xác nhận không được âm.',
      );
    }
    if (accumulatedBreakSeconds < 0) {
      throw ArgumentError.value(
        accumulatedBreakSeconds,
        'accumulatedBreakSeconds',
        'Thời lượng nghỉ tích lũy không được âm.',
      );
    }
    if (plannedStudyMinutes < 0) {
      throw ArgumentError.value(
        plannedStudyMinutes,
        'plannedStudyMinutes',
        'Thời lượng học dự kiến không được âm.',
      );
    }
    if (plannedBreakMinutes < 0) {
      throw ArgumentError.value(
        plannedBreakMinutes,
        'plannedBreakMinutes',
        'Thời lượng nghỉ dự kiến không được âm.',
      );
    }
    if (status == StudySessionStatus.completed && endedAt == null) {
      throw ArgumentError(
        'Phiên học đã hoàn thành (completed) bắt buộc phải có endedAt.',
      );
    }
    if (status.isActiveOrPending && endedAt != null) {
      throw ArgumentError(
        'Phiên học chưa kết thúc (${status.dbValue}) không được có endedAt.',
      );
    }
  }

  StudySession copyWith({
    String? id,
    String? subjectId,
    bool clearSubjectId = false,
    String? subjectNameSnapshot,
    int? subjectColorSnapshot,
    bool clearSubjectColorSnapshot = false,
    String? taskId,
    bool clearTaskId = false,
    String? taskTitleSnapshot,
    bool clearTaskTitleSnapshot = false,
    String? scheduledSessionId,
    bool clearScheduledSessionId = false,
    DateTime? startedAt,
    DateTime? endedAt,
    bool clearEndedAt = false,
    DateTime? lastHeartbeatAt,
    DateTime? lastStateChangedAt,
    String? studyDate,
    int? verifiedStudySeconds,
    int? accumulatedBreakSeconds,
    StudySessionStatus? status,
    StudySessionMode? sessionMode,
    int? plannedStudyMinutes,
    int? plannedBreakMinutes,
    String? notes,
  }) {
    return StudySession(
      id: id ?? this.id,
      subjectId: clearSubjectId ? null : (subjectId ?? this.subjectId),
      subjectNameSnapshot: subjectNameSnapshot ?? this.subjectNameSnapshot,
      subjectColorSnapshot: clearSubjectColorSnapshot
          ? null
          : (subjectColorSnapshot ?? this.subjectColorSnapshot),
      taskId: clearTaskId ? null : (taskId ?? this.taskId),
      taskTitleSnapshot: clearTaskTitleSnapshot
          ? null
          : (taskTitleSnapshot ?? this.taskTitleSnapshot),
      scheduledSessionId: clearScheduledSessionId
          ? null
          : (scheduledSessionId ?? this.scheduledSessionId),
      startedAt: startedAt ?? this.startedAt,
      endedAt: clearEndedAt ? null : (endedAt ?? this.endedAt),
      lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
      lastStateChangedAt: lastStateChangedAt ?? this.lastStateChangedAt,
      studyDate: studyDate ?? this.studyDate,
      verifiedStudySeconds: verifiedStudySeconds ?? this.verifiedStudySeconds,
      accumulatedBreakSeconds:
          accumulatedBreakSeconds ?? this.accumulatedBreakSeconds,
      status: status ?? this.status,
      sessionMode: sessionMode ?? this.sessionMode,
      plannedStudyMinutes: plannedStudyMinutes ?? this.plannedStudyMinutes,
      plannedBreakMinutes: plannedBreakMinutes ?? this.plannedBreakMinutes,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'subject_id': subjectId,
      'subject_name_snapshot': subjectNameSnapshot,
      'subject_color_snapshot': subjectColorSnapshot,
      'task_id': taskId,
      'task_title_snapshot': taskTitleSnapshot,
      'scheduled_session_id': scheduledSessionId,
      'started_at': startedAt.toUtc().toIso8601String(),
      'ended_at': endedAt?.toUtc().toIso8601String(),
      'last_heartbeat_at': lastHeartbeatAt.toUtc().toIso8601String(),
      'last_state_changed_at': lastStateChangedAt.toUtc().toIso8601String(),
      'study_date': studyDate,
      'verified_study_seconds': verifiedStudySeconds,
      'accumulated_break_seconds': accumulatedBreakSeconds,
      'status': status.dbValue,
      'session_mode': sessionMode.dbValue,
      'planned_study_minutes': plannedStudyMinutes,
      'planned_break_minutes': plannedBreakMinutes,
      'notes': notes,
    };
  }

  static DateTime _parseRequiredUtcTimestamp(dynamic raw, String fieldName) {
    final text = raw?.toString().trim() ?? '';
    if (text.isEmpty) {
      throw FormatException('Thiếu mốc thời gian bắt buộc: $fieldName.');
    }
    if (!_timezoneSuffixPattern.hasMatch(text)) {
      throw FormatException(
        'Mốc thời gian $fieldName phải kèm múi giờ UTC (Z hoặc offset): "$text".',
      );
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) {
      throw FormatException(
        'Định dạng mốc thời gian $fieldName không hợp lệ: "$text".',
      );
    }
    return parsed.toUtc();
  }

  static DateTime? _parseNullableUtcTimestamp(dynamic raw, String fieldName) {
    if (raw == null) return null;
    final text = raw.toString().trim();
    if (text.isEmpty) return null;
    return _parseRequiredUtcTimestamp(text, fieldName);
  }

  static int _parseNonNegativeInt(
    dynamic raw,
    String fieldName, {
    int defaultValue = 0,
  }) {
    if (raw == null) return defaultValue;
    final parsed = (raw is int)
        ? raw
        : (raw is num ? raw.toInt() : int.tryParse(raw.toString()));
    if (parsed == null) {
      throw FormatException('Giá trị số $fieldName không hợp lệ: "$raw".');
    }
    if (parsed < 0) {
      throw ArgumentError.value(
        parsed,
        fieldName,
        'Giá trị $fieldName không được âm.',
      );
    }
    return parsed;
  }

  factory StudySession.fromMap(Map<String, dynamic> map) {
    final status = StudySessionStatus.fromDbValue(map['status']?.toString());
    final mode = StudySessionMode.fromDbValue(map['session_mode']?.toString());
    final colorRaw = map['subject_color_snapshot'];
    final int? parsedColor = colorRaw == null
        ? null
        : (colorRaw is num
              ? colorRaw.toInt()
              : int.tryParse(colorRaw.toString()));

    final rawSubjectId = map['subject_id']?.toString();
    final rawTaskId = map['task_id']?.toString();
    final rawTaskTitle = map['task_title_snapshot']?.toString();
    final rawScheduledId = map['scheduled_session_id']?.toString();

    return StudySession(
      id: map['id']?.toString() ?? '',
      subjectId: (rawSubjectId != null && rawSubjectId.isEmpty)
          ? null
          : rawSubjectId,
      subjectNameSnapshot: map['subject_name_snapshot']?.toString() ?? '',
      subjectColorSnapshot: parsedColor,
      taskId: (rawTaskId != null && rawTaskId.isEmpty) ? null : rawTaskId,
      taskTitleSnapshot: (rawTaskTitle != null && rawTaskTitle.isEmpty)
          ? null
          : rawTaskTitle,
      scheduledSessionId: (rawScheduledId != null && rawScheduledId.isEmpty)
          ? null
          : rawScheduledId,
      startedAt: _parseRequiredUtcTimestamp(map['started_at'], 'started_at'),
      endedAt: _parseNullableUtcTimestamp(map['ended_at'], 'ended_at'),
      lastHeartbeatAt: _parseRequiredUtcTimestamp(
        map['last_heartbeat_at'],
        'last_heartbeat_at',
      ),
      lastStateChangedAt: _parseRequiredUtcTimestamp(
        map['last_state_changed_at'],
        'last_state_changed_at',
      ),
      studyDate: map['study_date']?.toString() ?? '',
      verifiedStudySeconds: _parseNonNegativeInt(
        map['verified_study_seconds'],
        'verified_study_seconds',
      ),
      accumulatedBreakSeconds: _parseNonNegativeInt(
        map['accumulated_break_seconds'],
        'accumulated_break_seconds',
      ),
      status: status,
      sessionMode: mode,
      plannedStudyMinutes: _parseNonNegativeInt(
        map['planned_study_minutes'],
        'planned_study_minutes',
      ),
      plannedBreakMinutes: _parseNonNegativeInt(
        map['planned_break_minutes'],
        'planned_break_minutes',
      ),
      notes: map['notes']?.toString() ?? '',
    );
  }

  /// Tính tổng thời lượng học đã hoàn thành (giây) trong khoảng ngày lịch `[startDateKey, endDateKey]`.
  /// Chỉ tính các phiên có `status == StudySessionStatus.completed`.
  static int sumCompletedSecondsInDateRange(
    List<StudySession> sessions,
    String startDateKey,
    String endDateKey,
  ) {
    int total = 0;
    for (final s in sessions) {
      if (s.status != StudySessionStatus.completed) continue;
      if (s.studyDate.compareTo(startDateKey) >= 0 &&
          s.studyDate.compareTo(endDateKey) <= 0) {
        total += s.verifiedStudySeconds;
      }
    }
    return total;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StudySession &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          subjectId == other.subjectId &&
          subjectNameSnapshot == other.subjectNameSnapshot &&
          subjectColorSnapshot == other.subjectColorSnapshot &&
          taskId == other.taskId &&
          taskTitleSnapshot == other.taskTitleSnapshot &&
          scheduledSessionId == other.scheduledSessionId &&
          startedAt == other.startedAt &&
          endedAt == other.endedAt &&
          lastHeartbeatAt == other.lastHeartbeatAt &&
          lastStateChangedAt == other.lastStateChangedAt &&
          studyDate == other.studyDate &&
          verifiedStudySeconds == other.verifiedStudySeconds &&
          accumulatedBreakSeconds == other.accumulatedBreakSeconds &&
          status == other.status &&
          sessionMode == other.sessionMode &&
          plannedStudyMinutes == other.plannedStudyMinutes &&
          plannedBreakMinutes == other.plannedBreakMinutes &&
          notes == other.notes;

  @override
  int get hashCode => Object.hashAll([
    id,
    subjectId,
    subjectNameSnapshot,
    subjectColorSnapshot,
    taskId,
    taskTitleSnapshot,
    scheduledSessionId,
    startedAt,
    endedAt,
    lastHeartbeatAt,
    lastStateChangedAt,
    studyDate,
    verifiedStudySeconds,
    accumulatedBreakSeconds,
    status,
    sessionMode,
    plannedStudyMinutes,
    plannedBreakMinutes,
    notes,
  ]);
}

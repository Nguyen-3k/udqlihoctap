import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/study_session.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../repositories/session_repository.dart';

/// Nguồn thời gian có thể tiêm (injectable) phục vụ vận hành thực tế
/// và kiểm thử tất định (Fake Clock) không cần chờ đợi theo thời gian thực.
abstract class TimerClock {
  DateTime nowUtc();
  DateTime nowLocal();

  /// Bộ đếm đơn điệu dùng để kiểm chứng chênh lệch giờ hệ thống (null nếu không khả dụng).
  Duration? get monotonicElapsed;

  bool get hasMonotonicClock => monotonicElapsed != null;
}

/// Nguồn thời gian hệ thống dùng cho môi trường chạy thực tế.
class SystemTimerClock implements TimerClock {
  final Stopwatch _stopwatch;

  SystemTimerClock() : _stopwatch = Stopwatch()..start();

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  DateTime nowLocal() => DateTime.now().toLocal();

  @override
  Duration? get monotonicElapsed => _stopwatch.elapsed;

  @override
  bool get hasMonotonicClock => true;
}

/// Đồng hồ giả phục vụ unit/widget test:
/// - [advance]: Dịch chuyển đồng thời cả đồng hồ thực (wall clock) và bộ đếm đơn điệu.
/// - [jumpWallClock] / [setWallUtc]: Chỉ thay đổi đồng hồ hệ thống để mô phỏng lỗi chỉnh tiến/lùi giờ.
/// - [setSimulatedLocalOffset]: Cho phép giả lập múi giờ địa phương độc lập với múi giờ máy chạy test.
class FakeTimerClock implements TimerClock {
  DateTime _wallUtc;
  Duration _monotonic;
  Duration? _simulatedLocalOffset;

  FakeTimerClock(
    DateTime initialTime, {
    Duration? initialLocalOffset,
    Duration initialMonotonic = Duration.zero,
  }) : _wallUtc = initialTime.toUtc(),
       _monotonic = initialMonotonic,
       _simulatedLocalOffset = initialLocalOffset;

  /// Tiến đồng thời cả thời gian thực và đồng hồ đơn điệu (mô phỏng thời gian học trôi qua hợp lệ).
  void advance(Duration duration) {
    if (duration.isNegative) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Không thể tua lùi đồng hồ bằng advance(); hãy dùng jumpWallClock().',
      );
    }
    _wallUtc = _wallUtc.add(duration);
    _monotonic += duration;
  }

  /// Chỉ dịch chuyển đồng hồ hệ thống (tiến hoặc lùi) mà không tăng thời gian vật lý.
  void jumpWallClock(Duration delta) {
    _wallUtc = _wallUtc.add(delta);
  }

  /// Đặt mốc thời gian UTC hệ thống trực tiếp mà không thay đổi bộ đếm đơn điệu.
  void setWallUtc(DateTime newUtc) {
    _wallUtc = newUtc.toUtc();
  }

  /// Thay đổi độ lệch múi giờ địa phương giả lập (ví dụ Duration(hours: 7) -> Duration(hours: 9)).
  void setSimulatedLocalOffset(Duration? offset) {
    _simulatedLocalOffset = offset;
  }

  @override
  DateTime nowUtc() => _wallUtc;

  @override
  DateTime nowLocal() {
    final offset = _simulatedLocalOffset;
    if (offset == null) {
      return _wallUtc.toLocal();
    }
    final shifted = _wallUtc.add(offset);
    return DateTime(
      shifted.year,
      shifted.month,
      shifted.day,
      shifted.hour,
      shifted.minute,
      shifted.second,
      shifted.millisecond,
      shifted.microsecond,
    );
  }

  @override
  Duration? get monotonicElapsed => _monotonic;

  @override
  bool get hasMonotonicClock => true;
}

/// Ba lựa chọn bắt buộc khi phục hồi phiên học bị gián đoạn (Quyết định D3).
enum StudyRecoveryAction { continueStudying, completeAndConfirm, cancel }

/// Phân loại bất thường đồng hồ phát hiện trong phiên hoặc lúc khôi phục.
enum StudyClockAnomaly { none, backward, forwardJump }

/// Dữ liệu chẩn đoán cung cấp cho Recovery Dialog tương lai khi phát hiện phiên gián đoạn.
class RecoveryContext {
  final StudySession session;

  /// Trạng thái trước khi bị gián đoạn nếu phát hiện chuyển từ pha sống sang `interruptedPending`.
  final StudySessionStatus? interruptedFromStatus;
  final DateTime detectedAtUtc;

  /// Thời lượng đã được xác nhận chắc chắn tại thời điểm checkpoint gần nhất.
  final int verifiedStudySeconds;
  final int verifiedBreakSeconds;

  /// Khoảng chênh lệch thời gian vật lý kể từ lần heartbeat cuối.
  final int rawWallGapSeconds;

  /// Khoảng thời gian gián đoạn tối đa cần hỏi xác nhận (bằng 0 nếu ngắt khi đang Paused/InBreak hoặc giờ lùi).
  final int unverifiedGapSeconds;

  /// Số giây bổ sung tối đa hợp lý mà người dùng được phép xác nhận thêm ngoài phần đã chốt.
  final int maxConfirmableExtraSeconds;

  final bool isStaleOver8Hours;
  final bool isClockMovedBackward;
  final bool isClockJumpedForward;
  final String? warningReason;

  const RecoveryContext({
    required this.session,
    required this.interruptedFromStatus,
    required this.detectedAtUtc,
    required this.verifiedStudySeconds,
    required this.verifiedBreakSeconds,
    required this.rawWallGapSeconds,
    required this.unverifiedGapSeconds,
    required this.maxConfirmableExtraSeconds,
    required this.isStaleOver8Hours,
    required this.isClockMovedBackward,
    this.isClockJumpedForward = false,
    this.warningReason,
  });

  bool get hasAbnormalClock => isClockMovedBackward || isClockJumpedForward;
}

/// Bộ máy xử lý nghiệp vụ Study Timer (ExamPilot Phase 2).
/// - Nguồn dữ liệu thời gian duy nhất là UTC timestamps + Single Checkpoint Anchor (`lastHeartbeatAt`).
/// - Không sử dụng số lần tick `Timer.periodic` để cộng thời gian.
/// - Không cho phép tồn tại hai phiên học hoạt động đồng thời hoặc hai heartbeat loop song song.
/// - Nếu ghi CSDL thất bại, bộ nhớ không cập nhật sai và bảo toàn nguyên vẹn khả năng retry.
class StudyTimerEngine extends ChangeNotifier with WidgetsBindingObserver {
  static const Duration defaultHeartbeatInterval = Duration(seconds: 15);
  static const Duration defaultStaleThreshold = Duration(hours: 8);
  static const Duration defaultForegroundSkewThreshold = Duration(minutes: 2);
  static const int maxConfirmableExtraCapSeconds = 12 * 3600; // 720 phút

  final SessionRepository repository;
  final TimerClock _clock;
  final Duration heartbeatInterval;
  final Duration _staleThreshold;
  final Duration foregroundSkewThreshold;
  final FutureOr<void> Function()? onSessionsChanged;
  final bool autoStartHeartbeat;
  final bool autoStartUiTicker;

  StudySession? _activeSession;
  StudySession? _lastEndedSession;
  RecoveryContext? _recoveryContext;
  Object? _lastSyncError;
  StudyClockAnomaly _clockAnomaly = StudyClockAnomaly.none;
  int? _currentBreakBaselineSeconds;

  final _UiTickNotifier _uiTickNotifier = _UiTickNotifier();
  Timer? _heartbeatTimer;
  int _activeHeartbeatTimerCount = 0;
  bool _isDisposed = false;
  bool _isLifecycleBound = false;
  bool _isInBackground = false;
  int _sessionCounter = 0;

  // Neo đơn điệu tương ứng với mốc `lastHeartbeatAt` của `_activeSession`.
  String? _anchorSessionId;
  Duration? _anchorMonotonicElapsed;

  // Hàng đợi tuần tự hóa giúp chặn double-tap / race condition giữa heartbeat và chuyển pha.
  Future<void> _operationQueue = Future<void>.value();

  StudyTimerEngine({
    required this.repository,
    TimerClock? clock,
    this.heartbeatInterval = defaultHeartbeatInterval,
    Duration staleSessionThreshold = defaultStaleThreshold,
    this.foregroundSkewThreshold = defaultForegroundSkewThreshold,
    this.onSessionsChanged,
    this.autoStartHeartbeat = true,
    this.autoStartUiTicker = true,
    bool bindLifecycleObserver = false,
  }) : _clock = clock ?? SystemTimerClock(),
       _staleThreshold = staleSessionThreshold {
    if (bindLifecycleObserver) {
      attachLifecycleObserver();
    }
  }

  /// Phiên học đang mở hoặc đang chờ Recovery (null khi engine ở trạng thái Idle).
  StudySession? get activeSession => _activeSession;

  /// Phiên học vừa kết thúc gần nhất (`completed` hoặc `cancelled`).
  StudySession? get lastEndedSession => _lastEndedSession;

  /// Trạng thái hiện tại của engine (`null` tương đương Idle).
  StudySessionStatus? get currentStatus => _activeSession?.status;

  bool get isIdle => _activeSession == null;
  bool get isRunning => _activeSession?.status == StudySessionStatus.running;
  bool get isPaused => _activeSession?.status == StudySessionStatus.paused;
  bool get isInBreak => _activeSession?.status == StudySessionStatus.inBreak;
  bool get hasPendingRecovery =>
      _activeSession?.status == StudySessionStatus.interruptedPending;

  RecoveryContext? get recoveryContext => _recoveryContext;
  Object? get lastSyncError => _lastSyncError;
  StudyClockAnomaly get clockAnomaly => _clockAnomaly;
  bool get hasClockAnomaly => _clockAnomaly != StudyClockAnomaly.none;

  @visibleForTesting
  int get activeHeartbeatTimerCount => _activeHeartbeatTimerCount;

  /// Bộ lắng nghe duy nhất cho đồng hồ hiển thị (1 nhịp/giây chỉ khi có UI lắng nghe và đang chạy/nghỉ).
  /// Không chứa dữ liệu thời gian độc lập; UI vẫn đọc trực tiếp từ `getCurrentElapsedSeconds()`/`getCurrentBreakSeconds()`.
  Listenable get uiTickListenable => _uiTickNotifier;

  @visibleForTesting
  int get activeUiTickerCount => _uiTickNotifier.activeTickerCount;

  /// Kiểm tra phiên hiện tại có đạt thời lượng dự kiến tham khảo hay chưa (KHÔNG tự dừng/chuyển pha).
  bool get hasReachedPlannedStudyDuration {
    final s = _activeSession;
    if (s == null || s.plannedStudyMinutes <= 0) return false;
    return getCurrentElapsedSeconds() >= s.plannedStudyMinutes * 60;
  }

  /// Thời lượng nghỉ của lần nghỉ hiện tại (tách biệt với tổng thời gian nghỉ các lần trước trong phiên).
  int getCurrentActiveBreakSeconds() {
    final s = _activeSession;
    if (s == null || s.status != StudySessionStatus.inBreak) return 0;
    final totalBreak = getCurrentBreakSeconds();
    final baseline = _currentBreakBaselineSeconds ?? 0;
    return math.max(0, totalBreak - baseline);
  }

  /// Kiểm tra lần nghỉ hiện tại đã chạm thời gian nghỉ dự kiến tham khảo hay chưa (KHÔNG tự chuyển pha).
  bool get hasReachedPlannedBreakDuration {
    final s = _activeSession;
    if (s == null ||
        s.status != StudySessionStatus.inBreak ||
        s.plannedBreakMinutes <= 0) {
      return false;
    }
    return getCurrentActiveBreakSeconds() >= s.plannedBreakMinutes * 60;
  }

  /// Đăng ký nhận sự kiện vòng đời ứng dụng Flutter.
  void attachLifecycleObserver() {
    if (_isLifecycleBound || _isDisposed) return;
    WidgetsBinding.instance.addObserver(this);
    _isLifecycleBound = true;
  }

  /// Hủy đăng ký sự kiện vòng đời ứng dụng Flutter.
  void detachLifecycleObserver() {
    if (!_isLifecycleBound) return;
    WidgetsBinding.instance.removeObserver(this);
    _isLifecycleBound = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(handleLifecycleChange(state));
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    if (_isDisposed) {
      return Future<T>.error(
        StateError(
          'StudyTimerEngine đã bị dispose và không thể nhận thao tác mới.',
        ),
      );
    }
    final completer = Completer<T>();
    _operationQueue = _operationQueue.then((_) async {
      if (_isDisposed) {
        completer.completeError(
          StateError(
            'StudyTimerEngine đã bị dispose trước khi thực thi tác vụ.',
          ),
        );
        return;
      }
      try {
        final result = await action();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  String _generateSessionId(DateTime nowUtc) {
    _sessionCounter++;
    return 'sess_${nowUtc.microsecondsSinceEpoch}_$_sessionCounter';
  }

  void _syncMonotonicAnchor(StudySession? session) {
    if (session == null ||
        !_clock.hasMonotonicClock ||
        (session.status != StudySessionStatus.running &&
            session.status != StudySessionStatus.inBreak)) {
      _anchorSessionId = null;
      _anchorMonotonicElapsed = null;
      return;
    }
    _anchorSessionId = session.id;
    _anchorMonotonicElapsed = _clock.monotonicElapsed;
  }

  /// Tính số giây trôi qua hợp lệ kể từ mốc `lastHeartbeatAt` của `session`,
  /// bảo vệ chống số âm và phát hiện chỉnh đồng hồ hệ thống tiến/lùi bất thường.
  ({int trustedDeltaSeconds, StudyClockAnomaly anomaly, int rawWallSeconds})
  _measureDeltaSinceAnchor(
    StudySession session,
    DateTime nowUtc, {
    bool ignoreForegroundSkewCheck = false,
  }) {
    final wallDiffMs = nowUtc
        .difference(session.lastHeartbeatAt)
        .inMilliseconds;
    if (wallDiffMs < 0) {
      final anomaly = wallDiffMs < -5000
          ? StudyClockAnomaly.backward
          : StudyClockAnomaly.none;
      return (
        trustedDeltaSeconds: 0,
        anomaly: anomaly,
        rawWallSeconds: wallDiffMs ~/ 1000,
      );
    }

    final rawWallSeconds = wallDiffMs ~/ 1000;

    if (!ignoreForegroundSkewCheck &&
        _clock.hasMonotonicClock &&
        _anchorSessionId == session.id &&
        _anchorMonotonicElapsed != null) {
      final monoDiffSec = math.max(
        0,
        (_clock.monotonicElapsed! - _anchorMonotonicElapsed!).inSeconds,
      );
      if (rawWallSeconds - monoDiffSec > foregroundSkewThreshold.inSeconds) {
        return (
          trustedDeltaSeconds: monoDiffSec,
          anomaly: StudyClockAnomaly.forwardJump,
          rawWallSeconds: rawWallSeconds,
        );
      }
    }

    return (
      trustedDeltaSeconds: rawWallSeconds,
      anomaly: StudyClockAnomaly.none,
      rawWallSeconds: rawWallSeconds,
    );
  }

  /// Thời gian học thực tế hiện tại (giây) để tầng UI đọc và hiển thị mà không tự tính toán.
  int getCurrentElapsedSeconds() {
    final s = _activeSession;
    if (s == null) return 0;
    if (s.status != StudySessionStatus.running) {
      return s.verifiedStudySeconds;
    }
    final measurement = _measureDeltaSinceAnchor(s, _clock.nowUtc());
    if (measurement.anomaly != StudyClockAnomaly.none) {
      _clockAnomaly = measurement.anomaly;
    }
    return s.verifiedStudySeconds + measurement.trustedDeltaSeconds;
  }

  /// Thời gian nghỉ hiện tại (giây) để tầng UI đọc và hiển thị riêng biệt khỏi giờ học.
  int getCurrentBreakSeconds() {
    final s = _activeSession;
    if (s == null) return 0;
    if (s.status != StudySessionStatus.inBreak) {
      return s.accumulatedBreakSeconds;
    }
    final measurement = _measureDeltaSinceAnchor(s, _clock.nowUtc());
    if (measurement.anomaly != StudyClockAnomaly.none) {
      _clockAnomaly = measurement.anomaly;
    }
    return s.accumulatedBreakSeconds + measurement.trustedDeltaSeconds;
  }

  void _stopHeartbeatLoop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _activeHeartbeatTimerCount = 0;
  }

  void _ensureSingleHeartbeatLoop() {
    _stopHeartbeatLoop();
    if (!autoStartHeartbeat || _isDisposed || _isInBackground) return;
    final s = _activeSession;
    if (s == null) return;
    if (s.status != StudySessionStatus.running &&
        s.status != StudySessionStatus.inBreak) {
      return;
    }
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      if (_isDisposed) return;
      unawaited(_runPeriodicHeartbeat());
    });
    _activeHeartbeatTimerCount = 1;
  }

  Future<void> _notifySessionsUpdated() async {
    final callback = onSessionsChanged;
    if (callback != null) {
      await callback();
    }
  }

  void _syncUiTicker() {
    final s = _activeSession;
    if (s?.status != StudySessionStatus.inBreak) {
      _currentBreakBaselineSeconds = null;
    }
    final shouldRun =
        autoStartUiTicker &&
        !_isDisposed &&
        !_isInBackground &&
        s != null &&
        (s.status == StudySessionStatus.running ||
            s.status == StudySessionStatus.inBreak);
    _uiTickNotifier.syncShouldRun(shouldRun);
  }

  void _emitStateChanged() {
    _syncUiTicker();
    notifyListeners();
  }

  /// Bắt đầu một phiên học mới (hỗ trợ cả học theo môn học và học theo công việc).
  /// Chặn tuyệt đối trường hợp có hai phiên đang chạy / tạm dừng / nghỉ / chờ khôi phục cùng lúc.
  Future<StudySession> startSession({
    Subject? subject,
    StudyTask? task,
    String? subjectId,
    String? subjectNameSnapshot,
    int? subjectColorSnapshot,
    String? taskId,
    String? taskTitleSnapshot,
    String? scheduledSessionId,
    StudySessionMode sessionMode = StudySessionMode.stopwatch,
    int plannedStudyMinutes = 0,
    int plannedBreakMinutes = 0,
    String notes = '',
  }) {
    return _enqueue(() async {
      if (_activeSession != null) {
        throw StateError(
          'Đang có phiên học ${_activeSession!.id} (${_activeSession!.status.dbValue}). Không thể bắt đầu hai phiên đồng thời.',
        );
      }

      // Kiểm tra chéo với storage phòng trường hợp có phiên mở/pending chưa được khôi phục
      final activeInStorage = await repository.getActiveOrPendingSessions();
      if (activeInStorage.isNotEmpty) {
        throw StateError(
          'Tồn tại phiên học chưa kết thúc (${activeInStorage.first.id}) trong cơ sở dữ liệu.',
        );
      }

      final resolvedTaskId = task?.id ?? _normalizeOptionalId(taskId);
      final resolvedTaskTitle =
          task?.title.trim() ?? _normalizeOptionalText(taskTitleSnapshot);

      String? resolvedSubjectId =
          subject?.id ??
          (task != null && task.subjectId.trim().isNotEmpty
              ? task.subjectId.trim()
              : _normalizeOptionalId(subjectId));

      final rawSubjectName =
          subject?.name ??
          subjectNameSnapshot ??
          (task != null ? task.subject : '');
      final resolvedSubjectName = rawSubjectName.trim();

      if (resolvedSubjectName.isEmpty) {
        throw ArgumentError(
          'Cần cung cấp thông tin môn học hoặc công việc hợp lệ để bắt đầu phiên học.',
        );
      }

      final resolvedColor = subject?.color.toARGB32() ?? subjectColorSnapshot;

      final nowUtc = _clock.nowUtc();
      final nowLocal = _clock.nowLocal();
      final studyDate = StudySession.formatLocalDateKey(nowLocal);

      final session = StudySession(
        id: _generateSessionId(nowUtc),
        subjectId: resolvedSubjectId,
        subjectNameSnapshot: resolvedSubjectName,
        subjectColorSnapshot: resolvedColor,
        taskId: resolvedTaskId,
        taskTitleSnapshot: resolvedTaskTitle,
        scheduledSessionId: _normalizeOptionalId(scheduledSessionId),
        startedAt: nowUtc,
        endedAt: null,
        lastHeartbeatAt: nowUtc,
        lastStateChangedAt: nowUtc,
        studyDate: studyDate,
        verifiedStudySeconds: 0,
        accumulatedBreakSeconds: 0,
        status: StudySessionStatus.running,
        sessionMode: sessionMode,
        plannedStudyMinutes: plannedStudyMinutes,
        plannedBreakMinutes: plannedBreakMinutes,
        notes: notes,
      );

      try {
        await repository.createSession(session);
      } catch (e) {
        _lastSyncError = e;
        rethrow;
      }

      _lastSyncError = null;
      _clockAnomaly = StudyClockAnomaly.none;
      _activeSession = session;
      _recoveryContext = null;
      _syncMonotonicAnchor(session);
      _ensureSingleHeartbeatLoop();
      await _notifySessionsUpdated();
      _emitStateChanged();
      return session;
    });
  }

  /// Tạo ứng viên checkpoint nguyên tử cho pha hiện tại (`running` hoặc `in_break`)
  /// giữ nguyên phần lẻ mili-giây bằng cách tịnh tiến `lastHeartbeatAt` đúng `Duration(seconds: delta)`.
  ({StudySession candidate, int deltaSeconds, StudyClockAnomaly anomaly})
  _buildCheckpointCandidate(
    StudySession current,
    DateTime nowUtc, {
    bool ignoreForegroundSkewCheck = false,
  }) {
    final measurement = _measureDeltaSinceAnchor(
      current,
      nowUtc,
      ignoreForegroundSkewCheck: ignoreForegroundSkewCheck,
    );
    final delta = measurement.trustedDeltaSeconds;

    if (current.status == StudySessionStatus.running) {
      final nextAnchor = delta > 0
          ? current.lastHeartbeatAt.add(Duration(seconds: delta))
          : current.lastHeartbeatAt;
      return (
        candidate: current.copyWith(
          verifiedStudySeconds: current.verifiedStudySeconds + delta,
          lastHeartbeatAt: nextAnchor,
        ),
        deltaSeconds: delta,
        anomaly: measurement.anomaly,
      );
    }

    if (current.status == StudySessionStatus.inBreak) {
      final nextAnchor = delta > 0
          ? current.lastHeartbeatAt.add(Duration(seconds: delta))
          : current.lastHeartbeatAt;
      return (
        candidate: current.copyWith(
          accumulatedBreakSeconds: current.accumulatedBreakSeconds + delta,
          lastHeartbeatAt: nextAnchor,
        ),
        deltaSeconds: delta,
        anomaly: measurement.anomaly,
      );
    }

    return (
      candidate: current,
      deltaSeconds: 0,
      anomaly: StudyClockAnomaly.none,
    );
  }

  Future<void> _runPeriodicHeartbeat() async {
    try {
      await heartbeat(throwOnError: false);
    } catch (e) {
      _lastSyncError = e;
      _emitStateChanged();
    }
  }

  /// Thực thi heartbeat chốt thời gian bền vững theo Single Checkpoint Anchor (`lastHeartbeatAt`).
  /// Không cộng trùng, không tăng thời gian khi Paused/InterruptedPending, và không cộng giờ học khi InBreak.
  Future<StudySession?> heartbeat({bool throwOnError = true}) {
    return _enqueue(() async {
      return _performHeartbeatLocked(throwOnError: throwOnError);
    });
  }

  Future<StudySession?> _performHeartbeatLocked({
    required bool throwOnError,
    bool ignoreForegroundSkewCheck = false,
  }) async {
    final current = _activeSession;
    if (current == null) return null;

    if (current.status != StudySessionStatus.running &&
        current.status != StudySessionStatus.inBreak) {
      // Paused hoặc InterruptedPending: không cộng thời gian học/nghỉ.
      return current;
    }

    final nowUtc = _clock.nowUtc();
    final built = _buildCheckpointCandidate(
      current,
      nowUtc,
      ignoreForegroundSkewCheck: ignoreForegroundSkewCheck,
    );
    if (built.anomaly != StudyClockAnomaly.none) {
      _clockAnomaly = built.anomaly;
    }

    // Nếu nhảy giờ tiến bất thường quá ngưỡng khi đang chạy, chốt đúng phần đơn điệu tin cậy rồi đưa về Recovery
    if (built.anomaly == StudyClockAnomaly.forwardJump) {
      return _transitionToInterruptedDueToClockAnomalyLocked(
        current: built.candidate,
        nowUtc: nowUtc,
      );
    }

    // Nếu không có giây mới nào và không thay đổi anchor, không cần ghi DB thừa
    if (built.deltaSeconds == 0 &&
        built.candidate.lastHeartbeatAt == current.lastHeartbeatAt) {
      return current;
    }

    try {
      await repository.updateSession(built.candidate);
    } catch (e) {
      _lastSyncError = e;
      _emitStateChanged();
      if (throwOnError) rethrow;
      return current;
    }

    _lastSyncError = null;
    _activeSession = built.candidate;
    if (built.deltaSeconds > 0 && _anchorMonotonicElapsed != null) {
      _anchorMonotonicElapsed =
          _anchorMonotonicElapsed! + Duration(seconds: built.deltaSeconds);
    }
    _emitStateChanged();
    return built.candidate;
  }

  Future<StudySession> _transitionToInterruptedDueToClockAnomalyLocked({
    required StudySession current,
    required DateTime nowUtc,
    bool isForwardJump = true,
  }) async {
    final interrupted = current.copyWith(
      status: StudySessionStatus.interruptedPending,
      lastStateChangedAt: nowUtc,
      clearEndedAt: true,
    );

    try {
      await repository.updateSession(interrupted);
    } catch (e) {
      _lastSyncError = e;
      _emitStateChanged();
      rethrow;
    }

    _lastSyncError = null;
    _stopHeartbeatLoop();
    _syncMonotonicAnchor(null);
    _activeSession = interrupted;
    _recoveryContext = _buildRecoveryContext(
      persistedInterrupted: interrupted,
      interruptedFrom: current.status,
      nowUtc: nowUtc,
      forceForwardJumpFlag: isForwardJump,
    );
    await _notifySessionsUpdated();
    _emitStateChanged();
    return interrupted;
  }

  /// Tạm dừng phiên học: chỉ cho phép từ `Running -> Paused`.
  /// Chốt toàn bộ giây học đã trôi qua trước khi chuyển sang `Paused`.
  Future<StudySession> pauseSession() {
    return _enqueue(() async {
      final current = _activeSession;
      if (current == null || current.status != StudySessionStatus.running) {
        throw StateError(
          'Chỉ có thể tạm dừng khi phiên học đang ở trạng thái Running.',
        );
      }

      final nowUtc = _clock.nowUtc();
      final checkpointed = _buildCheckpointCandidate(current, nowUtc);
      if (checkpointed.anomaly != StudyClockAnomaly.none) {
        _clockAnomaly = checkpointed.anomaly;
      }

      final nextAnchor = _resolvePhaseAnchor(
        previousHeartbeat: checkpointed.candidate.lastHeartbeatAt,
        nowUtc: nowUtc,
        preserveForwardAnchorOnBackwardSkew: true,
      );

      final paused = checkpointed.candidate.copyWith(
        status: StudySessionStatus.paused,
        lastHeartbeatAt: nextAnchor,
        lastStateChangedAt: nowUtc,
      );

      try {
        await repository.updateSession(paused);
      } catch (e) {
        _lastSyncError = e;
        _emitStateChanged();
        rethrow;
      }

      _lastSyncError = null;
      _stopHeartbeatLoop();
      _activeSession = paused;
      _syncMonotonicAnchor(null);
      await _notifySessionsUpdated();
      _emitStateChanged();
      return paused;
    });
  }

  /// Tiếp tục học: chỉ cho phép từ `Paused -> Running`.
  /// Không cộng khoảng thời gian đã tạm dừng.
  Future<StudySession> resumeSession() {
    return _enqueue(() async {
      final current = _activeSession;
      if (current == null || current.status != StudySessionStatus.paused) {
        throw StateError(
          'Chỉ có thể tiếp tục khi phiên học đang ở trạng thái Paused.',
        );
      }

      final nowUtc = _clock.nowUtc();
      final resumed = current.copyWith(
        status: StudySessionStatus.running,
        lastHeartbeatAt: nowUtc,
        lastStateChangedAt: nowUtc,
      );

      try {
        await repository.updateSession(resumed);
      } catch (e) {
        _lastSyncError = e;
        _emitStateChanged();
        rethrow;
      }

      _lastSyncError = null;
      _clockAnomaly = StudyClockAnomaly.none;
      _activeSession = resumed;
      _syncMonotonicAnchor(resumed);
      _ensureSingleHeartbeatLoop();
      await _notifySessionsUpdated();
      _emitStateChanged();
      return resumed;
    });
  }

  /// Bắt đầu nghỉ giải lao: chỉ cho phép từ `Running -> InBreak`.
  /// Chốt thời gian học thực tế trước khi bắt đầu đếm giờ nghỉ riêng biệt.
  Future<StudySession> startBreak({String? notes}) {
    return _enqueue(() async {
      final current = _activeSession;
      if (current == null || current.status != StudySessionStatus.running) {
        throw StateError(
          'Chỉ có thể bắt đầu nghỉ giải lao khi phiên học đang Running.',
        );
      }

      final nowUtc = _clock.nowUtc();
      final checkpointed = _buildCheckpointCandidate(current, nowUtc);
      if (checkpointed.anomaly != StudyClockAnomaly.none) {
        _clockAnomaly = checkpointed.anomaly;
      }

      final nextAnchor = _resolvePhaseAnchor(
        previousHeartbeat: checkpointed.candidate.lastHeartbeatAt,
        nowUtc: nowUtc,
        preserveForwardAnchorOnBackwardSkew: false,
      );

      final inBreak = checkpointed.candidate.copyWith(
        status: StudySessionStatus.inBreak,
        lastHeartbeatAt: nextAnchor,
        lastStateChangedAt: nowUtc,
        notes: notes ?? current.notes,
      );

      try {
        await repository.updateSession(inBreak);
      } catch (e) {
        _lastSyncError = e;
        _emitStateChanged();
        rethrow;
      }

      _lastSyncError = null;
      _currentBreakBaselineSeconds = inBreak.accumulatedBreakSeconds;
      _activeSession = inBreak;
      _syncMonotonicAnchor(inBreak);
      _ensureSingleHeartbeatLoop();
      await _notifySessionsUpdated();
      _emitStateChanged();
      return inBreak;
    });
  }

  /// Kết thúc nghỉ và quay lại học: chỉ cho phép từ `InBreak -> Running`.
  /// Chỉ cộng phần nghỉ vào `accumulatedBreakSeconds`, tuyệt đối không cộng vào giờ học.
  Future<StudySession> endBreak() {
    return _enqueue(() async {
      final current = _activeSession;
      if (current == null || current.status != StudySessionStatus.inBreak) {
        throw StateError(
          'Chỉ có thể kết thúc nghỉ giải lao khi đang ở trạng thái InBreak.',
        );
      }

      final nowUtc = _clock.nowUtc();
      final checkpointed = _buildCheckpointCandidate(current, nowUtc);
      if (checkpointed.anomaly != StudyClockAnomaly.none) {
        _clockAnomaly = checkpointed.anomaly;
      }

      final resumedStudy = checkpointed.candidate.copyWith(
        status: StudySessionStatus.running,
        lastHeartbeatAt: nowUtc,
        lastStateChangedAt: nowUtc,
      );

      try {
        await repository.updateSession(resumedStudy);
      } catch (e) {
        _lastSyncError = e;
        _emitStateChanged();
        rethrow;
      }

      _lastSyncError = null;
      _clockAnomaly = StudyClockAnomaly.none;
      _currentBreakBaselineSeconds = null;
      _activeSession = resumedStudy;
      _syncMonotonicAnchor(resumedStudy);
      _ensureSingleHeartbeatLoop();
      await _notifySessionsUpdated();
      _emitStateChanged();
      return resumedStudy;
    });
  }

  /// Hoàn thành phiên học hợp lệ: cho phép từ `Running`, `Paused`, hoặc `InBreak`.
  /// Nếu đang `InBreak`, khoảng nghỉ hiện tại chỉ chốt vào `accumulatedBreakSeconds`.
  /// Sau khi lưu bền vững thành công, engine trở về Idle và đồng bộ Weekly Goal + Study Streak.
  Future<StudySession> completeSession() {
    return _enqueue(() async {
      final current = _activeSession;
      if (current == null) {
        throw StateError('Không có phiên học đang hoạt động để hoàn thành.');
      }
      if (current.status == StudySessionStatus.interruptedPending) {
        throw StateError(
          'Phiên đang chờ xác nhận phục hồi; hãy gọi recoverInterruptedSession().',
        );
      }
      if (current.status != StudySessionStatus.running &&
          current.status != StudySessionStatus.paused &&
          current.status != StudySessionStatus.inBreak) {
        throw StateError(
          'Không thể hoàn thành phiên ở trạng thái ${current.status.dbValue}.',
        );
      }

      final nowUtc = _clock.nowUtc();
      final checkpointed = _buildCheckpointCandidate(current, nowUtc);
      if (checkpointed.anomaly != StudyClockAnomaly.none) {
        _clockAnomaly = checkpointed.anomaly;
      }

      final completed = checkpointed.candidate.copyWith(
        status: StudySessionStatus.completed,
        endedAt: nowUtc,
        lastHeartbeatAt: nowUtc,
        lastStateChangedAt: nowUtc,
      );

      try {
        await repository.updateSession(completed);
      } catch (e) {
        _lastSyncError = e;
        _emitStateChanged();
        rethrow;
      }

      _lastSyncError = null;
      _stopHeartbeatLoop();
      _syncMonotonicAnchor(null);
      _activeSession = null;
      _recoveryContext = null;
      _lastEndedSession = completed;
      await _notifySessionsUpdated();
      _emitStateChanged();
      return completed;
    });
  }

  /// Hủy phiên học: cho phép từ `Running`, `Paused`, hoặc `InBreak`.
  /// Phiên `Cancelled` giữ nguyên lịch sử nhưng KHÔNG được tính vào Weekly Goal hay Study Streak.
  Future<StudySession> cancelSession() {
    return _enqueue(() async {
      final current = _activeSession;
      if (current == null) {
        throw StateError('Không có phiên học đang hoạt động để hủy.');
      }
      if (current.status == StudySessionStatus.interruptedPending) {
        throw StateError(
          'Phiên đang ở trạng thái chờ phục hồi; hãy hủy qua recoverInterruptedSession(action: StudyRecoveryAction.cancel).',
        );
      }
      if (current.status != StudySessionStatus.running &&
          current.status != StudySessionStatus.paused &&
          current.status != StudySessionStatus.inBreak) {
        throw StateError(
          'Không thể hủy phiên ở trạng thái ${current.status.dbValue}.',
        );
      }

      final nowUtc = _clock.nowUtc();
      final cancelled = current.copyWith(
        status: StudySessionStatus.cancelled,
        endedAt: nowUtc,
        lastHeartbeatAt: nowUtc,
        lastStateChangedAt: nowUtc,
      );

      try {
        await repository.updateSession(cancelled);
      } catch (e) {
        _lastSyncError = e;
        _emitStateChanged();
        rethrow;
      }

      _lastSyncError = null;
      _stopHeartbeatLoop();
      _syncMonotonicAnchor(null);
      _activeSession = null;
      _recoveryContext = null;
      _lastEndedSession = cancelled;
      await _notifySessionsUpdated();
      _emitStateChanged();
      return cancelled;
    });
  }

  /// Kiểm tra CSDL khi ứng dụng khởi động lại và phát hiện phiên gián đoạn.
  /// Mọi phiên `Running` / `Paused` / `InBreak` còn mở khi tiến trình khởi động lại
  /// đều chuyển sang `InterruptedPending` (giữ nguyên `lastHeartbeatAt` để tính `unverifiedGap`),
  /// tuyệt đối KHÔNG tự động cộng thời gian chưa xác minh.
  Future<RecoveryContext?> restoreSessionState() {
    return _enqueue(() async {
      final nowUtc = _clock.nowUtc();
      final scan = await repository.getActiveOrPendingSessionsSafe(
        fallbackEndedAtUtc: nowUtc,
      );

      if (scan.corruptedIds.isNotEmpty) {
        await _notifySessionsUpdated();
      }

      if (scan.valid.isEmpty) {
        _stopHeartbeatLoop();
        _syncMonotonicAnchor(null);
        _activeSession = null;
        _recoveryContext = null;
        _emitStateChanged();
        return null;
      }

      final target = scan.valid.first;

      // Dọn các bản ghi mở mồ côi cũ hơn (nếu có >1 dòng lỗi do crash) về cancelled
      if (scan.valid.length > 1) {
        for (var i = 1; i < scan.valid.length; i++) {
          final staleExtra = scan.valid[i];
          await repository.updateSession(
            staleExtra.copyWith(
              status: StudySessionStatus.cancelled,
              endedAt: nowUtc,
              lastStateChangedAt: nowUtc,
            ),
          );
        }
      }

      final StudySessionStatus? originalStatus =
          target.status == StudySessionStatus.interruptedPending
          ? null
          : target.status;

      StudySession pendingSession = target;
      if (target.status != StudySessionStatus.interruptedPending) {
        // Giữ nguyên `lastHeartbeatAt` cũ để không làm mất dấu thời gian cuối cùng đã chốt sổ
        pendingSession = target.copyWith(
          status: StudySessionStatus.interruptedPending,
          lastStateChangedAt: nowUtc,
          clearEndedAt: true,
        );
        await repository.updateSession(pendingSession);
        await _notifySessionsUpdated();
      }

      final context = _buildRecoveryContext(
        persistedInterrupted: pendingSession,
        interruptedFrom: originalStatus,
        nowUtc: nowUtc,
      );

      _stopHeartbeatLoop();
      _syncMonotonicAnchor(null);
      _activeSession = pendingSession;
      _recoveryContext = context;
      if (context.isClockMovedBackward) {
        _clockAnomaly = StudyClockAnomaly.backward;
      } else if (context.isClockJumpedForward) {
        _clockAnomaly = StudyClockAnomaly.forwardJump;
      }
      _emitStateChanged();
      return context;
    });
  }

  RecoveryContext _buildRecoveryContext({
    required StudySession persistedInterrupted,
    required StudySessionStatus? interruptedFrom,
    required DateTime nowUtc,
    bool forceForwardJumpFlag = false,
  }) {
    final diffMs = nowUtc
        .difference(persistedInterrupted.lastHeartbeatAt)
        .inMilliseconds;
    final startDiffMs = nowUtc
        .difference(persistedInterrupted.startedAt)
        .inMilliseconds;

    final isClockMovedBackward = diffMs < 0 || startDiffMs < 0;
    final rawWallGapSeconds = isClockMovedBackward ? 0 : (diffMs ~/ 1000);
    final isStaleOver8Hours = rawWallGapSeconds > _staleThreshold.inSeconds;

    final wasPausedOrInBreak =
        interruptedFrom == StudySessionStatus.paused ||
        interruptedFrom == StudySessionStatus.inBreak;

    final int unverifiedGapSeconds =
        (isClockMovedBackward || wasPausedOrInBreak) ? 0 : rawWallGapSeconds;

    final int maxConfirmableExtraSeconds = math.min(
      unverifiedGapSeconds,
      maxConfirmableExtraCapSeconds,
    );

    String? warning;
    if (isClockMovedBackward) {
      warning =
          'Phát hiện đồng hồ hệ thống lùi so với lần lưu cuối. Vui lòng xác nhận hoặc tiếp tục từ mốc hiện tại.';
    } else if (forceForwardJumpFlag) {
      warning =
          'Phát hiện đồng hồ hệ thống tăng đột biến. Khoảng chênh lệch chưa xác minh không được tự động cộng.';
    } else if (isStaleOver8Hours) {
      warning =
          'Phiên học đã gián đoạn quá ${_staleThreshold.inHours} giờ kể từ lần lưu cuối.';
    } else if (interruptedFrom == StudySessionStatus.paused) {
      warning = 'Phiên học bị gián đoạn khi đang tạm dừng.';
    } else if (interruptedFrom == StudySessionStatus.inBreak) {
      warning = 'Phiên học bị gián đoạn khi đang nghỉ giải lao.';
    }

    return RecoveryContext(
      session: persistedInterrupted,
      interruptedFromStatus: interruptedFrom,
      detectedAtUtc: nowUtc,
      verifiedStudySeconds: persistedInterrupted.verifiedStudySeconds,
      verifiedBreakSeconds: persistedInterrupted.accumulatedBreakSeconds,
      rawWallGapSeconds: rawWallGapSeconds,
      unverifiedGapSeconds: unverifiedGapSeconds,
      maxConfirmableExtraSeconds: maxConfirmableExtraSeconds,
      isStaleOver8Hours: isStaleOver8Hours,
      isClockMovedBackward: isClockMovedBackward,
      isClockJumpedForward: forceForwardJumpFlag,
      warningReason: warning,
    );
  }

  /// Thực thi 1 trong 3 lựa chọn phục hồi phiên gián đoạn (Quyết định D3):
  /// - [StudyRecoveryAction.continueStudying]: Giữ nguyên thời gian đã chốt, bỏ hoàn toàn khoảng gián đoạn, tiếp tục `Running`.
  /// - [StudyRecoveryAction.completeAndConfirm]: Xác nhận phần thời gian trong biên hợp lệ, kết thúc thành `Completed`.
  /// - [StudyRecoveryAction.cancel]: Hủy phiên (`Cancelled`), không tính vào Thống kê/Weekly Goal/Streak.
  Future<StudySession> recoverInterruptedSession({
    required StudyRecoveryAction action,
    int? confirmedExtraSeconds,
    int? confirmedTotalSeconds,
  }) {
    return _enqueue(() async {
      final current = _activeSession;
      if (current == null ||
          current.status != StudySessionStatus.interruptedPending) {
        throw StateError(
          'Không có phiên học nào đang ở trạng thái chờ phục hồi (interrupted_pending).',
        );
      }

      if (confirmedExtraSeconds != null && confirmedTotalSeconds != null) {
        throw ArgumentError(
          'Chỉ được truyền confirmedExtraSeconds hoặc confirmedTotalSeconds, không truyền đồng thời.',
        );
      }

      final nowUtc = _clock.nowUtc();
      final ctx =
          _recoveryContext ??
          _buildRecoveryContext(
            persistedInterrupted: current,
            interruptedFrom: null,
            nowUtc: nowUtc,
          );

      switch (action) {
        case StudyRecoveryAction.continueStudying:
          final continued = current.copyWith(
            status: StudySessionStatus.running,
            lastHeartbeatAt: nowUtc,
            lastStateChangedAt: nowUtc,
            clearEndedAt: true,
          );
          try {
            await repository.updateSession(continued);
          } catch (e) {
            _lastSyncError = e;
            _emitStateChanged();
            rethrow;
          }
          _lastSyncError = null;
          _clockAnomaly = StudyClockAnomaly.none;
          _recoveryContext = null;
          _activeSession = continued;
          _syncMonotonicAnchor(continued);
          _ensureSingleHeartbeatLoop();
          await _notifySessionsUpdated();
          _emitStateChanged();
          return continued;

        case StudyRecoveryAction.completeAndConfirm:
          final baseVerified = current.verifiedStudySeconds;
          final maxTotal = baseVerified + ctx.maxConfirmableExtraSeconds;
          final int resolvedTotal;

          if (confirmedTotalSeconds != null) {
            if (confirmedTotalSeconds < baseVerified ||
                confirmedTotalSeconds > maxTotal) {
              throw ArgumentError.value(
                confirmedTotalSeconds,
                'confirmedTotalSeconds',
                'Thời gian xác nhận phải nằm trong khoảng hợp lệ [$baseVerified..$maxTotal] giây.',
              );
            }
            resolvedTotal = confirmedTotalSeconds;
          } else {
            final extra = confirmedExtraSeconds ?? 0;
            if (extra < 0 || extra > ctx.maxConfirmableExtraSeconds) {
              throw ArgumentError.value(
                extra,
                'confirmedExtraSeconds',
                'Thời gian bổ sung phải nằm trong khoảng [0..${ctx.maxConfirmableExtraSeconds}] giây.',
              );
            }
            resolvedTotal = baseVerified + extra;
          }

          final completed = current.copyWith(
            status: StudySessionStatus.completed,
            verifiedStudySeconds: resolvedTotal,
            endedAt: nowUtc,
            lastHeartbeatAt: nowUtc,
            lastStateChangedAt: nowUtc,
          );

          try {
            await repository.updateSession(completed);
          } catch (e) {
            _lastSyncError = e;
            _emitStateChanged();
            rethrow;
          }

          _lastSyncError = null;
          _stopHeartbeatLoop();
          _syncMonotonicAnchor(null);
          _activeSession = null;
          _recoveryContext = null;
          _lastEndedSession = completed;
          await _notifySessionsUpdated();
          _emitStateChanged();
          return completed;

        case StudyRecoveryAction.cancel:
          final cancelled = current.copyWith(
            status: StudySessionStatus.cancelled,
            endedAt: nowUtc,
            lastHeartbeatAt: nowUtc,
            lastStateChangedAt: nowUtc,
          );

          try {
            await repository.updateSession(cancelled);
          } catch (e) {
            _lastSyncError = e;
            _emitStateChanged();
            rethrow;
          }

          _lastSyncError = null;
          _stopHeartbeatLoop();
          _syncMonotonicAnchor(null);
          _activeSession = null;
          _recoveryContext = null;
          _lastEndedSession = cancelled;
          await _notifySessionsUpdated();
          _emitStateChanged();
          return cancelled;
      }
    });
  }

  /// Đồng bộ với Flutter AppLifecycleState (`inactive`, `paused`, `detached`, `resumed`).
  Future<void> handleLifecycleChange(AppLifecycleState state) {
    return _enqueue(() async {
      switch (state) {
        case AppLifecycleState.inactive:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
        case AppLifecycleState.hidden:
          _isInBackground = true;
          _stopHeartbeatLoop();
          _syncUiTicker();
          await _performHeartbeatLocked(throwOnError: false);
          return;

        case AppLifecycleState.resumed:
          _isInBackground = false;
          final current = _activeSession;
          if (current == null) return;

          if (current.status == StudySessionStatus.running ||
              current.status == StudySessionStatus.inBreak) {
            final nowUtc = _clock.nowUtc();
            final wallDiffMs = nowUtc
                .difference(current.lastHeartbeatAt)
                .inMilliseconds;

            // Nếu giờ hệ thống lùi hoặc rời app quá ngưỡng stale (> 8 giờ) khi đang chạy -> đưa vào Recovery
            final isBackward = wallDiffMs < -5000;
            final wallSec = isBackward ? 0 : (wallDiffMs ~/ 1000);
            final isStale = wallSec > _staleThreshold.inSeconds;

            if (isBackward || isStale) {
              if (isBackward) {
                _clockAnomaly = StudyClockAnomaly.backward;
              }
              await _transitionToInterruptedDueToClockAnomalyLocked(
                current: current,
                nowUtc: nowUtc,
                isForwardJump: false,
              );
              return;
            }

            await _performHeartbeatLocked(
              throwOnError: false,
              ignoreForegroundSkewCheck: true,
            );
            _syncMonotonicAnchor(_activeSession);
            _ensureSingleHeartbeatLoop();
            _syncUiTicker();
          } else if (current.status == StudySessionStatus.paused ||
              current.status == StudySessionStatus.interruptedPending) {
            _stopHeartbeatLoop();
            _emitStateChanged();
          }
          return;
      }
    });
  }

  /// Đồng bộ lại `_activeSession` từ CSDL nếu có thay đổi liên kết môn học/task từ bên ngoài.
  Future<void> refreshActiveFromRepository() {
    return _enqueue(() async {
      final current = _activeSession;
      if (current == null) return;
      final refreshed = await repository.getSessionById(current.id);
      if (refreshed == null || !refreshed.status.isActiveOrPending) {
        _stopHeartbeatLoop();
        _syncMonotonicAnchor(null);
        _activeSession = null;
        _recoveryContext = null;
      } else {
        _activeSession = refreshed;
      }
      _emitStateChanged();
    });
  }

  /// Xóa trạng thái trong bộ nhớ khi người dùng thực hiện "Đặt lại toàn bộ dữ liệu học tập".
  Future<void> resetStateForDataClear() {
    return _enqueue(() async {
      _stopHeartbeatLoop();
      _syncMonotonicAnchor(null);
      _activeSession = null;
      _lastEndedSession = null;
      _recoveryContext = null;
      _lastSyncError = null;
      _clockAnomaly = StudyClockAnomaly.none;
      _emitStateChanged();
    });
  }

  DateTime _resolvePhaseAnchor({
    required DateTime previousHeartbeat,
    required DateTime nowUtc,
    required bool preserveForwardAnchorOnBackwardSkew,
  }) {
    if (preserveForwardAnchorOnBackwardSkew &&
        nowUtc.isBefore(previousHeartbeat)) {
      return previousHeartbeat;
    }
    return nowUtc;
  }

  String? _normalizeOptionalId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  String? _normalizeOptionalText(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _stopHeartbeatLoop();
    _uiTickNotifier.dispose();
    detachLifecycleObserver();
    super.dispose();
  }
}

/// Bộ phát xung hiển thị 1 giây/lần dùng chung duy nhất cho toàn bộ UI đồng hồ.
/// Chỉ chạy khi có ít nhất 1 widget đăng ký lắng nghe và Engine đang Running/InBreak.
class _UiTickNotifier extends ChangeNotifier {
  Timer? _timer;
  bool _shouldRun = false;
  bool _disposed = false;

  int get activeTickerCount => _timer != null ? 1 : 0;

  void syncShouldRun(bool shouldRun) {
    _shouldRun = shouldRun;
    _reconcileTimer();
  }

  void _reconcileTimer() {
    if (_disposed) {
      _stopTimer();
      return;
    }
    final needTimer = _shouldRun && hasListeners;
    if (needTimer && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!_disposed && _shouldRun && hasListeners) {
          notifyListeners();
        }
      });
    } else if (!needTimer && _timer != null) {
      _stopTimer();
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _reconcileTimer();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _reconcileTimer();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopTimer();
    super.dispose();
  }
}

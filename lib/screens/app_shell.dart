import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/alarm_state.dart';
import '../models/class_schedule.dart';
import '../models/study_activity.dart';
import '../models/study_session.dart';
import '../models/study_streak.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../models/task_priority.dart';
import '../models/task_status.dart';
import '../models/understanding_level.dart';
import '../models/user_profile.dart';
import '../database/database_helper.dart';
import '../repositories/profile_repository.dart';
import '../repositories/schedule_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/subject_repository.dart';
import '../repositories/task_repository.dart';
import '../services/backup_service.dart';
import '../services/session_storage.dart';
import '../services/study_notification_coordinator.dart';
import '../services/study_timer_engine.dart';
import '../theme/app_colors.dart';
import '../services/web_storage.dart';
import '../widgets/active_alarm_banner.dart';
import '../widgets/backup_dialogs.dart';
import '../widgets/floating_mini_timer_bar.dart';
import '../widgets/study_recovery_dialog.dart';
import '../widgets/task_assessment_dialog.dart';
import '../widgets/task_detail_sheet.dart';
import '../widgets/task_form_dialog.dart';
import 'overview_screen.dart';
import 'plan_screen.dart';
import 'profile_screen.dart';
import 'statistics_screen.dart';
import 'study_timer_screen.dart';
import 'subjects_screen.dart';

// Bí danh tương thích ngược
const primaryColor = AppColors.primary;
const backgroundColor = AppColors.background;

/// Màn hình khung chính quản lý điều hướng 5 tab và lưu trữ dữ liệu bền vững qua SQLite (Android)
/// hoặc chế độ xem trước an toàn trên Web (không gọi sqflite).
class AppShell extends StatefulWidget {
  final TaskRepository? taskRepository;
  final SubjectRepository? subjectRepository;
  final ProfileRepository? profileRepository;
  final SessionRepository? sessionRepository;
  final ScheduleRepository? scheduleRepository;
  final StudyTimerEngine? timerEngine;
  final StudyNotificationCoordinator? notificationCoordinator;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  const AppShell({
    super.key,
    this.taskRepository,
    this.subjectRepository,
    this.profileRepository,
    this.sessionRepository,
    this.scheduleRepository,
    this.timerEngine,
    this.notificationCoordinator,
    this.onThemeModeChanged,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _isLoading = true;
  String? _errorMessage;

  late final TaskRepository _taskRepository;
  late final SubjectRepository _subjectRepository;
  late final ProfileRepository _profileRepository;
  late final SessionRepository _sessionRepository;
  late final ScheduleRepository _scheduleRepository;

  // Danh mục môn học đồng bộ từ SQLite hoặc Web preview
  List<Subject> _subjects = [];

  // Danh sách công việc được đồng bộ từ SQLite hoặc Web preview
  List<StudyTask> _tasks = [];

  // Danh sách lịch học cố định theo tuần (Phase 4.3)
  List<ClassSchedule> _schedules = [];

  // Danh sách ngày học tập ghi nhận (Study Streak)
  Set<String> _activeDates = {};

  // Danh sách các hoạt động học tập ghi nhận (dành cho Thống kê)
  List<StudyActivity> _activities = [];

  // Danh sách phiên học thực tế (study_sessions - G8.8 Phase 1)
  List<StudySession> _sessions = [];

  // Thông tin hồ sơ cá nhân, mục tiêu và cài đặt (Giai đoạn 5)
  UserProfile _userProfile = const UserProfile();

  // Bộ máy điều phối Study Timer (G8.8 Phase 2) - cô lập tick khỏi AppShell
  late final StudyTimerEngine _timerEngine;
  late final bool _ownsTimerEngine;
  late final StudyNotificationCoordinator _notificationCoordinator;
  late final bool _ownsNotificationCoordinator;
  StudySessionStatus? _observedTimerStatus;
  String? _observedActiveSessionId;
  String? _observedLastEndedSessionId;
  bool _hasCheckedInitialRecovery = false;
  bool _isRecoveryDialogOpen = false;

  // Dịch vụ sao lưu và khôi phục dữ liệu (Giai đoạn 8.7)
  late final BackupService _backupService;
  DateTime? _lastBackupTime;

  @override
  void initState() {
    super.initState();
    _taskRepository = widget.taskRepository ?? TaskRepository();
    _subjectRepository = widget.subjectRepository ?? SubjectRepository();
    _profileRepository =
        widget.profileRepository ??
        ProfileRepository(useWebPreview: _taskRepository.isWebPreview);
    _sessionRepository =
        widget.sessionRepository ??
        SessionRepository(useWebPreview: _taskRepository.isWebPreview);
    _scheduleRepository =
        widget.scheduleRepository ??
        ScheduleRepository(useWebPreview: _taskRepository.isWebPreview);
    _ownsTimerEngine = widget.timerEngine == null;
    _timerEngine =
        widget.timerEngine ??
        StudyTimerEngine(
          repository: _sessionRepository,
          onSessionsChanged: _syncSessionsFromRepository,
          bindLifecycleObserver: true,
        );
    _ownsNotificationCoordinator = widget.notificationCoordinator == null;
    _notificationCoordinator =
        widget.notificationCoordinator ??
        StudyNotificationCoordinator.createDefault(
          initialProfile: _userProfile,
          scheduleSlotsProvider: _generateUpcomingStudySlots,
          tasksProvider: () => _tasks,
          onAlarmStartStudyRequested: _handleAlarmStartStudyRequested,
        );
    _notificationCoordinator.bindTimerEngine(_timerEngine);
    _captureObservedTimerSnapshot();
    _timerEngine.addListener(_handleTimerBoundaryStateChanged);
    _backupService = BackupService(
      taskRepository: _taskRepository,
      subjectRepository: _subjectRepository,
      profileRepository: _profileRepository,
      scheduleRepository: _scheduleRepository,
      dbHelper: _taskRepository.isWebPreview ? null : DatabaseHelper.instance,
    );
    _loadData();
  }

  void _captureObservedTimerSnapshot() {
    _observedTimerStatus = _timerEngine.currentStatus;
    _observedActiveSessionId = _timerEngine.activeSession?.id;
    _observedLastEndedSessionId = _timerEngine.lastEndedSession?.id;
  }

  void _handleTimerBoundaryStateChanged() {
    if (!mounted) return;
    final nextStatus = _timerEngine.currentStatus;
    final nextActiveId = _timerEngine.activeSession?.id;
    final nextEndedId = _timerEngine.lastEndedSession?.id;
    if (nextStatus != _observedTimerStatus ||
        nextActiveId != _observedActiveSessionId ||
        nextEndedId != _observedLastEndedSessionId) {
      _captureObservedTimerSnapshot();
      if (!_ownsTimerEngine) {
        unawaited(_syncSessionsFromRepository());
      }
      if (_timerEngine.hasPendingRecovery) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeShowRecoveryDialog();
        });
      }
    }
  }

  /// Đồng bộ lại danh sách phiên học từ nguồn dữ liệu duy nhất (SessionRepository),
  /// giúp Weekly Goal và Study Streak cập nhật tức thì khi Timer thay đổi trạng thái.
  Future<void> _syncSessionsFromRepository() async {
    if (!mounted) return;
    try {
      final refreshed = await _sessionRepository.getAllSessions();
      if (!mounted) return;
      setState(() {
        _sessions = refreshed;
      });
    } catch (e) {
      debugPrint('Lỗi đồng bộ danh sách phiên học: $e');
    }
  }

  @override
  void dispose() {
    _notificationCoordinator.unbindTimerEngine();
    if (_ownsNotificationCoordinator) {
      _notificationCoordinator.dispose();
    }
    _timerEngine.removeListener(_handleTimerBoundaryStateChanged);
    if (_ownsTimerEngine) {
      _timerEngine.dispose();
    }
    super.dispose();
  }

  void _handleAlarmStartStudyRequested(AlarmRecord alarm) {
    if (!mounted) return;
    Subject? matchedSubject;
    if (alarm.subjectId != null && alarm.subjectId!.isNotEmpty) {
      for (final s in _subjects) {
        if (s.id == alarm.subjectId) {
          matchedSubject = s;
          break;
        }
      }
    }
    _openStudyTimer(initialSubject: matchedSubject);
  }

  void _handleNotificationTap(String? payload, String? actionId) {
    if (!mounted || payload == null) return;
    if (payload.startsWith('timer')) {
      _openStudyTimer();
    }
  }

  /// Tải đồng bộ cả môn học, nhiệm vụ, lịch sử ngày học, hoạt động và phiên học từ các Repository.
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final subjectsFuture = _subjectRepository.getAllSubjects();
      final tasksFuture = _taskRepository.getAllTasks();
      final activeDatesFuture = _taskRepository.getActiveStudyDates();
      final activitiesFuture = _taskRepository.getAllActivities();
      final profileFuture = _profileRepository.getProfile();
      final sessionsFuture = _sessionRepository.getAllSessions();
      final schedulesFuture = _scheduleRepository.getAllSchedules();

      final results = await Future.wait([
        subjectsFuture,
        tasksFuture,
        activeDatesFuture,
        activitiesFuture,
        profileFuture,
        sessionsFuture,
        schedulesFuture,
      ]);
      final loadedSubjects = results[0] as List<Subject>;
      final loadedTasks = results[1] as List<StudyTask>;
      final loadedActiveDates = results[2] as Set<String>;
      final loadedActivities = results[3] as List<StudyActivity>;
      final loadedProfile = results[4] as UserProfile;
      var loadedSessions = results[5] as List<StudySession>;
      final loadedSchedules = results[6] as List<ClassSchedule>;

      if (!_hasCheckedInitialRecovery) {
        _hasCheckedInitialRecovery = true;
        if (_timerEngine.activeSession == null &&
            loadedSessions.any((s) => s.status.isActiveOrPending)) {
          await _timerEngine.restoreSessionState();
          loadedSessions = await _sessionRepository.getAllSessions();
        }
      } else if (_timerEngine.activeSession != null) {
        await _timerEngine.refreshActiveFromRepository();
      }
      _captureObservedTimerSnapshot();

      if (!mounted) return;
      setState(() {
        _subjects = loadedSubjects;
        _tasks = loadedTasks;
        _activeDates = loadedActiveDates;
        _activities = loadedActivities;
        _userProfile = loadedProfile;
        _sessions = loadedSessions;
        _schedules = loadedSchedules;
        _isLoading = false;
      });
      widget.onThemeModeChanged?.call(loadedProfile.flutterThemeMode);
      unawaited(
        _notificationCoordinator
            .applyProfile(loadedProfile, promptPermissionIfEnabling: false)
            .then((_) async {
              if (!_notificationCoordinator.isInitialized) {
                await _notificationCoordinator.initialize(
                  onNotificationTap: _handleNotificationTap,
                );
              }
            }),
      );
      if (_timerEngine.hasPendingRecovery) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _maybeShowRecoveryDialog();
        });
      }
    } catch (e, stackTrace) {
      if (!mounted) return;
      debugPrint('LỖI TRUY XUẤT CƠ SỞ DỮ LIỆU: $e\n$stackTrace');

      // Chỉ trên Web (không có sqflite) mới dùng dữ liệu xem trước
      if (kIsWeb) {
        final webProfile =
            WebStreakStorage.loadProfile() ?? const UserProfile();
        setState(() {
          _subjects = SubjectRepository.getDefaultSubjects();
          _tasks = _getSampleTasks();
          _activeDates = WebStreakStorage.loadActiveDates();
          _activities = WebStreakStorage.loadActivities();
          _sessions = WebSessionStorage.loadSessions();
          _schedules = WebScheduleStorage.loadSchedules();
          _userProfile = webProfile;
          _isLoading = false;
          _errorMessage = null;
        });
        widget.onThemeModeChanged?.call(webProfile.flutterThemeMode);
        return;
      }

      // Trên Android / Thiết bị di động: Tuyệt đối không tự động nạp dữ liệu mẫu ghi đè dữ liệu người dùng.
      // Giữ nguyên exception và hiển thị lỗi trung thực lên giao diện.
      setState(() {
        _errorMessage = 'Lỗi truy xuất cơ sở dữ liệu: $e';
        _isLoading = false;
      });
    }
  }

  List<StudyTask> _getSampleTasks() {
    final now = DateTime.now();
    return [
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
    ];
  }

  // --- TIỆN ÍCH THÔNG BÁO NHẸ NHÀNG, KHÔNG CHE NỘI DUNG VÀ KHÔNG XẾP CHỒNG ---

  void _showNotification(
    String message, {
    bool isError = false,
    Duration duration = const Duration(milliseconds: 2000),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    // Xóa ngay thông báo cũ để không xếp chồng khi người dùng tương tác liên tục
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        duration: duration,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: isError ? AppColors.error : null,
        action: (actionLabel != null && onAction != null)
            ? SnackBarAction(
                label: actionLabel,
                textColor: Colors.amberAccent,
                onPressed: onAction,
              )
            : null,
      ),
    );
  }

  // --- CÁC HÀM XỬ LÝ LỊCH HỌC TUẦN & THỜI KHÓA BIỂU (Phase 4.3) ---

  List<ScheduledStudySlot> _generateUpcomingStudySlots() {
    final now = DateTime.now();
    final slots = <ScheduledStudySlot>[];
    for (final schedule in _schedules) {
      if (schedule.isActive) {
        slots.addAll(
          schedule.generateUpcomingSlots(fromTime: now, daysAhead: 14),
        );
      }
    }
    return slots;
  }

  Future<void> _addSchedule(ClassSchedule schedule) async {
    try {
      await _scheduleRepository.insertSchedule(schedule);
      final updated = await _scheduleRepository.getAllSchedules();
      if (!mounted) return;
      setState(() {
        _schedules = updated;
      });
      await _notificationCoordinator.syncSchedules();
      _showNotification('Đã thêm lịch học: ${schedule.subjectName}');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi thêm lịch học: $e', isError: true);
    }
  }

  Future<void> _updateSchedule(ClassSchedule schedule) async {
    try {
      await _scheduleRepository.updateSchedule(schedule);
      final updated = await _scheduleRepository.getAllSchedules();
      if (!mounted) return;
      setState(() {
        _schedules = updated;
      });
      await _notificationCoordinator.syncSchedules();
      _showNotification('Đã cập nhật lịch học: ${schedule.subjectName}');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi cập nhật lịch học: $e', isError: true);
    }
  }

  Future<void> _deleteSchedule(ClassSchedule schedule) async {
    try {
      await _scheduleRepository.deleteSchedule(schedule.id);
      final updated = await _scheduleRepository.getAllSchedules();
      if (!mounted) return;
      setState(() {
        _schedules = updated;
      });
      await _notificationCoordinator.syncSchedules();
      _showNotification('Đã xóa lịch học: ${schedule.subjectName}');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi xóa lịch học: $e', isError: true);
    }
  }

  Future<void> _toggleScheduleActive(
    ClassSchedule schedule,
    bool isActive,
  ) async {
    try {
      await _scheduleRepository.toggleScheduleActive(schedule.id, isActive);
      final updated = await _scheduleRepository.getAllSchedules();
      if (!mounted) return;
      setState(() {
        _schedules = updated;
      });
      await _notificationCoordinator.syncSchedules();
      _showNotification(
        isActive
            ? 'Đã bật lịch học: ${schedule.subjectName}'
            : 'Đã tắt lịch học: ${schedule.subjectName}',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi đổi trạng thái lịch: $e', isError: true);
    }
  }

  Future<void> _handleImportSchedules({
    required List<ClassSchedule> schedules,
    required List<Subject> newSubjects,
  }) async {
    try {
      // 1. Thêm các môn học mới nếu có
      for (final subject in newSubjects) {
        await _subjectRepository.insertSubject(subject);
      }
      if (newSubjects.isNotEmpty) {
        final updatedSubjects = await _subjectRepository.getAllSubjects();
        if (mounted) {
          setState(() {
            _subjects = updatedSubjects;
          });
        }
      }

      // 2. Batch insert các lịch học
      await _scheduleRepository.insertSchedulesBatch(schedules);
      final updatedSchedules = await _scheduleRepository.getAllSchedules();

      if (!mounted) return;
      setState(() {
        _schedules = updatedSchedules;
      });

      // 3. Đồng bộ lại hệ thống nhắc nhở và báo thức
      await _notificationCoordinator.syncSchedules();

      _showNotification(
        'Đã nhập thành công ${schedules.length} lịch học'
        '${newSubjects.isNotEmpty ? ' và tạo ${newSubjects.length} môn học mới' : ''}.',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi nhập thời khóa biểu: $e', isError: true);
    }
  }

  // --- CÁC HÀM XỬ LÝ NGHIỆP VỤ CRUD NHIỆM VỤ (TASK) ---

  Future<void> _addTask(StudyTask newTask) async {
    try {
      await _taskRepository.insertTask(newTask);
      if (!mounted) return;
      setState(() {
        _tasks.insert(0, newTask);
      });
      unawaited(_notificationCoordinator.scheduleTaskDeadline(newTask));
      _showNotification(
        kIsWeb
            ? 'Đã thêm: "${newTask.title}" (Chế độ xem trước Web)'
            : 'Đã lưu công việc: "${newTask.title}"',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi thêm công việc: $e', isError: true);
    }
  }

  Future<void> _updateTask(StudyTask updatedTask) async {
    try {
      await _taskRepository.updateTask(updatedTask);
      if (!mounted) return;
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == updatedTask.id);
        if (index != -1) {
          _tasks[index] = updatedTask;
        }
      });
      unawaited(_notificationCoordinator.scheduleTaskDeadline(updatedTask));
      _showNotification(
        kIsWeb
            ? 'Đã cập nhật: "${updatedTask.title}" (Chế độ xem trước Web)'
            : 'Đã cập nhật: "${updatedTask.title}"',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi cập nhật: $e', isError: true);
    }
  }

  Future<void> _deleteTask(StudyTask taskToDelete) async {
    try {
      await _taskRepository.deleteTask(taskToDelete.id);
      await _sessionRepository.detachTaskForWeb(taskToDelete.id);
      await _timerEngine.refreshActiveFromRepository();
      final updatedSessions = await _sessionRepository.getAllSessions();
      if (!mounted) return;
      setState(() {
        _tasks.removeWhere((t) => t.id == taskToDelete.id);
        _sessions = updatedSessions;
      });
      unawaited(_notificationCoordinator.cancelTaskDeadline(taskToDelete.id));
      _showNotification(
        kIsWeb
            ? 'Đã xóa: "${taskToDelete.title}" (Chế độ xem trước Web)'
            : 'Đã xóa công việc: "${taskToDelete.title}"',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi xóa: $e', isError: true);
    }
  }

  int _getVerifiedSecondsForTask(String taskId) {
    if (taskId.isEmpty) return 0;
    return _sessions
        .where(
          (s) => s.taskId == taskId && s.status == StudySessionStatus.completed,
        )
        .fold<int>(0, (sum, s) => sum + s.verifiedStudySeconds);
  }

  void _handleStartStudyWithTask(StudyTask task) {
    final matchingSubject = _subjects
        .where(
          (s) =>
              (task.subjectId.isNotEmpty && s.id == task.subjectId) ||
              s.name == task.subject,
        )
        .firstOrNull;
    _openStudyTimer(initialSubject: matchingSubject, initialTask: task);
  }

  Future<void> _handleRescheduleTask(StudyTask task) async {
    final now = DateTime.now();
    final initialDate = task.deadline != null && task.deadline!.isAfter(now)
        ? task.deadline!
        : now.add(const Duration(days: 1));

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 2)),
      helpText: 'Chọn hạn hoàn thành mới (Chuyển lịch)',
    );

    if (pickedDate == null || !mounted) return;

    final initialTime = task.deadline != null
        ? TimeOfDay.fromDateTime(task.deadline!)
        : const TimeOfDay(hour: 23, minute: 59);

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: 'Chọn giờ hạn hoàn thành mới',
    );

    if (!mounted) return;

    final finalHour = pickedTime?.hour ?? initialTime.hour;
    final finalMinute = pickedTime?.minute ?? initialTime.minute;
    final newDeadline = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      finalHour,
      finalMinute,
    );

    final updatedTask = task.copyWith(deadline: newDeadline);
    await _updateTask(updatedTask);
    if (!mounted) return;
    final dayStr = newDeadline.day.toString().padLeft(2, '0');
    final monthStr = newDeadline.month.toString().padLeft(2, '0');
    final hourStr = newDeadline.hour.toString().padLeft(2, '0');
    final minuteStr = newDeadline.minute.toString().padLeft(2, '0');
    _showNotification(
      'Đã chuyển lịch "${task.title}" sang $dayStr/$monthStr $hourStr:$minuteStr',
    );
  }

  Future<void> _toggleTaskComplete(StudyTask task) async {
    final newStatus = task.isCompleted ? TaskStatus.todo : TaskStatus.completed;

    // Phase 4.2 - Quy tắc tối thiểu 15 phút học thực tế đã xác nhận trước khi cho phép hoàn thành
    if (newStatus == TaskStatus.completed) {
      final verifiedSecs = _getVerifiedSecondsForTask(task.id);
      if (verifiedSecs < 900) {
        final currentMins = verifiedSecs ~/ 60;
        _showNotification(
          'Công việc cần tối thiểu 15 phút học thực tế để hoàn thành (hiện có $currentMins/15 phút).',
          isError: true,
          actionLabel: 'HỌC NGAY',
          onAction: () => _handleStartStudyWithTask(task),
        );
        return;
      }
    }

    try {
      // 1. Ghi nhận thay đổi xuống repository/database trước
      await _taskRepository.updateTaskStatus(task.id, newStatus);

      // Cập nhật lại lịch sử ngày học (Study Streak) và hoạt động học tập (Statistics)
      final updatedActiveDates = await _taskRepository.getActiveStudyDates();
      final updatedActivities = await _taskRepository.getAllActivities();

      // 2. Chỉ khi ghi SQLite thành công mới cập nhật giao diện
      if (!mounted) return;
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index] = _tasks[index].copyWith(status: newStatus);
        }
        task.status = newStatus;
        _activeDates = updatedActiveDates;
        _activities = updatedActivities;
      });

      // 3. Nếu chuyển sang hoàn thành: Hiển thị thông báo kèm nút "ĐÁNH GIÁ" tiện lợi, không ép buộc
      if (newStatus == TaskStatus.completed) {
        unawaited(_notificationCoordinator.cancelTaskDeadline(task.id));
        _showNotification(
          kIsWeb
              ? 'Đã hoàn thành! 🎉 (Xem trước Web)'
              : 'Đã hoàn thành công việc 🎉',
          duration: const Duration(seconds: 3),
          actionLabel: 'ĐÁNH GIÁ',
          onAction: () => _openAssessmentDialog(task),
        );
      } else {
        unawaited(
          _notificationCoordinator.scheduleTaskDeadline(
            task.copyWith(status: newStatus),
          ),
        );
        _showNotification('Đã chuyển về Chưa làm');
      }
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi cập nhật trạng thái: $e', isError: true);
    }
  }

  Future<void> _updateTaskAssessment(
    StudyTask task,
    UnderstandingLevel? level,
    String? reviewNotes, [
    int? actualMinutes,
  ]) async {
    try {
      await _taskRepository.updateTaskAssessment(
        task.id,
        level,
        reviewNotes,
        actualMinutes,
      );
      final updatedActivities = await _taskRepository.getAllActivities();
      if (!mounted) return;
      setState(() {
        final index = _tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          _tasks[index] = _tasks[index].copyWith(
            understandingLevel: level,
            clearUnderstandingLevel: level == null,
            reviewNotes: reviewNotes,
            clearReviewNotes: reviewNotes == null,
            actualMinutes: actualMinutes,
            clearActualMinutes: actualMinutes == null,
          );
        }
        task.understandingLevel = level;
        task.reviewNotes = reviewNotes;
        task.actualMinutes = actualMinutes;
        _activities = updatedActivities;
      });
      _showNotification(
        level != null
            ? 'Đã lưu đánh giá: ${level.label}'
            : 'Đã cập nhật đánh giá thành công',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi lưu đánh giá: $e', isError: true);
    }
  }

  void _openAssessmentDialog(StudyTask task) {
    showDialog(
      context: context,
      builder: (context) => TaskAssessmentDialog(
        task: task,
        onSaveWithDuration: (level, reviewNotes, actualMinutes) {
          _updateTaskAssessment(task, level, reviewNotes, actualMinutes);
        },
      ),
    );
  }

  void _openTaskForm({StudyTask? initialTask, String? preselectedSubjectId}) {
    showDialog(
      context: context,
      builder: (context) => TaskFormDialog(
        initialTask: initialTask,
        subjects: _subjects,
        preselectedSubjectId: preselectedSubjectId,
        onSave: (savedTask) {
          if (initialTask == null) {
            _addTask(savedTask);
          } else {
            _updateTask(savedTask);
          }
        },
      ),
    );
  }

  Future<void> _maybeShowRecoveryDialog() async {
    if (!mounted || _isRecoveryDialogOpen || !_timerEngine.hasPendingRecovery) {
      return;
    }
    _isRecoveryDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => StudyRecoveryDialog(timerEngine: _timerEngine),
      );
    } finally {
      _isRecoveryDialogOpen = false;
    }
  }

  Future<void> _openStudyTimer({
    Subject? initialSubject,
    StudyTask? initialTask,
  }) async {
    if (_timerEngine.hasPendingRecovery) {
      await _maybeShowRecoveryDialog();
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StudyTimerScreen(
          timerEngine: _timerEngine,
          subjects: _subjects,
          tasks: _tasks,
          userProfile: _userProfile,
          initialSubject: initialSubject,
          initialTask: initialTask,
          onRequestRecovery: _maybeShowRecoveryDialog,
        ),
      ),
    );
  }

  void _openTaskDetail(StudyTask task) {
    final matchingSubject = _subjects
        .where(
          (s) =>
              (task.subjectId.isNotEmpty && s.id == task.subjectId) ||
              s.name == task.subject,
        )
        .firstOrNull;
    final verifiedSeconds = _getVerifiedSecondsForTask(task.id);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => TaskDetailSheet(
        task: task,
        accumulatedStudySeconds: verifiedSeconds,
        onToggleComplete: () => _toggleTaskComplete(task),
        onEdit: () => _openTaskForm(initialTask: task),
        onDelete: () => _deleteTask(task),
        onAssess: () => _openAssessmentDialog(task),
        onStartTimer: () =>
            _openStudyTimer(initialSubject: matchingSubject, initialTask: task),
        onStartStudy: () => _handleStartStudyWithTask(task),
        onReschedule: () => _handleRescheduleTask(task),
      ),
    );
  }

  // --- CÁC HÀM XỬ LÝ NGHIỆP VỤ CRUD MÔN HỌC (SUBJECT) ---

  Future<void> _addSubject(Subject newSubject) async {
    try {
      await _subjectRepository.insertSubject(newSubject);
      if (!mounted) return;
      setState(() {
        _subjects.add(newSubject);
      });
      _showNotification(
        kIsWeb
            ? 'Đã thêm môn: "${newSubject.name}" (Xem trước Web)'
            : 'Đã thêm và lưu môn: "${newSubject.name}"',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi thêm môn học: $e', isError: true);
    }
  }

  Future<void> _updateSubject(Subject updatedSubject) async {
    try {
      await _subjectRepository.updateSubject(updatedSubject);
      await _taskRepository.updateTasksSubjectName(
        updatedSubject.id,
        updatedSubject.name,
      );

      if (!mounted) return;
      setState(() {
        final subIndex = _subjects.indexWhere((s) => s.id == updatedSubject.id);
        if (subIndex != -1) {
          _subjects[subIndex] = updatedSubject;
        }
        for (final t in _tasks) {
          if (t.subjectId == updatedSubject.id) {
            t.subject = updatedSubject.name;
          }
        }
      });

      _showNotification(
        kIsWeb
            ? 'Đã cập nhật môn: "${updatedSubject.name}" (Xem trước Web)'
            : 'Đã cập nhật môn: "${updatedSubject.name}"',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi cập nhật môn học: $e', isError: true);
    }
  }

  Future<void> _deleteSubject(
    String subjectId, {
    String? migrateToSubjectId,
  }) async {
    try {
      // 1. Nếu có môn đích để chuyển giao nhiệm vụ
      if (migrateToSubjectId != null && migrateToSubjectId.isNotEmpty) {
        final targetSub = _subjects.firstWhere(
          (s) => s.id == migrateToSubjectId,
        );
        await _taskRepository.migrateTasksSubject(
          subjectId,
          migrateToSubjectId,
          targetSub.name,
        );
      }

      // 2. Xóa môn học trong repository (SQLite ON DELETE SET NULL giữ nguyên lịch sử session)
      await _subjectRepository.deleteSubject(subjectId);
      await _sessionRepository.detachSubjectForWeb(subjectId);

      // 3. Tải lại toàn bộ dữ liệu để cập nhật đồng bộ UI
      await _loadData();

      if (!mounted) return;
      _showNotification(
        migrateToSubjectId != null
            ? 'Đã chuyển toàn bộ nhiệm vụ và xóa môn học thành công.'
            : 'Đã xóa môn học thành công.',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi xóa môn học: $e', isError: true);
    }
  }

  // --- CÔNG CỤ QUẢN LÝ HỒ SƠ, MỤC TIÊU VÀ CÀI ĐẶT (G5) ---

  Future<void> _updateProfile(UserProfile newProfile) async {
    try {
      await _profileRepository.saveProfile(newProfile);
      if (!mounted) return;
      setState(() {
        _userProfile = newProfile;
      });
      _showNotification('Đã cập nhật hồ sơ cá nhân thành công');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi lưu hồ sơ: $e', isError: true);
    }
  }

  Future<void> _updateGoals(double hours, int tasks) async {
    try {
      final updated = await _profileRepository.updateWeeklyGoals(
        hours: hours,
        tasks: tasks,
      );
      if (!mounted) return;
      setState(() {
        _userProfile = updated;
      });
      _showNotification('Đã lưu mục tiêu học tập tuần này');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi lưu mục tiêu: $e', isError: true);
    }
  }

  Future<void> _updateThemeMode(String mode) async {
    try {
      final updated = await _profileRepository.updateThemeMode(mode);
      if (!mounted) return;
      setState(() {
        _userProfile = updated;
      });
      widget.onThemeModeChanged?.call(updated.flutterThemeMode);
      _showNotification(
        'Đã chuyển giao diện: ${mode == 'light'
            ? 'Sáng'
            : mode == 'dark'
            ? 'Tối'
            : 'Theo hệ thống'}',
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi đổi giao diện: $e', isError: true);
    }
  }

  Future<void> _updateReminderEnabled(bool enabled) async {
    try {
      final updated = await _profileRepository.updateReminderEnabled(enabled);
      await _notificationCoordinator.applyProfile(
        updated,
        promptPermissionIfEnabling: enabled,
      );
      if (!mounted) return;
      setState(() {
        _userProfile = updated;
      });
      if (!enabled) {
        _showNotification('Đã tắt thông báo và hủy các lịch nhắc chờ');
      } else if (_notificationCoordinator
          .permissionStatus
          .notificationsGranted) {
        _showNotification('Đã bật hệ thống thông báo học tập');
      } else {
        _showNotification(
          'Đã lưu tùy chọn bật thông báo, nhưng thiết bị chưa cấp quyền thông báo.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi cập nhật thông báo: $e', isError: true);
    }
  }

  Future<void> _updateNotificationPrefs({
    String? alarmSoundId,
    String? breakSoundId,
    int? preReminderMinutes,
    bool? notifyPreStudy,
    bool? notifyAlarmOnTime,
    bool? notifySessionStart,
    bool? notifyBreakStart,
    bool? notifyBreakEnd,
  }) async {
    try {
      final updated = await _profileRepository.updateStudyPreferences(
        alarmSoundId: alarmSoundId,
        breakSoundId: breakSoundId,
        preReminderMinutes: preReminderMinutes,
        notifyPreStudy: notifyPreStudy,
        notifyAlarmOnTime: notifyAlarmOnTime,
        notifySessionStart: notifySessionStart,
        notifyBreakStart: notifyBreakStart,
        notifyBreakEnd: notifyBreakEnd,
      );
      await _notificationCoordinator.applyProfile(
        updated,
        promptPermissionIfEnabling: false,
      );
      if (!mounted) return;
      setState(() {
        _userProfile = updated;
      });
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi lưu cài đặt thông báo: $e', isError: true);
    }
  }

  Future<void> _resetStudyData() async {
    try {
      await _timerEngine.resetStateForDataClear();
      await _taskRepository.clearAllTasks();
      await _sessionRepository.clearAllSessions();
      await _loadData();
      await _notificationCoordinator.syncAfterRestoreOrReset(_userProfile);
      if (!mounted) return;
      _showNotification('Đã xóa toàn bộ công việc và lịch sử học tập');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi đặt lại dữ liệu học tập: $e', isError: true);
    }
  }

  Future<void> _resetProfile() async {
    try {
      await _profileRepository.resetProfile();
      const reset = UserProfile();
      await _notificationCoordinator.syncAfterRestoreOrReset(reset);
      if (!mounted) return;
      setState(() {
        _userProfile = reset;
      });
      widget.onThemeModeChanged?.call(ThemeMode.system);
      _showNotification('Đã đặt lại hồ sơ cá nhân về mặc định');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi đặt lại hồ sơ: $e', isError: true);
    }
  }

  Future<void> _resetAllData() async {
    try {
      await _timerEngine.resetStateForDataClear();
      await _taskRepository.clearAllTasks();
      await _sessionRepository.clearAllSessions();
      await _profileRepository.resetProfile();
      await _subjectRepository.resetDefaultSubjects(
        SubjectRepository.getDefaultSubjects(),
      );
      await _loadData();
      await _notificationCoordinator.syncAfterRestoreOrReset(_userProfile);
      if (!mounted) return;
      widget.onThemeModeChanged?.call(ThemeMode.system);
      _showNotification('Đã khôi phục toàn bộ ứng dụng về mặc định');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi khôi phục toàn bộ: $e', isError: true);
    }
  }

  // --- CÔNG CỤ SAO LƯU VÀ KHÔI PHỤC DỮ LIỆU (G8.7) ---

  Future<void> _handleBackupData() async {
    try {
      final backupMap = await _backupService.createBackupData();
      final jsonString = _backupService.exportBackupJson(backupMap);
      final savedPath = await _backupService.saveBackupToFile(jsonString);

      if (!mounted) return;
      setState(() {
        _lastBackupTime = BackupService.lastBackupTime;
      });

      showDialog(
        context: context,
        builder: (ctx) => BackupSuccessDialog(
          backupMap: backupMap,
          jsonString: jsonString,
          filePath: savedPath,
          backupService: _backupService,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi sao lưu dữ liệu: $e', isError: true);
    }
  }

  Future<void> _handleRestoreData() async {
    showDialog(
      context: context,
      builder: (dialogCtx) => RestoreInputDialog(
        backupService: _backupService,
        onValidBackup: (validationResult) {
          final preview = validationResult.preview;
          final backupMap = validationResult.backupMap;
          if (preview == null || backupMap == null) return;

          showDialog(
            context: context,
            builder: (previewCtx) => RestorePreviewDialog(
              preview: preview,
              onConfirmRestore: () async {
                try {
                  await _timerEngine.resetStateForDataClear();
                  await _backupService.restoreBackup(backupMap);
                  _hasCheckedInitialRecovery = false;
                  await _loadData();
                  await _notificationCoordinator.syncAfterRestoreOrReset(
                    _userProfile,
                  );
                  if (!mounted) return;
                  setState(() {
                    _lastBackupTime = BackupService.lastBackupTime;
                  });
                  widget.onThemeModeChanged?.call(
                    _userProfile.flutterThemeMode,
                  );
                  _showNotification(
                    'Khôi phục dữ liệu thành công! Đã nạp ${preview.totalSubjects} môn học và ${preview.totalTasks} công việc.',
                  );
                } catch (e) {
                  if (!mounted) return;
                  _showNotification(
                    'Lỗi khi khôi phục dữ liệu: $e',
                    isError: true,
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }

  // --- CÔNG CỤ DỌN DẸP / KHÔI PHỤC DỮ LIỆU ---

  Future<void> _resetSampleData() async {
    try {
      final sampleSubjects = SubjectRepository.getDefaultSubjects();
      final sampleTasks = _getSampleTasks();
      await _subjectRepository.resetDefaultSubjects(sampleSubjects);
      await _taskRepository.resetSampleTasks(sampleTasks);
      await _loadData();
      if (!mounted) return;
      _showNotification('Đã khôi phục dữ liệu mẫu thành công');
    } catch (e) {
      if (!mounted) return;
      _showNotification('Lỗi khi khôi phục dữ liệu mẫu: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_rounded, color: AppColors.primary, size: 24),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'ExamPilot',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () {
              _showNotification(
                kIsWeb
                    ? 'Chế độ Web Preview: Dữ liệu mẫu chỉ phục vụ xem trước giao diện và không làm thay đổi dữ liệu SQLite trên Android.'
                    : 'Dữ liệu hiện đang được đồng bộ và lưu trữ cục bộ bằng SQLite.',
                duration: const Duration(seconds: 2),
              );
            },
            icon: Icon(
              kIsWeb ? Icons.cloud_done_outlined : Icons.storage_rounded,
              color: AppColors.primary,
            ),
            tooltip: kIsWeb ? 'Chế độ Web Preview' : 'Trạng thái CSDL',
          ),
          IconButton(
            onPressed: () {
              unawaited(_notificationCoordinator.audioGateway.stopPreview());
              setState(() => _selectedIndex = 4);
              final perm = _notificationCoordinator.permissionStatus;
              if (!_userProfile.reminderEnabled) {
                _showNotification(
                  'Thông báo đang tắt. Bạn có thể bật trong mục Cá nhân.',
                );
              } else if (!perm.notificationsGranted) {
                _showNotification(
                  'Cần cấp quyền thông báo hệ thống để nhận nhắc học.',
                );
              } else {
                _showNotification(
                  'Hệ thống thông báo phiên học & nghỉ giữa giờ đang sẵn sàng.',
                );
              }
            },
            icon: Icon(
              _userProfile.reminderEnabled &&
                      _notificationCoordinator
                          .permissionStatus
                          .notificationsGranted
                  ? Icons.notifications_active_outlined
                  : Icons.notifications_none_rounded,
            ),
            tooltip: 'Cài đặt thông báo',
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          ActiveAlarmBanner(
            alarmStateManager: _notificationCoordinator.alarmStateManager,
          ),
          // Banner thông báo rõ ràng khi chạy trên nền tảng Web
          if (kIsWeb)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              decoration: BoxDecoration(
                color: context.primaryContainerColor,
                border: Border(
                  bottom: BorderSide(color: context.borderColor, width: 0.8),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: context.onPrimaryContainerColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bản xem trước Web: Dữ liệu chỉ phục vụ preview giao diện, không ghi đè dữ liệu SQLite trên Android.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.onPrimaryContainerColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
      floatingActionButton:
          (!_isLoading && (_selectedIndex == 0 || _selectedIndex == 1))
          ? FloatingActionButton.extended(
              onPressed: () => _openTaskForm(),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add, size: 20),
              label: const Text(
                'Thêm việc',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : null,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingMiniTimerBar(
            timerEngine: _timerEngine,
            onTap: () => _openStudyTimer(),
          ),
          Container(
            decoration: BoxDecoration(
              color: context.surfaceColor,
              border: Border(
                top: BorderSide(color: context.borderColor, width: 1),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                if (_selectedIndex == 4 && index != 4) {
                  unawaited(
                    _notificationCoordinator.audioGateway.stopPreview(),
                  );
                }
                setState(() => _selectedIndex = index);
              },
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Tổng quan',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_month_outlined),
                  selectedIcon: Icon(Icons.calendar_month_rounded),
                  label: 'Kế hoạch',
                ),
                NavigationDestination(
                  icon: Icon(Icons.menu_book_outlined),
                  selectedIcon: Icon(Icons.menu_book_rounded),
                  label: 'Môn học',
                ),
                NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart_rounded),
                  label: 'Thống kê',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline_rounded),
                  selectedIcon: Icon(Icons.person_rounded),
                  label: 'Cá nhân',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              kIsWeb
                  ? 'Đang nạp dữ liệu xem trước Web...'
                  : 'Đang tải dữ liệu từ SQLite...',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.error,
                size: 52,
              ),
              const SizedBox(height: 14),
              const Text(
                'Lỗi truy xuất cơ sở dữ liệu',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _errorMessage = null;
                      });
                      _loadData();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Thử lại'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _subjects = SubjectRepository.getDefaultSubjects();
                        _tasks = _getSampleTasks();
                        _errorMessage = null;
                        _isLoading = false;
                      });
                    },
                    icon: const Icon(Icons.preview_rounded),
                    label: const Text('Tiếp tục với dữ liệu mẫu'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    final pages = [
      OverviewScreen(
        tasks: _tasks,
        studyStreak: StudyStreak.fromSessions(_sessions),
        legacyActiveDatesCount: _activeDates.length,
        userProfile: _userProfile,
        sessions: _sessions,
        timerEngine: _timerEngine,
        onOpenTimer: () => _openStudyTimer(),
        onToggleComplete: _toggleTaskComplete,
        onTapTask: _openTaskDetail,
        onEditTask: (task) => _openTaskForm(initialTask: task),
        onDeleteTask: _deleteTask,
        onAddTask: () => _openTaskForm(),
        onGoToPlan: () => setState(() => _selectedIndex = 1),
        onGoToSubjects: () => setState(() => _selectedIndex = 2),
        onGoToProfile: () => setState(() => _selectedIndex = 4),
        onStartStudy: _handleStartStudyWithTask,
        onReschedule: _handleRescheduleTask,
      ),
      PlanScreen(
        tasks: _tasks,
        subjects: _subjects,
        sessions: _sessions,
        schedules: _schedules,
        onToggleComplete: _toggleTaskComplete,
        onTapTask: _openTaskDetail,
        onEditTask: (task) => _openTaskForm(initialTask: task),
        onDeleteTask: _deleteTask,
        onAddTask: () => _openTaskForm(),
        onStartStudy: _handleStartStudyWithTask,
        onReschedule: _handleRescheduleTask,
        onAddSchedule: _addSchedule,
        onEditSchedule: _updateSchedule,
        onDeleteSchedule: _deleteSchedule,
        onToggleScheduleActive: _toggleScheduleActive,
        onImportSchedules: _handleImportSchedules,
      ),
      SubjectsScreen(
        subjects: _subjects,
        tasks: _tasks,
        sessions: _sessions,
        onAddSubject: _addSubject,
        onUpdateSubject: _updateSubject,
        onDeleteSubject: _deleteSubject,
        onToggleCompleteTask: _toggleTaskComplete,
        onTapTask: _openTaskDetail,
        onEditTask: (task) => _openTaskForm(initialTask: task),
        onDeleteTask: _deleteTask,
        onAddTaskForSubject: (subject) =>
            _openTaskForm(preselectedSubjectId: subject.id),
        onStartTimerForSubject: (subject) =>
            _openStudyTimer(initialSubject: subject),
        onStartStudyTask: _handleStartStudyWithTask,
        onRescheduleTask: _handleRescheduleTask,
      ),
      StatisticsScreen(
        tasks: _tasks,
        subjects: _subjects,
        activities: _activities,
      ),
      AnimatedBuilder(
        animation: _notificationCoordinator,
        builder: (context, _) => ProfileScreen(
          profile: _userProfile,
          activities: _activities,
          lastBackupTime: _lastBackupTime,
          onBackupData: _handleBackupData,
          onRestoreData: _handleRestoreData,
          onUpdateProfile: _updateProfile,
          onUpdateGoals: _updateGoals,
          onUpdateThemeMode: _updateThemeMode,
          onUpdateReminderEnabled: _updateReminderEnabled,
          onUpdateNotificationPrefs: _updateNotificationPrefs,
          permissionStatus: _notificationCoordinator.permissionStatus,
          onRequestNotificationPermission: () async {
            await _notificationCoordinator.requestNotificationPermission();
          },
          onRequestExactAlarmPermission: () async {
            await _notificationCoordinator.requestExactAlarmPermission();
          },
          onOpenSystemSettings: () async {
            await _notificationCoordinator.openSystemNotificationSettings();
          },
          audioGateway: _notificationCoordinator.audioGateway,
          hasValidScheduleSource: false,
          onScheduleTestAlarm: () => _notificationCoordinator.scheduleTestAlarm(),
          onResetStudyData: _resetStudyData,
          onResetProfile: _resetProfile,
          onResetSampleData: _resetSampleData,
          onResetAllData: _resetAllData,
        ),
      ),
    ];

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: IndexedStack(index: _selectedIndex, children: pages),
      ),
    );
  }
}

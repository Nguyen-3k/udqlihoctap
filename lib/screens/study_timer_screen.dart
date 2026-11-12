import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/study_session.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../models/user_profile.dart';
import '../services/study_timer_engine.dart';
import '../theme/app_colors.dart';
import '../widgets/study_recovery_dialog.dart';
import '../widgets/study_timer_formatters.dart';

enum _StartMode { bySubject, byTask }

/// Màn hình Study Timer chính thức của ExamPilot (Phase 3).
/// - Chỉ kết nối với Singleton [StudyTimerEngine], tuyệt đối không khởi tạo Engine mới hoặc tự đếm thời gian.
/// - Đóng màn hình không làm dừng hoặc hủy phiên học; chỉ các thao tác điều khiển mới thay đổi trạng thái Engine.
/// - Hỗ trợ Light/Dark Mode và responsive an toàn từ màn hình hẹp 320dp trở lên.
class StudyTimerScreen extends StatefulWidget {
  final StudyTimerEngine timerEngine;
  final List<Subject> subjects;
  final List<StudyTask> tasks;
  final UserProfile userProfile;
  final Subject? initialSubject;
  final StudyTask? initialTask;
  final VoidCallback? onRequestRecovery;

  const StudyTimerScreen({
    super.key,
    required this.timerEngine,
    required this.subjects,
    required this.tasks,
    this.userProfile = const UserProfile(),
    this.initialSubject,
    this.initialTask,
    this.onRequestRecovery,
  });

  @override
  State<StudyTimerScreen> createState() => _StudyTimerScreenState();
}

class _StudyTimerScreenState extends State<StudyTimerScreen> {
  static const List<int> _quickPlannedStudyOptions = [25, 45, 60, 90];

  late _StartMode _startMode;
  Subject? _selectedSubject;
  StudyTask? _selectedTask;
  String _selectedBreakPresetId = 'pomodoro_25_5';
  int _plannedStudyMinutes = 25;
  int _plannedBreakMinutes = 5;
  bool _isCustomPlannedDuration = false;
  bool _isSubmitting = false;

  final TextEditingController _taskSearchController = TextEditingController();
  final TextEditingController _customStudyController = TextEditingController();
  final TextEditingController _customBreakController = TextEditingController();
  String _taskSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _initDefaults();
  }

  @override
  void dispose() {
    _taskSearchController.dispose();
    _customStudyController.dispose();
    _customBreakController.dispose();
    super.dispose();
  }

  List<StudyTask> get _validSelectableTasks {
    return widget.tasks
        .where((t) => t.id.trim().isNotEmpty && t.title.trim().isNotEmpty)
        .toList();
  }

  void _initDefaults() {
    final defaultPreset = StudyBreakPreset.resolveDefaultFromProfile(
      widget.userProfile,
    );
    _selectedBreakPresetId = defaultPreset.id;
    _plannedStudyMinutes = defaultPreset.studyMinutes;
    _plannedBreakMinutes = defaultPreset.breakMinutes;
    _customStudyController.text = '${widget.userProfile.customStudyMinutes}';
    _customBreakController.text = '${widget.userProfile.customBreakMinutes}';

    // Chỉ chấp nhận initialTask nếu công việc còn tồn tại hợp lệ trong danh sách hiện tại
    final liveTasks = _validSelectableTasks;
    StudyTask? validInitialTask;
    if (widget.initialTask != null) {
      validInitialTask = liveTasks
          .where((t) => t.id == widget.initialTask!.id)
          .firstOrNull;
    }

    if (validInitialTask != null) {
      _startMode = _StartMode.byTask;
      _selectedTask = validInitialTask;
      _selectedSubject = _resolveSubjectForTask(validInitialTask);
    } else {
      _startMode = _StartMode.bySubject;
      _selectedSubject = _resolveInitialSubject();
    }
  }

  Subject? _resolveInitialSubject() {
    if (widget.initialSubject != null) {
      final matched = widget.subjects
          .where((s) => s.id == widget.initialSubject!.id)
          .firstOrNull;
      if (matched != null) return matched;
      return widget.initialSubject;
    }
    return widget.subjects.isNotEmpty ? widget.subjects.first : null;
  }

  Subject? _resolveSubjectForTask(StudyTask task) {
    final byId = widget.subjects
        .where((s) => task.subjectId.isNotEmpty && s.id == task.subjectId)
        .firstOrNull;
    if (byId != null) return byId;

    final byName = widget.subjects
        .where((s) => s.name.trim() == task.subject.trim())
        .firstOrNull;
    return byName ?? _resolveInitialSubject();
  }

  void _selectPreset(StudyBreakPreset preset) {
    setState(() {
      _selectedBreakPresetId = preset.id;
      _plannedStudyMinutes = preset.studyMinutes;
      _plannedBreakMinutes = preset.breakMinutes;
      _isCustomPlannedDuration = preset.id == 'custom';
      _customStudyController.text = '${preset.studyMinutes}';
      _customBreakController.text = '${preset.breakMinutes}';
    });
  }

  StudySessionMode _resolveSessionMode() {
    switch (_selectedBreakPresetId) {
      case 'pomodoro_25_5':
        return _plannedStudyMinutes == 25 && !_isCustomPlannedDuration
            ? StudySessionMode.pomodoro25_5
            : StudySessionMode.custom;
      case 'deep_50_10':
        return _plannedStudyMinutes == 50 && !_isCustomPlannedDuration
            ? StudySessionMode.deep50_10
            : StudySessionMode.custom;
      case 'long_90_15':
        return _plannedStudyMinutes == 90 && !_isCustomPlannedDuration
            ? StudySessionMode.long90_15
            : StudySessionMode.custom;
      default:
        return StudySessionMode.custom;
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openRecoveryModal() async {
    if (widget.onRequestRecovery != null) {
      widget.onRequestRecovery!();
      return;
    }
    if (!widget.timerEngine.hasPendingRecovery) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StudyRecoveryDialog(timerEngine: widget.timerEngine),
    );
  }

  Future<void> _handleStartSession() async {
    if (_isSubmitting) return;
    if (widget.timerEngine.hasPendingRecovery) {
      await _openRecoveryModal();
      return;
    }

    // Kiểm tra lại nhiệm vụ còn hợp lệ trong danh sách trước khi tạo phiên
    StudyTask? taskToStart;
    Subject? subjectToStart = _selectedSubject;
    if (_startMode == _StartMode.byTask) {
      if (_selectedTask == null) {
        _showSnack('Vui lòng chọn một công việc để bắt đầu.', isError: true);
        return;
      }
      taskToStart = _validSelectableTasks
          .where((t) => t.id == _selectedTask!.id)
          .firstOrNull;
      if (taskToStart == null) {
        setState(() => _selectedTask = null);
        _showSnack('Công việc đã bị xóa hoặc không còn hợp lệ.', isError: true);
        return;
      }
      subjectToStart ??= _resolveSubjectForTask(taskToStart);
    } else if (subjectToStart == null) {
      _showSnack('Vui lòng chọn một môn học để bắt đầu.', isError: true);
      return;
    }

    final safeStudyMins = _plannedStudyMinutes.clamp(1, 360);
    final safeBreakMins = _plannedBreakMinutes.clamp(1, 60);

    setState(() => _isSubmitting = true);
    try {
      await widget.timerEngine.startSession(
        subject: subjectToStart,
        task: taskToStart,
        sessionMode: _resolveSessionMode(),
        plannedStudyMinutes: safeStudyMins,
        plannedBreakMinutes: safeBreakMins,
      );
    } catch (e) {
      _showSnack('Không thể bắt đầu phiên học: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _runEngineAction(
    Future<StudySession> Function() action, {
    String? successMessage,
  }) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    try {
      await action();
      if (successMessage != null) {
        _showSnack(successMessage);
      }
    } catch (e) {
      _showSnack('Không thể thực hiện thao tác: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _confirmCancelSession() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: dialogContext.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Hủy phiên học hiện tại?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: dialogContext.textPrimaryColor,
          ),
        ),
        content: Text(
          'Thời gian của phiên bị hủy sẽ không được tính vào Mục tiêu tuần hay Study Streak.',
          style: TextStyle(
            fontSize: 13,
            color: dialogContext.textSecondaryColor,
            height: 1.4,
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Giữ lại phiên'),
          ),
          FilledButton(
            key: const ValueKey('timer_confirm_cancel_action'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hủy phiên'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _runEngineAction(
        widget.timerEngine.cancelSession,
        successMessage: 'Đã hủy phiên học.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Study Timer')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListenableBuilder(
            listenable: widget.timerEngine,
            builder: (context, _) {
              final engine = widget.timerEngine;
              final session = engine.activeSession;

              if (session == null) {
                return _buildIdleSetupView(context);
              }
              if (session.status == StudySessionStatus.interruptedPending) {
                return _buildPendingRecoveryGateView(context, session);
              }
              return _buildActiveTimerView(context, session);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPendingRecoveryGateView(
    BuildContext context,
    StudySession session,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.priorityMediumBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.priorityMedium,
                  size: 26,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Có phiên học đang chờ xác nhận',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Phiên học "${session.subjectNameSnapshot}" bị gián đoạn cần được bạn xác nhận trước khi bắt đầu phiên mới.',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: const ValueKey('timer_open_recovery_button'),
                onPressed: _openRecoveryModal,
                icon: const Icon(Icons.restore_rounded),
                label: const Text('Xác nhận phiên bị gián đoạn'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleSetupView(BuildContext context) {
    final customPreset = StudyBreakPreset.customFromProfile(widget.userProfile);
    final allPresets = [...StudyBreakPreset.standardPresets, customPreset];
    final selectableTasks = _validSelectableTasks.where((t) {
      final q = _taskSearchQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      return t.title.toLowerCase().contains(q) ||
          t.subject.toLowerCase().contains(q);
    }).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Chuyển đổi chế độ Theo môn học / Theo công việc
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.surfaceMutedColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildModeTabButton(
                    context,
                    key: const ValueKey('timer_mode_subject_tab'),
                    label: 'Theo môn học',
                    icon: Icons.menu_book_rounded,
                    selected: _startMode == _StartMode.bySubject,
                    onTap: () =>
                        setState(() => _startMode = _StartMode.bySubject),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: _buildModeTabButton(
                    context,
                    key: const ValueKey('timer_mode_task_tab'),
                    label: 'Theo công việc',
                    icon: Icons.task_alt_rounded,
                    selected: _startMode == _StartMode.byTask,
                    onTap: () => setState(() => _startMode = _StartMode.byTask),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 2. Chọn môn học hoặc công việc
          if (_startMode == _StartMode.bySubject) ...[
            Text(
              'Chọn môn học',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),
            if (widget.subjects.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  'Chưa có môn học nào. Hãy thêm môn học trong tab Môn học trước khi bắt đầu.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                  ),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: widget.subjects.map((subject) {
                  final isSelected = _selectedSubject?.id == subject.id;
                  return ChoiceChip(
                    key: ValueKey('timer_subject_chip_${subject.id}'),
                    selected: isSelected,
                    onSelected: (_) =>
                        setState(() => _selectedSubject = subject),
                    avatar: CircleAvatar(
                      backgroundColor: subject.color.withValues(alpha: 0.16),
                      child: Icon(subject.icon, size: 14, color: subject.color),
                    ),
                    label: Text(subject.name, overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
              ),
          ] else ...[
            Text(
              'Chọn công việc để học',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('timer_task_search_field'),
              controller: _taskSearchController,
              decoration: InputDecoration(
                hintText: 'Tìm kiếm công việc theo tên hoặc môn...',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                suffixIcon: _taskSearchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _taskSearchController.clear();
                          setState(() => _taskSearchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _taskSearchQuery = v),
            ),
            const SizedBox(height: 10),
            if (selectableTasks.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.surfaceColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: context.borderColor),
                ),
                child: Text(
                  _validSelectableTasks.isEmpty
                      ? 'Chưa có công việc nào. Bạn vẫn có thể chuyển sang tab Theo môn học để bắt đầu ngay.'
                      : 'Không tìm thấy công việc phù hợp.',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: selectableTasks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final task = selectableTasks[index];
                    final isSelected = _selectedTask?.id == task.id;
                    return InkWell(
                      key: ValueKey('timer_task_option_${task.id}'),
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          _selectedTask = task;
                          _selectedSubject = _resolveSubjectForTask(task);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? context.primaryContainerColor
                              : context.surfaceColor,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : context.borderColor,
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 18,
                                  color: isSelected
                                      ? AppColors.primary
                                      : context.textSecondaryColor,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    task.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: context.textPrimaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                _buildMiniBadge(
                                  context,
                                  task.subject,
                                  AppColors.primary,
                                ),
                                _buildMiniBadge(
                                  context,
                                  task.priority.label,
                                  task.priority.color,
                                ),
                                _buildMiniBadge(
                                  context,
                                  task.status.label,
                                  task.status.color,
                                ),
                                if (task.deadline != null)
                                  _buildMiniBadge(
                                    context,
                                    'Hạn: ${formatSessionLocalTimestamp(task.deadline!)}',
                                    task.isOverdue
                                        ? AppColors.error
                                        : context.textSecondaryColor,
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],

          const SizedBox(height: 18),

          // 3. Chu kỳ học / nghỉ & Thời gian dự kiến tham khảo
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Chu kỳ học & nghỉ',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: allPresets.map((preset) {
                    final isSelected = _selectedBreakPresetId == preset.id;
                    return ChoiceChip(
                      key: ValueKey('timer_preset_${preset.id}'),
                      selected: isSelected,
                      onSelected: (_) => _selectPreset(preset),
                      label: Text(
                        '${preset.label} (${preset.studyMinutes}/${preset.breakMinutes})',
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 14),
                Text(
                  'Thời gian học dự kiến (tham khảo)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._quickPlannedStudyOptions.map((mins) {
                      final isSelected =
                          !_isCustomPlannedDuration &&
                          _plannedStudyMinutes == mins;
                      return ChoiceChip(
                        key: ValueKey('timer_planned_minutes_$mins'),
                        selected: isSelected,
                        onSelected: (_) {
                          setState(() {
                            _isCustomPlannedDuration = false;
                            _plannedStudyMinutes = mins;
                            _customStudyController.text = '$mins';
                          });
                        },
                        label: Text('$mins phút'),
                      );
                    }),
                    ChoiceChip(
                      key: const ValueKey('timer_planned_minutes_custom'),
                      selected: _isCustomPlannedDuration,
                      onSelected: (_) {
                        setState(() {
                          _isCustomPlannedDuration = true;
                          _selectedBreakPresetId = 'custom';
                        });
                      },
                      label: const Text('Tùy chỉnh'),
                    ),
                  ],
                ),

                if (_isCustomPlannedDuration) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const ValueKey('timer_custom_study_field'),
                          controller: _customStudyController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Học (phút)',
                            isDense: true,
                          ),
                          onChanged: (raw) {
                            final parsed = int.tryParse(raw.trim());
                            if (parsed != null && parsed > 0) {
                              setState(
                                () =>
                                    _plannedStudyMinutes = parsed.clamp(1, 360),
                              );
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('timer_custom_break_field'),
                          controller: _customBreakController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Nghỉ (phút)',
                            isDense: true,
                          ),
                          onChanged: (raw) {
                            final parsed = int.tryParse(raw.trim());
                            if (parsed != null && parsed > 0) {
                              setState(
                                () =>
                                    _plannedBreakMinutes = parsed.clamp(1, 60),
                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 10),
                Text(
                  'Thời gian dự kiến chỉ để tham khảo, đồng hồ sẽ không tự dừng hay tự hoàn thành phiên khi hết giờ.',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 4. Nút Bắt đầu lớn (>= 48dp)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton.icon(
              key: const ValueKey('timer_start_button'),
              onPressed: _isSubmitting ? null : _handleStartSession,
              icon: const Icon(Icons.play_arrow_rounded, size: 24),
              label: const Text(
                'Bắt đầu phiên học',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTimerView(BuildContext context, StudySession session) {
    final subjectColor = session.subjectColorSnapshot != null
        ? Color(session.subjectColorSnapshot!)
        : AppColors.primary;
    final statusColor = sessionStatusColor(session.status);
    final isRunning = session.status == StudySessionStatus.running;
    final isPaused = session.status == StudySessionStatus.paused;
    final isInBreak = session.status == StudySessionStatus.inBreak;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 1. Khu vực thông tin môn học / công việc & trạng thái
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 12,
                  height: 44,
                  decoration: BoxDecoration(
                    color: subjectColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.subjectNameSnapshot,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      if (session.taskTitleSnapshot != null &&
                          session.taskTitleSnapshot!.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          session.taskTitleSnapshot!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: context.textSecondaryColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  key: const ValueKey('timer_status_badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    sessionStatusLabel(session.status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // 2. Khu vực đồng hồ - chỉ bọc ListenableBuilder quanh phần hiển thị số
          ListenableBuilder(
            listenable: Listenable.merge([
              widget.timerEngine,
              widget.timerEngine.uiTickListenable,
            ]),
            builder: (context, _) {
              final engine = widget.timerEngine;
              final studySeconds = engine.getCurrentElapsedSeconds();
              final totalBreakSeconds = engine.getCurrentBreakSeconds();
              final activeBreakSeconds = engine.getCurrentActiveBreakSeconds();

              final int dialSeconds = isInBreak
                  ? activeBreakSeconds
                  : studySeconds;
              final double ringProgress;
              if (isInBreak) {
                ringProgress = session.plannedBreakMinutes > 0
                    ? (activeBreakSeconds / (session.plannedBreakMinutes * 60))
                          .clamp(0.0, 1.0)
                    : 1.0;
              } else if (session.plannedStudyMinutes > 0) {
                ringProgress =
                    (studySeconds / (session.plannedStudyMinutes * 60)).clamp(
                      0.0,
                      1.0,
                    );
              } else {
                ringProgress = 0.0;
              }

              final dialSize = MediaQuery.of(context).size.width < 350
                  ? 184.0
                  : 216.0;

              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 22,
                    ),
                    decoration: BoxDecoration(
                      color: context.surfaceColor,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        SizedBox(
                          width: dialSize,
                          height: dialSize,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              CircularProgressIndicator(
                                value: ringProgress,
                                strokeWidth: 10,
                                backgroundColor: context.surfaceMutedColor,
                                color: statusColor,
                              ),
                              Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      isInBreak
                                          ? 'THỜI GIAN NGHỈ'
                                          : 'THỜI GIAN HỌC',
                                      style: TextStyle(
                                        fontSize: 11,
                                        letterSpacing: 0.8,
                                        fontWeight: FontWeight.w700,
                                        color: context.textSecondaryColor,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      formatTimerDuration(dialSeconds),
                                      key: const ValueKey('timer_main_readout'),
                                      style: TextStyle(
                                        fontSize: dialSize < 200 ? 32 : 38,
                                        fontWeight: FontWeight.bold,
                                        color: context.textPrimaryColor,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      sessionStatusLabel(session.status),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: statusColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Thông tin tách biệt giữa thời gian học và thời gian nghỉ
                        if (isInBreak) ...[
                          Container(
                            key: const ValueKey('timer_break_study_summary'),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: context.surfaceMutedColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.school_outlined,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    'Thời gian học đã chốt: ${formatTimerDuration(studySeconds)} (không tăng khi nghỉ)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: context.textPrimaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (engine.hasReachedPlannedBreakDuration) ...[
                            const SizedBox(height: 10),
                            Container(
                              key: const ValueKey(
                                'break_planned_reached_banner',
                              ),
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.statusCompletedBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Đã hết ${session.plannedBreakMinutes} phút nghỉ dự kiến. Nhấn "Tiếp tục học" khi bạn sẵn sàng.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.statusCompleted,
                                ),
                              ),
                            ),
                          ] else if (session.plannedBreakMinutes > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Nghỉ dự kiến: ${session.plannedBreakMinutes} phút • Có thể kết thúc nghỉ sớm bất kỳ lúc nào.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondaryColor,
                              ),
                            ),
                          ],
                        ] else ...[
                          if (session.plannedStudyMinutes > 0)
                            Text(
                              engine.hasReachedPlannedStudyDuration
                                  ? 'Đã đạt mục tiêu tham khảo ${session.plannedStudyMinutes} phút — đồng hồ vẫn tiếp tục đếm để bạn học trọn vẹn.'
                                  : 'Mục tiêu tham khảo: ${session.plannedStudyMinutes} phút (không tự dừng khi hết giờ)',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    engine.hasReachedPlannedStudyDuration
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                                color: engine.hasReachedPlannedStudyDuration
                                    ? AppColors.success
                                    : context.textSecondaryColor,
                              ),
                            ),
                          if (totalBreakSeconds > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Đã nghỉ giải lao: ${formatTimerDuration(totalBreakSeconds)} (tách riêng khỏi giờ học)',
                              key: const ValueKey('timer_study_break_summary'),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: context.textSecondaryColor,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),

          // 3. Khu vực điều khiển tương ứng đúng trạng thái
          if (isRunning) ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      key: const ValueKey('timer_pause_button'),
                      onPressed: _isSubmitting
                          ? null
                          : () => _runEngineAction(
                              widget.timerEngine.pauseSession,
                            ),
                      icon: const Icon(Icons.pause_rounded),
                      label: const Text('Tạm dừng'),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('timer_start_break_button'),
                      onPressed: _isSubmitting
                          ? null
                          : () => _runEngineAction(
                              () => widget.timerEngine.startBreak(),
                            ),
                      icon: const Icon(Icons.coffee_outlined),
                      label: const Text('Bắt đầu nghỉ'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: const ValueKey('timer_complete_button'),
                onPressed: _isSubmitting
                    ? null
                    : () => _runEngineAction(
                        widget.timerEngine.completeSession,
                        successMessage:
                            'Đã hoàn thành phiên học và cập nhật tiến độ!',
                      ),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Kết thúc phiên'),
              ),
            ),
          ] else if (isPaused) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: const ValueKey('timer_resume_button'),
                onPressed: _isSubmitting
                    ? null
                    : () => _runEngineAction(widget.timerEngine.resumeSession),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Tiếp tục học'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                key: const ValueKey('timer_complete_button'),
                onPressed: _isSubmitting
                    ? null
                    : () => _runEngineAction(
                        widget.timerEngine.completeSession,
                        successMessage:
                            'Đã hoàn thành phiên học và cập nhật tiến độ!',
                      ),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Kết thúc phiên'),
              ),
            ),
          ] else if (isInBreak) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: const ValueKey('timer_end_break_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                onPressed: _isSubmitting
                    ? null
                    : () => _runEngineAction(widget.timerEngine.endBreak),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Tiếp tục học'),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                key: const ValueKey('timer_complete_button'),
                onPressed: _isSubmitting
                    ? null
                    : () => _runEngineAction(
                        widget.timerEngine.completeSession,
                        successMessage:
                            'Đã hoàn thành phiên học và cập nhật tiến độ!',
                      ),
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Kết thúc phiên'),
              ),
            ),
          ],

          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: TextButton.icon(
              key: const ValueKey('timer_cancel_button'),
              onPressed: _isSubmitting ? null : _confirmCancelSession,
              style: TextButton.styleFrom(foregroundColor: AppColors.error),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Hủy phiên'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTabButton(
    BuildContext context, {
    required Key key,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      key: key,
      color: selected ? context.surfaceColor : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? AppColors.primary
                    : context.textSecondaryColor,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected
                        ? AppColors.primary
                        : context.textSecondaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniBadge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

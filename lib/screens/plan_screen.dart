import 'package:flutter/material.dart';
import '../models/class_schedule.dart';
import '../models/class_schedule_occurrence.dart';
import '../models/study_session.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../models/task_status.dart';
import '../theme/app_colors.dart';
import '../widgets/schedule_form_dialog.dart';
import '../widgets/task_card.dart';
import '../widgets/timetable_import_dialog.dart';
import '../widgets/image_timetable_import_dialog.dart';

/// Tab chế độ hiển thị trong màn hình Kế hoạch: Công việc hoặc Lịch học tuần
enum PlanTab {
  tasks('Công việc'),
  schedules('Lịch học tuần');

  final String label;
  const PlanTab(this.label);
}

/// Các tùy chọn sắp xếp danh sách công việc trong Kế hoạch học tập (G8.2).
enum TaskSortOption {
  deadlineNearest('Hạn chót gần nhất', Icons.access_time_rounded),
  priorityHighToLow('Ưu tiên cao nhất', Icons.flag_rounded),
  status('Trạng thái công việc', Icons.task_alt_rounded),
  deadlineFurthest('Hạn chót xa nhất', Icons.history_toggle_off_rounded),
  priorityLowToHigh('Ưu tiên thấp nhất', Icons.flag_outlined);

  final String label;
  final IconData icon;
  const TaskSortOption(this.label, this.icon);
}

/// Màn hình Kế hoạch học tập (Quản lý danh sách công việc).
/// Tích hợp đầy đủ: Tìm kiếm theo thời gian thực, Lọc kết hợp (Trạng thái + Môn học),
/// Sắp xếp đa tiêu chí và Trạng thái rỗng trực quan.
class PlanScreen extends StatefulWidget {
  final List<StudyTask> tasks;
  final List<Subject>? subjects;
  final List<StudySession>? sessions;
  final ValueChanged<StudyTask> onToggleComplete;
  final ValueChanged<StudyTask> onTapTask;
  final ValueChanged<StudyTask> onEditTask;
  final ValueChanged<StudyTask> onDeleteTask;
  final VoidCallback onAddTask;
  final ValueChanged<StudyTask>? onStartStudy;
  final ValueChanged<StudyTask>? onReschedule;
  final List<ClassSchedule>? schedules;
  final List<ClassScheduleOccurrence>? occurrences;
  final ValueChanged<ClassSchedule>? onAddSchedule;
  final ValueChanged<ClassSchedule>? onEditSchedule;
  final ValueChanged<ClassSchedule>? onDeleteSchedule;
  final void Function(ClassSchedule schedule, bool isActive)?
  onToggleScheduleActive;
  final Future<void> Function({
    required List<ClassSchedule> schedules,
    required List<Subject> newSubjects,
  })? onImportSchedules;
  final Future<void> Function({
    required List<ClassScheduleOccurrence> occurrences,
    required List<Subject> newSubjects,
  })? onImportOccurrences;

  const PlanScreen({
    super.key,
    required this.tasks,
    this.subjects,
    this.sessions,
    required this.onToggleComplete,
    required this.onTapTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onAddTask,
    this.onStartStudy,
    this.onReschedule,
    this.schedules,
    this.occurrences,
    this.onAddSchedule,
    this.onEditSchedule,
    this.onDeleteSchedule,
    this.onToggleScheduleActive,
    this.onImportSchedules,
    this.onImportOccurrences,
  });

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Tab chế độ xem: Công việc hoặc Lịch học tuần
  PlanTab _selectedTab = PlanTab.tasks;

  // Lọc theo ngày trong tuần của lịch học (null = Tất cả, 1 = T2.. 7 = CN)
  int? _selectedDayOfWeekFilter;

  // Lọc theo trạng thái: null = Tất cả, hoặc TaskStatus cụ thể
  TaskStatus? _filterStatus;

  // Lọc theo môn học: null = Tất cả môn, hoặc subjectId cụ thể
  String? _filterSubjectId;

  // Sắp xếp: Mặc định là hạn chót gần nhất
  TaskSortOption _sortOption = TaskSortOption.deadlineNearest;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _clearAllFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _filterStatus = null;
      _filterSubjectId = null;
    });
  }

  void _openAddScheduleDialog() {
    showDialog(
      context: context,
      builder: (ctx) => ScheduleFormDialog(
        subjects: widget.subjects ?? const [],
        existingSchedules: widget.schedules ?? const [],
        onSave: (newSchedule) {
          widget.onAddSchedule?.call(newSchedule);
        },
      ),
    );
  }

  void _openImportScheduleDialog() {
    showDialog(
      context: context,
      builder: (ctx) => TimetableImportDialog(
        subjects: widget.subjects ?? const [],
        existingSchedules: widget.schedules ?? const [],
        onImport: ({required schedules, required newSubjects}) async {
          if (widget.onImportSchedules != null) {
            await widget.onImportSchedules!(
              schedules: schedules,
              newSubjects: newSubjects,
            );
          }
        },
      ),
    );
  }

  void _openImageImportScheduleDialog() {
    showDialog(
      context: context,
      builder: (ctx) => ImageTimetableImportDialog(
        subjects: widget.subjects ?? const [],
        existingSchedules: widget.schedules ?? const [],
        onImportOccurrences: widget.onImportOccurrences,
        onImport: ({required schedules, required newSubjects}) async {
          if (widget.onImportSchedules != null) {
            await widget.onImportSchedules!(
              schedules: schedules,
              newSubjects: newSubjects,
            );
          }
        },
      ),
    );
  }

  void _openEditScheduleDialog(ClassSchedule schedule) {
    showDialog(
      context: context,
      builder: (ctx) => ScheduleFormDialog(
        initialSchedule: schedule,
        subjects: widget.subjects ?? const [],
        existingSchedules: widget.schedules ?? const [],
        onSave: (updatedSchedule) {
          widget.onEditSchedule?.call(updatedSchedule);
        },
      ),
    );
  }

  void _confirmDeleteSchedule(ClassSchedule schedule) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.surfaceColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Xác nhận xóa',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: ctx.textPrimaryColor,
          ),
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa lịch học môn "${schedule.subjectName}" (${schedule.dayOfWeekText} ${schedule.timeRangeText}) không?',
          style: TextStyle(
            fontSize: 14,
            color: ctx.textSecondaryColor,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Hủy'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onDeleteSchedule?.call(schedule);
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();

    // 1. Chuẩn hóa danh sách môn học phục vụ bộ lọc môn và tra cứu tên môn
    final availableSubjects = <_SubjectFilterItem>[];
    final subjectNameMap = <String, String>{};

    if (widget.subjects != null && widget.subjects!.isNotEmpty) {
      for (final s in widget.subjects!) {
        availableSubjects.add(
          _SubjectFilterItem(id: s.id, name: s.name, color: s.color),
        );
        subjectNameMap[s.id] = s.name;
      }
    } else {
      // Fallback từ các task hiện tại nếu không truyền danh sách subjects
      final seenIds = <String>{};
      for (final t in widget.tasks) {
        if (!seenIds.contains(t.subjectId)) {
          seenIds.add(t.subjectId);
          availableSubjects.add(
            _SubjectFilterItem(
              id: t.subjectId,
              name: t.subject,
              color: AppColors.primary,
            ),
          );
        }
        subjectNameMap[t.subjectId] = t.subject;
      }
    }

    // 2. Lọc danh sách công việc kết hợp tìm kiếm + trạng thái + môn học
    final filteredTasks = widget.tasks.where((task) {
      // Điều kiện tìm kiếm không phân biệt hoa thường theo: tên công việc, mô tả/ghi chú, tên môn học
      if (query.isNotEmpty) {
        final title = task.title.toLowerCase();
        final notes = task.notes.toLowerCase();
        final reviewNotes = (task.reviewNotes ?? '').toLowerCase();

        final subjectFromTask = task.subject.toLowerCase();
        final mappedSubjectName = (subjectNameMap[task.subjectId] ?? '')
            .toLowerCase();

        final titleMatch = title.contains(query);
        final notesMatch = notes.contains(query) || reviewNotes.contains(query);
        final subjectMatch =
            subjectFromTask.contains(query) ||
            mappedSubjectName.contains(query);

        if (!titleMatch && !notesMatch && !subjectMatch) return false;
      }

      // Điều kiện trạng thái
      if (_filterStatus != null && task.status != _filterStatus) {
        return false;
      }

      // Điều kiện môn học (hỗ trợ so khớp qua subjectId hoặc tên môn tương thích)
      if (_filterSubjectId != null) {
        if (task.subjectId != _filterSubjectId &&
            task.subject != _filterSubjectId) {
          return false;
        }
      }

      return true;
    }).toList();

    // Hàm phụ trợ so sánh hạn chót có xử lý null nhất quán (công việc không hạn chót xếp sau)
    int compareDeadlines(DateTime? a, DateTime? b, {bool ascending = true}) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return ascending ? a.compareTo(b) : b.compareTo(a);
    }

    // 3. Sắp xếp danh sách công việc sau khi lọc (Deterministic & Stable Sort)
    filteredTasks.sort((a, b) {
      int comparison = 0;
      switch (_sortOption) {
        case TaskSortOption.deadlineNearest:
          comparison = compareDeadlines(
            a.deadline,
            b.deadline,
            ascending: true,
          );
          break;
        case TaskSortOption.deadlineFurthest:
          comparison = compareDeadlines(
            a.deadline,
            b.deadline,
            ascending: false,
          );
          break;
        case TaskSortOption.priorityHighToLow:
          comparison = b.priority.index.compareTo(a.priority.index);
          if (comparison == 0) {
            comparison = compareDeadlines(
              a.deadline,
              b.deadline,
              ascending: true,
            );
          }
          break;
        case TaskSortOption.priorityLowToHigh:
          comparison = a.priority.index.compareTo(b.priority.index);
          if (comparison == 0) {
            comparison = compareDeadlines(
              a.deadline,
              b.deadline,
              ascending: true,
            );
          }
          break;
        case TaskSortOption.status:
          // Sắp xếp trạng thái: Chưa làm (todo) -> Đang làm (inProgress) -> Hoàn thành (completed)
          comparison = a.status.index.compareTo(b.status.index);
          if (comparison == 0) {
            // Khi cùng trạng thái, ưu tiên cao hơn lên trước
            comparison = b.priority.index.compareTo(a.priority.index);
            if (comparison == 0) {
              comparison = compareDeadlines(
                a.deadline,
                b.deadline,
                ascending: true,
              );
            }
          }
          break;
      }

      // Tie-breaker ổn định cuối cùng: so sánh theo tiêu đề rồi đến id
      if (comparison != 0) return comparison;
      final titleComp = a.title.compareTo(b.title);
      if (titleComp != 0) return titleComp;
      return a.id.compareTo(b.id);
    });

    final hasActiveFilter =
        query.isNotEmpty || _filterStatus != null || _filterSubjectId != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.only(
          left: 16,
          top: 16,
          right: 16,
          bottom: 88,
        ),
        children: [
          // Tiêu đề trang & Menu sắp xếp
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kế hoạch học tập',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _selectedTab == PlanTab.tasks
                          ? (hasActiveFilter
                              ? 'Hiển thị ${filteredTasks.length}/${widget.tasks.length} công việc'
                              : 'Quản lý ${widget.tasks.length} công việc & hạn nộp')
                          : 'Thời khóa biểu ${widget.schedules?.length ?? 0} lịch học theo tuần',
                      style: TextStyle(
                        color: context.textSecondaryColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Nút Menu sắp xếp (chỉ hiện khi xem tab Công việc)
              if (_selectedTab == PlanTab.tasks)
                PopupMenuButton<TaskSortOption>(
                  tooltip: 'Sắp xếp danh sách',
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                initialValue: _sortOption,
                onSelected: (option) {
                  setState(() => _sortOption = option);
                },
                itemBuilder: (context) => TaskSortOption.values.map((option) {
                  final isSelected = _sortOption == option;
                  return PopupMenuItem<TaskSortOption>(
                    value: option,
                    child: Row(
                      children: [
                        Icon(
                          option.icon,
                          size: 18,
                          color: isSelected
                              ? AppColors.primary
                              : context.textSecondaryColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            option.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? AppColors.primary
                                  : context.textPrimaryColor,
                            ),
                          ),
                        ),
                        if (isSelected)
                          const Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: AppColors.primary,
                          ),
                      ],
                    ),
                  );
                }).toList(),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: context.surfaceColor,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: context.borderColor),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _sortOption.icon,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 130),
                        child: Text(
                          _sortOption.label,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: context.textSecondaryColor,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Bộ chuyển đổi Tab: Công việc vs Lịch học tuần (hiển thị khi tính năng lịch học được cung cấp)
          if (widget.schedules != null) ...[
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<PlanTab>(
                key: const ValueKey('plan_tab_segmented_button'),
                segments: [
                  ButtonSegment(
                    value: PlanTab.tasks,
                    label: Text('Công việc (${widget.tasks.length})'),
                    icon: const Icon(Icons.check_circle_outline_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: PlanTab.schedules,
                    label: Text('Lịch học tuần (${widget.schedules?.length ?? 0})'),
                    icon: const Icon(Icons.calendar_month_rounded, size: 16),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (set) =>
                    setState(() => _selectedTab = set.first),
              ),
            ),
            const SizedBox(height: 14),
          ],

          if (_selectedTab == PlanTab.schedules)
            _buildWeeklyScheduleView(context)
          else ...[
            // Thanh tìm kiếm theo thời gian thực (Real-time Search)
            TextField(
            controller: _searchController,
            onChanged: (val) {
              setState(() {
                _searchQuery = val;
              });
            },
            style: TextStyle(fontSize: 14, color: context.textPrimaryColor),
            decoration: InputDecoration(
              hintText: 'Tìm theo tên việc, môn học, ghi chú...',
              hintStyle: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: context.textSecondaryColor,
                size: 20,
              ),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(
                        Icons.clear_rounded,
                        color: context.textSecondaryColor,
                        size: 18,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: context.surfaceColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.5,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Nhóm bộ lọc Trạng thái (Tất cả, Chưa làm, Đang làm, Hoàn thành)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusChip('Tất cả', _filterStatus == null, () {
                  setState(() => _filterStatus = null);
                }),
                const SizedBox(width: 8),
                _buildStatusChip(
                  'Chưa làm',
                  _filterStatus == TaskStatus.todo,
                  () => setState(() => _filterStatus = TaskStatus.todo),
                ),
                const SizedBox(width: 8),
                _buildStatusChip(
                  'Đang làm',
                  _filterStatus == TaskStatus.inProgress,
                  () => setState(() => _filterStatus = TaskStatus.inProgress),
                ),
                const SizedBox(width: 8),
                _buildStatusChip(
                  'Hoàn thành',
                  _filterStatus == TaskStatus.completed,
                  () => setState(() => _filterStatus = TaskStatus.completed),
                ),
              ],
            ),
          ),

          // Nhóm bộ lọc Môn học (Nếu có môn học)
          if (availableSubjects.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Text(
                    'Môn: ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.textSecondaryColor,
                    ),
                  ),
                  _buildSubjectChip(
                    'Tất cả môn',
                    _filterSubjectId == null,
                    null,
                    () => setState(() => _filterSubjectId = null),
                  ),
                  const SizedBox(width: 6),
                  ...availableSubjects.map(
                    (subj) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildSubjectChip(
                        subj.name,
                        _filterSubjectId == subj.id,
                        subj.color,
                        () => setState(() {
                          _filterSubjectId = (_filterSubjectId == subj.id)
                              ? null
                              : subj.id;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Danh sách công việc hoặc Trạng thái rỗng
          if (filteredTasks.isEmpty)
            _buildEmptyState(
              hasActiveFilter: hasActiveFilter,
              isQueryEmpty: query.isEmpty,
            )
          else ...[
            ...filteredTasks.map(
              (task) => TaskCard(
                task: task,
                accumulatedStudySeconds: widget.sessions
                    ?.where(
                      (s) =>
                          s.taskId == task.id &&
                          s.status == StudySessionStatus.completed,
                    )
                    .fold<int>(0, (sum, s) => sum + s.verifiedStudySeconds),
                onToggleComplete: (_) => widget.onToggleComplete(task),
                onTap: () => widget.onTapTask(task),
                onEdit: () => widget.onEditTask(task),
                onDelete: () => widget.onDeleteTask(task),
                onStartStudy: widget.onStartStudy != null
                    ? () => widget.onStartStudy!(task)
                    : null,
                onReschedule: widget.onReschedule != null
                    ? () => widget.onReschedule!(task)
                    : null,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ],
        ],
      ),
    );
  }

  Widget _buildWeeklyScheduleView(BuildContext context) {
    final allSchedules = widget.schedules ?? const <ClassSchedule>[];
    final filtered = _selectedDayOfWeekFilter == null
        ? allSchedules
        : allSchedules
            .where((s) => s.dayOfWeek == _selectedDayOfWeekFilter)
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thanh công cụ: Tiêu đề danh sách & Nút thêm
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lịch học cố định',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                ),
                Text(
                  'Lặp lại hàng tuần & kích hoạt chuông báo',
                  style: TextStyle(
                    fontSize: 12,
                    color: context.textSecondaryColor,
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('import_schedule_button'),
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('Nhập file'),
                  onPressed: _openImportScheduleDialog,
                ),
                OutlinedButton.icon(
                  key: const ValueKey('import_image_schedule_button'),
                  icon: const Icon(Icons.document_scanner_rounded, size: 18),
                  label: const Text('Nhập từ ảnh'),
                  onPressed: _openImageImportScheduleDialog,
                ),
                FilledButton.icon(
                  key: const ValueKey('add_schedule_button'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Thêm lịch'),
                  onPressed: _openAddScheduleDialog,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Bộ lọc ngày trong tuần: Tất cả, T2..CN
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildDayChip('Tất cả', null),
              const SizedBox(width: 6),
              _buildDayChip('T2', 1),
              const SizedBox(width: 6),
              _buildDayChip('T3', 2),
              const SizedBox(width: 6),
              _buildDayChip('T4', 3),
              const SizedBox(width: 6),
              _buildDayChip('T5', 4),
              const SizedBox(width: 6),
              _buildDayChip('T6', 5),
              const SizedBox(width: 6),
              _buildDayChip('T7', 6),
              const SizedBox(width: 6),
              _buildDayChip('CN', 7),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (filtered.isEmpty)
          _buildEmptyScheduleState()
        else
          ...filtered.map((schedule) => _buildScheduleCard(context, schedule)),
      ],
    );
  }

  Widget _buildDayChip(String label, int? dayValue) {
    final isSelected = _selectedDayOfWeekFilter == dayValue;
    return ChoiceChip(
      key: ValueKey('day_filter_${dayValue ?? 'all'}'),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedDayOfWeekFilter = dayValue;
        });
      },
    );
  }

  Widget _buildScheduleCard(BuildContext context, ClassSchedule schedule) {
    Subject? subject;
    if (widget.subjects != null) {
      for (final s in widget.subjects!) {
        if (s.id == schedule.subjectId) {
          subject = s;
          break;
        }
      }
    }
    final subjectColor = subject?.color ?? AppColors.primary;

    return Container(
      key: ValueKey('schedule_card_${schedule.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: schedule.isActive
              ? context.borderColor
              : context.borderColor.withValues(alpha: 0.5),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Thanh màu nhận diện môn học bên trái
              Container(
                width: 5,
                color: schedule.isActive
                    ? subjectColor
                    : context.textSecondaryColor.withValues(alpha: 0.3),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: subjectColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              schedule.dayOfWeekText,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.bold,
                                color: subjectColor,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              schedule.subjectName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: schedule.isActive
                                    ? context.textPrimaryColor
                                    : context.textSecondaryColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Switch(
                            key: ValueKey('schedule_switch_${schedule.id}'),
                            value: schedule.isActive,
                            onChanged: (val) {
                              widget.onToggleScheduleActive?.call(schedule, val);
                            },
                          ),
                          PopupMenuButton<String>(
                            key: ValueKey('schedule_menu_${schedule.id}'),
                            icon: Icon(
                              Icons.more_vert_rounded,
                              size: 20,
                              color: context.textSecondaryColor,
                            ),
                            onSelected: (action) {
                              if (action == 'edit') {
                                _openEditScheduleDialog(schedule);
                              } else if (action == 'delete') {
                                _confirmDeleteSchedule(schedule);
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_rounded, size: 18),
                                    SizedBox(width: 8),
                                    Text('Chỉnh sửa'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                      color: AppColors.error,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Xóa',
                                      style: TextStyle(color: AppColors.error),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 15,
                            color: context.textSecondaryColor,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            schedule.timeRangeText,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          if (schedule.location.isNotEmpty) ...[
                            const SizedBox(width: 14),
                            Icon(
                              Icons.location_on_outlined,
                              size: 15,
                              color: context.textSecondaryColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                schedule.location,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: context.textSecondaryColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (schedule.teacher.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.person_outline_rounded,
                              size: 15,
                              color: context.textSecondaryColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'GV: ${schedule.teacher}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.textSecondaryColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (schedule.notes.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          schedule.notes,
                          style: TextStyle(
                            fontSize: 12,
                            color: context.textSecondaryColor,
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyScheduleState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.primaryContainerColor,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Chưa có lịch học nào',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Thêm lịch học cố định theo tuần để nhận thông báo và chuông báo thức trước giờ học.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondaryColor,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('empty_schedule_import_button'),
                onPressed: _openImportScheduleDialog,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Nhập Excel/CSV'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('empty_schedule_import_image_button'),
                onPressed: _openImageImportScheduleDialog,
                icon: const Icon(Icons.document_scanner_rounded, size: 18),
                label: const Text('Nhập từ ảnh'),
              ),
              FilledButton.icon(
                key: const ValueKey('empty_schedule_add_button'),
                onPressed: _openAddScheduleDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm lịch học tuần'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required bool hasActiveFilter,
    required bool isQueryEmpty,
  }) {
    // Trường hợp 1: Không có công việc nào trong toàn bộ ứng dụng
    if (widget.tasks.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
        decoration: BoxDecoration(
          color: context.surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.borderColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: context.primaryContainerColor,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.calendar_today_rounded,
                size: 40,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa có công việc học tập nào',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Lập kế hoạch các bài học, bài tập để theo dõi tiến độ và ôn tập hiệu quả.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: widget.onAddTask,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tạo công việc đầu tiên'),
            ),
          ],
        ),
      );
    }

    // Trường hợp 2: Có công việc nhưng bộ lọc / tìm kiếm không tìm thấy kết quả
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.surfaceMutedColor,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isQueryEmpty
                  ? Icons.filter_alt_off_rounded
                  : Icons.search_off_rounded,
              size: 38,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isQueryEmpty
                ? 'Không có công việc thuộc bộ lọc đã chọn'
                : 'Không tìm thấy kết quả phù hợp',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isQueryEmpty
                ? 'Thử thay đổi bộ lọc trạng thái hoặc môn học để xem các công việc khác.'
                : 'Thử kiểm tra lỗi chính tả hoặc xóa từ khóa tìm kiếm.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondaryColor,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _clearAllFilters,
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Xóa tất cả bộ lọc & tìm kiếm'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(
    String label,
    bool isSelected,
    VoidCallback onSelected,
  ) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: context.primaryContainerColor,
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        color: isSelected
            ? (context.isDark ? AppColors.primaryLight : AppColors.primary)
            : context.textPrimaryColor,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.primary : context.borderColor,
        width: 1,
      ),
    );
  }

  Widget _buildSubjectChip(
    String label,
    bool isSelected,
    Color? dotColor,
    VoidCallback onSelected,
  ) {
    return ActionChip(
      avatar: dotColor != null
          ? Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            )
          : (isSelected
                ? const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: AppColors.primary,
                  )
                : null),
      label: Text(label),
      onPressed: onSelected,
      backgroundColor: isSelected
          ? context.primaryContainerColor
          : context.surfaceColor,
      side: BorderSide(
        color: isSelected ? AppColors.primary : context.borderColor,
        width: 1,
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        color: isSelected
            ? (context.isDark ? AppColors.primaryLight : AppColors.primary)
            : context.textSecondaryColor,
      ),
    );
  }
}

class _SubjectFilterItem {
  final String id;
  final String name;
  final Color color;

  const _SubjectFilterItem({
    required this.id,
    required this.name,
    required this.color,
  });
}

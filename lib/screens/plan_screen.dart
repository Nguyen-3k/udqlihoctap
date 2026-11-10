import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../models/task_status.dart';
import '../theme/app_colors.dart';
import '../widgets/task_card.dart';

/// Các tùy chọn sắp xếp danh sách công việc trong Kế hoạch học tập.
enum TaskSortOption {
  deadlineNearest('Hạn chót gần nhất', Icons.access_time_rounded),
  deadlineFurthest('Hạn chót xa nhất', Icons.history_toggle_off_rounded),
  priorityHighToLow('Ưu tiên cao \u2192 thấp', Icons.arrow_downward_rounded),
  priorityLowToHigh('Ưu tiên thấp \u2192 cao', Icons.arrow_upward_rounded);

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
  final ValueChanged<StudyTask> onToggleComplete;
  final ValueChanged<StudyTask> onTapTask;
  final ValueChanged<StudyTask> onEditTask;
  final ValueChanged<StudyTask> onDeleteTask;
  final VoidCallback onAddTask;

  const PlanScreen({
    super.key,
    required this.tasks,
    this.subjects,
    required this.onToggleComplete,
    required this.onTapTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onAddTask,
  });

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

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

  @override
  Widget build(BuildContext context) {
    final query = _searchQuery.trim().toLowerCase();

    // 1. Chuẩn hóa danh sách môn học phục vụ bộ lọc môn
    final availableSubjects = <_SubjectFilterItem>[];
    if (widget.subjects != null && widget.subjects!.isNotEmpty) {
      for (final s in widget.subjects!) {
        availableSubjects.add(
          _SubjectFilterItem(id: s.id, name: s.name, color: s.color),
        );
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
      }
    }

    // 2. Lọc danh sách công việc kết hợp tìm kiếm + trạng thái + môn học
    final filteredTasks = widget.tasks.where((task) {
      // Điều kiện tìm kiếm theo tên công việc (không phân biệt hoa thường)
      if (query.isNotEmpty) {
        final titleMatch = task.title.toLowerCase().contains(query);
        final notesMatch = task.notes.toLowerCase().contains(query);
        if (!titleMatch && !notesMatch) return false;
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

    // 3. Sắp xếp danh sách công việc sau khi lọc
    filteredTasks.sort((a, b) {
      switch (_sortOption) {
        case TaskSortOption.deadlineNearest:
          return a.deadline.compareTo(b.deadline);
        case TaskSortOption.deadlineFurthest:
          return b.deadline.compareTo(a.deadline);
        case TaskSortOption.priorityHighToLow:
          final priorityCompare = b.priority.index.compareTo(a.priority.index);
          if (priorityCompare != 0) return priorityCompare;
          return a.deadline.compareTo(b.deadline);
        case TaskSortOption.priorityLowToHigh:
          final priorityCompare = a.priority.index.compareTo(b.priority.index);
          if (priorityCompare != 0) return priorityCompare;
          return a.deadline.compareTo(b.deadline);
      }
    });

    final hasActiveFilter =
        query.isNotEmpty || _filterStatus != null || _filterSubjectId != null;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
                      hasActiveFilter
                          ? 'Hiển thị ${filteredTasks.length}/${widget.tasks.length} công việc'
                          : 'Quản lý ${widget.tasks.length} công việc & hạn nộp',
                      style: TextStyle(
                        color: context.textSecondaryColor,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

              // Nút Menu sắp xếp
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
                      Text(
                        _sortOption.label,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
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
              hintText: 'Tìm kiếm theo tên công việc, ghi chú...',
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
          else
            ...filteredTasks.map(
              (task) => TaskCard(
                task: task,
                onToggleComplete: (_) => widget.onToggleComplete(task),
                onTap: () => widget.onTapTask(task),
                onEdit: () => widget.onEditTask(task),
                onDelete: () => widget.onDeleteTask(task),
              ),
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

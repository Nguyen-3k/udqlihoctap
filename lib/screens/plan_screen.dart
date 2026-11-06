import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/task_status.dart';
import '../theme/app_colors.dart';
import '../widgets/task_card.dart';

/// Màn hình Kế hoạch học tập (Quản lý danh sách công việc).
/// Tối ưu bộ lọc theo trạng thái và môn học, loại bỏ nút dư thừa, tập trung vào thao tác nhanh.
class PlanScreen extends StatefulWidget {
  final List<StudyTask> tasks;
  final ValueChanged<StudyTask> onToggleComplete;
  final ValueChanged<StudyTask> onTapTask;
  final ValueChanged<StudyTask> onEditTask;
  final ValueChanged<StudyTask> onDeleteTask;
  final VoidCallback onAddTask;

  const PlanScreen({
    super.key,
    required this.tasks,
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
  // Lọc theo trạng thái: null = Tất cả, hoặc TaskStatus cụ thể
  TaskStatus? _filterStatus;
  String? _filterSubject;

  @override
  Widget build(BuildContext context) {
    // Lấy danh sách các môn học có trong tasks
    final subjects = widget.tasks.map((t) => t.subject).toSet().toList();

    // Lọc công việc
    final filteredTasks = widget.tasks.where((task) {
      if (_filterStatus != null && task.status != _filterStatus) {
        return false;
      }
      if (_filterSubject != null && task.subject != _filterSubject) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // Tiêu đề trang
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Kế hoạch học tập',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Quản lý nhiệm vụ, hạn nộp & thời lượng',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Thanh lọc trạng thái (Tất cả, Chưa làm, Đang làm, Hoàn thành)
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

          // Lọc theo môn học nếu có từ 2 môn trở lên
          if (subjects.length > 1) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text(
                    'Môn: ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  _buildSubjectChip(
                    'Tất cả môn',
                    _filterSubject == null,
                    () => setState(() => _filterSubject = null),
                  ),
                  const SizedBox(width: 6),
                  ...subjects.map(
                    (subj) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _buildSubjectChip(
                        subj,
                        _filterSubject == subj,
                        () => setState(() {
                          _filterSubject = (_filterSubject == subj)
                              ? null
                              : subj;
                        }),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Danh sách công việc
          if (filteredTasks.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.filter_list_off_rounded,
                    size: 44,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Không tìm thấy công việc phù hợp bộ lọc.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Thử chọn lại bộ lọc hoặc tạo thêm nhiệm vụ mới.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_filterStatus != null || _filterSubject != null)
                    OutlinedButton(
                      onPressed: () {
                        setState(() {
                          _filterStatus = null;
                          _filterSubject = null;
                        });
                      },
                      child: const Text('Xóa bộ lọc'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: widget.onAddTask,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Tạo công việc mới'),
                    ),
                ],
              ),
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

  Widget _buildStatusChip(
    String label,
    bool isSelected,
    VoidCallback onSelected,
  ) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onSelected(),
      selectedColor: AppColors.primaryContainer,
      checkmarkColor: AppColors.primary,
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        color: isSelected ? AppColors.primary : AppColors.textPrimary,
      ),
      side: BorderSide(
        color: isSelected ? AppColors.primary : AppColors.border,
        width: 1,
      ),
    );
  }

  Widget _buildSubjectChip(
    String label,
    bool isSelected,
    VoidCallback onSelected,
  ) {
    return ActionChip(
      label: Text(label),
      avatar: isSelected
          ? const Icon(Icons.check_rounded, size: 16, color: AppColors.primary)
          : null,
      onPressed: onSelected,
      backgroundColor: isSelected
          ? AppColors.primaryContainer
          : AppColors.surface,
      side: BorderSide(
        color: isSelected ? AppColors.primary : AppColors.border,
        width: 1,
      ),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
        color: isSelected ? AppColors.primary : AppColors.textSecondary,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../models/task_status.dart';
import '../theme/app_colors.dart';
import '../widgets/task_card.dart';

/// Màn hình Chi tiết Môn học (SubjectDetailScreen).
/// Bố cục chuẩn mực 6 phần:
/// 1. Thanh tiêu đề và nút quay lại
/// 2. Thẻ thông tin môn học (Tên, mô tả, biểu tượng, màu sắc)
/// 3. Thanh tiến độ học tập (Tính từ dữ liệu thực tế)
/// 4. Các chỉ số tổng quan (Tổng số việc, Đã xong, Chưa xong, Tỷ lệ hoàn thành)
/// 5. Danh sách công việc theo môn (Kèm bộ lọc trạng thái & hiển thị mức độ hiểu bài)
/// 6. Nút thêm công việc trực tiếp chọn sẵn môn học này
class SubjectDetailScreen extends StatefulWidget {
  final Subject subject;
  final List<Subject> allSubjects;
  final List<StudyTask> tasks;
  final ValueChanged<StudyTask> onToggleComplete;
  final ValueChanged<StudyTask> onTapTask;
  final ValueChanged<StudyTask> onEditTask;
  final ValueChanged<StudyTask> onDeleteTask;
  final VoidCallback onAddTaskForThisSubject;
  final VoidCallback onEditSubject;
  final ValueChanged<Subject>? onUpdateSubject;
  final VoidCallback onDeleteSubject;

  const SubjectDetailScreen({
    super.key,
    required this.subject,
    required this.allSubjects,
    required this.tasks,
    required this.onToggleComplete,
    required this.onTapTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onAddTaskForThisSubject,
    required this.onEditSubject,
    this.onUpdateSubject,
    required this.onDeleteSubject,
  });

  @override
  State<SubjectDetailScreen> createState() => _SubjectDetailScreenState();
}

class _SubjectDetailScreenState extends State<SubjectDetailScreen> {
  // Lọc theo trạng thái trong môn: null = Tất cả
  TaskStatus? _filterStatus;
  Subject? _localSubject;

  Subject get _currentSubject {
    final found = widget.allSubjects.where(
      (s) => s.id == (_localSubject?.id ?? widget.subject.id),
    );
    if (found.isNotEmpty) return found.first;
    return _localSubject ?? widget.subject;
  }

  void _handleToggleComplete(StudyTask task) {
    widget.onToggleComplete(task);
    setState(() {});
  }

  void _handleDeleteTask(StudyTask task) {
    widget.onDeleteTask(task);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final currentSub = _currentSubject;

    // Lọc công việc theo đúng subjectId (hoặc fallback tên môn nếu bản ghi cũ chưa có subjectId)
    final subjectTasks = widget.tasks
        .where(
          (t) =>
              t.subjectId == currentSub.id ||
              (t.subjectId.isEmpty && t.subject == currentSub.name),
        )
        .toList();

    // Tính toán số liệu thống kê thực tế
    final totalCount = subjectTasks.length;
    final completedCount = subjectTasks.where((t) => t.isCompleted).length;
    final uncompletedCount = totalCount - completedCount;
    final progress = totalCount > 0 ? (completedCount / totalCount) : 0.0;
    final percentInt = (progress * 100).toInt();

    // Lọc theo trạng thái nếu người dùng chọn chip lọc
    final filteredTasks = subjectTasks.where((task) {
      if (_filterStatus != null && task.status != _filterStatus) {
        return false;
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentSub.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Chỉnh sửa môn học',
            onPressed: widget.onEditSubject,
          ),
          IconButton(
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.error,
            ),
            tooltip: 'Xóa môn học',
            onPressed: widget.onDeleteSubject,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(
          left: 16,
          top: 16,
          right: 16,
          bottom: 88,
        ),
        children: [
          // 1. Thẻ thông tin môn học (Tên, mô tả, biểu tượng, màu sắc)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: currentSub.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      currentSub.icon,
                      color: currentSub.color,
                      size: 26,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentSub.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        currentSub.description.isNotEmpty
                            ? currentSub.description
                            : 'Chưa có mô tả cho môn học này.',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.textSecondaryColor,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. Thẻ tiến độ học tập môn này (Tính từ dữ liệu thực tế)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.trending_up_rounded,
                            size: 18,
                            color: currentSub.color,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Tiến độ học tập môn này',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: context.textPrimaryColor,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: currentSub.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$percentInt% hoàn thành',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: currentSub.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: context.surfaceMutedColor,
                    color: completedCount == totalCount && totalCount > 0
                        ? AppColors.statusCompleted
                        : currentSub.color,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  totalCount == 0
                      ? 'Chưa có công việc nào để tính tiến độ (0%). Hãy nhấn "Thêm nhiệm vụ" bên dưới để bắt đầu!'
                      : (completedCount == totalCount
                            ? 'Tuyệt vời! Bạn đã hoàn thành 100% tất cả các công việc của môn này 🎉'
                            : 'Đã hoàn thành $completedCount trong tổng số $totalCount công việc ($uncompletedCount việc chưa xong).'),
                  style: TextStyle(
                    fontSize: 12,
                    color: completedCount == totalCount && totalCount > 0
                        ? AppColors.statusCompleted
                        : context.textSecondaryColor,
                    fontStyle: totalCount == 0 ? FontStyle.italic : null,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 3. Lưới chỉ số tổng quan (Tổng nhiệm vụ, Đã hoàn thành, Chưa hoàn thành, Tỷ lệ)
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 420;
              if (isNarrow) {
                // Bố cục 2x2 chống tràn chữ trên màn hình nhỏ/hẹp (<= 420dp)
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricItem(
                            label: 'Tổng nhiệm vụ',
                            value: '$totalCount',
                            color: AppColors.primary,
                            icon: Icons.list_alt_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricItem(
                            label: 'Đã hoàn thành',
                            value: '$completedCount',
                            color: AppColors.statusCompleted,
                            icon: Icons.check_circle_rounded,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricItem(
                            label: 'Chưa hoàn thành',
                            value: '$uncompletedCount',
                            color: AppColors.statusInProgress,
                            icon: Icons.timelapse_rounded,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildMetricItem(
                            label: 'Tỷ lệ',
                            value: '$percentInt%',
                            color: currentSub.color,
                            icon: Icons.pie_chart_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }

              // Bố cục 4 cột cân đối trên màn hình lớn (> 420dp)
              return Row(
                children: [
                  Expanded(
                    child: _buildMetricItem(
                      label: 'Tổng nhiệm vụ',
                      value: '$totalCount',
                      color: AppColors.primary,
                      icon: Icons.list_alt_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricItem(
                      label: 'Đã hoàn thành',
                      value: '$completedCount',
                      color: AppColors.statusCompleted,
                      icon: Icons.check_circle_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricItem(
                      label: 'Chưa hoàn thành',
                      value: '$uncompletedCount',
                      color: AppColors.statusInProgress,
                      icon: Icons.timelapse_rounded,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildMetricItem(
                      label: 'Tỷ lệ',
                      value: '$percentInt%',
                      color: currentSub.color,
                      icon: Icons.pie_chart_rounded,
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 18),

          // 4. Tiêu đề danh sách nhiệm vụ & nút thêm việc
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Nhiệm vụ của môn ($totalCount)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: widget.onAddTaskForThisSubject,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Thêm nhiệm vụ'),
              ),
            ],
          ),

          // 5. Thanh lọc trạng thái công việc trong môn học (nếu có nhiệm vụ)
          if (totalCount > 0) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatusChip('Tất cả', _filterStatus == null, () {
                    setState(() => _filterStatus = null);
                  }),
                  const SizedBox(width: 6),
                  _buildStatusChip(
                    'Chưa làm',
                    _filterStatus == TaskStatus.todo,
                    () => setState(() => _filterStatus = TaskStatus.todo),
                  ),
                  const SizedBox(width: 6),
                  _buildStatusChip(
                    'Đang làm',
                    _filterStatus == TaskStatus.inProgress,
                    () => setState(() => _filterStatus = TaskStatus.inProgress),
                  ),
                  const SizedBox(width: 6),
                  _buildStatusChip(
                    'Hoàn thành',
                    _filterStatus == TaskStatus.completed,
                    () => setState(() => _filterStatus = TaskStatus.completed),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 12),

          // 6. Danh sách công việc hoặc Trạng thái rỗng
          if (subjectTasks.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Center(
                child: Column(
                  children: [
                    const Icon(
                      Icons.assignment_outlined,
                      size: 44,
                      color: AppColors.textMuted,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Môn "${currentSub.name}" chưa có nhiệm vụ nào.',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tạo nhiệm vụ đầu tiên để bắt đầu theo dõi tiến độ môn học.',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.textSecondaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: widget.onAddTaskForThisSubject,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Thêm nhiệm vụ ngay'),
                    ),
                  ],
                ),
              ),
            )
          else if (filteredTasks.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.filter_list_off_rounded,
                    size: 36,
                    color: AppColors.textMuted,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Không có công việc thuộc trạng thái đã chọn',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => setState(() => _filterStatus = null),
                    child: const Text('Xóa bộ lọc'),
                  ),
                ],
              ),
            )
          else
            ...filteredTasks.map(
              (task) => TaskCard(
                task: task,
                onToggleComplete: (_) => _handleToggleComplete(task),
                onTap: () => widget.onTapTask(task),
                onEdit: () => widget.onEditTask(task),
                onDelete: () => _handleDeleteTask(task),
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onAddTaskForThisSubject,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        icon: const Icon(Icons.add, size: 20),
        label: const Text(
          'Thêm việc môn này',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
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
        fontSize: 12,
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

  Widget _buildMetricItem({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: context.textSecondaryColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

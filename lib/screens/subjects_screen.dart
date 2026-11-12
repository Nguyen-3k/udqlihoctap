import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../theme/app_colors.dart';
import 'subject_detail_screen.dart';

/// Màn hình Danh sách Môn học (SubjectsScreen).
/// Hiển thị thẻ môn học với biểu tượng, màu sắc, tên, mô tả, tổng số việc, số việc đã xong và thanh tiến độ thực tế.
/// Hỗ trợ thêm, sửa, xóa môn học an toàn (có chuyển giao nhiệm vụ) và nhấn vào thẻ để mở màn hình Chi tiết môn học.
class SubjectsScreen extends StatelessWidget {
  final List<Subject> subjects;
  final List<StudyTask> tasks;
  final ValueChanged<Subject> onAddSubject;
  final ValueChanged<Subject> onUpdateSubject;
  final void Function(String subjectId, {String? migrateToSubjectId})
  onDeleteSubject;
  final ValueChanged<StudyTask> onToggleCompleteTask;
  final ValueChanged<StudyTask> onTapTask;
  final ValueChanged<StudyTask> onEditTask;
  final ValueChanged<StudyTask> onDeleteTask;
  final void Function(Subject subject) onAddTaskForSubject;
  final void Function(Subject subject)? onStartTimerForSubject;

  const SubjectsScreen({
    super.key,
    required this.subjects,
    required this.tasks,
    required this.onAddSubject,
    required this.onUpdateSubject,
    required this.onDeleteSubject,
    required this.onToggleCompleteTask,
    required this.onTapTask,
    required this.onEditTask,
    required this.onDeleteTask,
    required this.onAddTaskForSubject,
    this.onStartTimerForSubject,
  });

  // Danh mục màu đại diện gợi ý
  static const List<Color> _availableColors = [
    Color(0xFF3B5BDB), // Indigo
    Color(0xFF0284C7), // Sky Blue
    Color(0xFF009688), // Teal
    Color(0xFFD97706), // Amber
    Color(0xFFE11D48), // Rose
    Color(0xFF7C3AED), // Purple
  ];

  // Danh mục biểu tượng học tập gợi ý
  static const List<IconData> _availableIcons = [
    Icons.menu_book_rounded,
    Icons.code_rounded,
    Icons.functions_rounded,
    Icons.storage_rounded,
    Icons.language_rounded,
    Icons.science_rounded,
  ];

  void _showSubjectFormDialog(BuildContext context, {Subject? initialSubject}) {
    final isEditing = initialSubject != null;
    final nameController = TextEditingController(
      text: initialSubject?.name ?? '',
    );
    final descController = TextEditingController(
      text: initialSubject?.description ?? '',
    );
    Color selectedColor = initialSubject?.color ?? _availableColors.first;
    IconData selectedIcon = initialSubject?.icon ?? _availableIcons.first;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: context.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            isEditing ? 'Chỉnh sửa môn học' : 'Thêm môn học mới',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.textPrimaryColor,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên môn học *',
                    hintText: 'Ví dụ: Lập trình Di động',
                    prefixIcon: Icon(Icons.book_rounded, size: 20),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Mô tả môn học',
                    hintText: 'Ví dụ: Học Flutter và Dart căn bản',
                    prefixIcon: Icon(Icons.description_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: 16),

                // Chọn màu sắc
                Text(
                  'Màu đại diện:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: _availableColors.map((color) {
                    final isSelected =
                        selectedColor.toARGB32() == color.toARGB32();
                    return GestureDetector(
                      onTap: () => setDialogState(() => selectedColor = color),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : Colors.transparent,
                            width: 2.5,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.5),
                                    blurRadius: 6,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // Chọn biểu tượng
                Text(
                  'Biểu tượng môn học:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.textSecondaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: _availableIcons.map((icon) {
                    final isSelected = selectedIcon.codePoint == icon.codePoint;
                    return InkWell(
                      onTap: () => setDialogState(() => selectedIcon = icon),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? context.primaryContainerColor
                              : context.surfaceMutedColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : context.borderColor,
                            width: 1.2,
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 20,
                          color: isSelected
                              ? AppColors.primary
                              : context.textSecondaryColor,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                if (isEditing) {
                  final updated = initialSubject.copyWith(
                    name: name,
                    description: descController.text.trim(),
                    color: selectedColor,
                    icon: selectedIcon,
                  );
                  onUpdateSubject(updated);
                } else {
                  final newSub = Subject(
                    id: 'subj_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    description: descController.text.trim().isNotEmpty
                        ? descController.text.trim()
                        : 'Môn học cá nhân',
                    color: selectedColor,
                    icon: selectedIcon,
                  );
                  onAddSubject(newSub);
                }
                Navigator.of(dialogContext).pop();
              },
              child: Text(isEditing ? 'Cập nhật' : 'Thêm môn'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteSubject(BuildContext context, Subject subject) {
    // Đếm số nhiệm vụ đang thuộc môn học này
    final subjectTasks = tasks
        .where(
          (t) =>
              t.subjectId == subject.id ||
              (t.subjectId.isEmpty && t.subject == subject.name),
        )
        .toList();
    final taskCount = subjectTasks.length;

    // Trường hợp 1: Môn chưa có nhiệm vụ nào -> Xác nhận xóa thông thường
    if (taskCount == 0) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: dialogContext.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Xác nhận xóa môn học',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: dialogContext.textPrimaryColor,
            ),
          ),
          content: Text(
            'Bạn có chắc chắn muốn xóa môn "${subject.name}" không? Môn này hiện chưa có nhiệm vụ nào.',
            style: TextStyle(color: dialogContext.textSecondaryColor),
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onDeleteSubject(subject.id);
              },
              child: const Text('Xóa'),
            ),
          ],
        ),
      );
      return;
    }

    // Trường hợp 2: Môn đang có nhiệm vụ
    final otherSubjects = subjects.where((s) => s.id != subject.id).toList();

    // Nếu không còn môn học nào khác để chuyển -> Không cho xóa và giải thích rõ ràng
    if (otherSubjects.isEmpty) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: dialogContext.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.error),
              const SizedBox(width: 8),
              Text(
                'Không thể xóa môn học',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: dialogContext.textPrimaryColor,
                ),
              ),
            ],
          ),
          content: Text(
            'Môn "${subject.name}" hiện đang có $taskCount nhiệm vụ và đây là môn học duy nhất còn lại trong ứng dụng.\n\n'
            'Để tránh nhiệm vụ bị mất hoặc mồ côi, bạn vui lòng tạo thêm môn học mới hoặc xóa hết nhiệm vụ trước khi xóa môn này.',
            style: TextStyle(
              color: dialogContext.textSecondaryColor,
              height: 1.4,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
      return;
    }

    // Nếu còn môn học khác -> Cho phép chọn môn đích để chuyển giao nhiệm vụ
    String selectedTargetSubjectId = otherSubjects.first.id;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: dialogContext.surfaceColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chuyển nhiệm vụ trước khi xóa',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: dialogContext.textPrimaryColor,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Môn "${subject.name}" đang có $taskCount nhiệm vụ.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: dialogContext.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Để tránh mất dữ liệu hoặc nhiệm vụ bị mồ côi, vui lòng chọn môn học để chuyển giao toàn bộ các nhiệm vụ này sang:',
                style: TextStyle(
                  fontSize: 13,
                  color: dialogContext.textSecondaryColor,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: selectedTargetSubjectId,
                decoration: const InputDecoration(
                  labelText: 'Chuyển nhiệm vụ sang môn *',
                  prefixIcon: Icon(Icons.arrow_forward_rounded, size: 20),
                ),
                items: otherSubjects.map((s) {
                  return DropdownMenuItem<String>(
                    value: s.id,
                    child: Text(s.name),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selectedTargetSubjectId = val);
                  }
                },
              ),
            ],
          ),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Hủy'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onDeleteSubject(
                  subject.id,
                  migrateToSubjectId: selectedTargetSubjectId,
                );
              },
              child: Text('Chuyển $taskCount việc & Xóa môn'),
            ),
          ],
        ),
      ),
    );
  }

  void _openSubjectDetail(BuildContext context, Subject subject) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SubjectDetailScreen(
          subject: subject,
          allSubjects: subjects,
          tasks: tasks,
          onToggleComplete: onToggleCompleteTask,
          onTapTask: onTapTask,
          onEditTask: onEditTask,
          onDeleteTask: onDeleteTask,
          onAddTaskForThisSubject: () => onAddTaskForSubject(subject),
          onStartTimerForThisSubject: onStartTimerForSubject == null
              ? null
              : () => onStartTimerForSubject!(subject),
          onEditSubject: () =>
              _showSubjectFormDialog(context, initialSubject: subject),
          onUpdateSubject: onUpdateSubject,
          onDeleteSubject: () {
            Navigator.of(context).pop(); // Đóng màn chi tiết trước
            _confirmDeleteSubject(context, subject);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(left: 16, top: 16, right: 16, bottom: 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Môn học của tôi',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Quản lý ${subjects.length} môn học & tiến độ bài học',
                    style: TextStyle(
                      color: context.textSecondaryColor,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showSubjectFormDialog(context),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Thêm môn'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (subjects.isEmpty)
          Container(
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
                    Icons.school_outlined,
                    size: 40,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Chưa có môn học nào',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tạo môn học đầu tiên để bắt đầu phân loại nhiệm vụ và theo dõi tiến độ tự học.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.textSecondaryColor,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => _showSubjectFormDialog(context),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Tạo môn học đầu tiên'),
                ),
              ],
            ),
          )
        else
          ...subjects.map((subject) {
            final subjectTasks = tasks.where(
              (t) =>
                  t.subjectId == subject.id ||
                  (t.subjectId.isEmpty && t.subject == subject.name),
            );
            final taskCount = subjectTasks.length;
            final completedCount = subjectTasks
                .where((t) => t.isCompleted)
                .length;
            final overdueCount = subjectTasks.where((t) => t.isOverdue).length;
            final isAllCompleted = taskCount > 0 && completedCount == taskCount;
            final progress = taskCount > 0 ? (completedCount / taskCount) : 0.0;
            final percentInt = (progress * 100).toInt();

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.borderColor, width: 1),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  onTap: () => _openSubjectDetail(context, subject),
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Biểu tượng môn học với màu đại diện
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: subject.color.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Icon(
                                  subject.icon,
                                  color: subject.color,
                                  size: 24,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Tên và mô tả ngắn môn học
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    subject.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: context.textPrimaryColor,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    subject.description.isNotEmpty
                                        ? subject.description
                                        : 'Chưa có mô tả cho môn học này',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: context.textSecondaryColor,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            // Menu thao tác nhanh
                            PopupMenuButton<String>(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                Icons.more_vert_rounded,
                                color: context.textSecondaryColor,
                                size: 20,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              onSelected: (val) {
                                if (val == 'detail') {
                                  _openSubjectDetail(context, subject);
                                } else if (val == 'timer') {
                                  onStartTimerForSubject?.call(subject);
                                } else if (val == 'edit') {
                                  _showSubjectFormDialog(
                                    context,
                                    initialSubject: subject,
                                  );
                                } else if (val == 'delete') {
                                  _confirmDeleteSubject(context, subject);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'detail',
                                  child: Row(
                                    children: [
                                      Icon(Icons.visibility_outlined, size: 18),
                                      SizedBox(width: 8),
                                      Text('Xem chi tiết'),
                                    ],
                                  ),
                                ),
                                if (onStartTimerForSubject != null)
                                  const PopupMenuItem(
                                    value: 'timer',
                                    child: Row(
                                      children: [
                                        Icon(Icons.timer_outlined, size: 18),
                                        SizedBox(width: 8),
                                        Text('Học với Study Timer'),
                                      ],
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined, size: 18),
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
                                        color: AppColors.error,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text(
                                        'Xóa môn',
                                        style: TextStyle(
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),
                        Divider(height: 1, color: context.borderSubtleColor),
                        const SizedBox(height: 10),

                        // Hàng tiến độ hoàn thành thực tế
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                taskCount == 0
                                    ? 'Chưa có công việc'
                                    : (isAllCompleted
                                          ? 'Toàn bộ $taskCount việc đã hoàn thành 🎉'
                                          : '$completedCount/$taskCount việc đã hoàn thành'),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isAllCompleted
                                      ? AppColors.statusCompleted
                                      : context.textSecondaryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              taskCount == 0 ? '0%' : '$percentInt%',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isAllCompleted
                                    ? AppColors.statusCompleted
                                    : subject.color,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),

                        // Thanh tiến độ trực quan theo màu môn học
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 6,
                            backgroundColor: context.surfaceMutedColor,
                            color: isAllCompleted
                                ? AppColors.statusCompleted
                                : subject.color,
                          ),
                        ),

                        // Nhắc nhở nếu có công việc quá hạn
                        if (overdueCount > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.warning_amber_rounded,
                                size: 13,
                                color: AppColors.error,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Có $overdueCount việc quá hạn',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../theme/app_colors.dart';
import '../widgets/info_card.dart';
import 'subject_detail_screen.dart';

/// Màn hình Môn học & Chủ đề.
/// Quản lý phân loại môn học, hiển thị số lượng nhiệm vụ, hỗ trợ thêm, sửa, xóa (có kiểm tra ràng buộc)
/// và nhấn vào môn học để mở màn hình chi tiết nhiệm vụ theo môn.
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
  });

  // Danh mục màu gợi ý
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
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            isEditing ? 'Chỉnh sửa môn học' : 'Thêm môn học mới',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
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
                const Text(
                  'Màu đại diện:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
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
                const Text(
                  'Biểu tượng môn học:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
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
                              ? AppColors.primaryContainer
                              : AppColors.surfaceMuted,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.border,
                            width: 1.2,
                          ),
                        ),
                        child: Icon(
                          icon,
                          size: 20,
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textSecondary,
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
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Xác nhận xóa môn học',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          content: Text(
            'Bạn có chắc chắn muốn xóa môn "${subject.name}" không? Môn này hiện chưa có nhiệm vụ nào.',
            style: const TextStyle(color: AppColors.textSecondary),
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
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.error),
              SizedBox(width: 8),
              Text(
                'Không thể xóa môn học',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          content: Text(
            'Môn "${subject.name}" hiện đang có $taskCount nhiệm vụ và đây là môn học duy nhất còn lại trong ứng dụng.\n\n'
            'Để tránh nhiệm vụ bị mất hoặc mồ côi, bạn vui lòng tạo thêm môn học mới hoặc xóa hết nhiệm vụ trước khi xóa môn này.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
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
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.swap_horiz_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Chuyển nhiệm vụ trước khi xóa',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.textPrimary,
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
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Để tránh mất dữ liệu hoặc nhiệm vụ bị mồ côi, vui lòng chọn môn học để chuyển giao toàn bộ các nhiệm vụ này sang:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
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
          onEditSubject: () =>
              _showSubjectFormDialog(context, initialSubject: subject),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Môn học của tôi',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Quản lý danh mục bài học & phân loại',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () => _showSubjectFormDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Thêm môn'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        if (subjects.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: const Center(
              child: Text(
                'Chưa có môn học nào. Nhấn "+ Thêm môn" để tạo mới!',
                style: TextStyle(color: AppColors.textSecondary),
              ),
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

            return InfoCard(
              icon: subject.icon,
              iconColor: subject.color,
              title: subject.name,
              subtitle:
                  '${subject.description}\n$taskCount công việc ($completedCount đã hoàn thành)',
              onTap: () => _openSubjectDetail(context, subject),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: subject.color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$taskCount việc',
                      style: TextStyle(
                        color: subject.color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: AppColors.textSecondary,
                      size: 20,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    onSelected: (val) {
                      if (val == 'detail') {
                        _openSubjectDetail(context, subject);
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
                            Text('Xem nhiệm vụ'),
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
                              style: TextStyle(color: AppColors.error),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 16),
        const Text(
          'Hướng dẫn & Gợi ý',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        const InfoCard(
          icon: Icons.touch_app_rounded,
          iconColor: AppColors.primary,
          title: 'Nhấn vào môn để xem chi tiết',
          subtitle:
              'Bấm vào bất kỳ thẻ môn học nào để xem toàn bộ danh sách bài tập và thêm nhiệm vụ riêng cho môn đó.',
        ),
      ],
    );
  }
}

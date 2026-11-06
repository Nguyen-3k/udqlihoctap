import 'package:flutter/material.dart';
import '../models/study_task.dart';
import '../models/subject.dart';
import '../models/task_priority.dart';
import '../models/task_status.dart';
import '../theme/app_colors.dart';

/// Hộp thoại Thêm hoặc Chỉnh sửa một công việc học tập.
/// Liên kết môn học bằng `subjectId`, tự động chọn sẵn môn học khi mở từ chi tiết môn.
class TaskFormDialog extends StatefulWidget {
  final StudyTask? initialTask;
  final List<Subject>? subjects;
  final List<String>? availableSubjects;
  final String? preselectedSubjectId;
  final ValueChanged<StudyTask> onSave;

  const TaskFormDialog({
    super.key,
    this.initialTask,
    this.subjects,
    this.availableSubjects,
    this.preselectedSubjectId,
    required this.onSave,
  });

  @override
  State<TaskFormDialog> createState() => _TaskFormDialogState();
}

class _TaskFormDialogState extends State<TaskFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _titleController;
  late TextEditingController _notesController;
  late TextEditingController _durationController;

  late String _selectedSubjectId;
  late String _selectedSubjectName;
  late DateTime _selectedDeadline;
  late TaskPriority _selectedPriority;
  late TaskStatus _selectedStatus;

  late final List<Subject> _effectiveSubjects;

  @override
  void initState() {
    super.initState();
    final task = widget.initialTask;

    // Chuẩn hóa danh sách môn học
    if (widget.subjects != null && widget.subjects!.isNotEmpty) {
      _effectiveSubjects = widget.subjects!;
    } else if (widget.availableSubjects != null &&
        widget.availableSubjects!.isNotEmpty) {
      _effectiveSubjects = widget.availableSubjects!
          .map(
            (name) => Subject(
              id: 'subj_${name.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}',
              name: name,
              description: '',
            ),
          )
          .toList();
    } else {
      _effectiveSubjects = const [
        Subject(id: 'subj_1', name: 'Toán cao cấp', description: ''),
      ];
    }

    _titleController = TextEditingController(text: task?.title ?? '');
    _notesController = TextEditingController(text: task?.notes ?? '');
    _durationController = TextEditingController(
      text: (task?.estimatedMinutes ?? 45).toString(),
    );

    // Xác định subjectId ban đầu
    if (task != null && task.subjectId.isNotEmpty) {
      _selectedSubjectId = task.subjectId;
      _selectedSubjectName = task.subject;
    } else if (widget.preselectedSubjectId != null &&
        widget.preselectedSubjectId!.isNotEmpty) {
      _selectedSubjectId = widget.preselectedSubjectId!;
      final found = _effectiveSubjects.where((s) => s.id == _selectedSubjectId);
      _selectedSubjectName = found.isNotEmpty
          ? found.first.name
          : _effectiveSubjects.first.name;
    } else {
      _selectedSubjectId = _effectiveSubjects.first.id;
      _selectedSubjectName = _effectiveSubjects.first.name;
    }

    _selectedDeadline =
        task?.deadline ?? DateTime.now().add(const Duration(days: 1, hours: 2));
    _selectedPriority = task?.priority ?? TaskPriority.medium;
    _selectedStatus = task?.status ?? TaskStatus.todo;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _durationController.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDeadline,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Chọn ngày hạn hoàn thành',
    );

    if (pickedDate == null || !mounted) return;

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDeadline),
      helpText: 'Chọn giờ hạn hoàn thành',
    );

    if (pickedTime == null || !mounted) return;

    setState(() {
      _selectedDeadline = DateTime(
        pickedDate.year,
        pickedDate.month,
        pickedDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
    });
  }

  String _formatDateTime(DateTime dt) {
    final day = dt.day.toString().padLeft(2, '0');
    final month = dt.month.toString().padLeft(2, '0');
    final year = dt.year;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$day/$month/$year lúc $hour:$minute';
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    final notes = _notesController.text.trim();
    final duration = int.tryParse(_durationController.text.trim()) ?? 45;

    final taskToSave = StudyTask(
      id:
          widget.initialTask?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      subjectId: _selectedSubjectId,
      subject: _selectedSubjectName,
      deadline: _selectedDeadline,
      estimatedMinutes: duration,
      priority: _selectedPriority,
      status: _selectedStatus,
      notes: notes,
    );

    widget.onSave(taskToSave);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialTask != null;
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: AppColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: screenHeight * 0.88,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Tiêu đề Hộp thoại
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isEditing
                            ? Icons.edit_note_rounded
                            : Icons.add_task_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isEditing
                            ? 'Chỉnh sửa công việc'
                            : 'Thêm công việc mới',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 12),

                // Nội dung form cuộn mượt mà
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      // Tiêu đề
                      TextFormField(
                        controller: _titleController,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Tiêu đề công việc *',
                          hintText: 'Ví dụ: Ôn tập chương 3 Đạo hàm',
                          prefixIcon: Icon(Icons.title_rounded, size: 20),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập tiêu đề công việc';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      // Môn học (Dropdown chọn theo ID môn học)
                      DropdownButtonFormField<String>(
                        initialValue:
                            _effectiveSubjects.any(
                              (s) => s.id == _selectedSubjectId,
                            )
                            ? _selectedSubjectId
                            : _effectiveSubjects.first.id,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Môn học *',
                          prefixIcon: Icon(Icons.menu_book_rounded, size: 20),
                        ),
                        items: _effectiveSubjects.map((subject) {
                          return DropdownMenuItem<String>(
                            value: subject.id,
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    color: subject.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Text(subject.name),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (newSubjectId) {
                          if (newSubjectId != null) {
                            setState(() {
                              _selectedSubjectId = newSubjectId;
                              final sub = _effectiveSubjects.firstWhere(
                                (s) => s.id == newSubjectId,
                              );
                              _selectedSubjectName = sub.name;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 14),

                      // Hạn hoàn thành
                      InkWell(
                        onTap: _pickDeadline,
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Hạn hoàn thành',
                            prefixIcon: Icon(
                              Icons.calendar_today_rounded,
                              size: 20,
                            ),
                            suffixIcon: Icon(
                              Icons.arrow_drop_down_rounded,
                              size: 26,
                            ),
                          ),
                          child: Text(
                            _formatDateTime(_selectedDeadline),
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Thời lượng dự kiến
                      TextFormField(
                        controller: _durationController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Thời lượng dự kiến (phút)',
                          hintText: 'Ví dụ: 45',
                          prefixIcon: Icon(Icons.timelapse_rounded, size: 20),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập thời lượng';
                          }
                          final parsed = int.tryParse(value);
                          if (parsed == null || parsed <= 0) {
                            return 'Thời lượng phải là số nguyên dương';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Mức độ ưu tiên
                      const Text(
                        'Mức độ ưu tiên',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<TaskPriority>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.selected)) {
                              return AppColors.primaryContainer;
                            }
                            return AppColors.surface;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.selected)) {
                              return AppColors.primary;
                            }
                            return AppColors.textSecondary;
                          }),
                          side: const WidgetStatePropertyAll(
                            BorderSide(color: AppColors.border, width: 1),
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: TaskPriority.low,
                            label: Text(
                              'Thấp',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          ButtonSegment(
                            value: TaskPriority.medium,
                            label: Text(
                              'Trung bình',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          ButtonSegment(
                            value: TaskPriority.high,
                            label: Text(
                              'Cao',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                        selected: {_selectedPriority},
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            _selectedPriority = newSelection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Trạng thái công việc
                      const Text(
                        'Trạng thái',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<TaskStatus>(
                        showSelectedIcon: false,
                        style: ButtonStyle(
                          backgroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.selected)) {
                              return AppColors.primaryContainer;
                            }
                            return AppColors.surface;
                          }),
                          foregroundColor: WidgetStateProperty.resolveWith((
                            states,
                          ) {
                            if (states.contains(WidgetState.selected)) {
                              return AppColors.primary;
                            }
                            return AppColors.textSecondary;
                          }),
                          side: const WidgetStatePropertyAll(
                            BorderSide(color: AppColors.border, width: 1),
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                        segments: const [
                          ButtonSegment(
                            value: TaskStatus.todo,
                            label: Text(
                              'Chưa làm',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          ButtonSegment(
                            value: TaskStatus.inProgress,
                            label: Text(
                              'Đang làm',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          ButtonSegment(
                            value: TaskStatus.completed,
                            label: Text(
                              'Xong',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                        selected: {_selectedStatus},
                        onSelectionChanged: (newSelection) {
                          setState(() {
                            _selectedStatus = newSelection.first;
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Ghi chú / Nội dung khó hiểu
                      TextFormField(
                        controller: _notesController,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Ghi chú / Nội dung khó hiểu',
                          hintText:
                              'Ghi chú kiến thức cần lưu ý hoặc nội dung chưa hiểu rõ...',
                          prefixIcon: Icon(Icons.note_alt_outlined, size: 20),
                          alignLabelWithHint: true,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.border),
                const SizedBox(height: 16),

                // Footer Buttons (Chuẩn chiều cao 44-48dp)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Hủy'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: _submit,
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: Text(isEditing ? 'Cập nhật' : 'Thêm công việc'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

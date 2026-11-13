import 'package:flutter/material.dart';
import '../models/class_schedule.dart';
import '../models/subject.dart';
import '../theme/app_colors.dart';

/// Hộp thoại Thêm hoặc Chỉnh sửa Lịch học cố định theo tuần (Phase 4.3).
/// Cho phép chọn môn học có sẵn, thứ trong tuần, giờ bắt đầu/kết thúc,
/// địa điểm và ghi chú. Kiểm tra `start < end` và cảnh báo khi trùng lịch.
class ScheduleFormDialog extends StatefulWidget {
  final ClassSchedule? initialSchedule;
  final List<Subject> subjects;
  final List<ClassSchedule> existingSchedules;
  final ValueChanged<ClassSchedule> onSave;

  const ScheduleFormDialog({
    super.key,
    this.initialSchedule,
    required this.subjects,
    this.existingSchedules = const [],
    required this.onSave,
  });

  @override
  State<ScheduleFormDialog> createState() => _ScheduleFormDialogState();
}

class _ScheduleFormDialogState extends State<ScheduleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _locationController;
  late TextEditingController _teacherController;
  late TextEditingController _notesController;

  late String _selectedSubjectId;
  late String _selectedSubjectName;
  late int _selectedDayOfWeek;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  late bool _isActive;
  late bool _repeatWeekly;
  String? _timeErrorMessage;

  static const List<MapEntry<int, String>> _daysOfWeek = [
    MapEntry(1, 'Thứ Hai'),
    MapEntry(2, 'Thứ Ba'),
    MapEntry(3, 'Thứ Tư'),
    MapEntry(4, 'Thứ Năm'),
    MapEntry(5, 'Thứ Sáu'),
    MapEntry(6, 'Thứ Bảy'),
    MapEntry(7, 'Chủ Nhật'),
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.initialSchedule;

    if (widget.subjects.isNotEmpty) {
      if (item != null && widget.subjects.any((s) => s.id == item.subjectId)) {
        _selectedSubjectId = item.subjectId;
        _selectedSubjectName = item.subjectName;
      } else {
        _selectedSubjectId = widget.subjects.first.id;
        _selectedSubjectName = widget.subjects.first.name;
      }
    } else {
      _selectedSubjectId = 'subj_default';
      _selectedSubjectName = 'Môn học chung';
    }

    _selectedDayOfWeek = item?.dayOfWeek ?? DateTime.now().weekday;

    if (item != null) {
      _startTime = TimeOfDay(hour: item.startHour, minute: item.startMinute);
      _endTime = TimeOfDay(hour: item.endHour, minute: item.endMinute);
      _locationController = TextEditingController(text: item.location);
      _teacherController = TextEditingController(text: item.teacher);
      _notesController = TextEditingController(text: item.notes);
      _isActive = item.isActive;
      _repeatWeekly = item.repeatWeekly;
    } else {
      _startTime = const TimeOfDay(hour: 8, minute: 0);
      _endTime = const TimeOfDay(hour: 9, minute: 30);
      _locationController = TextEditingController();
      _teacherController = TextEditingController();
      _notesController = TextEditingController();
      _isActive = true;
      _repeatWeekly = true;
    }
  }

  @override
  void dispose() {
    _locationController.dispose();
    _teacherController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatTimeOfDay(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
      helpText: 'Chọn giờ bắt đầu học',
    );
    if (picked != null && mounted) {
      setState(() {
        _startTime = picked;
        _validateTime();
      });
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
      helpText: 'Chọn giờ kết thúc học',
    );
    if (picked != null && mounted) {
      setState(() {
        _endTime = picked;
        _validateTime();
      });
    }
  }

  bool _validateTime() {
    final startMin = _startTime.hour * 60 + _startTime.minute;
    final endMin = _endTime.hour * 60 + _endTime.minute;
    if (startMin >= endMin) {
      setState(() {
        _timeErrorMessage = 'Giờ bắt đầu phải trước giờ kết thúc';
      });
      return false;
    }
    setState(() {
      _timeErrorMessage = null;
    });
    return true;
  }

  /// Tìm xem có lịch nào bị trùng thời gian trên cùng thứ trong tuần hay không
  ClassSchedule? _findOverlappingSchedule() {
    final startMin = _startTime.hour * 60 + _startTime.minute;
    final endMin = _endTime.hour * 60 + _endTime.minute;
    final currentId = widget.initialSchedule?.id;

    for (final other in widget.existingSchedules) {
      if (other.id == currentId) continue;
      if (other.dayOfWeek == _selectedDayOfWeek && other.isActive) {
        if (startMin < other.endMinutesSinceMidnight &&
            other.startMinutesSinceMidnight < endMin) {
          return other;
        }
      }
    }
    return null;
  }

  void _submit() {
    if (!_validateTime()) return;
    if (!_formKey.currentState!.validate()) return;

    final schedule = ClassSchedule(
      id: widget.initialSchedule?.id ??
          'sched_${DateTime.now().millisecondsSinceEpoch}',
      subjectId: _selectedSubjectId,
      subjectName: _selectedSubjectName,
      dayOfWeek: _selectedDayOfWeek,
      startTime: _formatTimeOfDay(_startTime),
      endTime: _formatTimeOfDay(_endTime),
      location: _locationController.text.trim(),
      teacher: _teacherController.text.trim(),
      notes: _notesController.text.trim(),
      isActive: _isActive,
      repeatWeekly: _repeatWeekly,
    );

    widget.onSave(schedule);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialSchedule != null;
    final overlapping = _findOverlappingSchedule();

    return Dialog(
      backgroundColor: context.surfaceColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tiêu đề
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: context.primaryContainerColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isEditing
                              ? Icons.edit_calendar_rounded
                              : Icons.add_alarm_rounded,
                          color: AppColors.primary,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          isEditing
                              ? 'Chỉnh sửa lịch học'
                              : 'Thêm lịch học tuần',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: context.textPrimaryColor,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: context.textSecondaryColor,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(height: 1, color: context.borderColor),
                  const SizedBox(height: 14),

                  // Cảnh báo trùng lịch (nếu có)
                  if (overlapping != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: AppColors.priorityMediumBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.priorityMediumBorder,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.priorityMedium,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Cảnh báo: Trùng thời gian với "${overlapping.subjectName}" (${overlapping.timeRangeText}) vào ${overlapping.dayOfWeekText}.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: context.textPrimaryColor,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Chọn Môn học
                  DropdownButtonFormField<String>(
                    initialValue: widget.subjects.any((s) => s.id == _selectedSubjectId)
                        ? _selectedSubjectId
                        : (widget.subjects.isNotEmpty
                            ? widget.subjects.first.id
                            : null),
                    decoration: const InputDecoration(
                      labelText: 'Môn học *',
                      prefixIcon: Icon(Icons.menu_book_rounded, size: 20),
                    ),
                    items: widget.subjects.map((sub) {
                      return DropdownMenuItem<String>(
                        value: sub.id,
                        child: Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: sub.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                            Text(sub.name),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (newId) {
                      if (newId != null) {
                        setState(() {
                          _selectedSubjectId = newId;
                          final found = widget.subjects.firstWhere(
                            (s) => s.id == newId,
                            orElse: () => widget.subjects.first,
                          );
                          _selectedSubjectName = found.name;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // Thứ trong tuần
                  DropdownButtonFormField<int>(
                    initialValue: _selectedDayOfWeek,
                    decoration: const InputDecoration(
                      labelText: 'Thứ trong tuần *',
                      prefixIcon: Icon(Icons.calendar_today_rounded, size: 20),
                    ),
                    items: _daysOfWeek.map((entry) {
                      return DropdownMenuItem<int>(
                        value: entry.key,
                        child: Text(entry.value),
                      );
                    }).toList(),
                    onChanged: (newDay) {
                      if (newDay != null) {
                        setState(() => _selectedDayOfWeek = newDay);
                      }
                    },
                  ),
                  const SizedBox(height: 14),

                  // Giờ bắt đầu và Giờ kết thúc
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: _pickStartTime,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Giờ bắt đầu *',
                              prefixIcon: Icon(Icons.access_time_rounded, size: 20),
                            ),
                            child: Text(
                              _formatTimeOfDay(_startTime),
                              style: TextStyle(
                                fontSize: 15,
                                color: context.textPrimaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: _pickEndTime,
                          borderRadius: BorderRadius.circular(12),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Giờ kết thúc *',
                              prefixIcon:
                                  Icon(Icons.schedule_rounded, size: 20),
                            ),
                            child: Text(
                              _formatTimeOfDay(_endTime),
                              style: TextStyle(
                                fontSize: 15,
                                color: context.textPrimaryColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (_timeErrorMessage != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _timeErrorMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.priorityHigh,
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // Địa điểm / Phòng học (tùy chọn)
                  TextFormField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: 'Địa điểm / Phòng học (tùy chọn)',
                      hintText: 'Ví dụ: Phòng B204, Giảng đường A',
                      prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Giảng viên phụ trách (tùy chọn)
                  TextFormField(
                    controller: _teacherController,
                    decoration: const InputDecoration(
                      labelText: 'Giảng viên phụ trách (tùy chọn)',
                      hintText: 'Ví dụ: TS. Nguyễn Văn A',
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Ghi chú (tùy chọn)
                  TextFormField(
                    controller: _notesController,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú (tùy chọn)',
                      hintText: 'Ví dụ: Mang theo laptop và slide in sẵn',
                      prefixIcon: Icon(Icons.notes_rounded, size: 20),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Tùy chọn lặp hàng tuần & Bật/tắt lịch
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Lặp lại hàng tuần', style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                      'Tự động lên lịch báo thức cho các tuần tiếp theo',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    value: _repeatWeekly,
                    onChanged: (val) => setState(() => _repeatWeekly = val),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bật lịch học & báo thức', style: TextStyle(fontSize: 14)),
                    subtitle: const Text(
                      'Nhận thông báo và chuông báo trước giờ học',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    value: _isActive,
                    onChanged: (val) => setState(() => _isActive = val),
                  ),

                  const SizedBox(height: 16),

                  // Nút Hủy và Lưu
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Hủy'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: Text(isEditing ? 'Cập nhật' : 'Thêm lịch học'),
                        onPressed: _submit,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

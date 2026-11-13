import 'package:flutter/material.dart';

import '../models/class_schedule.dart';
import '../models/subject.dart';
import '../models/timetable_import_model.dart';
import '../services/image_timetable_importer.dart';
import '../theme/app_colors.dart';

/// Hộp thoại Nhập thời khóa biểu từ ảnh (Phase 6B Foundation - Free-First)
/// Hỗ trợ chọn ảnh JPG, JPEG, PNG, hiển thị ảnh đã chọn, thông báo trạng thái
/// nhận diện OCR (chưa xử lý, đang xử lý, chưa hỗ trợ nhận diện, có lỗi),
/// và cho phép xem trước, sửa, bỏ qua, bổ sung lịch học từ ảnh trước khi xác nhận lưu.
class ImageTimetableImportDialog extends StatefulWidget {
  final List<Subject> subjects;
  final List<ClassSchedule> existingSchedules;
  final ImageTimetableCoordinator? coordinator;
  final Future<void> Function({
    required List<ClassSchedule> schedules,
    required List<Subject> newSubjects,
  }) onImport;

  const ImageTimetableImportDialog({
    super.key,
    required this.subjects,
    required this.existingSchedules,
    this.coordinator,
    required this.onImport,
  });

  @override
  State<ImageTimetableImportDialog> createState() =>
      _ImageTimetableImportDialogState();
}

class _ImageTimetableImportDialogState
    extends State<ImageTimetableImportDialog> {
  late final ImageTimetableCoordinator _coordinator;

  TimetableImage? _selectedImage;
  OcrEngineStatus _ocrStatus = OcrEngineStatus.idle;
  String? _statusMessage;
  bool _isProcessing = false;
  bool _showImagePreview = true;

  // Danh sách các dòng lịch học đã bóc tách / nhập thủ công từ ảnh
  final List<ImportedScheduleItem> _items = [];

  // Bảng màu cho môn học mới
  static const List<Color> _palette = [
    Color(0xFF3B5BDB),
    Color(0xFF0284C7),
    Color(0xFFD97706),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  @override
  void initState() {
    super.initState();
    _coordinator = widget.coordinator ?? ImageTimetableCoordinator();
  }

  // --- THAO TÁC CHỌN VÀ ĐỔI ẢNH (CAMERA & GALLERY) ---

  Future<void> _pickImage({
    TimetableImageSource source = TimetableImageSource.gallery,
  }) async {
    try {
      final img = await _coordinator.imagePicker.pickImage(source: source);
      if (img == null || !mounted) return;

      setState(() {
        _selectedImage = img;
        _ocrStatus = OcrEngineStatus.idle;
        _statusMessage =
            'Ảnh đã sẵn sàng. Nhấn "Quét & Nhận diện thời khóa biểu" bên dưới để trích xuất dữ liệu.';
        _items.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocrStatus = OcrEngineStatus.error;
        _statusMessage = 'Lỗi khi chụp hoặc đọc ảnh: $e';
      });
    }
  }

  void _showImageSourcePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.surfaceColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'Chọn nguồn ảnh thời khóa biểu',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: ctx.textPrimaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ctx.primaryContainerColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: AppColors.primary, size: 22),
                  ),
                  title: const Text('Chụp ảnh mới bằng Camera',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Chụp trực tiếp thời khóa biểu giấy hoặc màn hình'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickImage(source: TimetableImageSource.camera);
                  },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ctx.primaryContainerColor,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.photo_library_rounded,
                        color: AppColors.primary, size: 22),
                  ),
                  title: const Text('Chọn ảnh từ Thư viện thiết bị',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Chọn ảnh chụp màn hình hoặc tệp ảnh có sẵn (JPG, PNG)'),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _pickImage(source: TimetableImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _runRecognition(TimetableImage image) async {
    setState(() {
      _isProcessing = true;
      _ocrStatus = OcrEngineStatus.processing;
      _statusMessage =
          'Đang tiến hành quét và nhận diện chữ On-Device qua Google ML Kit...';
    });

    try {
      final result = await _coordinator.textRecognizer.recognizeText(image);

      if (!mounted) return;

      if (!result.isSuccess) {
        setState(() {
          _isProcessing = false;
          _ocrStatus = result.status;
          _statusMessage = result.errorMessage ??
              'Không thể nhận diện văn bản từ hình ảnh này.';
        });
        return;
      }

      // Khi có kết quả text thật từ OCR:
      final parsed = _coordinator.textParser.parseTextToSchedules(
        rawText: result.rawText,
        textBlocks: result.textBlocks,
        structuredBlocks: result.structuredBlocks,
        existingSubjects: widget.subjects,
        existingSchedules: widget.existingSchedules,
      );

      setState(() {
        _isProcessing = false;
        _ocrStatus = OcrEngineStatus.success;
        _statusMessage = parsed.isNotEmpty
            ? 'Đã nhận diện thành công ${parsed.length} buổi học từ ảnh.'
            : 'Đã nhận diện chữ trong ảnh nhưng chưa tìm thấy cấu trúc thời khóa biểu rõ ràng. '
                'Bạn có thể nhìn ảnh phía trên và bấm "+ Thêm buổi học" để lập lịch.';
        _items.clear();
        _items.addAll(parsed);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _ocrStatus = OcrEngineStatus.error;
        _statusMessage = 'Đã xảy ra sự cố trong quá trình nhận diện: $e';
      });
    }
  }

  // --- THAO TÁC THÊM & CHỈNH SỬA TỪNG DÒNG ---

  void _openEditItemDialog({ImportedScheduleItem? item, int? index}) {
    final isNew = item == null;
    final formKey = GlobalKey<FormState>();

    final subjectController =
        TextEditingController(text: item?.matchedSubjectName ?? '');
    final locationController =
        TextEditingController(text: item?.location ?? '');
    final teacherController =
        TextEditingController(text: item?.teacher ?? '');
    final notesController = TextEditingController(text: item?.notes ?? '');

    int selectedDay = item?.dayOfWeek ?? DateTime.now().weekday;
    TimeOfDay startTime = item?.startTime != null
        ? _parseTime(item!.startTime!)
        : const TimeOfDay(hour: 8, minute: 0);
    TimeOfDay endTime = item?.endTime != null
        ? _parseTime(item!.endTime!)
        : const TimeOfDay(hour: 9, minute: 30);

    String? matchedSubId = item?.matchedSubjectId;
    bool isNewSub = item?.isNewSubject ?? true;

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              backgroundColor: ctx.surfaceColor,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text(
                isNew ? 'Thêm buổi học từ ảnh' : 'Chỉnh sửa thông tin buổi học',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: ctx.textPrimaryColor,
                ),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Tên môn học
                        TextFormField(
                          controller: subjectController,
                          decoration: InputDecoration(
                            labelText: 'Tên môn học *',
                            hintText: 'Ví dụ: Toán cao cấp',
                            prefixIcon: const Icon(Icons.menu_book_rounded),
                            filled: true,
                            fillColor: ctx.surfaceMutedColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Vui lòng nhập tên môn học';
                            }
                            return null;
                          },
                          onChanged: (val) {
                            // Tự động tìm xem có khớp môn có sẵn không
                            Subject? match;
                            for (final s in widget.subjects) {
                              if (s.name.trim().toLowerCase() ==
                                  val.trim().toLowerCase()) {
                                match = s;
                                break;
                              }
                            }
                            setDialogState(() {
                              if (match != null) {
                                matchedSubId = match.id;
                                isNewSub = false;
                              } else {
                                matchedSubId = null;
                                isNewSub = true;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Dropdown liên kết môn học
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: ctx.surfaceMutedColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: ctx.borderColor),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String?>(
                              value: isNewSub ? null : matchedSubId,
                              isExpanded: true,
                              hint: Text(
                                isNewSub
                                    ? 'Tạo môn mới "${subjectController.text.trim()}"'
                                    : 'Chọn môn học liên kết',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isNewSub
                                      ? AppColors.primary
                                      : ctx.textPrimaryColor,
                                  fontWeight: isNewSub
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('+ Tạo thành môn học mới'),
                                ),
                                ...widget.subjects.map(
                                  (s) => DropdownMenuItem<String?>(
                                    value: s.id,
                                    child: Row(
                                      children: [
                                        Icon(s.icon, size: 16, color: s.color),
                                        const SizedBox(width: 8),
                                        Text(s.name),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == null) {
                                    isNewSub = true;
                                    matchedSubId = null;
                                  } else {
                                    isNewSub = false;
                                    matchedSubId = val;
                                    final found = widget.subjects
                                        .firstWhere((s) => s.id == val);
                                    subjectController.text = found.name;
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Thứ trong tuần
                        DropdownButtonFormField<int>(
                          value: selectedDay,
                          decoration: InputDecoration(
                            labelText: 'Thứ trong tuần *',
                            prefixIcon: const Icon(Icons.calendar_today_rounded),
                            filled: true,
                            fillColor: ctx.surfaceMutedColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Thứ Hai')),
                            DropdownMenuItem(value: 2, child: Text('Thứ Ba')),
                            DropdownMenuItem(value: 3, child: Text('Thứ Tư')),
                            DropdownMenuItem(value: 4, child: Text('Thứ Năm')),
                            DropdownMenuItem(value: 5, child: Text('Thứ Sáu')),
                            DropdownMenuItem(value: 6, child: Text('Thứ Bảy')),
                            DropdownMenuItem(value: 7, child: Text('Chủ Nhật')),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() => selectedDay = val);
                            }
                          },
                        ),
                        const SizedBox(height: 14),

                        // Khung giờ học
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: ctx,
                                    initialTime: startTime,
                                  );
                                  if (picked != null) {
                                    setDialogState(() => startTime = picked);
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: ctx.surfaceMutedColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: ctx.borderColor),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Giờ bắt đầu',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: ctx.textSecondaryColor)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatTime(startTime),
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: () async {
                                  final picked = await showTimePicker(
                                    context: ctx,
                                    initialTime: endTime,
                                  );
                                  if (picked != null) {
                                    setDialogState(() => endTime = picked);
                                  }
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: ctx.surfaceMutedColor,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: ctx.borderColor),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Giờ kết thúc',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: ctx.textSecondaryColor)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _formatTime(endTime),
                                        style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Phòng học
                        TextFormField(
                          controller: locationController,
                          decoration: InputDecoration(
                            labelText: 'Phòng học / Địa điểm',
                            hintText: 'Ví dụ: P.302, Tòa A1',
                            prefixIcon: const Icon(Icons.location_on_outlined),
                            filled: true,
                            fillColor: ctx.surfaceMutedColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Giảng viên
                        TextFormField(
                          controller: teacherController,
                          decoration: InputDecoration(
                            labelText: 'Giảng viên',
                            hintText: 'Ví dụ: TS. Nguyễn Văn A',
                            prefixIcon: const Icon(Icons.person_outline_rounded),
                            filled: true,
                            fillColor: ctx.surfaceMutedColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Ghi chú
                        TextFormField(
                          controller: notesController,
                          decoration: InputDecoration(
                            labelText: 'Ghi chú',
                            hintText: 'Ví dụ: Mang laptop thực hành',
                            prefixIcon: const Icon(Icons.notes_rounded),
                            filled: true,
                            fillColor: ctx.surfaceMutedColor,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () {
                    if (!formKey.currentState!.validate()) return;

                    final startStr = _formatTime(startTime);
                    final endStr = _formatTime(endTime);
                    final subName = subjectController.text.trim();

                    // Xác định lỗi giờ
                    final startMin = startTime.hour * 60 + startTime.minute;
                    final endMin = endTime.hour * 60 + endTime.minute;
                    ImportItemStatus status = ImportItemStatus.valid;
                    String? errorMsg;
                    String? warnMsg;

                    if (startMin >= endMin) {
                      status = ImportItemStatus.errorInvalidTime;
                      errorMsg = 'Giờ bắt đầu phải trước giờ kết thúc';
                    } else {
                      // Kiểm tra trùng lịch
                      for (final ex in widget.existingSchedules) {
                        if (ex.dayOfWeek == selectedDay && ex.isActive) {
                          if (startMin < ex.endMinutesSinceMidnight &&
                              ex.startMinutesSinceMidnight < endMin) {
                            status = ImportItemStatus.warningOverlap;
                            warnMsg =
                                'Trùng giờ với ${ex.subjectName} (${ex.timeRangeText})';
                            break;
                          }
                        }
                      }
                      if (status == ImportItemStatus.valid && isNewSub) {
                        status = ImportItemStatus.newSubject;
                      }
                    }

                    final newItem = ImportedScheduleItem(
                      rowIndex: item?.rowIndex ?? (_items.length + 1),
                      rawSubjectName: subName,
                      matchedSubjectId: matchedSubId,
                      matchedSubjectName: subName,
                      isNewSubject: isNewSub,
                      dayOfWeek: selectedDay,
                      startTime: startStr,
                      endTime: endStr,
                      location: locationController.text.trim(),
                      teacher: teacherController.text.trim(),
                      notes: notesController.text.trim(),
                      isSelected: !status.hasError,
                      status: status,
                      errorMessage: errorMsg,
                      warningMessage: warnMsg,
                    );

                    setState(() {
                      if (isNew || index == null) {
                        _items.add(newItem);
                      } else {
                        _items[index] = newItem;
                      }
                    });

                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Lưu thông tin'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  void _toggleItemSelection(int index) {
    final item = _items[index];
    if (item.hasError) return;
    setState(() {
      item.isSelected = !item.isSelected;
    });
  }

  // --- LƯU VÀO CƠ SỞ DỮ LIỆU ---

  Future<void> _saveAndImport() async {
    final selectedItems =
        _items.where((i) => i.isSelected && !i.hasError).toList();

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn ít nhất một lịch học hợp lệ để lưu.'),
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // 1. Tạo danh sách môn học mới không trùng lặp
      final Map<String, Subject> createdSubjectByName = {};
      final List<Subject> newSubjectsToCreate = [];
      int colorIdx = 0;

      for (final item in selectedItems) {
        if (item.isNewSubject &&
            (item.matchedSubjectId == null || item.matchedSubjectId!.isEmpty)) {
          final normName = item.matchedSubjectName.trim().toLowerCase();
          if (!createdSubjectByName.containsKey(normName)) {
            final newSubId =
                'subj_img_${DateTime.now().millisecondsSinceEpoch}_${createdSubjectByName.length}';
            final newSub = Subject(
              id: newSubId,
              name: item.matchedSubjectName.trim(),
              description: 'Tạo tự động khi nhập thời khóa biểu từ ảnh',
              color: _palette[colorIdx % _palette.length],
              icon: Icons.school_rounded,
            );
            colorIdx++;
            createdSubjectByName[normName] = newSub;
            newSubjectsToCreate.add(newSub);
          }
          item.matchedSubjectId = createdSubjectByName[normName]!.id;
        }
      }

      // 2. Chuyển thành ClassSchedule
      final List<ClassSchedule> schedulesToSave = [];
      for (final item in selectedItems) {
        final targetSubId = item.matchedSubjectId ??
            (widget.subjects.isNotEmpty
                ? widget.subjects.first.id
                : 'subj_default');
        schedulesToSave.add(item.toClassSchedule(targetSubjectId: targetSubId));
      }

      // 3. Thực hiện lưu qua repository
      await widget.onImport(
        schedules: schedulesToSave,
        newSubjects: newSubjectsToCreate,
      );

      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _ocrStatus = OcrEngineStatus.error;
        _statusMessage = 'Lỗi khi lưu dữ liệu lịch học: $e';
      });
    }
  }

  // --- CÁC HÀM TIỆN ÍCH ---

  TimeOfDay _parseTime(String time) {
    try {
      final parts = time.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  String _formatTime(TimeOfDay t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  // --- GIAO DIỆN CHÍNH (BUILD) ---

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final dialogHeight = mediaQuery.size.height * 0.88;
    final validSelectedCount =
        _items.where((i) => i.isSelected && !i.hasError).length;

    return Dialog(
      backgroundColor: context.surfaceColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 680,
          maxHeight: dialogHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const Divider(height: 22),
              Expanded(
                child: _isProcessing
                    ? _buildLoadingState(context)
                    : _selectedImage == null
                        ? _buildImageSelectionPrompt(context)
                        : _buildMainContent(context),
              ),
              const SizedBox(height: 12),
              _buildFooter(context, validSelectedCount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.primaryContainerColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.document_scanner_rounded,
            color: AppColors.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nhập thời khóa biểu từ ảnh',
                style: TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Hỗ trợ JPG, JPEG, PNG • Ưu tiên xử lý cục bộ trên thiết bị',
                style: TextStyle(
                  fontSize: 12,
                  color: context.textSecondaryColor,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('close_image_import_dialog'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Đóng',
        ),
      ],
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 18),
          Text(
            _statusMessage ?? 'Đang xử lý...',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.textPrimaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageSelectionPrompt(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                // 1. Chụp ảnh mới từ Camera
                Expanded(
                  child: InkWell(
                    key: const ValueKey('capture_timetable_camera_button'),
                    onTap: () => _pickImage(source: TimetableImageSource.camera),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 28, horizontal: 16),
                      decoration: BoxDecoration(
                        color: context.surfaceMutedColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: context.primaryContainerColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt_rounded,
                              size: 32,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Chụp ảnh Camera',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Chụp trực tiếp thời khóa biểu',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // 2. Chọn ảnh từ Thư viện
                Expanded(
                  child: InkWell(
                    key: const ValueKey('pick_timetable_gallery_button'),
                    onTap: () => _pickImage(source: TimetableImageSource.gallery),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 28, horizontal: 16),
                      decoration: BoxDecoration(
                        color: context.surfaceMutedColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: context.primaryContainerColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.photo_library_rounded,
                              size: 32,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Thư viện ảnh',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: context.textPrimaryColor,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Chọn ảnh chụp màn hình (JPG/PNG)',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: context.textSecondaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      size: 20, color: AppColors.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Chụp hoặc chọn ảnh rõ nét, ngay ngắn để nhận diện môn học, '
                      'thứ và khung giờ chính xác nhất.',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.textSecondaryColor,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Thanh hiển thị ảnh & nút đổi ảnh
        _buildImageBar(context),
        const SizedBox(height: 10),

        // 2. Banner trạng thái OCR
        _buildOcrStatusBanner(context),
        const SizedBox(height: 8),

        // Nút hành động OCR tương ứng với từng trạng thái
        if (_ocrStatus == OcrEngineStatus.idle)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: FilledButton.icon(
              key: const ValueKey('start_ocr_recognition_button'),
              onPressed: () => _runRecognition(_selectedImage!),
              icon: const Icon(Icons.document_scanner_rounded, size: 20),
              label: const Text('Quét & Nhận diện thời khóa biểu'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          )
        else if (_ocrStatus == OcrEngineStatus.error)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('rescan_ocr_button'),
                    onPressed: () => _runRecognition(_selectedImage!),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Quét lại ảnh này'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('try_another_image_button'),
                    onPressed: _showImageSourcePicker,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('Thử ảnh khác'),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 6),

        // 3. Tiêu đề danh sách & nút thêm dòng
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Danh sách buổi học (${_items.length})',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
              ),
            ),
            Row(
              children: [
                if (_ocrStatus == OcrEngineStatus.success)
                  TextButton.icon(
                    key: const ValueKey('rescan_ocr_button'),
                    onPressed: () => _runRecognition(_selectedImage!),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label:
                        const Text('Quét lại', style: TextStyle(fontSize: 12)),
                  ),
                TextButton.icon(
                  key: const ValueKey('add_manual_schedule_from_image_button'),
                  onPressed: () => _openEditItemDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Thêm buổi học',
                      style: TextStyle(fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 4. Danh sách các buổi học xem trước
        Expanded(
          child: _items.isEmpty
              ? _buildEmptySchedulePrompt(context)
              : ListView.separated(
                  key: const ValueKey('image_import_preview_list'),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, idx) =>
                      _buildScheduleItemCard(ctx, _items[idx], idx),
                ),
        ),
      ],
    );
  }

  Widget _buildImageBar(BuildContext context) {
    final img = _selectedImage!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.surfaceMutedColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.image_outlined,
                  size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${img.name} (${img.sizeInKb.toStringAsFixed(1)} KB)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: context.textPrimaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Icon(
                  _showImagePreview
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 20,
                ),
                tooltip: _showImagePreview ? 'Thu gọn ảnh' : 'Mở rộng ảnh',
                onPressed: () {
                  setState(() => _showImagePreview = !_showImagePreview);
                },
                visualDensity: VisualDensity.compact,
              ),
              TextButton.icon(
                key: const ValueKey('repick_timetable_image_button'),
                onPressed: _showImageSourcePicker,
                icon: const Icon(Icons.change_circle_outlined, size: 16),
                label: const Text('Đổi ảnh', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ],
          ),
          if (_showImagePreview) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 130,
                color: Colors.black12,
                child: Image.memory(
                  img.bytes,
                  fit: BoxFit.contain,
                  width: double.infinity,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOcrStatusBanner(BuildContext context) {
    Color bg = context.surfaceMutedColor;
    Color fg = context.textSecondaryColor;
    IconData icon = Icons.info_outline_rounded;
    String title = 'Trạng thái xử lý';
    String desc = _statusMessage ?? '';

    switch (_ocrStatus) {
      case OcrEngineStatus.idle:
        bg = context.primaryContainerColor;
        fg = AppColors.primary;
        icon = Icons.photo_library_outlined;
        title = 'Ảnh đã sẵn sàng';
        desc =
            'Nhấn nút "Quét & Nhận diện thời khóa biểu" để Google ML Kit On-Device bắt đầu trích xuất.';
        break;
      case OcrEngineStatus.processing:
        bg = context.primaryContainerColor;
        fg = AppColors.primary;
        icon = Icons.sync_rounded;
        title = 'Đang nhận diện chữ On-Device...';
        desc =
            'Google ML Kit đang quét các khối chữ và tọa độ bảng trong ảnh cục bộ.';
        break;
      case OcrEngineStatus.unsupported:
        bg = AppColors.primary.withValues(alpha: 0.1);
        fg = AppColors.primary;
        icon = Icons.info_outline_rounded;
        title = 'Môi trường Web Preview';
        desc =
            'Google ML Kit On-Device OCR chỉ khả dụng trên thiết bị di động (Android / iOS). '
            'Trên Web, bạn có thể xem ảnh phía trên và bấm "+ Thêm buổi học" để lập lịch thủ công.';
        break;
      case OcrEngineStatus.error:
        bg = AppColors.error.withValues(alpha: 0.12);
        fg = AppColors.error;
        icon = Icons.error_outline_rounded;
        title = 'Không nhận diện được nội dung';
        desc = _statusMessage ?? 'Không thể phân tích văn bản từ ảnh.';
        break;
      case OcrEngineStatus.success:
        bg = AppColors.success.withValues(alpha: 0.12);
        fg = AppColors.success;
        icon = Icons.check_circle_outline_rounded;
        title = 'Nhận diện thành công';
        desc =
            _statusMessage ?? 'Vui lòng kiểm tra lại các mục bên dưới trước khi lưu.';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: context.textPrimaryColor,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySchedulePrompt(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_month_outlined,
                size: 38, color: context.textSecondaryColor),
            const SizedBox(height: 10),
            Text(
              'Chưa có buổi học nào trong danh sách',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Nhấn "+ Thêm buổi học" ở trên để nhập các môn học nhìn thấy từ ảnh.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: context.textSecondaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleItemCard(
      BuildContext context, ImportedScheduleItem item, int index) {
    Color cardBorder = context.borderColor;
    if (item.hasError) {
      cardBorder = AppColors.error.withValues(alpha: 0.6);
    } else if (item.status == ImportItemStatus.warningOverlap) {
      cardBorder = AppColors.warning.withValues(alpha: 0.6);
    }

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      padding: const EdgeInsets.all(10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: item.isSelected && !item.hasError,
            onChanged: item.hasError ? null : (_) => _toggleItemSelection(index),
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: context.primaryContainerColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.dayOfWeekText,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.matchedSubjectName,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: context.textPrimaryColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      tooltip: 'Chỉnh sửa',
                      onPressed: () =>
                          _openEditItemDialog(item: item, index: index),
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded,
                          size: 18, color: AppColors.error),
                      tooltip: 'Bỏ qua',
                      onPressed: () => _removeItem(index),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time_rounded,
                        size: 13, color: context.textSecondaryColor),
                    const SizedBox(width: 4),
                    Text(
                      item.timeRangeText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    if (item.location.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Icon(Icons.location_on_outlined,
                          size: 13, color: context.textSecondaryColor),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          item.location,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: context.textSecondaryColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.teacher.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline_rounded,
                          size: 13, color: context.textSecondaryColor),
                      const SizedBox(width: 4),
                      Text(
                        'GV: ${item.teacher}',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: context.textSecondaryColor,
                        ),
                      ),
                    ],
                  ),
                ],
                if (item.hasError) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.errorMessage ?? 'Dữ liệu không hợp lệ',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else if (item.status == ImportItemStatus.warningOverlap) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.warningMessage ?? 'Trùng khung giờ học',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context, int validCount) {
    return Row(
      children: [
        OutlinedButton(
          key: const ValueKey('cancel_image_import_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        const Spacer(),
        FilledButton.icon(
          key: const ValueKey('confirm_save_image_schedule_button'),
          onPressed: validCount > 0 ? _saveAndImport : null,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text('Lưu $validCount lịch học'),
        ),
      ],
    );
  }
}

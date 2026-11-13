import 'dart:io' as io;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/class_schedule.dart';
import '../models/subject.dart';
import '../models/timetable_import_model.dart';
import '../services/timetable_import_service.dart';
import '../theme/app_colors.dart';

/// Hộp thoại 4 bước nhập thời khóa biểu thông minh từ file Excel (.xlsx) và CSV (.csv)
/// - Bước 1: Chọn file và xem hướng dẫn định dạng mẫu
/// - Bước 2: Đọc và phân tích cấu trúc dữ liệu
/// - Bước 3: Xem trước, tùy chỉnh chọn dòng, gán môn học và cảnh báo trùng lịch
/// - Bước 4: Xác nhận lưu vào CSDL và tóm tắt kết quả
class TimetableImportDialog extends StatefulWidget {
  final List<Subject> subjects;
  final List<ClassSchedule> existingSchedules;
  final Future<void> Function({
    required List<ClassSchedule> schedules,
    required List<Subject> newSubjects,
  }) onImport;

  const TimetableImportDialog({
    super.key,
    required this.subjects,
    required this.existingSchedules,
    required this.onImport,
  });

  @override
  State<TimetableImportDialog> createState() => _TimetableImportDialogState();
}

class _TimetableImportDialogState extends State<TimetableImportDialog> {
  int _currentStep = 1; // 1: Chọn file, 2: Đang đọc, 3: Xem trước, 4: Hoàn tất
  bool _isProcessing = false;
  String? _selectedFileName;
  TimetableParseResult? _parseResult;
  TimetableImportSummary? _importSummary;
  String? _errorMessage;

  // Màu sắc cấp phát cho các môn học mới được tạo tự động
  static const List<Color> _paletteColors = [
    Color(0xFF3B5BDB),
    Color(0xFF0284C7),
    Color(0xFFD97706),
    Color(0xFF10B981),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
    Color(0xFFF97316),
    Color(0xFF14B8A6),
    Color(0xFF6366F1),
  ];

  // --- BƯỚC 1: CHỌN FILE VÀ ĐỌC BYTES ---

  Future<void> _pickFile() async {
    try {
      setState(() {
        _errorMessage = null;
      });

      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv'],
      );

      if (result.isEmpty) {
        return; // Người dùng hủy chọn
      }

      final file = result.first;
      _selectedFileName = file.name;

      Uint8List? fileBytes;
      try {
        fileBytes = await file.readAsBytes();
      } catch (_) {}

      if ((fileBytes == null || fileBytes.isEmpty) && !kIsWeb && file.path != null) {
        final f = io.File(file.path!);
        if (await f.exists()) {
          fileBytes = await f.readAsBytes();
        }
      }

      if (fileBytes == null || fileBytes.isEmpty) {
        setState(() {
          _errorMessage =
              'Không thể đọc nội dung file hoặc file có kích thước rỗng (0 bytes).';
        });
        return;
      }

      // Chuyển sang Bước 2 & chạy phân tích
      setState(() {
        _currentStep = 2;
        _isProcessing = true;
      });

      // Phân tích dữ liệu trong microtask
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _processFileBytes(fileBytes, file.name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Lỗi khi chọn file: $e';
        _currentStep = 1;
        _isProcessing = false;
      });
    }
  }

  // --- BƯỚC 2: PHÂN TÍCH DỮ LIỆU ---

  void _processFileBytes(Uint8List bytes, String fileName) {
    final parseRes = TimetableImportService.parseFileBytes(
      bytes: bytes,
      fileName: fileName,
      existingSubjects: widget.subjects,
      existingSchedules: widget.existingSchedules,
    );

    if (!mounted) return;

    if (parseRes.fatalError != null) {
      setState(() {
        _parseResult = parseRes;
        _errorMessage = parseRes.fatalError;
        _currentStep = 1;
        _isProcessing = false;
      });
      return;
    }

    setState(() {
      _parseResult = parseRes;
      _currentStep = 3;
      _isProcessing = false;
    });
  }

  // --- BƯỚC 3: TÙY CHỌN & CHỌN / BỎ CHỌN ---

  void _toggleSelectAll(bool select) {
    if (_parseResult == null) return;
    setState(() {
      for (final item in _parseResult!.items) {
        if (!item.hasError) {
          item.isSelected = select;
        }
      }
    });
  }

  void _toggleItemSelection(ImportedScheduleItem item) {
    if (item.hasError) return;
    setState(() {
      item.isSelected = !item.isSelected;
    });
  }

  void _showLinkSubjectDialog(ImportedScheduleItem item) {
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
                    'Liên kết môn học cho "${item.rawSubjectName}"',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: ctx.textPrimaryColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(
                    Icons.add_circle_outline_rounded,
                    color: AppColors.primary,
                  ),
                  title: Text(
                    'Tạo môn mới: "${item.rawSubjectName}"',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text('Tự động thêm vào danh mục môn học'),
                  trailing: item.isNewSubject
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      item.isNewSubject = true;
                      item.matchedSubjectId = null;
                      item.matchedSubjectName = item.rawSubjectName;
                      if (!item.hasError) {
                        item.status = ImportItemStatus.newSubject;
                      }
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
                const Divider(height: 1),
                if (widget.subjects.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('Chưa có môn học nào khác trong hệ thống.'),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.subjects.length,
                      itemBuilder: (context, idx) {
                        final s = widget.subjects[idx];
                        final isSelected =
                            !item.isNewSubject && item.matchedSubjectId == s.id;
                        return ListTile(
                          leading: Icon(s.icon, color: s.color),
                          title: Text(s.name),
                          trailing: isSelected
                              ? const Icon(Icons.check, color: AppColors.primary)
                              : null,
                          onTap: () {
                            setState(() {
                              item.isNewSubject = false;
                              item.matchedSubjectId = s.id;
                              item.matchedSubjectName = s.name;
                              if (!item.hasError) {
                                item.status = ImportItemStatus.valid;
                              }
                            });
                            Navigator.of(ctx).pop();
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- BƯỚC 4: THỰC THI NHẬP & TẠO MÔN MỚI ---

  Future<void> _executeImport() async {
    if (_parseResult == null) return;
    final selectedItems =
        _parseResult!.items.where((i) => i.isSelected && !i.hasError).toList();

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn ít nhất một lịch học hợp lệ để nhập.')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      // 1. Nhóm các môn học mới cần tạo (loại trừ trùng lặp theo tên)
      final Map<String, Subject> createdSubjectByName = {};
      final List<Subject> newSubjectsToCreate = [];
      int colorIdx = 0;

      for (final item in selectedItems) {
        if (item.isNewSubject &&
            (item.matchedSubjectId == null || item.matchedSubjectId!.isEmpty)) {
          final normName = item.matchedSubjectName.trim().toLowerCase();
          if (!createdSubjectByName.containsKey(normName)) {
            final newSubId =
                'subj_imp_${DateTime.now().millisecondsSinceEpoch}_${createdSubjectByName.length}';
            final newSub = Subject(
              id: newSubId,
              name: item.matchedSubjectName.trim(),
              description: 'Tự động tạo khi nhập thời khóa biểu',
              color: _paletteColors[colorIdx % _paletteColors.length],
              icon: Icons.school_rounded,
            );
            colorIdx++;
            createdSubjectByName[normName] = newSub;
            newSubjectsToCreate.add(newSub);
          }
          item.matchedSubjectId = createdSubjectByName[normName]!.id;
        }
      }

      // 2. Chuyển đổi thành ClassSchedule
      final List<ClassSchedule> schedulesToSave = [];
      for (final item in selectedItems) {
        final targetSubId = item.matchedSubjectId ??
            (widget.subjects.isNotEmpty
                ? widget.subjects.first.id
                : 'subj_default');
        schedulesToSave.add(item.toClassSchedule(targetSubjectId: targetSubId));
      }

      // 3. Thực hiện lưu thông qua callback
      await widget.onImport(
        schedules: schedulesToSave,
        newSubjects: newSubjectsToCreate,
      );

      final summary = TimetableImportSummary(
        importedCount: schedulesToSave.length,
        skippedCount: _parseResult!.items.length - schedulesToSave.length,
        errorCount: _parseResult!.errorCount,
        createdSubjectsCount: newSubjectsToCreate.length,
        createdSubjects: newSubjectsToCreate,
      );

      if (!mounted) return;
      setState(() {
        _importSummary = summary;
        _currentStep = 4;
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Lỗi trong quá trình nhập dữ liệu: $e';
        _isProcessing = false;
      });
    }
  }

  void _copySampleCsv() {
    final sample = TimetableImportService.generateSampleCsv();
    Clipboard.setData(ClipboardData(text: sample));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Đã sao chép nội dung CSV mẫu vào bộ nhớ tạm!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // --- GIAO DIỆN (BUILD METHODS) ---

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final dialogHeight = mediaQuery.size.height * 0.86;

    return Dialog(
      backgroundColor: context.surfaceColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: dialogHeight,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(context),
              const Divider(height: 24),
              Expanded(
                child: _buildBody(context),
              ),
              if (_currentStep == 3) ...[
                const SizedBox(height: 12),
                _buildStep3Footer(context),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    String title = 'Nhập thời khóa biểu';
    String subtitle = 'Nhập nhanh từ Excel (.xlsx) hoặc CSV (.csv)';

    if (_currentStep == 3) {
      title = 'Xem trước & Xác nhận';
      subtitle = 'Kiểm tra thông tin trước khi lưu vào hệ thống';
    } else if (_currentStep == 4) {
      title = 'Kết quả nhập';
      subtitle = 'Thời khóa biểu đã được cập nhật thành công';
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: context.primaryContainerColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _currentStep == 4
                ? Icons.check_circle_rounded
                : Icons.upload_file_rounded,
            color: _currentStep == 4 ? AppColors.success : AppColors.primary,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: context.textPrimaryColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12.5,
                  color: context.textSecondaryColor,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('close_import_dialog_button'),
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
          tooltip: 'Đóng',
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isProcessing) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 18),
            Text(
              _currentStep == 2
                  ? 'Đang đọc và phân tích tệp...'
                  : 'Đang lưu lịch học và đồng bộ báo thức...',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Quá trình này chỉ mất vài giây',
              style: TextStyle(
                fontSize: 13,
                color: context.textSecondaryColor,
              ),
            ),
          ],
        ),
      );
    }

    switch (_currentStep) {
      case 1:
        return _buildStep1SelectFile(context);
      case 3:
        return _buildStep3Preview(context);
      case 4:
        return _buildStep4Summary(context);
      default:
        return const SizedBox.shrink();
    }
  }

  // --- GIAO DIỆN BƯỚC 1: CHỌN FILE ---

  Widget _buildStep1SelectFile(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.error.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Vùng chọn file nổi bật
          InkWell(
            key: const ValueKey('pick_timetable_file_button'),
            onTap: _pickFile,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
              decoration: BoxDecoration(
                color: context.surfaceMutedColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.4),
                  width: 1.5,
                  strokeAlign: BorderSide.strokeAlignInside,
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
                      Icons.cloud_upload_outlined,
                      size: 36,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Nhấn để chọn tệp .xlsx hoặc .csv',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: context.textPrimaryColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hỗ trợ tệp bảng tính Excel hoặc tệp phân cách dấu phẩy CSV',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: context.textSecondaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Khối hướng dẫn định dạng file
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.surfaceColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Quy cách định dạng tệp',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _copySampleCsv,
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Sao chép mẫu CSV',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildGuidelineRow(
                  context,
                  Icons.check_circle_outline_rounded,
                  'Cột bắt buộc: "Môn học", "Thứ", "Giờ bắt đầu", "Giờ kết thúc" (hoặc "Khung giờ").',
                ),
                const SizedBox(height: 6),
                _buildGuidelineRow(
                  context,
                  Icons.check_circle_outline_rounded,
                  'Cột tùy chọn: "Phòng học", "Ghi chú".',
                ),
                const SizedBox(height: 6),
                _buildGuidelineRow(
                  context,
                  Icons.info_outline_rounded,
                  'Nhận diện thứ linh hoạt: "Thứ 2".."Thứ 7", "CN", "T2".."T7", "Monday".."Sunday".',
                ),
                const SizedBox(height: 6),
                _buildGuidelineRow(
                  context,
                  Icons.access_time_rounded,
                  'Định dạng giờ: "HH:mm" (ví dụ: 08:00, 13:30, 8h, 8h30, hoặc "08:00 - 09:30").',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuidelineRow(
      BuildContext context, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: context.textSecondaryColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondaryColor,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  // --- GIAO DIỆN BƯỚC 3: XEM TRƯỚC VÀ CHỈNH SỬA ---

  Widget _buildStep3Preview(BuildContext context) {
    final result = _parseResult!;
    final items = result.items;
    final validItems = items.where((i) => !i.hasError).toList();
    final allSelected =
        validItems.isNotEmpty && validItems.every((i) => i.isSelected);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Thống kê nhanh kết quả đọc file
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: context.surfaceMutedColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: context.borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedFileName ?? 'Tệp đã chọn',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: context.textPrimaryColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Đọc được ${items.length} dòng: ${result.validCount} hợp lệ, '
                      '${items.where((i) => i.status == ImportItemStatus.warningOverlap).length} trùng giờ, '
                      '${result.errorCount} lỗi',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: context.textSecondaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => _toggleSelectAll(!allSelected),
                icon: Icon(
                  allSelected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 16,
                ),
                label: Text(
                  allSelected ? 'Bỏ chọn hết' : 'Chọn hết (${validItems.length})',
                  style: const TextStyle(fontSize: 11.5),
                ),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Danh sách các dòng lịch học
        Expanded(
          child: ListView.separated(
            key: const ValueKey('import_preview_list'),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildPreviewCard(context, item);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewCard(BuildContext context, ImportedScheduleItem item) {
    Color cardBorder = context.borderColor;
    Color statusBg = context.surfaceMutedColor;
    Color statusFg = context.textSecondaryColor;
    String statusLabel = 'Hợp lệ';
    IconData statusIcon = Icons.check_circle_outline_rounded;

    if (item.hasError) {
      cardBorder = AppColors.error.withValues(alpha: 0.5);
      statusBg = AppColors.error.withValues(alpha: 0.12);
      statusFg = AppColors.error;
      statusLabel = item.errorMessage ?? 'Lỗi dữ liệu';
      statusIcon = Icons.error_outline_rounded;
    } else if (item.status == ImportItemStatus.warningOverlap) {
      cardBorder = AppColors.warning.withValues(alpha: 0.5);
      statusBg = AppColors.warning.withValues(alpha: 0.12);
      statusFg = AppColors.warning;
      statusLabel = item.warningMessage ?? 'Trùng lịch';
      statusIcon = Icons.warning_amber_rounded;
    } else if (item.isNewSubject) {
      statusBg = AppColors.primary.withValues(alpha: 0.12);
      statusFg = AppColors.primary;
      statusLabel = 'Môn học mới';
      statusIcon = Icons.fiber_new_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: context.surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Checkbox chọn dòng (disable nếu có lỗi)
            Checkbox(
              value: item.isSelected && !item.hasError,
              onChanged: item.hasError ? null : (_) => _toggleItemSelection(item),
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Badge thứ
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
                      // Tên môn
                      Expanded(
                        child: Text(
                          item.matchedSubjectName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: item.hasError
                                ? context.textSecondaryColor
                                : context.textPrimaryColor,
                            decoration:
                                item.hasError ? TextDecoration.lineThrough : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Nút đổi liên kết môn học
                      InkWell(
                        onTap: () => _showLinkSubjectDialog(item),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item.isNewSubject ? 'Tạo mới' : 'Đã khớp',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: item.isNewSubject
                                      ? AppColors.primary
                                      : context.textSecondaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 2),
                              Icon(
                                Icons.arrow_drop_down,
                                size: 16,
                                color: context.textSecondaryColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // Khung giờ & Phòng học
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded,
                          size: 14, color: context.textSecondaryColor),
                      const SizedBox(width: 4),
                      Text(
                        item.timeRangeText,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: context.textPrimaryColor,
                        ),
                      ),
                      if (item.location.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.location_on_outlined,
                            size: 14, color: context.textSecondaryColor),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            item.location,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.textSecondaryColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Badge trạng thái / cảnh báo / lỗi
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(statusIcon, size: 14, color: statusFg),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: statusFg,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
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

  Widget _buildStep3Footer(BuildContext context) {
    final validItems =
        _parseResult!.items.where((i) => !i.hasError).toList();
    final selectedCount = validItems.where((i) => i.isSelected).length;

    return Row(
      children: [
        OutlinedButton(
          key: const ValueKey('cancel_or_repick_file_button'),
          onPressed: () {
            setState(() {
              _currentStep = 1;
              _selectedFileName = null;
              _parseResult = null;
              _errorMessage = null;
            });
          },
          child: const Text('Chọn file khác'),
        ),
        const Spacer(),
        FilledButton.icon(
          key: const ValueKey('confirm_import_button'),
          onPressed: selectedCount > 0 ? _executeImport : null,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text('Nhập $selectedCount lịch học'),
        ),
      ],
    );
  }

  // --- GIAO DIỆN BƯỚC 4: KẾT QUẢ TÓM TẮT ---

  Widget _buildStep4Summary(BuildContext context) {
    final summary = _importSummary!;

    return SingleChildScrollView(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              size: 56,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nhập dữ liệu thành công!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: context.textPrimaryColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Lịch học và hệ thống chuông báo thức đã được cập nhật đồng bộ.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: context.textSecondaryColor,
            ),
          ),
          const SizedBox(height: 20),

          // Khối thống kê chi tiết
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.surfaceMutedColor,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.borderColor),
            ),
            child: Column(
              children: [
                _buildSummaryRow(
                  context,
                  'Số lịch học đã thêm',
                  '${summary.importedCount}',
                  AppColors.success,
                ),
                const Divider(height: 18),
                _buildSummaryRow(
                  context,
                  'Số môn học mới được tạo',
                  '${summary.createdSubjectsCount}',
                  AppColors.primary,
                ),
                if (summary.createdSubjects.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: summary.createdSubjects
                        .map((s) => Chip(
                              label: Text(s.name,
                                  style: const TextStyle(fontSize: 11)),
                              avatar: Icon(s.icon, size: 14, color: s.color),
                              visualDensity: VisualDensity.compact,
                              padding: EdgeInsets.zero,
                            ))
                        .toList(),
                  ),
                ],
                const Divider(height: 18),
                _buildSummaryRow(
                  context,
                  'Đã bỏ qua (hoặc lỗi)',
                  '${summary.skippedCount}',
                  context.textSecondaryColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          FilledButton(
            key: const ValueKey('finish_import_button'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hoàn tất'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    BuildContext context,
    String title,
    String value,
    Color valueColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13.5,
            color: context.textPrimaryColor,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/backup_service.dart';
import '../services/backup_storage.dart';
import '../theme/app_colors.dart';

/// Hộp thoại hiển thị kết quả sau khi tạo bản sao lưu thành công.
class BackupSuccessDialog extends StatelessWidget {
  final Map<String, dynamic> backupMap;
  final String jsonString;
  final String filePath;
  final BackupService? backupService;

  const BackupSuccessDialog({
    super.key,
    required this.backupMap,
    required this.jsonString,
    required this.filePath,
    this.backupService,
  });

  @override
  Widget build(BuildContext context) {
    final metadata = backupMap['metadata'] as Map<String, dynamic>? ?? {};
    final subjectsCount = metadata['totalSubjects'] ?? 0;
    final tasksCount = metadata['totalTasks'] ?? 0;
    final activitiesCount = metadata['totalActivities'] ?? 0;

    return AlertDialog(
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.statusCompletedBg,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.success,
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sao lưu thành công!',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Toàn bộ dữ liệu của bạn đã được đóng gói thành tệp sao lưu an toàn.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.surfaceMutedColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                children: [
                  _buildStatRow(
                    context,
                    Icons.menu_book_rounded,
                    'Môn học',
                    '$subjectsCount môn',
                  ),
                  const SizedBox(height: 6),
                  _buildStatRow(
                    context,
                    Icons.task_alt_rounded,
                    'Công việc học tập',
                    '$tasksCount việc',
                  ),
                  const SizedBox(height: 6),
                  _buildStatRow(
                    context,
                    Icons.history_edu_rounded,
                    'Lịch sử hoạt động',
                    '$activitiesCount lượt',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Vị trí lưu trữ:',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: context.textPrimaryColor,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.surfaceColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.borderColor),
              ),
              child: SelectableText(
                filePath,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: context.textSecondaryColor,
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('share_backup_file_button'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                try {
                  final fileName = filePath.split(RegExp(r'[/\\]')).last;
                  if (backupService != null) {
                    await backupService!.shareBackup(
                      filePath,
                      fileName: fileName,
                    );
                  } else {
                    await shareBackupFileExternal(filePath, fileName);
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Không thể chia sẻ tệp: $e'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.share_rounded, size: 16),
              label: const Text('Chia sẻ / Lưu tệp ra ngoài'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('copy_backup_json_button'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 40),
              ),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: jsonString));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Đã sao chép mã sao lưu JSON vào bộ nhớ tạm! Bạn có thể dán vào ứng dụng ghi chú hoặc gửi qua tin nhắn.',
                    ),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy_rounded, size: 16),
              label: const Text('Sao chép mã JSON'),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
      ],
    );
  }

  Widget _buildStatRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
        ),
      ],
    );
  }
}

/// Hộp thoại cho phép người dùng dán hoặc nhập nội dung tệp sao lưu JSON để khôi phục.
class RestoreInputDialog extends StatefulWidget {
  final BackupService backupService;
  final ValueChanged<BackupValidationResult> onValidBackup;

  const RestoreInputDialog({
    super.key,
    required this.backupService,
    required this.onValidBackup,
  });

  @override
  State<RestoreInputDialog> createState() => _RestoreInputDialogState();
}

class _RestoreInputDialogState extends State<RestoreInputDialog> {
  final TextEditingController _jsonController = TextEditingController();
  String? _errorMessage;

  @override
  void dispose() {
    _jsonController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null && data.text!.isNotEmpty) {
      setState(() {
        _jsonController.text = data.text!;
        _errorMessage = null;
      });
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bộ nhớ tạm không có nội dung văn bản.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _pickFileAndValidate() async {
    try {
      final content = await widget.backupService.pickAndReadBackupFile();
      if (content == null || content.trim().isEmpty) {
        return;
      }
      setState(() {
        _jsonController.text = content;
        _errorMessage = null;
      });
      _validateAndProceed();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Lỗi khi mở hoặc đọc tệp: $e';
      });
    }
  }

  void _validateAndProceed() {
    final text = _jsonController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng dán hoặc nhập nội dung tệp sao lưu JSON.';
      });
      return;
    }

    final result = widget.backupService.validateBackupJson(text);
    if (!result.isValid) {
      setState(() {
        _errorMessage = result.errorMessage;
      });
    } else {
      Navigator.of(context).pop();
      widget.onValidBackup(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            Icons.settings_backup_restore_rounded,
            color: AppColors.primary,
            size: 24,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Khôi phục dữ liệu',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chọn tệp sao lưu (.json) từ thiết bị hoặc dán nội dung mã sao lưu bên dưới:',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: context.textSecondaryColor,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const ValueKey('pick_backup_file_button'),
                  onPressed: _pickFileAndValidate,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Chọn tệp sao lưu (.json)'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('paste_clipboard_button'),
                  onPressed: _pasteFromClipboard,
                  icon: const Icon(Icons.paste_rounded, size: 16),
                  label: const Text('Dán từ bộ nhớ tạm'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const ValueKey('restore_json_input_field'),
              controller: _jsonController,
              maxLines: 6,
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              decoration: InputDecoration(
                hintText:
                    '{\n  "app": "ExamPilot",\n  "formatVersion": 1,\n  ...\n}',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.all(12),
              ),
              onChanged: (_) {
                if (_errorMessage != null) {
                  setState(() => _errorMessage = null);
                }
              },
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.isDark
                      ? const Color(0xFF450A0A)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.error),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.error,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const ValueKey('validate_backup_button'),
          onPressed: _validateAndProceed,
          child: const Text('Kiểm tra & Xem trước'),
        ),
      ],
    );
  }
}

/// Hộp thoại hiển thị thông tin bản xem trước (Preview) và cảnh báo thay thế dữ liệu trước khi khôi phục.
class RestorePreviewDialog extends StatelessWidget {
  final BackupPreview preview;
  final VoidCallback onConfirmRestore;

  const RestorePreviewDialog({
    super.key,
    required this.preview,
    required this.onConfirmRestore,
  });

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year;
    final hr = local.hour.toString().padLeft(2, '0');
    final min = local.minute.toString().padLeft(2, '0');
    return '$hr:$min, $d/$m/$y';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.preview_rounded, color: AppColors.primary, size: 24),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Xem trước bản sao lưu',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: context.textPrimaryColor,
              ),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thẻ thống kê nội dung sao lưu
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.surfaceMutedColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: context.borderColor),
              ),
              child: Column(
                children: [
                  _buildPreviewRow(
                    context,
                    'Thời gian tạo',
                    _formatDate(preview.createdAt),
                  ),
                  const SizedBox(height: 6),
                  _buildPreviewRow(
                    context,
                    'Phiên bản ứng dụng',
                    preview.appVersion,
                  ),
                  const SizedBox(height: 6),
                  _buildPreviewRow(
                    context,
                    'Số môn học',
                    '${preview.totalSubjects} môn',
                  ),
                  const SizedBox(height: 6),
                  _buildPreviewRow(
                    context,
                    'Số công việc học tập',
                    '${preview.totalTasks} việc',
                  ),
                  const SizedBox(height: 6),
                  _buildPreviewRow(
                    context,
                    'Lịch sử hoạt động',
                    '${preview.totalActivities} lượt',
                  ),
                  if (preview.userName.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildPreviewRow(
                      context,
                      'Hồ sơ người dùng',
                      preview.userName,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Banner cảnh báo quan trọng
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.isDark
                    ? const Color(0xFF451A03)
                    : const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: context.isDark
                      ? const Color(0xFFB45309)
                      : const Color(0xFFF59E0B),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFD97706),
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'CẢNH BÁO: Quá trình này sẽ THAY THẾ TOÀN BỘ dữ liệu hiện tại trên thiết bị bằng dữ liệu từ bản sao lưu này. Hãy sao lưu dữ liệu hiện tại trước nếu bạn muốn bảo tồn dữ liệu cũ.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: context.isDark
                            ? const Color(0xFFFDE68A)
                            : const Color(0xFF92400E),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        FilledButton(
          key: const ValueKey('confirm_restore_button'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            onConfirmRestore();
          },
          child: const Text('Xác nhận khôi phục'),
        ),
      ],
    );
  }

  Widget _buildPreviewRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: context.textSecondaryColor),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: context.textPrimaryColor,
          ),
        ),
      ],
    );
  }
}

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Triển khai lưu, đọc, chọn và chia sẻ tệp sao lưu trên các nền tảng Native (Android, Desktop, Unit Test).
Future<String> saveBackupFile(String fileName, String content) async {
  Directory? targetDir;

  // 1. Thử ghi vào thư mục tài liệu ứng dụng (chuẩn Android Scoped Storage)
  try {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${docsDir.path}/exampilot_backups');
    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }
    targetDir = backupDir;
  } catch (_) {}

  // 2. Thử ghi vào thư mục Download công cộng của Android nếu có thể truy cập
  if (targetDir == null) {
    try {
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (downloadDir.existsSync()) {
        targetDir = downloadDir;
      }
    } catch (_) {}
  }

  // 3. Fallback thư mục tạm hệ thống
  if (targetDir == null) {
    try {
      final tempDir = Directory.systemTemp;
      final backupDir = Directory('${tempDir.path}/exampilot_backups');
      if (!backupDir.existsSync()) {
        backupDir.createSync(recursive: true);
      }
      targetDir = backupDir;
    } catch (_) {}
  }

  if (targetDir == null) {
    throw const FileSystemException(
      'Không thể xác định thư mục lưu trữ trên thiết bị. Vui lòng kiểm tra quyền lưu trữ.',
    );
  }

  final file = File('${targetDir.path}/$fileName');
  await file.writeAsString(content);
  return file.path;
}

Future<String?> readBackupFile(String path) async {
  try {
    final file = File(path);
    if (file.existsSync()) {
      return await file.readAsString();
    }
  } catch (_) {}
  return null;
}

/// Mở trình chọn tệp của hệ điều hành (Android SAF, Desktop) và đọc nội dung tệp .json
Future<String?> pickBackupFileContent() async {
  try {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (files.isEmpty) {
      return null;
    }

    final picked = files.first;

    // 1. Đọc trực tiếp qua readAsBytes (hỗ trợ cả Android SAF content:// và Web)
    try {
      final bytes = await picked.readAsBytes();
      if (bytes.isNotEmpty) {
        return utf8.decode(bytes);
      }
    } catch (_) {}

    // 2. Thử đọc qua xFile
    try {
      final str = await picked.xFile.readAsString();
      if (str.isNotEmpty) {
        return str;
      }
    } catch (_) {}

    // 3. Đọc từ đường dẫn file nếu có
    if (picked.path != null && picked.path!.isNotEmpty) {
      final file = File(picked.path!);
      if (await file.exists()) {
        return await file.readAsString();
      }
    }
  } catch (e) {
    throw Exception('Lỗi khi mở hoặc đọc tệp qua trình chọn tệp: $e');
  }
  return null;
}

/// Chia sẻ tệp sao lưu ra ngoài thiết bị thông qua hệ thống (Android Sharesheet)
Future<void> shareBackupFileExternal(String filePath, String fileName) async {
  try {
    final file = File(filePath);
    if (await file.exists()) {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile(filePath, name: fileName, mimeType: 'application/json'),
          ],
          subject: 'Bản sao lưu ExamPilot',
          text: 'Tệp sao lưu ExamPilot ($fileName)',
        ),
      );
      return;
    }
  } catch (e) {
    throw Exception('Lỗi khi chia sẻ tệp sao lưu: $e');
  }
  throw const FileSystemException(
    'Tệp sao lưu không tồn tại trên thiết bị để chia sẻ.',
  );
}

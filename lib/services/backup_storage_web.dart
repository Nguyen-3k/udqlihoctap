import 'dart:convert';
import 'dart:js_interop';
import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;

/// Triển khai tải tệp sao lưu trên trình duyệt Web (Chrome) thông qua Blob và AnchorElement.
Future<String> saveBackupFile(String fileName, String content) async {
  try {
    final blob = web.Blob(
      [content.toJS].toJS,
      web.BlobPropertyBag(type: 'application/json'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    anchor.click();
    web.URL.revokeObjectURL(url);
    return 'Đã kích hoạt tải xuống tệp $fileName vào thư mục Tải về của trình duyệt.';
  } catch (e) {
    throw Exception('Lỗi tải xuống trên Web: $e');
  }
}

Future<String?> readBackupFile(String path) async {
  return null;
}

/// Mở trình chọn tệp trên Web và đọc nội dung tệp .json
Future<String?> pickBackupFileContent() async {
  try {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (files.isNotEmpty) {
      final picked = files.first;
      try {
        final bytes = await picked.readAsBytes();
        if (bytes.isNotEmpty) {
          return utf8.decode(bytes);
        }
      } catch (_) {}

      try {
        final str = await picked.xFile.readAsString();
        if (str.isNotEmpty) {
          return str;
        }
      } catch (_) {}
    }
  } catch (e) {
    throw Exception('Lỗi khi chọn tệp trên Web: $e');
  }
  return null;
}

/// Chia sẻ tệp trên Web (kích hoạt lại tải xuống nếu cần)
Future<void> shareBackupFileExternal(String filePath, String fileName) async {
  // Trên nền tảng Web, tệp đã được tải trực tiếp về máy tính người dùng khi tạo sao lưu
}

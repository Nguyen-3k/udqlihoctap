import 'dart:io' as io;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import '../image_timetable_importer.dart';

/// Bộ nhận diện OCR thực tế sử dụng Google ML Kit On-Device Text Recognition trên Android & iOS.
/// - Hoàn toàn miễn phí, chạy offline cục bộ trên máy.
/// - Không cần API key, không cần backend server.
/// - Trích xuất đầy đủ văn bản và tọa độ Bounding Box.
class GoogleMlKitTextRecognizer implements ImageTextRecognizer {
  @override
  String get engineName => 'Google ML Kit On-Device Text Recognition (Latin)';

  @override
  bool get isAvailable => !kIsWeb;

  @override
  Future<OcrRecognitionResult> recognizeText(TimetableImage image) async {
    if (kIsWeb) {
      return const OcrRecognitionResult.unsupported(
        message:
            'Google ML Kit On-Device OCR chỉ khả dụng trên thiết bị di động (Android / iOS).',
      );
    }

    if (image.bytes.isEmpty) {
      return const OcrRecognitionResult.error('Tệp ảnh có dung lượng rỗng (0 bytes).');
    }

    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    io.File? tempFile;

    try {
      InputImage inputImage;

      // 1. Chuẩn bị InputImage từ tệp có sẵn hoặc ghi bytes ra tệp tạm
      if (image.path != null && image.path!.isNotEmpty) {
        final existingFile = io.File(image.path!);
        if (await existingFile.exists()) {
          inputImage = InputImage.fromFile(existingFile);
        } else {
          tempFile = await _writeBytesToTempFile(image.bytes);
          inputImage = InputImage.fromFile(tempFile);
        }
      } else {
        tempFile = await _writeBytesToTempFile(image.bytes);
        inputImage = InputImage.fromFile(tempFile);
      }

      // 2. Chạy quá trình nhận diện chữ trực tiếp trên thiết bị
      final recognizedText = await recognizer.processImage(inputImage);

      // 3. Kiểm tra xem có nhận diện được chữ nào không
      final fullText = recognizedText.text.trim();
      if (fullText.isEmpty && recognizedText.blocks.isEmpty) {
        return const OcrRecognitionResult.error(
          'Không tìm thấy chữ hoặc bảng biểu nào trong ảnh. '
          'Vui lòng thử chụp lại ảnh rõ nét, đủ ánh sáng và không bị mờ.',
        );
      }

      // 4. Trích xuất textBlocks và cấu trúc bounding box
      final List<String> textBlockStrings = [];
      final List<OcrTextBlock> structuredBlocks = [];

      for (final block in recognizedText.blocks) {
        final bText = block.text.trim();
        if (bText.isEmpty) continue;
        textBlockStrings.add(bText);

        final lines = block.lines.map((l) {
          return OcrTextLine(
            text: l.text.trim(),
            left: l.boundingBox.left,
            top: l.boundingBox.top,
            right: l.boundingBox.right,
            bottom: l.boundingBox.bottom,
          );
        }).toList();

        structuredBlocks.add(
          OcrTextBlock(
            text: bText,
            left: block.boundingBox.left,
            top: block.boundingBox.top,
            right: block.boundingBox.right,
            bottom: block.boundingBox.bottom,
            lines: lines,
          ),
        );
      }

      return OcrRecognitionResult(
        rawText: fullText,
        textBlocks: textBlockStrings,
        structuredBlocks: structuredBlocks,
        isSuccess: true,
        status: OcrEngineStatus.success,
      );
    } catch (e) {
      return OcrRecognitionResult.error('Lỗi trong quá trình nhận diện OCR: $e');
    } finally {
      // 5. Đóng TextRecognizer đúng vòng đời để giải phóng tài nguyên Native
      try {
        await recognizer.close();
      } catch (_) {}

      // Xóa tệp tạm nếu có
      if (tempFile != null) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
      }
    }
  }

  Future<io.File> _writeBytesToTempFile(Uint8List bytes) async {
    final tempDir = await getTemporaryDirectory();
    final tempPath =
        '${tempDir.path}/ocr_input_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final file = io.File(tempPath);
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}

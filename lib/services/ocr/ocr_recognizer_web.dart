import '../image_timetable_importer.dart';

/// Triển khai tương thích Web Preview cho Google ML Kit Text Recognizer.
/// Do Google ML Kit là Native Android/iOS C++ plugin, trên trình duyệt Web
/// sẽ thông báo trạng thái chưa hỗ trợ và cho phép người dùng nhập thủ công.
class GoogleMlKitTextRecognizer implements ImageTextRecognizer {
  @override
  String get engineName => 'Google ML Kit On-Device (Web Preview Fallback)';

  @override
  bool get isAvailable => false;

  @override
  Future<OcrRecognitionResult> recognizeText(TimetableImage image) async {
    return const OcrRecognitionResult.unsupported(
      message:
          'Tính năng nhận diện ảnh OCR tự động bằng Google ML Kit On-Device '
          'chỉ hỗ trợ trên thiết bị di động (Android / iOS). '
          'Trên Web Preview, bạn có thể xem ảnh và bấm "+ Thêm buổi học" để lập lịch thủ công.',
    );
  }
}

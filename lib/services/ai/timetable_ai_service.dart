import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

import '../../config/supabase_config.dart';
import '../../models/ai_timetable_model.dart';

/// Giao diện dịch vụ phân tích ảnh thời khóa biểu bằng AI
abstract class TimetableAiService {
  Future<AiTimetableResult> analyzeTimetableImage({
    required Uint8List imageBytes,
    required String mimeType,
  });

  Future<AiTimetableResult> analyzeTimetable({
    required Uint8List imageBytes,
    required String mimeType,
  }) =>
      analyzeTimetableImage(imageBytes: imageBytes, mimeType: mimeType);
}

/// Dịch vụ kết nối tới Supabase Edge Function `analyze-timetable-image`
/// để gọi Google Gemini Vision (Phase 6D).
class SupabaseTimetableAiService implements TimetableAiService {
  final http.Client _client;

  SupabaseTimetableAiService({http.Client? client})
      : _client = client ?? http.Client();

  @override
  Future<AiTimetableResult> analyzeTimetable({
    required Uint8List imageBytes,
    required String mimeType,
  }) =>
      analyzeTimetableImage(imageBytes: imageBytes, mimeType: mimeType);

  @override
  Future<AiTimetableResult> analyzeTimetableImage({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    // 1. Kiểm tra tính hợp lệ sơ bộ của ảnh
    if (imageBytes.isEmpty) {
      return AiTimetableResult.error('Tệp ảnh rỗng, không có dữ liệu để phân tích.');
    }

    // Giới hạn 10 MB
    if (imageBytes.lengthInBytes > 10 * 1024 * 1024) {
      return AiTimetableResult.error(
        'Dung lượng ảnh vượt quá 10 MB. Vui lòng chọn ảnh có độ phân giải vừa phải.',
      );
    }

    // 2. Kiểm tra cấu hình Supabase
    if (!SupabaseConfig.isConfigured) {
      return AiTimetableResult.error(
        'Chưa cấu hình Supabase Edge Function URL hợp lệ. '
        'Vui lòng kiểm tra lại cấu hình SUPABASE_URL trước khi sử dụng tính năng AI.',
      );
    }

    try {
      // 3. Mã hóa Base64
      final base64Image = base64Encode(imageBytes);

      // Chuẩn hóa MIME type
      var cleanMime = mimeType.toLowerCase().trim();
      if (cleanMime == 'jpg') cleanMime = 'image/jpeg';
      if (!cleanMime.startsWith('image/')) cleanMime = 'image/$cleanMime';

      final endpoint = Uri.parse(SupabaseConfig.analyzeTimetableFunctionUrl);

      final payload = jsonEncode({
        'image': base64Image,
        'mimeType': cleanMime,
      });

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      if (SupabaseConfig.hasAnonKey) {
        final key = SupabaseConfig.anonKey.trim();
        headers['apikey'] = key;
        headers['Authorization'] = 'Bearer $key';
      }

      // 4. Gửi HTTP POST tới Supabase Edge Function với timeout 50 giây
      final response = await _client
          .post(
            endpoint,
            headers: headers,
            body: payload,
          )
          .timeout(const Duration(seconds: 50));

      final statusCode = response.statusCode;
      final bodyUtf8 = utf8.decode(response.bodyBytes);

      // 5. Xử lý các mã lỗi HTTP từ Edge Function
      if (statusCode == 200) {
        final Map<String, dynamic> decoded = jsonDecode(bodyUtf8);
        return AiTimetableResult.fromJson(decoded);
      } else if (statusCode == 429) {
        return AiTimetableResult.error(
          'Hạn mức gọi Gemini AI miễn phí tạm thời bị giới hạn (Quota / Rate Limit Exceeded). '
          'Vui lòng đợi 1-2 phút trước khi thử lại.',
        );
      } else if (statusCode == 413) {
        return AiTimetableResult.error(
          'Kích thước ảnh vượt quá giới hạn của máy chủ Edge Function (Tối đa 10 MB).',
        );
      } else if (statusCode == 401 || statusCode == 403) {
        return AiTimetableResult.error(
          'Khóa Anon Key hoặc quyền truy cập Edge Function không hợp lệ (HTTP $statusCode). '
          'Vui lòng kiểm tra lại cấu hình SUPABASE_ANON_KEY.',
        );
      } else if (statusCode == 400) {
        try {
          final decoded = jsonDecode(bodyUtf8);
          final err = decoded['error']?.toString() ?? decoded['message']?.toString();
          return AiTimetableResult.error(err ?? 'Yêu cầu không hợp lệ.');
        } catch (_) {
          return AiTimetableResult.error('Yêu cầu không hợp lệ với máy chủ AI (HTTP 400).');
        }
      } else if (statusCode >= 500) {
        try {
          final decoded = jsonDecode(bodyUtf8);
          final err = decoded['error']?.toString() ?? decoded['message']?.toString();
          if (err != null && err.isNotEmpty) {
            return AiTimetableResult.error(err);
          }
        } catch (_) {}
        return AiTimetableResult.error(
          'Dịch vụ Supabase Edge Function hoặc Gemini AI tạm thời gặp sự cố ($statusCode). '
          'Vui lòng thử lại sau.',
        );
      }

      return AiTimetableResult.error(
        'Máy chủ phản hồi với mã lỗi không xác định: $statusCode.',
      );
    } on TimeoutException {
      return AiTimetableResult.error(
        'Quá trình phân tích ảnh bằng AI bị quá hạn (Timeout 50s). '
        'Vui lòng kiểm tra kết nối mạng và thử lại với ảnh nhỏ hơn.',
      );
    } catch (e) {
      return AiTimetableResult.error(
        'Không thể kết nối đến máy chủ Supabase Edge Functions: $e. '
        'Vui lòng kiểm tra kết nối Internet của thiết bị.',
      );
    }
  }
}

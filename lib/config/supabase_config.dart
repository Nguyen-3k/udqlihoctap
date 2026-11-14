/// Cấu hình kết nối Supabase Edge Functions cho ExamPilot (Phase 6D).
///
/// Dự án Supabase chính thức: ExampilotAI
/// - Project Reference: ihpvvlcqsuileijgrfrd
/// - Project URL: https://ihpvvlcqsuileijgrfrd.supabase.co
/// - Edge Function: analyze-timetable-image
/// - Function URL: https://ihpvvlcqsuileijgrfrd.supabase.co/functions/v1/analyze-timetable-image
///
/// Người dùng có thể truyền giá trị khi chạy hoặc build APK qua:
/// `--dart-define=SUPABASE_URL=https://ihpvvlcqsuileijgrfrd.supabase.co`
/// `--dart-define=SUPABASE_ANON_KEY=<anon-key>`
class SupabaseConfig {
  /// URL dự án Supabase chính thức mặc định
  static const String defaultProjectUrl =
      'https://ihpvvlcqsuileijgrfrd.supabase.co';

  static const String _defaultUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: defaultProjectUrl,
  );

  static const String _defaultAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// URL dự án Supabase (Mặc định: https://ihpvvlcqsuileijgrfrd.supabase.co)
  static String url = _defaultUrl;

  /// Khóa công khai Anon Key / Publishable Key của Supabase
  static String anonKey = _defaultAnonKey;

  /// Kiểm tra xem URL dự án đã được cấu hình hợp lệ hay chưa
  static bool get isConfigured {
    final cleanUrl = url.trim();
    return cleanUrl.isNotEmpty && cleanUrl.startsWith('https://');
  }

  /// Kiểm tra xem Anon Key có được cung cấp hay không
  static bool get hasAnonKey => anonKey.trim().isNotEmpty;

  /// Cập nhật URL và Anon Key (phục vụ runtime hoặc testing)
  static void override({required String url, required String anonKey}) {
    SupabaseConfig.url = url;
    SupabaseConfig.anonKey = anonKey;
  }

  /// Reset về giá trị cấu hình ban đầu
  static void reset() {
    url = _defaultUrl;
    anonKey = _defaultAnonKey;
  }

  /// Đường dẫn đầy đủ đến Edge Function analyze-timetable-image
  static String get analyzeTimetableFunctionUrl {
    final cleanUrl = url.trim().replaceAll(RegExp(r'/+$'), '');
    return '$cleanUrl/functions/v1/analyze-timetable-image';
  }
}

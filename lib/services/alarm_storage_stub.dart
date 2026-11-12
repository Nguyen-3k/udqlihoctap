/// Lưu trữ trạng thái báo thức trong bộ nhớ tạm khi không chạy trên Web
/// hoặc khi dùng kho lưu in-memory trong kiểm thử.
class WebAlarmStorage {
  static String? _inMemoryJson;

  static String? loadRawJson() => _inMemoryJson;

  static void saveRawJson(String rawJson) {
    _inMemoryJson = rawJson;
  }

  static void clear() {
    _inMemoryJson = null;
  }
}

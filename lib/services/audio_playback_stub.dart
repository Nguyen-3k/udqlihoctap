/// Bộ phát âm mẫu nền tảng Web (stub trên Android/Desktop/Test).
class WebSoundPreviewPlayer {
  Future<void> playSystemTone({
    required bool isAlarmGroup,
    required bool loop,
    void Function()? onEnded,
  }) async {
    onEnded?.call();
  }

  void stop() {}
  void dispose() {}
}

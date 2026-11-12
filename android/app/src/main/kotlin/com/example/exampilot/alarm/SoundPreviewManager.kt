package com.example.exampilot.alarm

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Handler
import android.os.Looper

/**
 * Quản lý phát nghe thử một âm thanh duy nhất tại một thời điểm trên Android.
 * Hiện sử dụng âm thanh hệ thống mặc định (RingtoneManager TYPE_ALARM / TYPE_NOTIFICATION)
 * và dừng sạch khi đổi lựa chọn hoặc đóng màn hình.
 */
class SoundPreviewManager(private val context: Context) {
    private var player: MediaPlayer? = null
    private var currentSoundId: String? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var autoStopRunnable: Runnable? = null

    fun playPreview(
        soundId: String,
        isAlarmGroup: Boolean,
        onCompleted: () -> Unit,
    ) {
        stopPreview()
        if (soundId == "none") {
            onCompleted()
            return
        }

        try {
            val uri: Uri = if (isAlarmGroup) {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            } else {
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            } ?: run {
                onCompleted()
                return
            }

            val mediaPlayer = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(
                            if (isAlarmGroup) {
                                AudioAttributes.USAGE_ALARM
                            } else {
                                AudioAttributes.USAGE_NOTIFICATION
                            },
                        )
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(context.applicationContext, uri)
                isLooping = false
                setOnCompletionListener {
                    stopPreview()
                    onCompleted()
                }
                prepare()
                start()
            }
            player = mediaPlayer
            currentSoundId = soundId

            // Giới hạn tối đa 4 giây nếu thiết bị dùng âm alarm mặc định lặp dài trên một số ROM
            val stopper = Runnable {
                if (currentSoundId == soundId) {
                    stopPreview()
                    onCompleted()
                }
            }
            autoStopRunnable = stopper
            mainHandler.postDelayed(stopper, 4000L)
        } catch (_: Throwable) {
            stopPreview()
            onCompleted()
        }
    }

    fun stopPreview() {
        autoStopRunnable?.let { mainHandler.removeCallbacks(it) }
        autoStopRunnable = null
        currentSoundId = null
        try {
            player?.let { p ->
                if (p.isPlaying) {
                    p.stop()
                }
                p.reset()
                p.release()
            }
        } catch (_: Throwable) {
        } finally {
            player = null
        }
    }
}

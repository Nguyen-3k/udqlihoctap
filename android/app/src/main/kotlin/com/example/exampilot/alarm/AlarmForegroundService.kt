package com.example.exampilot.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import com.example.exampilot.MainActivity
import com.example.exampilot.R

/**
 * Foreground Service duy trì phát âm thanh báo thức lặp liên tục (STREAM_ALARM)
 * cho tới khi người dùng bấm Tắt, Nhắc lại (Snooze) hoặc Vào học.
 * Tuân thủ Quyết định bất biến D2: KHÔNG có timer auto-timeout tự tắt báo thức.
 */
class AlarmForegroundService : Service() {

    private var mediaPlayer: MediaPlayer? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var vibrator: Vibrator? = null
    private var activeAlarmId: Int = DEFAULT_NOTIFICATION_ID

    companion object {
        const val CHANNEL_ID = "exampilot_alarm_foreground_v1"
        const val DEFAULT_NOTIFICATION_ID = 900100

        const val ACTION_START_ALARM = "com.example.exampilot.alarm.START_ALARM"
        const val ACTION_STOP_ALARM = "com.example.exampilot.alarm.STOP_ALARM"

        const val EXTRA_ALARM_KEY = "alarmKey"
        const val EXTRA_ALARM_ID = "alarmId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TASK_TITLE = "taskTitle"
        const val EXTRA_SOUND_ID = "soundId"
        const val EXTRA_SNOOZE_COUNT = "snoozeCount"

        fun start(context: Context, record: AlarmStorage.NativeAlarmRecord) {
            val intent = Intent(context.applicationContext, AlarmForegroundService::class.java).apply {
                action = ACTION_START_ALARM
                putExtra(EXTRA_ALARM_KEY, record.alarmKey)
                putExtra(EXTRA_ALARM_ID, record.alarmId)
                putExtra(EXTRA_TITLE, record.title)
                putExtra(EXTRA_TASK_TITLE, record.taskTitle)
                putExtra(EXTRA_SOUND_ID, record.soundId)
                putExtra(EXTRA_SNOOZE_COUNT, record.snoozeCount)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.applicationContext.startForegroundService(intent)
            } else {
                context.applicationContext.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context.applicationContext, AlarmForegroundService::class.java).apply {
                action = ACTION_STOP_ALARM
            }
            context.applicationContext.stopService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP_ALARM) {
            stopAlarmAndSelf()
            return START_NOT_STICKY
        }

        val alarmKey = intent?.getStringExtra(EXTRA_ALARM_KEY) ?: ""
        val alarmId = intent?.getIntExtra(EXTRA_ALARM_ID, DEFAULT_NOTIFICATION_ID) ?: DEFAULT_NOTIFICATION_ID
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Đến giờ học tập"
        val taskTitle = intent?.getStringExtra(EXTRA_TASK_TITLE)
        val soundId = intent?.getStringExtra(EXTRA_SOUND_ID) ?: "alarm_dawn"
        val snoozeCount = intent?.getIntExtra(EXTRA_SNOOZE_COUNT, 0) ?: 0

        activeAlarmId = if (alarmId == 0) DEFAULT_NOTIFICATION_ID else alarmId
        ensureNotificationChannel()

        val notification = buildAlarmNotification(
            alarmKey = alarmKey,
            alarmId = activeAlarmId,
            title = title,
            taskTitle = taskTitle,
            snoozeCount = snoozeCount,
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                activeAlarmId,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
            )
        } else {
            startForeground(activeAlarmId, notification)
        }

        acquireWakeLockSafely()
        startLoopingAlarmSound(soundId)
        startVibrationPattern()

        return START_REDELIVER_INTENT
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Báo thức học tập đang reo",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Duy trì thông báo và chuông báo thức ExamPilot cho đến khi bạn tắt hoặc nhắc lại."
            // Âm thanh lặp do MediaPlayer trong Service quản lý trực tiếp trên USAGE_ALARM
            setSound(null, null)
            enableVibration(false)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildAlarmNotification(
        alarmKey: String,
        alarmId: Int,
        title: String,
        taskTitle: String?,
        snoozeCount: Int,
    ): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("alarmKey", alarmKey)
            putExtra("alarmAction", "open")
        }
        val openPending = PendingIntent.getActivity(
            this,
            alarmId + 1,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val dismissIntent = Intent(this, AlarmActionReceiver::class.java).apply {
            action = AlarmActionReceiver.ACTION_DISMISS
            putExtra(EXTRA_ALARM_KEY, alarmKey)
            putExtra(EXTRA_ALARM_ID, alarmId)
        }
        val dismissPending = PendingIntent.getBroadcast(
            this,
            alarmId + 2,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val startIntent = Intent(this, AlarmActionReceiver::class.java).apply {
            action = AlarmActionReceiver.ACTION_START_STUDY
            putExtra(EXTRA_ALARM_KEY, alarmKey)
            putExtra(EXTRA_ALARM_ID, alarmId)
        }
        val startPending = PendingIntent.getBroadcast(
            this,
            alarmId + 3,
            startIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val bodyText = if (!taskTitle.isNullOrBlank()) {
            "$taskTitle • Bấm Tắt hoặc Nhắc lại để dừng chuông"
        } else {
            "Báo thức đang phát âm thanh • Bấm Tắt để dừng chuông"
        }

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("Báo thức học tập: $title")
            .setContentText(bodyText)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(openPending)
            .addAction(0, "Tắt", dismissPending)
            .addAction(0, "Vào học", startPending)

        if (snoozeCount == 0) {
            val snoozeIntent = Intent(this, AlarmActionReceiver::class.java).apply {
                action = AlarmActionReceiver.ACTION_SNOOZE
                putExtra(EXTRA_ALARM_KEY, alarmKey)
                putExtra(EXTRA_ALARM_ID, alarmId)
            }
            val snoozePending = PendingIntent.getBroadcast(
                this,
                alarmId + 4,
                snoozeIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder.addAction(0, "Nhắc lại 5p", snoozePending)
        }

        return builder.build()
    }

    private fun acquireWakeLockSafely() {
        try {
            if (wakeLock?.isHeld == true) return
            val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ExamPilot:AlarmServiceWakeLock")
            wakeLock?.setReferenceCounted(false)
            wakeLock?.acquire(60 * 60 * 1000L)
        } catch (_: Throwable) {
        }
    }

    private fun startLoopingAlarmSound(soundId: String) {
        stopMediaPlayerSafely()
        if (soundId == "none") return

        try {
            val uri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
                ?: return

            val player = MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                setDataSource(applicationContext, uri)
                isLooping = true
                prepare()
                start()
            }
            mediaPlayer = player
        } catch (_: Throwable) {
            stopMediaPlayerSafely()
        }
    }

    private fun startVibrationPattern() {
        try {
            val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                vm?.defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
            }
            vibrator = v
            if (v == null || !v.hasVibrator()) return
            val pattern = longArrayOf(0, 500, 600, 500, 800)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                v.vibrate(VibrationEffect.createWaveform(pattern, 0))
            } else {
                @Suppress("DEPRECATION")
                v.vibrate(pattern, 0)
            }
        } catch (_: Throwable) {
        }
    }

    private fun stopMediaPlayerSafely() {
        try {
            mediaPlayer?.let { player ->
                if (player.isPlaying) {
                    player.stop()
                }
                player.reset()
                player.release()
            }
        } catch (_: Throwable) {
        } finally {
            mediaPlayer = null
        }
    }

    private fun stopAlarmAndSelf() {
        stopMediaPlayerSafely()
        try {
            vibrator?.cancel()
        } catch (_: Throwable) {
        }
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Throwable) {
        } finally {
            wakeLock = null
        }
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (_: Throwable) {
        }
        stopSelf()
    }

    override fun onDestroy() {
        stopMediaPlayerSafely()
        try {
            vibrator?.cancel()
        } catch (_: Throwable) {
        }
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Throwable) {
        }
        wakeLock = null
        super.onDestroy()
    }
}

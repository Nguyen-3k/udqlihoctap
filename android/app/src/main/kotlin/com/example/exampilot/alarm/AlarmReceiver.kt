package com.example.exampilot.alarm

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.util.Log
import androidx.core.app.NotificationCompat
import com.example.exampilot.MainActivity
import com.example.exampilot.R

/**
 * Nhận tín hiệu đánh thức từ AlarmManager khi đến giờ báo thức.
 * Cập nhật trạng thái bền vững sang Ringing và khởi động AlarmForegroundService.
 * Nếu Foreground Service bị chặn (ví dụ ForegroundServiceStartNotAllowedException trên Android 12+),
 * kích hoạt Fallback Alarm Notification trực tiếp từ NotificationManager để chuông không bao giờ bị mất.
 */
class AlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ExamPilotAlarm"

        const val ACTION_TRIGGER_ALARM = "com.example.exampilot.alarm.TRIGGER_ALARM"
        const val EXTRA_ALARM_KEY = "alarmKey"
        const val EXTRA_ALARM_ID = "alarmId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_TASK_TITLE = "taskTitle"
        const val EXTRA_SOUND_ID = "soundId"
        const val EXTRA_SCHEDULED_AT = "scheduledAtMillis"

        const val FALLBACK_CHANNEL_ID = "exampilot_alarm_fallback_channel"

        fun cancelFallbackNotification(context: Context, alarmId: Int) {
            try {
                val nm = context.applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                nm?.cancel(alarmId)
                Log.i(TAG, "Fallback notification cancelled for alarmId=$alarmId")
            } catch (_: Throwable) {
            }
        }

        fun ensureFallbackChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
            if (manager.getNotificationChannel(FALLBACK_CHANNEL_ID) != null) return

            val soundUri: Uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

            val channel = NotificationChannel(
                FALLBACK_CHANNEL_ID,
                "Báo thức học tập (Khẩn cấp)",
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "Thông báo khẩn khi báo thức đến giờ học"
                setSound(
                    soundUri,
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build(),
                )
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 600, 500, 800)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            manager.createNotificationChannel(channel)
        }

        fun postFallbackAlarmNotification(context: Context, record: AlarmStorage.NativeAlarmRecord) {
            try {
                ensureFallbackChannel(context)
                val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return

                val openIntent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("alarmKey", record.alarmKey)
                    putExtra("alarmAction", "open")
                }
                val safeId = record.alarmId and 0x3fffffff
                val openPending = PendingIntent.getActivity(
                    context,
                    safeId + 1,
                    openIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )

                val dismissIntent = Intent(context, AlarmActionReceiver::class.java).apply {
                    action = AlarmActionReceiver.ACTION_DISMISS
                    putExtra(AlarmForegroundService.EXTRA_ALARM_KEY, record.alarmKey)
                    putExtra(AlarmForegroundService.EXTRA_ALARM_ID, record.alarmId)
                }
                val dismissPending = PendingIntent.getBroadcast(
                    context,
                    safeId + 2,
                    dismissIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )

                val startIntent = Intent(context, AlarmActionReceiver::class.java).apply {
                    action = AlarmActionReceiver.ACTION_START_STUDY
                    putExtra(AlarmForegroundService.EXTRA_ALARM_KEY, record.alarmKey)
                    putExtra(AlarmForegroundService.EXTRA_ALARM_ID, record.alarmId)
                }
                val startPending = PendingIntent.getBroadcast(
                    context,
                    safeId + 3,
                    startIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )

                val bodyText = if (!record.taskTitle.isNullOrBlank()) {
                    "${record.taskTitle} • Báo thức đang reo!"
                } else {
                    "Đã đến giờ học tập theo kế hoạch • Báo thức đang reo!"
                }

                val builder = NotificationCompat.Builder(context, FALLBACK_CHANNEL_ID)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setContentTitle("Báo thức học tập: ${record.title}")
                    .setContentText(bodyText)
                    .setPriority(NotificationCompat.PRIORITY_MAX)
                    .setCategory(NotificationCompat.CATEGORY_ALARM)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setOngoing(true)
                    .setAutoCancel(false)
                    .setContentIntent(openPending)
                    .setFullScreenIntent(openPending, true)
                    .addAction(0, "Tắt", dismissPending)
                    .addAction(0, "Vào học", startPending)

                if (record.snoozeCount == 0) {
                    val snoozeIntent = Intent(context, AlarmActionReceiver::class.java).apply {
                        action = AlarmActionReceiver.ACTION_SNOOZE
                        putExtra(AlarmForegroundService.EXTRA_ALARM_KEY, record.alarmKey)
                        putExtra(AlarmForegroundService.EXTRA_ALARM_ID, record.alarmId)
                    }
                    val snoozePending = PendingIntent.getBroadcast(
                        context,
                        safeId + 4,
                        snoozeIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                    builder.addAction(0, "Nhắc lại 5p", snoozePending)
                }

                manager.notify(record.alarmId, builder.build())
                triggerFallbackVibration(context)
                Log.i(TAG, "4-fallback. Fallback notification posted successfully for alarmId=${record.alarmId}")
            } catch (e: Throwable) {
                Log.e(TAG, "4-fallback. Failed posting fallback notification: ${e.message}", e)
            }
        }

        private fun triggerFallbackVibration(context: Context) {
            try {
                val vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    val vm = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as? VibratorManager
                    vm?.defaultVibrator
                } else {
                    @Suppress("DEPRECATION")
                    context.getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
                }
                if (vibrator?.hasVibrator() == true) {
                    val pattern = longArrayOf(0, 500, 600, 500, 800)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        vibrator.vibrate(VibrationEffect.createWaveform(pattern, -1))
                    } else {
                        @Suppress("DEPRECATION")
                        vibrator.vibrate(pattern, -1)
                    }
                }
            } catch (_: Throwable) {
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        Log.i(TAG, "4. AlarmReceiver.onReceive triggered. Action=${intent.action}, now=${System.currentTimeMillis()}")

        // Giữ WakeLock ngắn (15s) bảo đảm CPU không ngủ gật trong lúc Service khởi động
        var receiverWakeLock: PowerManager.WakeLock? = null
        try {
            val pm = appContext.getSystemService(Context.POWER_SERVICE) as? PowerManager
            receiverWakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "ExamPilot:AlarmReceiverWakeLock")
            receiverWakeLock?.acquire(15000L)
        } catch (_: Throwable) {
        }

        val alarmKey = intent.getStringExtra(EXTRA_ALARM_KEY)
        if (alarmKey == null) {
            Log.e(TAG, "4. AlarmReceiver received intent without EXTRA_ALARM_KEY!")
            try { receiverWakeLock?.release() } catch (_: Throwable) {}
            return
        }
        val alarmId = intent.getIntExtra(EXTRA_ALARM_ID, alarmKey.hashCode() and 0x7fffffff)

        var existing = AlarmStorage.getByKey(appContext, alarmKey)
        if (existing == null) {
            Log.w(TAG, "4. Alarm key '$alarmKey' not in storage, reconstructing from intent extras")
            val title = intent.getStringExtra(EXTRA_TITLE) ?: "Đến giờ học tập"
            val taskTitle = intent.getStringExtra(EXTRA_TASK_TITLE)
            val soundId = intent.getStringExtra(EXTRA_SOUND_ID) ?: "alarm_dawn"
            val scheduledAt = intent.getLongExtra(EXTRA_SCHEDULED_AT, System.currentTimeMillis())
            existing = AlarmStorage.NativeAlarmRecord(
                alarmKey = alarmKey,
                alarmId = alarmId,
                title = title,
                taskTitle = taskTitle,
                soundId = soundId,
                status = AlarmStorage.STATUS_SCHEDULED,
                snoozeCount = 0,
                scheduledAtMillis = scheduledAt,
                snoozedUntilMillis = null,
                updatedAtMillis = System.currentTimeMillis(),
                acknowledgedAtMillis = null,
            )
        }

        // Không kích hoạt lại báo thức đã bị hủy, tắt hoặc đã vào học
        if (existing.status != AlarmStorage.STATUS_SCHEDULED &&
            existing.status != AlarmStorage.STATUS_SNOOZED
        ) {
            Log.i(TAG, "4. Skipping alarm '$alarmKey' because status is already '${existing.status}'")
            try { receiverWakeLock?.release() } catch (_: Throwable) {}
            return
        }

        val ringing = existing.copy(
            status = AlarmStorage.STATUS_RINGING,
            updatedAtMillis = System.currentTimeMillis(),
        )
        AlarmStorage.upsert(appContext, ringing)
        AlarmEventBus.emit(ringing)

        // Khởi động AlarmForegroundService để duy trì looping audio + vibration
        var serviceRequested = false
        try {
            AlarmForegroundService.start(appContext, ringing)
            serviceRequested = true
            Log.i(TAG, "4a. AlarmForegroundService.start requested for '${ringing.alarmKey}'")
        } catch (t: Throwable) {
            Log.e(TAG, "4a. AlarmForegroundService.start failed synchronously: ${t.message}. Firing immediate fallback notification.", t)
        }

        // Fallback: nếu lệnh startService ném exception ngay lập tức
        if (!serviceRequested) {
            postFallbackAlarmNotification(appContext, ringing)
        }
    }
}

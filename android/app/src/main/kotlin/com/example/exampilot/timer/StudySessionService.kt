package com.example.exampilot.timer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.example.exampilot.MainActivity
import com.example.exampilot.R

/**
 * Foreground Service duy trì thông báo ongoing theo dõi tiến trình phiên học của Study Timer (Phase 4.1).
 * Khai báo foregroundServiceType="dataSync", chạy hoàn toàn độc lập và không ảnh hưởng tới AlarmForegroundService.
 */
class StudySessionService : Service() {

    private var currentNotificationId: Int = DEFAULT_NOTIFICATION_ID
    private var isForegroundActive = false

    companion object {
        const val CHANNEL_ID = "exampilot_session_status_v1"
        const val DEFAULT_NOTIFICATION_ID = 900200

        const val ACTION_START_OR_UPDATE = "com.example.exampilot.timer.START_OR_UPDATE"
        const val ACTION_STOP = "com.example.exampilot.timer.STOP"

        const val EXTRA_SESSION_ID = "sessionId"
        const val EXTRA_NOTIFICATION_ID = "notificationId"
        const val EXTRA_TITLE = "title"
        const val EXTRA_CONTENT = "content"
        const val EXTRA_SUBTEXT = "subText"

        fun startOrUpdate(
            context: Context,
            sessionId: String,
            notificationId: Int,
            title: String,
            content: String,
            subText: String? = null,
        ) {
            val intent = Intent(context.applicationContext, StudySessionService::class.java).apply {
                action = ACTION_START_OR_UPDATE
                putExtra(EXTRA_SESSION_ID, sessionId)
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_CONTENT, content)
                putExtra(EXTRA_SUBTEXT, subText)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.applicationContext.startForegroundService(intent)
            } else {
                context.applicationContext.startService(intent)
            }
        }

        fun stop(context: Context) {
            val intent = Intent(context.applicationContext, StudySessionService::class.java).apply {
                action = ACTION_STOP
            }
            context.applicationContext.stopService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent == null || intent.action == ACTION_STOP) {
            stopSessionAndSelf()
            return START_NOT_STICKY
        }

        val notifId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, DEFAULT_NOTIFICATION_ID)
        currentNotificationId = if (notifId == 0) DEFAULT_NOTIFICATION_ID else notifId
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "ExamPilot · Đang học"
        val content = intent.getStringExtra(EXTRA_CONTENT) ?: ""
        val subText = intent.getStringExtra(EXTRA_SUBTEXT)

        ensureNotificationChannel()

        val notification = buildOngoingNotification(
            notificationId = currentNotificationId,
            title = title,
            content = content,
            subText = subText,
        )

        try {
            if (!isForegroundActive) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    startForeground(
                        currentNotificationId,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                    )
                } else {
                    startForeground(currentNotificationId, notification)
                }
                isForegroundActive = true
            } else {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(currentNotificationId, notification)
            }
        } catch (_: Exception) {
            // Bảo vệ an toàn chống gián đoạn Timer nếu OS hạn chế Foreground Service khởi chạy nền
        }

        return START_NOT_STICKY
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val existing = manager.getNotificationChannel(CHANNEL_ID)
            if (existing == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    "Phiên học đang chạy",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Thông báo trạng thái phiên học và thời gian học thực tế trên Study Timer."
                    setShowBadge(false)
                    enableLights(false)
                    enableVibration(false)
                    setSound(null, null)
                }
                manager.createNotificationChannel(channel)
            }
        }
    }

    private fun buildOngoingNotification(
        notificationId: Int,
        title: String,
        content: String,
        subText: String?,
    ): android.app.Notification {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val contentPendingIntent = PendingIntent.getActivity(this, notificationId, launchIntent, flags)

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(content)
            .setStyle(NotificationCompat.BigTextStyle().bigText(content))
            .setSubText(subText)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setContentIntent(contentPendingIntent)
            .build()
    }

    private fun stopSessionAndSelf() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(currentNotificationId)
        } catch (_: Exception) {}
        isForegroundActive = false
        stopSelf()
    }

    override fun onDestroy() {
        stopSessionAndSelf()
        super.onDestroy()
    }
}

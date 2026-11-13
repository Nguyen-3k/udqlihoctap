package com.example.exampilot.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.exampilot.MainActivity

/**
 * Xử lý các nút hành động trên notification báo thức (Tắt, Nhắc lại 5p, Vào học)
 * ngay cả khi Flutter UI đang đóng hoặc dưới nền.
 */
class AlarmActionReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "ExamPilotAlarm"

        const val ACTION_DISMISS = "com.example.exampilot.alarm.ACTION_DISMISS"
        const val ACTION_SNOOZE = "com.example.exampilot.alarm.ACTION_SNOOZE"
        const val ACTION_START_STUDY = "com.example.exampilot.alarm.ACTION_START_STUDY"
        private const val SNOOZE_DURATION_MILLIS = 5 * 60 * 1000L
    }

    override fun onReceive(context: Context, intent: Intent) {
        val alarmKey = intent.getStringExtra(AlarmForegroundService.EXTRA_ALARM_KEY) ?: ""
        val alarmId = intent.getIntExtra(AlarmForegroundService.EXTRA_ALARM_ID, 0)
        Log.i(TAG, "AlarmActionReceiver onReceive action=${intent.action}, alarmKey=$alarmKey, alarmId=$alarmId")
        val now = System.currentTimeMillis()
        val existing = if (alarmKey.isNotEmpty()) AlarmStorage.getByKey(context, alarmKey) else null

        // Luôn dừng AlarmForegroundService và xóa fallback notification (nếu có)
        AlarmForegroundService.stop(context)
        if (alarmId != 0) {
            AlarmReceiver.cancelFallbackNotification(context, alarmId)
        }

        when (intent.action) {
            ACTION_DISMISS -> {
                Log.i(TAG, "Alarm $alarmKey dismissed by user")
                if (existing != null) {
                    val updated = existing.copy(
                        status = AlarmStorage.STATUS_DISMISSED,
                        updatedAtMillis = now,
                        acknowledgedAtMillis = now,
                    )
                    AlarmStorage.upsert(context, updated)
                    AlarmEventBus.emit(updated)
                }
            }

            ACTION_SNOOZE -> {
                if (existing != null && existing.snoozeCount == 0) {
                    val snoozedUntil = now + SNOOZE_DURATION_MILLIS
                    Log.i(TAG, "Alarm $alarmKey snoozed by user until $snoozedUntil (+5 min)")
                    val updated = existing.copy(
                        status = AlarmStorage.STATUS_SNOOZED,
                        snoozeCount = 1,
                        snoozedUntilMillis = snoozedUntil,
                        updatedAtMillis = now,
                    )
                    AlarmSchedulerNative.scheduleAlarm(context, updated)
                    AlarmEventBus.emit(updated)
                } else {
                    Log.w(TAG, "Cannot snooze alarm $alarmKey: snoozeCount already ${existing?.snoozeCount}")
                }
            }

            ACTION_START_STUDY -> {
                Log.i(TAG, "Alarm $alarmKey starting study session directly")
                if (existing != null) {
                    val updated = existing.copy(
                        status = AlarmStorage.STATUS_STARTED,
                        updatedAtMillis = now,
                        acknowledgedAtMillis = now,
                    )
                    AlarmStorage.upsert(context, updated)
                    AlarmEventBus.emit(updated)
                }
                val launch = Intent(context.applicationContext, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    putExtra("alarmKey", alarmKey)
                    putExtra("alarmAction", "start")
                }
                context.applicationContext.startActivity(launch)
            }
        }
    }
}

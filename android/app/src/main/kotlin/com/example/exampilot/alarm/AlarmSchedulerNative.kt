package com.example.exampilot.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import com.example.exampilot.MainActivity

/**
 * Điều phối lập lịch AlarmManager cho báo thức học tập:
 * - Luôn hủy lịch cũ theo đúng alarmId trước khi đặt lại để tránh trùng lặp.
 * - Dùng setAlarmClock khi đủ quyền Exact Alarm để xuyên Doze tốt nhất trên AOSP.
 * - Tự động hạ cấp an toàn về setAndAllowWhileIdle khi chưa có quyền Exact Alarm,
 *   tuyệt đối không crash ứng dụng vì SecurityException.
 */
object AlarmSchedulerNative {

    fun canScheduleExactAlarms(context: Context): Boolean {
        val manager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            manager.canScheduleExactAlarms()
        } else {
            true
        }
    }

    private fun buildTriggerPendingIntent(
        context: Context,
        alarmKey: String,
        alarmId: Int,
    ): PendingIntent {
        val intent = Intent(context.applicationContext, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_TRIGGER_ALARM
            putExtra(AlarmReceiver.EXTRA_ALARM_KEY, alarmKey)
            putExtra(AlarmReceiver.EXTRA_ALARM_ID, alarmId)
        }
        return PendingIntent.getBroadcast(
            context.applicationContext,
            alarmId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun buildShowAppPendingIntent(context: Context, alarmId: Int): PendingIntent {
        val launchIntent = Intent(context.applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context.applicationContext,
            alarmId + 100000,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Trả về `true` nếu lịch đã đặt với chế độ chính xác (`setAlarmClock`),
     * `false` nếu fallback về lịch không chính xác do thiếu quyền Exact Alarm.
     */
    fun scheduleAlarm(
        context: Context,
        record: AlarmStorage.NativeAlarmRecord,
    ): Boolean {
        val appContext = context.applicationContext
        AlarmStorage.upsert(appContext, record)

        val triggerAt = record.effectiveTriggerMillis
        if (triggerAt <= System.currentTimeMillis()) {
            return canScheduleExactAlarms(appContext)
        }

        val manager = appContext.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return false
        val pending = buildTriggerPendingIntent(appContext, record.alarmKey, record.alarmId)
        // Chống trùng: hủy PendingIntent cũ cùng alarmId trước khi đăng ký mới
        manager.cancel(pending)

        val exactGranted = canScheduleExactAlarms(appContext)
        return try {
            if (exactGranted) {
                val showIntent = buildShowAppPendingIntent(appContext, record.alarmId)
                val info = AlarmManager.AlarmClockInfo(triggerAt, showIntent)
                manager.setAlarmClock(info, pending)
                true
            } else {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
                } else {
                    manager.set(AlarmManager.RTC_WAKEUP, triggerAt, pending)
                }
                false
            }
        } catch (_: SecurityException) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pending)
                } else {
                    manager.set(AlarmManager.RTC_WAKEUP, triggerAt, pending)
                }
            } catch (_: Throwable) {
            }
            false
        }
    }

    fun cancelAlarm(context: Context, alarmKey: String, alarmId: Int) {
        val appContext = context.applicationContext
        val manager = appContext.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        val intent = Intent(appContext, AlarmReceiver::class.java).apply {
            action = AlarmReceiver.ACTION_TRIGGER_ALARM
        }
        val existing = PendingIntent.getBroadcast(
            appContext,
            alarmId,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        )
        if (existing != null) {
            manager?.cancel(existing)
            existing.cancel()
        }
        val old = AlarmStorage.getByKey(appContext, alarmKey)
        if (old != null && (old.status == AlarmStorage.STATUS_SCHEDULED || old.status == AlarmStorage.STATUS_SNOOZED || old.status == AlarmStorage.STATUS_RINGING)) {
            AlarmStorage.upsert(
                appContext,
                old.copy(
                    status = AlarmStorage.STATUS_CANCELLED,
                    updatedAtMillis = System.currentTimeMillis(),
                ),
            )
        }
    }

    fun cancelAllAlarms(context: Context) {
        val appContext = context.applicationContext
        val records = AlarmStorage.getAll(appContext)
        for (record in records) {
            if (record.status == AlarmStorage.STATUS_SCHEDULED ||
                record.status == AlarmStorage.STATUS_SNOOZED ||
                record.status == AlarmStorage.STATUS_RINGING
            ) {
                cancelAlarm(appContext, record.alarmKey, record.alarmId)
            }
        }
        AlarmForegroundService.stop(appContext)
    }
}

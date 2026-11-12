package com.example.exampilot.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Nhận tín hiệu đánh thức từ AlarmManager khi đến giờ báo thức.
 * Cập nhật trạng thái bền vững sang Ringing và khởi động AlarmForegroundService.
 */
class AlarmReceiver : BroadcastReceiver() {
    companion object {
        const val ACTION_TRIGGER_ALARM = "com.example.exampilot.alarm.TRIGGER_ALARM"
        const val EXTRA_ALARM_KEY = "alarmKey"
        const val EXTRA_ALARM_ID = "alarmId"
    }

    override fun onReceive(context: Context, intent: Intent) {
        val alarmKey = intent.getStringExtra(EXTRA_ALARM_KEY) ?: return
        val existing = AlarmStorage.getByKey(context, alarmKey) ?: return

        // Không kích hoạt lại báo thức đã bị hủy, tắt hoặc đã vào học
        if (existing.status != AlarmStorage.STATUS_SCHEDULED &&
            existing.status != AlarmStorage.STATUS_SNOOZED
        ) {
            return
        }

        val ringing = existing.copy(
            status = AlarmStorage.STATUS_RINGING,
            updatedAtMillis = System.currentTimeMillis(),
        )
        AlarmStorage.upsert(context, ringing)
        AlarmEventBus.emit(ringing)
        AlarmForegroundService.start(context, ringing)
    }
}

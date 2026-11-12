package com.example.exampilot.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Phục hồi các báo thức đang chờ hợp lệ sau khi khởi động lại thiết bị hoặc cập nhật app.
 * - Không tạo lịch trùng.
 * - Tuyệt đối không kích hoạt lại báo thức đã Dismissed, Started hoặc Cancelled.
 */
class ExamPilotBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON" &&
            action != Intent.ACTION_TIME_CHANGED &&
            action != Intent.ACTION_TIMEZONE_CHANGED
        ) {
            return
        }

        val now = System.currentTimeMillis()
        val records = AlarmStorage.getAll(context)
        for (record in records) {
            if (record.status == AlarmStorage.STATUS_SCHEDULED ||
                record.status == AlarmStorage.STATUS_SNOOZED
            ) {
                if (record.effectiveTriggerMillis > now) {
                    AlarmSchedulerNative.scheduleAlarm(context, record)
                }
            }
        }
    }
}

package com.example.exampilot.alarm

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Lưu trữ bền vững trạng thái báo thức ở tầng Android native (SharedPreferences)
 * để AlarmReceiver, BootReceiver và AlarmForegroundService hoạt động độc lập
 * ngay cả khi tiến trình Flutter chưa khởi chạy hoặc bị OS thu hồi.
 */
object AlarmStorage {
    private const val PREFS_NAME = "exampilot_native_alarm_prefs"
    private const val KEY_ALARMS = "alarms_json"

    const val STATUS_SCHEDULED = "scheduled"
    const val STATUS_RINGING = "ringing"
    const val STATUS_SNOOZED = "snoozed"
    const val STATUS_DISMISSED = "dismissed"
    const val STATUS_STARTED = "started"
    const val STATUS_CANCELLED = "cancelled"

    data class NativeAlarmRecord(
        val alarmKey: String,
        val alarmId: Int,
        val title: String,
        val taskTitle: String?,
        val soundId: String,
        val status: String,
        val snoozeCount: Int,
        val scheduledAtMillis: Long,
        val snoozedUntilMillis: Long?,
        val updatedAtMillis: Long,
        val acknowledgedAtMillis: Long?,
    ) {
        val effectiveTriggerMillis: Long
            get() = if (status == STATUS_SNOOZED && snoozedUntilMillis != null) {
                snoozedUntilMillis
            } else {
                scheduledAtMillis
            }

        fun toJson(): JSONObject = JSONObject().apply {
            put("alarmKey", alarmKey)
            put("alarmId", alarmId)
            put("title", title)
            put("taskTitle", taskTitle)
            put("soundId", soundId)
            put("status", status)
            put("snoozeCount", snoozeCount)
            put("scheduledAtMillis", scheduledAtMillis)
            if (snoozedUntilMillis != null) {
                put("snoozedUntilMillis", snoozedUntilMillis)
            }
            put("updatedAtMillis", updatedAtMillis)
            if (acknowledgedAtMillis != null) {
                put("acknowledgedAtMillis", acknowledgedAtMillis)
            }
        }

        fun toMap(): Map<String, Any?> = mapOf(
            "alarmKey" to alarmKey,
            "alarmId" to alarmId,
            "title" to title,
            "taskTitle" to taskTitle,
            "soundId" to soundId,
            "status" to status,
            "snoozeCount" to snoozeCount,
            "scheduledAtMillis" to scheduledAtMillis,
            "snoozedUntilMillis" to snoozedUntilMillis,
            "updatedAtMillis" to updatedAtMillis,
            "acknowledgedAtMillis" to acknowledgedAtMillis,
        )

        companion object {
            fun fromJson(obj: JSONObject): NativeAlarmRecord? {
                val alarmKey = obj.optString("alarmKey", "")
                if (alarmKey.isEmpty()) return null
                return NativeAlarmRecord(
                    alarmKey = alarmKey,
                    alarmId = obj.optInt("alarmId", alarmKey.hashCode() and 0x7fffffff),
                    title = obj.optString("title", "Đến giờ học tập"),
                    taskTitle = if (obj.isNull("taskTitle")) null else obj.optString("taskTitle"),
                    soundId = obj.optString("soundId", "alarm_dawn"),
                    status = obj.optString("status", STATUS_SCHEDULED),
                    snoozeCount = obj.optInt("snoozeCount", 0),
                    scheduledAtMillis = obj.optLong("scheduledAtMillis", 0L),
                    snoozedUntilMillis = if (obj.has("snoozedUntilMillis") && !obj.isNull("snoozedUntilMillis")) {
                        obj.optLong("snoozedUntilMillis")
                    } else {
                        null
                    },
                    updatedAtMillis = obj.optLong("updatedAtMillis", System.currentTimeMillis()),
                    acknowledgedAtMillis = if (obj.has("acknowledgedAtMillis") && !obj.isNull("acknowledgedAtMillis")) {
                        obj.optLong("acknowledgedAtMillis")
                    } else {
                        null
                    },
                )
            }

            fun fromMap(map: Map<*, *>): NativeAlarmRecord? {
                val alarmKey = map["alarmKey"]?.toString() ?: return null
                val rawTaskTitle = map["taskTitle"]?.toString()
                return NativeAlarmRecord(
                    alarmKey = alarmKey,
                    alarmId = (map["alarmId"] as? Number)?.toInt() ?: (alarmKey.hashCode() and 0x7fffffff),
                    title = map["title"]?.toString() ?: "Đến giờ học tập",
                    taskTitle = if (rawTaskTitle.isNullOrBlank()) null else rawTaskTitle,
                    soundId = map["soundId"]?.toString() ?: "alarm_dawn",
                    status = map["status"]?.toString() ?: STATUS_SCHEDULED,
                    snoozeCount = (map["snoozeCount"] as? Number)?.toInt() ?: 0,
                    scheduledAtMillis = (map["scheduledAtMillis"] as? Number)?.toLong() ?: 0L,
                    snoozedUntilMillis = (map["snoozedUntilMillis"] as? Number)?.toLong(),
                    updatedAtMillis = (map["updatedAtMillis"] as? Number)?.toLong() ?: System.currentTimeMillis(),
                    acknowledgedAtMillis = (map["acknowledgedAtMillis"] as? Number)?.toLong(),
                )
            }
        }
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    @Synchronized
    fun getAll(context: Context): List<NativeAlarmRecord> {
        val raw = prefs(context).getString(KEY_ALARMS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            val result = mutableListOf<NativeAlarmRecord>()
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                NativeAlarmRecord.fromJson(obj)?.let { result.add(it) }
            }
            result
        } catch (_: Throwable) {
            emptyList()
        }
    }

    @Synchronized
    fun getByKey(context: Context, alarmKey: String): NativeAlarmRecord? {
        return getAll(context).firstOrNull { it.alarmKey == alarmKey }
    }

    @Synchronized
    fun upsert(context: Context, record: NativeAlarmRecord) {
        val all = getAll(context).toMutableList()
        val index = all.indexOfFirst { it.alarmKey == record.alarmKey }
        if (index >= 0) {
            all[index] = record
        } else {
            all.add(record)
        }
        saveAll(context, all)
    }

    @Synchronized
    fun saveAll(context: Context, records: List<NativeAlarmRecord>) {
        val arr = JSONArray()
        records.forEach { arr.put(it.toJson()) }
        prefs(context).edit().putString(KEY_ALARMS, arr.toString()).apply()
    }

    @Synchronized
    fun clearAll(context: Context) {
        prefs(context).edit().remove(KEY_ALARMS).apply()
    }
}

/**
 * Cầu nối phát sự kiện thay đổi trạng thái báo thức từ BroadcastReceiver / Service
 * về Flutter MainActivity khi ứng dụng đang mở.
 */
object AlarmEventBus {
    @Volatile
    var listener: ((Map<String, Any?>) -> Unit)? = null

    fun emit(record: AlarmStorage.NativeAlarmRecord) {
        listener?.invoke(record.toMap())
    }
}

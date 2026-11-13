package com.example.exampilot

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.example.exampilot.alarm.AlarmEventBus
import com.example.exampilot.alarm.AlarmForegroundService
import com.example.exampilot.alarm.AlarmSchedulerNative
import com.example.exampilot.alarm.AlarmStorage
import com.example.exampilot.alarm.SoundPreviewManager
import com.example.exampilot.timer.StudySessionService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var alarmChannel: MethodChannel? = null
    private var audioChannel: MethodChannel? = null
    private var soundPreviewManager: SoundPreviewManager? = null
    private var pendingAlarmLaunchAction: String? = null
    private var pendingAlarmKey: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        captureLaunchExtras(intent)

        val previewManager = SoundPreviewManager(this)
        soundPreviewManager = previewManager

        val alarmMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.exampilot/alarm_service",
        )
        alarmChannel = alarmMethodChannel

        alarmMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "canScheduleExactAlarms" -> {
                    result.success(AlarmSchedulerNative.canScheduleExactAlarms(this))
                }

                "isBatteryOptimizationIgnored" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                        result.success(pm?.isIgnoringBatteryOptimizations(packageName) ?: false)
                    } else {
                        result.success(true)
                    }
                }

                "scheduleAlarm" -> {
                    val args = call.arguments as? Map<*, *>
                    val record = args?.let { AlarmStorage.NativeAlarmRecord.fromMap(it) }
                    if (record == null) {
                        result.error("INVALID_ALARM", "Thiếu thông tin báo thức hợp lệ", null)
                        return@setMethodCallHandler
                    }
                    val scheduledExact = AlarmSchedulerNative.scheduleAlarm(this, record)
                    result.success(scheduledExact)
                }

                "startRingingService" -> {
                    val args = call.arguments as? Map<*, *>
                    val record = args?.let { AlarmStorage.NativeAlarmRecord.fromMap(it) }
                    if (record != null) {
                        AlarmStorage.upsert(this, record)
                        AlarmForegroundService.start(this, record)
                    }
                    result.success(null)
                }

                "stopRingingService" -> {
                    AlarmForegroundService.stop(this)
                    result.success(null)
                }

                "syncAlarmRecord" -> {
                    val args = call.arguments as? Map<*, *>
                    val record = args?.let { AlarmStorage.NativeAlarmRecord.fromMap(it) }
                    if (record != null) {
                        AlarmStorage.upsert(this, record)
                        if (record.status == AlarmStorage.STATUS_DISMISSED ||
                            record.status == AlarmStorage.STATUS_STARTED ||
                            record.status == AlarmStorage.STATUS_CANCELLED
                        ) {
                            AlarmSchedulerNative.cancelAlarm(this, record.alarmKey, record.alarmId)
                            AlarmForegroundService.stop(this)
                        }
                    }
                    result.success(null)
                }

                "cancelAlarm" -> {
                    val alarmKey = call.argument<String>("alarmKey") ?: ""
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    AlarmSchedulerNative.cancelAlarm(this, alarmKey, alarmId)
                    AlarmForegroundService.stop(this)
                    result.success(null)
                }

                "cancelAllAlarms" -> {
                    AlarmSchedulerNative.cancelAllAlarms(this)
                    result.success(null)
                }

                "getStoredAlarms" -> {
                    result.success(AlarmStorage.getAll(this).map { it.toMap() })
                }

                "consumePendingLaunchAction" -> {
                    val action = pendingAlarmLaunchAction
                    val key = pendingAlarmKey
                    pendingAlarmLaunchAction = null
                    pendingAlarmKey = null
                    if (action != null) {
                        result.success(mapOf("action" to action, "alarmKey" to key))
                    } else {
                        result.success(null)
                    }
                }

                "openExactAlarmSettings" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        try {
                            val settingsIntent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                data = android.net.Uri.parse("package:$packageName")
                            }
                            startActivity(settingsIntent)
                            result.success(true)
                        } catch (_: Throwable) {
                            try {
                                startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM))
                                result.success(true)
                            } catch (_: Throwable) {
                                result.success(false)
                            }
                        }
                    } else {
                        result.success(true)
                    }
                }

                else -> result.notImplemented()
            }
        }

        val audioMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.exampilot/alarm_audio",
        )
        audioChannel = audioMethodChannel

        audioMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "playPreview" -> {
                    val soundId = call.argument<String>("soundId") ?: "none"
                    val isAlarmGroup = call.argument<Boolean>("isAlarmGroup") ?: true
                    previewManager.playPreview(soundId, isAlarmGroup) {
                        runOnUiThread {
                            audioChannel?.invokeMethod("onPreviewCompleted", soundId)
                        }
                    }
                    result.success(null)
                }

                "stopPreview" -> {
                    previewManager.stopPreview()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        val sessionMethodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.example.exampilot/study_session_service",
        )

        sessionMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "startOrUpdateOngoingSession" -> {
                    val sessionId = call.argument<String>("sessionId") ?: ""
                    val notificationId = call.argument<Int>("notificationId") ?: StudySessionService.DEFAULT_NOTIFICATION_ID
                    val title = call.argument<String>("title") ?: "ExamPilot · Đang học"
                    val content = call.argument<String>("content") ?: ""
                    val subText = call.argument<String>("subText")
                    StudySessionService.startOrUpdate(this, sessionId, notificationId, title, content, subText)
                    result.success(null)
                }

                "stopOngoingSession" -> {
                    StudySessionService.stop(this)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        AlarmEventBus.listener = { payload ->
            runOnUiThread {
                alarmChannel?.invokeMethod("onNativeAlarmUpdated", payload)
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureLaunchExtras(intent)
        val action = pendingAlarmLaunchAction
        val key = pendingAlarmKey
        if (action != null) {
            alarmChannel?.invokeMethod(
                "onNativeAlarmLaunchAction",
                mapOf("action" to action, "alarmKey" to key),
            )
            pendingAlarmLaunchAction = null
            pendingAlarmKey = null
        }
    }

    private fun captureLaunchExtras(intent: Intent?) {
        val action = intent?.getStringExtra("alarmAction")
        val key = intent?.getStringExtra("alarmKey")
        if (!action.isNullOrBlank()) {
            pendingAlarmLaunchAction = action
            pendingAlarmKey = key
        }
    }

    override fun onPause() {
        soundPreviewManager?.stopPreview()
        super.onPause()
    }

    override fun onDestroy() {
        AlarmEventBus.listener = null
        soundPreviewManager?.stopPreview()
        soundPreviewManager = null
        super.onDestroy()
    }
}

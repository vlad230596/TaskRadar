package com.taskradar.app

import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.taskradar.app.widget.HomeWidgetStore
import com.taskradar.app.widget.TaskRadarWidgetProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /**
     * A home-screen widget tap the Dart side has not taken yet, as the map
     * `takeAction` answers with. Held here rather than pushed: Dart asks for it
     * once the user is signed in (`HomeWidgetScope`), which on a cold start is
     * long after the intent arrived.
     */
    private var pendingWidgetAction: Map<String, String>? = null
    private var widgetChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // A recreated activity gets its old launch intent again; the tap in it
        // was already handled the first time round.
        if (savedInstanceState == null) captureWidgetAction(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (captureWidgetAction(intent)) {
            // Only a nudge: Dart answers by calling `takeAction`. If nobody is
            // listening yet (signed out), the action simply waits.
            widgetChannel?.invokeMethod("actionAvailable", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        widgetChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "publish" -> {
                            val json = call.arguments as? String
                            if (json == null) {
                                result.error("bad_args", "publish expects the snapshot JSON", null)
                            } else {
                                HomeWidgetStore.writeSnapshot(applicationContext, json)
                                TaskRadarWidgetProvider.refreshAll(applicationContext)
                                result.success(null)
                            }
                        }
                        "takeAction" -> {
                            val action = pendingWidgetAction
                            pendingWidgetAction = null
                            result.success(action)
                        }
                        else -> result.notImplemented()
                    }
                }
            }

        // Emulator QA package only (`tests/android/`): Dart reports the first
        // rasterized frame that already shows the cached board, and Android
        // turns it into the standard "Fully drawn" launch metric. The regular
        // package never registers the channel.
        if (packageName != "com.taskradar.app.qa") return
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "taskradar/qa")
            .setMethodCallHandler { call, result ->
                if (call.method == "cachedBoardRasterized") {
                    reportFullyDrawn()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    /** Reads a widget action out of [intent], consuming it. True if there was one. */
    private fun captureWidgetAction(intent: Intent?): Boolean {
        if (intent == null) return false
        val action: Map<String, String> =
            when (intent.action) {
                ACTION_WIDGET_OPEN_TASK -> {
                    val taskId = intent.getStringExtra(EXTRA_WIDGET_TASK_ID) ?: return false
                    buildMap<String, String> {
                        put("action", "openTask")
                        put("taskId", taskId)
                        intent.getStringExtra(EXTRA_WIDGET_PROJECT_ID)?.let { put("projectId", it) }
                    }
                }
                ACTION_WIDGET_TAKE_STEP -> {
                    val taskId = intent.getStringExtra(EXTRA_WIDGET_TASK_ID) ?: return false
                    mapOf("action" to "takeStep", "taskId" to taskId)
                }
                ACTION_WIDGET_REFRESH -> mapOf("action" to "refresh")
                ACTION_WIDGET_DICTATE -> mapOf("action" to "dictate")
                ACTION_WIDGET_OPEN_WORK -> mapOf("action" to "openWork")
                else -> return false
            }
        pendingWidgetAction = action
        // So a later `getIntent()` (plugins read it too) does not see it again.
        intent.action = Intent.ACTION_MAIN
        intent.removeExtra(EXTRA_WIDGET_TASK_ID)
        intent.removeExtra(EXTRA_WIDGET_PROJECT_ID)
        return true
    }

    companion object {
        const val WIDGET_CHANNEL = "taskradar/home_widget"
        const val ACTION_WIDGET_OPEN_TASK = "com.taskradar.app.widget.OPEN_TASK"
        const val ACTION_WIDGET_REFRESH = "com.taskradar.app.widget.REFRESH"
        const val ACTION_WIDGET_OPEN_APP = "com.taskradar.app.widget.OPEN_APP"
        const val ACTION_WIDGET_DICTATE = "com.taskradar.app.widget.DICTATE"
        const val ACTION_WIDGET_TAKE_STEP = "com.taskradar.app.widget.TAKE_STEP"
        const val ACTION_WIDGET_OPEN_WORK = "com.taskradar.app.widget.OPEN_WORK"
        const val EXTRA_WIDGET_TASK_ID = "com.taskradar.app.widget.TASK_ID"
        const val EXTRA_WIDGET_PROJECT_ID = "com.taskradar.app.widget.PROJECT_ID"

        private fun base(context: Context, action: String) =
            Intent(context, MainActivity::class.java)
                .setAction(action)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)

        fun openTaskIntent(context: Context, taskId: String, projectId: String?): Intent =
            base(context, ACTION_WIDGET_OPEN_TASK)
                .putExtra(EXTRA_WIDGET_TASK_ID, taskId)
                .apply { if (projectId != null) putExtra(EXTRA_WIDGET_PROJECT_ID, projectId) }

        fun refreshIntent(context: Context): Intent = base(context, ACTION_WIDGET_REFRESH)

        /** A goal step's take button: the step goes into the active contour's set. */
        fun takeStepIntent(context: Context, taskId: String): Intent =
            base(context, ACTION_WIDGET_TAKE_STEP).putExtra(EXTRA_WIDGET_TASK_ID, taskId)

        /** The widget's microphone: the dictation screen, aimed at the sandbox. */
        fun dictateIntent(context: Context): Intent = base(context, ACTION_WIDGET_DICTATE)

        /** The «Сегодня» row: the app, on «Работа» (Dart switches the mode). */
        fun openWorkIntent(context: Context): Intent = base(context, ACTION_WIDGET_OPEN_WORK)

        /** The widget's title: just bring the app forward. */
        fun openAppIntent(context: Context): Intent = base(context, ACTION_WIDGET_OPEN_APP)
    }
}

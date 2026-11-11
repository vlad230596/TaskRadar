package com.taskradar.app.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.taskradar.app.MainActivity

/**
 * Row taps in the widget's list (see [TaskRadarWidgetProvider] for why every
 * row goes through one template).
 *
 * Not exported (`AndroidManifest.xml`): the provider has to be, for the
 * launcher's sake, and an exported receiver would let any app on the phone
 * open a task here or fold a group by naming the action.
 */
class TaskRadarWidgetClickReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TaskRadarWidgetProvider.ACTION_ROW_CLICK) return
        when (intent.getStringExtra(TaskRadarWidgetProvider.EXTRA_ROW_KIND)) {
            TaskRadarWidgetProvider.ROW_PROJECT -> {
                // Collapse/expand is the widget's own business: written here,
                // redrawn here, and the app is never woken for it.
                val projectId = intent.getStringExtra(TaskRadarWidgetProvider.EXTRA_PROJECT_ID) ?: return
                HomeWidgetStore.toggleCollapsed(context, projectId)
                TaskRadarWidgetProvider.refreshList(context)
            }
            TaskRadarWidgetProvider.ROW_TASK -> {
                val taskId = intent.getStringExtra(TaskRadarWidgetProvider.EXTRA_TASK_ID) ?: return
                // Allowed from a receiver: the broadcast comes from a widget
                // click, which grants the app a short window to start an
                // activity (the launcher is the visible sender).
                context.startActivity(
                    MainActivity.openTaskIntent(
                        context,
                        taskId = taskId,
                        projectId = intent.getStringExtra(TaskRadarWidgetProvider.EXTRA_PROJECT_ID),
                    ),
                )
            }
        }
    }
}

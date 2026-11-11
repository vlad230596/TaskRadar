package com.taskradar.app.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.text.format.DateUtils
import android.view.View
import android.widget.RemoteViews
import com.taskradar.app.MainActivity
import com.taskradar.app.R
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * The «В работе» home-screen widget: the work mode's set, grouped by project.
 *
 * ## Data
 *
 * Never fetched here. The app pushes a snapshot over `taskradar/home_widget`
 * (see `MainActivity`) whenever the set changes, and this draws the last one
 * from [HomeWidgetStore]. No snapshot yet, or the user signed out: a line that
 * says to open the app.
 *
 * ## Taps
 *
 * The list is a collection, so every row shares one click template -- a
 * broadcast to [TaskRadarWidgetClickReceiver], which is not exported -- and
 * each row's fill-in intent says what it is:
 *
 * - a **project header** flips its group in [HomeWidgetStore] and redraws the
 *   list. The app is never woken for it;
 * - a **task** starts `MainActivity` with [MainActivity.EXTRA_WIDGET_TASK_ID],
 *   which Dart resolves through the same path a reminder tap takes.
 *
 * The header's refresh arrow and title are activity intents of their own: they
 * open the app, which re-reads the set and pushes a new snapshot.
 */
class TaskRadarWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, buildViews(context, id))
        manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        manager: AppWidgetManager,
        id: Int,
        newOptions: Bundle,
    ) {
        manager.updateAppWidget(id, buildViews(context, id))
    }

    companion object {
        const val ACTION_ROW_CLICK = "com.taskradar.app.widget.ROW_CLICK"
        const val EXTRA_ROW_KIND = "rowKind"
        const val EXTRA_PROJECT_ID = "projectId"
        const val EXTRA_TASK_ID = "taskId"
        const val ROW_PROJECT = "project"
        const val ROW_TASK = "task"

        private fun widgetIds(context: Context): IntArray =
            AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, TaskRadarWidgetProvider::class.java))

        /** Redraws every placed widget: header and list. Called on a new snapshot. */
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = widgetIds(context)
            if (ids.isEmpty()) return
            for (id in ids) manager.updateAppWidget(id, buildViews(context, id))
            manager.notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
        }

        /** Redraws only the list: a collapse or expand. */
        fun refreshList(context: Context) {
            val ids = widgetIds(context)
            if (ids.isEmpty()) return
            AppWidgetManager.getInstance(context).notifyAppWidgetViewDataChanged(ids, R.id.widget_list)
        }

        private fun buildViews(context: Context, widgetId: Int): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.taskradar_widget)
            val snapshot = HomeWidgetStore.readSnapshot(context)

            // The list's adapter. The data URI makes the intent unique per
            // widget, so two placed widgets do not share one factory.
            val service =
                Intent(context, TaskRadarWidgetService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId)
                    data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
                }
            @Suppress("DEPRECATION")
            views.setRemoteAdapter(R.id.widget_list, service)
            views.setEmptyView(R.id.widget_list, R.id.widget_empty)

            val template =
                PendingIntent.getBroadcast(
                    context,
                    0,
                    Intent(context, TaskRadarWidgetClickReceiver::class.java).setAction(ACTION_ROW_CLICK),
                    // Mutable on purpose: the rows' fill-in intents have to be
                    // merged into it. The intent is explicit, so nothing else
                    // can receive it, and the fill-in cannot change its target.
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
                )
            views.setPendingIntentTemplate(R.id.widget_list, template)

            views.setOnClickPendingIntent(
                R.id.widget_title,
                PendingIntent.getActivity(
                    context,
                    1,
                    MainActivity.openAppIntent(context),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )
            views.setOnClickPendingIntent(
                R.id.widget_refresh,
                PendingIntent.getActivity(
                    context,
                    2,
                    MainActivity.refreshIntent(context),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                ),
            )

            val res = context.resources
            when {
                snapshot == null -> {
                    views.setTextViewText(R.id.widget_count, "")
                    views.setViewVisibility(R.id.widget_count, View.GONE)
                    views.setTextViewText(R.id.widget_updated, "")
                    views.setTextViewText(R.id.widget_empty, res.getString(R.string.widget_no_snapshot))
                }
                !snapshot.signedIn -> {
                    views.setViewVisibility(R.id.widget_count, View.GONE)
                    views.setTextViewText(R.id.widget_updated, "")
                    views.setTextViewText(R.id.widget_empty, res.getString(R.string.widget_signed_out))
                }
                else -> {
                    val total = snapshot.total
                    views.setViewVisibility(R.id.widget_count, if (total > 0) View.VISIBLE else View.GONE)
                    views.setTextViewText(R.id.widget_count, total.toString())
                    views.setTextViewText(R.id.widget_updated, updatedLabel(context, snapshot))
                    views.setTextViewText(R.id.widget_empty, res.getString(R.string.widget_empty))
                }
            }
            return views
        }

        /** «обновлено 14:05», «обновлено 12.11 14:05», «копия от 14:05». */
        private fun updatedLabel(context: Context, snapshot: HomeWidgetStore.Snapshot): String {
            if (snapshot.updatedAtMillis <= 0L) return ""
            val at = Date(snapshot.updatedAtMillis)
            val clock = SimpleDateFormat("HH:mm", Locale.forLanguageTag("ru")).format(at)
            val stamp =
                if (DateUtils.isToday(snapshot.updatedAtMillis)) {
                    clock
                } else {
                    val sameYear =
                        Calendar.getInstance().get(Calendar.YEAR) ==
                            Calendar.getInstance().also { it.time = at }.get(Calendar.YEAR)
                    val day = SimpleDateFormat(if (sameYear) "dd.MM" else "dd.MM.yy", Locale.forLanguageTag("ru")).format(at)
                    "$day $clock"
                }
            val prefix =
                context.getString(
                    if (snapshot.fromCache) R.string.widget_cached_prefix else R.string.widget_updated_prefix,
                )
            return "$prefix $stamp"
        }
    }
}

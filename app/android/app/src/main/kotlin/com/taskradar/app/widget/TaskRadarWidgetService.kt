package com.taskradar.app.widget

import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.taskradar.app.R

/** Feeds the widget's list: project headers, and the tasks of open groups. */
class TaskRadarWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory = Factory(applicationContext)

    /** One line of the list, flattened out of the snapshot. */
    sealed class Row {
        abstract val stableId: Long

        data class Header(val project: HomeWidgetStore.Project, val collapsed: Boolean) : Row() {
            override val stableId: Long get() = ("p:" + project.id).hashCode().toLong() shl 1
        }

        data class Item(val task: HomeWidgetStore.Task) : Row() {
            override val stableId: Long get() = ("t:" + task.id).hashCode().toLong() shl 1 or 1L
        }
    }

    companion object {
        /**
         * The list for a snapshot: every project is a header, followed by its
         * tasks unless its id is in [collapsed]. Order is the snapshot's own --
         * the app decided it, see `home_widget_snapshot.dart`.
         */
        fun flatten(snapshot: HomeWidgetStore.Snapshot?, collapsed: Set<String>): List<Row> {
            if (snapshot == null || !snapshot.signedIn) return emptyList()
            val rows = ArrayList<Row>()
            for (project in snapshot.projects) {
                val isCollapsed = project.id in collapsed
                rows.add(Row.Header(project, isCollapsed))
                if (!isCollapsed) project.tasks.forEach { rows.add(Row.Item(it)) }
            }
            return rows
        }
    }

    private class Factory(private val context: Context) : RemoteViewsFactory {
        private var rows: List<Row> = emptyList()

        override fun onCreate() {}

        override fun onDataSetChanged() {
            rows = flatten(HomeWidgetStore.readSnapshot(context), HomeWidgetStore.collapsed(context))
        }

        override fun onDestroy() {
            rows = emptyList()
        }

        override fun getCount(): Int = rows.size

        override fun getViewAt(position: Int): RemoteViews? {
            // The host may ask for a position from the previous data set while
            // the new one is being swapped in.
            val row = rows.getOrNull(position) ?: return null
            return when (row) {
                is Row.Header -> header(row)
                is Row.Item -> item(row)
            }
        }

        private fun header(row: Row.Header): RemoteViews {
            val project = row.project
            return RemoteViews(context.packageName, R.layout.taskradar_widget_project).apply {
                setTextViewText(R.id.widget_project_name, project.name)
                setTextViewText(R.id.widget_project_count, project.tasks.size.toString())
                setTextViewText(R.id.widget_project_chevron, if (row.collapsed) "▸" else "▾")
                setTextViewText(R.id.widget_project_letter, project.badgeLetter)
                setInt(R.id.widget_project_badge, "setColorFilter", badgeColor(project.badgeColor))
                setContentDescription(
                    R.id.widget_project_row,
                    context.getString(
                        if (row.collapsed) R.string.widget_expand_project else R.string.widget_collapse_project,
                        project.name,
                    ),
                )
                setOnClickFillInIntent(
                    R.id.widget_project_row,
                    Intent()
                        .putExtra(TaskRadarWidgetProvider.EXTRA_ROW_KIND, TaskRadarWidgetProvider.ROW_PROJECT)
                        .putExtra(TaskRadarWidgetProvider.EXTRA_PROJECT_ID, project.id),
                )
            }
        }

        private fun item(row: Row.Item): RemoteViews {
            val task = row.task
            return RemoteViews(context.packageName, R.layout.taskradar_widget_task).apply {
                setTextViewText(R.id.widget_task_title, task.title)
                setViewVisibility(R.id.widget_task_dot, if (task.blocked) View.GONE else View.VISIBLE)
                setViewVisibility(R.id.widget_task_dot_blocked, if (task.blocked) View.VISIBLE else View.GONE)
                setViewVisibility(R.id.widget_task_waiting, if (task.blocked) View.VISIBLE else View.GONE)
                setOnClickFillInIntent(
                    R.id.widget_task_row,
                    Intent()
                        .putExtra(TaskRadarWidgetProvider.EXTRA_ROW_KIND, TaskRadarWidgetProvider.ROW_TASK)
                        .putExtra(TaskRadarWidgetProvider.EXTRA_TASK_ID, task.id)
                        .putExtra(TaskRadarWidgetProvider.EXTRA_PROJECT_ID, task.projectId),
                )
            }
        }

        /**
         * The project colour from the app's palette, except `ink` on the dark
         * widget: a navy badge on a navy surface is the "cannot tell apart"
         * failure the palette exists to avoid, so it takes the rail's lighter
         * navy there.
         */
        private fun badgeColor(argb: Int): Int {
            val night =
                (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                    Configuration.UI_MODE_NIGHT_YES
            return if (night && argb == INK) RAIL_ACTIVE else argb
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 2

        override fun getItemId(position: Int): Long = rows.getOrNull(position)?.stableId ?: position.toLong()

        override fun hasStableIds(): Boolean = true

        private companion object {
            val INK = 0xFF1B2050.toInt()
            val RAIL_ACTIVE = 0xFF333A73.toInt()
        }
    }
}

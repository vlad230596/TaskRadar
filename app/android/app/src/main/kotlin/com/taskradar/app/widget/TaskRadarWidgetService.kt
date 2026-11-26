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

        /** A goal step row, above the projects. */
        data class GoalStep(val goal: HomeWidgetStore.Goal) : Row() {
            override val stableId: Long get() = ("g:" + goal.goalId).hashCode().toLong() shl 1
        }

        /** The line between the goal steps and the projects. */
        /** «Сегодня 3 из 7» (design/today-history-spec.md, п. 12). */
        data class TodayRow(val today: HomeWidgetStore.Today) : Row() {
            override val stableId: Long get() = "today".hashCode().toLong() shl 1
        }

        object Divider : Row() {
            override val stableId: Long get() = "divider".hashCode().toLong() shl 1 or 1L
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
            // The goal steps first, in the same list: a separate container
            // above it would eat the height of a small widget when scrolled.
            snapshot.goals.forEach { rows.add(Row.GoalStep(it)) }
            // Under the goal rows, over the set: «Сегодня N из M». Hidden when
            // the day has nothing and no tail is waiting.
            val today = snapshot.today?.takeIf { it.visible }
            if (today != null) rows.add(Row.TodayRow(today))
            if ((snapshot.goals.isNotEmpty() || today != null) && snapshot.projects.isNotEmpty()) {
                rows.add(Row.Divider)
            }
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
                is Row.GoalStep -> goal(row)
                is Row.TodayRow -> today(row.today)
                Row.Divider -> RemoteViews(context.packageName, R.layout.taskradar_widget_divider)
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

        /** A colour resource for the current (day or night) configuration. */
        @Suppress("DEPRECATION")
        private fun color(id: Int): Int = context.resources.getColor(id)

        private fun goal(row: Row.GoalStep): RemoteViews {
            val goal = row.goal
            val stepId = goal.stepId
            val hasStep = stepId != null
            return RemoteViews(context.packageName, R.layout.taskradar_widget_goal).apply {
                setTextViewText(
                    R.id.widget_goal_step,
                    if (hasStep) {
                        goal.stepTitle ?: ""
                    } else {
                        context.getString(R.string.widget_goal_discuss, goal.title)
                    },
                )
                if (goal.expired) {
                    setTextViewText(
                        R.id.widget_goal_meta,
                        context.getString(R.string.widget_goal_expired) + " · " + goal.title,
                    )
                    setTextColor(R.id.widget_goal_meta, color(R.color.widget_goal_expired))
                } else {
                    setTextViewText(
                        R.id.widget_goal_meta,
                        context.getString(R.string.widget_goal_meta, goal.title, goal.done, goal.total),
                    )
                    setTextColor(R.id.widget_goal_meta, color(R.color.widget_goal_muted))
                }
                setViewVisibility(
                    R.id.widget_goal_take,
                    if (hasStep && !goal.inWork) View.VISIBLE else View.GONE,
                )
                setViewVisibility(
                    R.id.widget_goal_in_work,
                    if (hasStep && goal.inWork) View.VISIBLE else View.GONE,
                )
                // The row opens the step; a goal with no step opens the app.
                setOnClickFillInIntent(
                    R.id.widget_goal_row,
                    if (stepId != null) {
                        Intent()
                            .putExtra(TaskRadarWidgetProvider.EXTRA_ROW_KIND, TaskRadarWidgetProvider.ROW_TASK)
                            .putExtra(TaskRadarWidgetProvider.EXTRA_TASK_ID, stepId)
                            .putExtra(TaskRadarWidgetProvider.EXTRA_PROJECT_ID, goal.stepProjectId)
                    } else {
                        Intent().putExtra(TaskRadarWidgetProvider.EXTRA_ROW_KIND, TaskRadarWidgetProvider.ROW_APP)
                    },
                )
                if (stepId != null && !goal.inWork) {
                    setOnClickFillInIntent(
                        R.id.widget_goal_take,
                        Intent()
                            .putExtra(TaskRadarWidgetProvider.EXTRA_ROW_KIND, TaskRadarWidgetProvider.ROW_TAKE)
                            .putExtra(TaskRadarWidgetProvider.EXTRA_TASK_ID, stepId),
                    )
                }
            }
        }

        /**
         * The project colour from the app's palette, except `ink` on the dark
         * widget: a navy badge on a navy surface is the "cannot tell apart"
         * failure the palette exists to avoid, so it takes the rail's lighter
         * navy there.
         */
        private fun today(today: HomeWidgetStore.Today): RemoteViews =
            RemoteViews(context.packageName, R.layout.taskradar_widget_today).apply {
                val allDone = today.total > 0 && today.done >= today.total
                if (today.total == 0) {
                    // An empty day with a tail: the tail is the plan
                    // (coordinator's answer 7).
                    setTextViewText(R.id.widget_today_title, context.getString(R.string.widget_today_tail, today.tail))
                    setViewVisibility(R.id.widget_today_count, View.GONE)
                    setViewVisibility(R.id.widget_today_progress, View.GONE)
                } else {
                    setTextViewText(R.id.widget_today_title, context.getString(R.string.widget_today_title))
                    setViewVisibility(R.id.widget_today_count, View.VISIBLE)
                    setTextViewText(
                        R.id.widget_today_count,
                        context.getString(
                            if (allDone) R.string.widget_today_all_done else R.string.widget_today_count,
                            today.done,
                            today.total,
                        ),
                    )
                    setViewVisibility(R.id.widget_today_progress, View.VISIBLE)
                    setProgressBar(R.id.widget_today_progress, 100, today.done * 100 / today.total, false)
                }
                val time = today.time
                val title = today.title
                if (!allDone && today.total > 0 && time != null && title != null) {
                    val line = android.text.SpannableStringBuilder()
                    line.append(time)
                    line.setSpan(
                        android.text.style.StyleSpan(android.graphics.Typeface.BOLD),
                        0,
                        time.length,
                        android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    line.setSpan(
                        android.text.style.ForegroundColorSpan(color(R.color.widget_today_time)),
                        0,
                        time.length,
                        android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE,
                    )
                    line.append(" ").append(title)
                    setTextViewText(R.id.widget_today_next, line)
                    setViewVisibility(R.id.widget_today_next, View.VISIBLE)
                } else {
                    setViewVisibility(R.id.widget_today_next, View.GONE)
                }
                setOnClickFillInIntent(
                    R.id.widget_today_row,
                    Intent().putExtra(TaskRadarWidgetProvider.EXTRA_ROW_KIND, TaskRadarWidgetProvider.ROW_WORK),
                )
            }

        private fun badgeColor(argb: Int): Int {
            val night =
                (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                    Configuration.UI_MODE_NIGHT_YES
            return if (night && argb == INK) RAIL_ACTIVE else argb
        }

        override fun getLoadingView(): RemoteViews? = null

        override fun getViewTypeCount(): Int = 5

        override fun getItemId(position: Int): Long = rows.getOrNull(position)?.stableId ?: position.toLong()

        override fun hasStableIds(): Boolean = true

        private companion object {
            val INK = 0xFF1B2050.toInt()
            val RAIL_ACTIVE = 0xFF333A73.toInt()
        }
    }
}

package com.taskradar.app.widget

import android.content.Context
import org.json.JSONObject

/**
 * The home-screen widget's memory: the last snapshot the app pushed, and which
 * project groups the user has collapsed.
 *
 * Plain SharedPreferences in a file of its own, not the Flutter
 * `shared_preferences` plugin's file: the widget reads this from a
 * `RemoteViewsFactory` with no Flutter engine anywhere, and the collapsed set
 * is written by the widget itself, never by Dart.
 *
 * The snapshot's shape is defined by `lib/home_widget/home_widget_snapshot.dart`.
 * Anything that does not parse, or carries another schema number, reads as
 * "no snapshot" -- the widget then asks the user to open the app, which is the
 * one answer that is always true.
 */
object HomeWidgetStore {
    /** Bump together with `HomeWidgetSnapshot.schemaVersion` in Dart. */
    const val SCHEMA_VERSION = 1

    private const val PREFS = "taskradar_home_widget"
    private const val KEY_SNAPSHOT = "snapshot"
    private const val KEY_COLLAPSED = "collapsed"

    data class Task(val id: String, val projectId: String, val title: String, val blocked: Boolean)

    data class Project(
        val id: String,
        val name: String,
        val badgeColor: Int,
        val badgeLetter: String,
        val tasks: List<Task>,
    )

    data class Snapshot(
        val updatedAtMillis: Long,
        val fromCache: Boolean,
        val signedIn: Boolean,
        val projects: List<Project>,
    ) {
        val total: Int get() = projects.sumOf { it.tasks.size }
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun writeSnapshot(context: Context, json: String) {
        prefs(context).edit().putString(KEY_SNAPSHOT, json).apply()
    }

    fun readSnapshot(context: Context): Snapshot? {
        val raw = prefs(context).getString(KEY_SNAPSHOT, null) ?: return null
        return try {
            parse(raw)
        } catch (error: Exception) {
            null
        }
    }

    fun collapsed(context: Context): Set<String> =
        prefs(context).getStringSet(KEY_COLLAPSED, emptySet())?.toSet() ?: emptySet()

    /** Flips one project between collapsed and expanded. */
    fun toggleCollapsed(context: Context, projectId: String) {
        val next = collapsed(context).toMutableSet()
        if (!next.remove(projectId)) next.add(projectId)
        // A fresh set every time: SharedPreferences must not be handed back the
        // instance it returned, or the change may never be written.
        prefs(context).edit().putStringSet(KEY_COLLAPSED, HashSet(next)).apply()
    }

    fun parse(raw: String): Snapshot? {
        val root = JSONObject(raw)
        if (root.optInt("v", -1) != SCHEMA_VERSION) return null
        val projectsJson = root.optJSONArray("projects")
        val projects = ArrayList<Project>()
        if (projectsJson != null) {
            for (i in 0 until projectsJson.length()) {
                val p = projectsJson.getJSONObject(i)
                val tasksJson = p.optJSONArray("tasks")
                val tasks = ArrayList<Task>()
                if (tasksJson != null) {
                    for (j in 0 until tasksJson.length()) {
                        val t = tasksJson.getJSONObject(j)
                        tasks.add(
                            Task(
                                id = t.getString("id"),
                                projectId = t.optString("projectId", p.getString("id")),
                                title = t.optString("title"),
                                blocked = t.optBoolean("blocked", false),
                            ),
                        )
                    }
                }
                projects.add(
                    Project(
                        id = p.getString("id"),
                        name = p.optString("name"),
                        // ARGB from Dart; above Int.MAX_VALUE as a JSON number.
                        badgeColor = p.optLong("badge", 0xFF4A56BEL).toInt(),
                        badgeLetter = p.optString("letter", "?"),
                        tasks = tasks,
                    ),
                )
            }
        }
        return Snapshot(
            updatedAtMillis = root.optLong("updatedAt", 0L),
            fromCache = root.optBoolean("fromCache", false),
            signedIn = root.optBoolean("signedIn", true),
            projects = projects,
        )
    }
}

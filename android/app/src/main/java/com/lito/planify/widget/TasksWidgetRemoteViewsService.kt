package com.lito.planify.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.lito.planify.R
import com.lito.planify.data.api.TaskResponse

class TasksWidgetRemoteViewsService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TasksWidgetViewsFactory(this.applicationContext, intent)
    }
}

class TasksWidgetViewsFactory(
    private val context: Context,
    private val intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private var tasks: List<TaskResponse> = emptyList()
    private var togglingTaskIds: Set<Int> = emptySet()

    private val appWidgetId: Int
        get() = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID
        )

    override fun onCreate() {
        loadTasks()
    }

    override fun onDataSetChanged() {
        loadTasks()
    }

    private fun loadTasks() {
        val prefs = context.getSharedPreferences("PlanifyWidgets", Context.MODE_PRIVATE)
        val listId = prefs.getInt("widget_${appWidgetId}_listId", 0)
        val allTasks = readTasks(prefs)
        tasks = if (listId == 0) allTasks else allTasks.filter { it.task_list_id == listId }
        togglingTaskIds = prefs.getStringSet("widget_toggling_tasks", emptySet())?.mapNotNull { it.toIntOrNull() }?.toSet() ?: emptySet()
    }

    override fun onDestroy() {
        tasks = emptyList()
    }

    override fun getCount(): Int = tasks.size

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_task_item)
        if (position >= tasks.size) return views

        val task = tasks[position]
        views.setTextViewText(R.id.task_title, task.title)
        
        val isToggling = togglingTaskIds.contains(task.id)
        if (isToggling) {
            views.setTextColor(R.id.task_title, android.graphics.Color.parseColor("#9E9E9E")) // Gray text
            views.setImageViewResource(R.id.task_check_circle, R.drawable.task_check_checked)
            // Empty intent to disable clicks while toggling
            views.setOnClickFillInIntent(R.id.widget_task_root, Intent())
        } else {
            views.setTextColor(R.id.task_title, android.graphics.Color.parseColor("#1D1B20")) // Normal text
            views.setImageViewResource(R.id.task_check_circle, R.drawable.task_check_outline)
            
            val fillInIntent = Intent().apply {
                putExtra("action", "COMPLETE_TASK")
                putExtra("taskId", task.id)
                putExtra("taskListId", task.task_list_id)
            }
            views.setOnClickFillInIntent(R.id.widget_task_root, fillInIntent)
        }

        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long =
        if (position < tasks.size) tasks[position].id.toLong() else position.toLong()

    override fun hasStableIds(): Boolean = true
}

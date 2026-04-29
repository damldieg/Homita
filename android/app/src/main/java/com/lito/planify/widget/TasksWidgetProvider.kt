package com.lito.planify.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import com.lito.planify.MainActivity
import com.lito.planify.R
import com.lito.planify.data.api.CompleteTaskRequest
import com.lito.planify.data.api.RetrofitClient
import com.lito.planify.data.api.TaskListResponse
import com.lito.planify.data.api.TaskResponse
import com.lito.planify.data.local.SessionManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

private const val TAG = "PlanifyTasksWidget"
private const val PREFS_NAME = "PlanifyWidgets"
const val PREFS_KEY_ALL_TASKS = "widget_all_tasks_json"
const val PREFS_KEY_ALL_LISTS = "widget_all_lists_json"

const val ACTION_NEXT_LIST = "com.lito.planify.ACTION_NEXT_LIST"
const val ACTION_PREV_LIST = "com.lito.planify.ACTION_PREV_LIST"
const val ACTION_WIDGET_CLICK = "com.lito.planify.ACTION_WIDGET_CLICK"
const val ACTION_CLEAR_CACHE = "com.lito.planify.widget.ACTION_CLEAR_CACHE"

private const val DEFAULT_LIST_NAME = "Todas las tareas"
private const val DEFAULT_COLOR = "#0B57D0"

class TasksWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        val pendingResult = goAsync()
        for (appWidgetId in appWidgetIds) {
            renderFullWidget(context, appWidgetManager, appWidgetId)
        }
        fetchAndRefresh(context, appWidgetIds, pendingResult)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        val action = intent.action ?: return

        when (action) {
            ACTION_NEXT_LIST, ACTION_PREV_LIST -> handleNavigate(context, intent, action == ACTION_NEXT_LIST)
            ACTION_WIDGET_CLICK -> handleClick(context, intent)
            ACTION_CLEAR_CACHE -> {
                val pendingResult = goAsync()
                fetchAndRefresh(context, allAppWidgetIds(context), pendingResult)
                // Re-programar el siguiente refresco
                com.lito.planify.util.AlarmHelper.scheduleWidgetUpdate(context)
            }
        }
    }

    private fun handleNavigate(context: Context, intent: Intent, forward: Boolean) {
        val appWidgetId = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val lists = readLists(prefs)
        if (lists.isEmpty()) return
        val tasks = readTasks(prefs)

        val currentId = prefs.getInt(listIdKey(appWidgetId), 0)
        val currentIdx = lists.indexOfFirst { it.id == currentId }.takeIf { it >= 0 } ?: 0
        val newIdx = if (forward) (currentIdx + 1) % lists.size
                     else (currentIdx - 1 + lists.size) % lists.size
        val newList = lists[newIdx]

        prefs.edit().putInt(listIdKey(appWidgetId), newList.id).commit()

        val manager = AppWidgetManager.getInstance(context)
        
        // 1. Actualización rápida de la cabecera y el botón de gestión
        val headerViews = buildHeaderRemoteViews(context, newList, tasks)
        
        val manageIntent = Intent(context, MainActivity::class.java).apply {
            data = Uri.parse("planify://tasks?list_id=${newList.id}")
        }
        val managePI = PendingIntent.getActivity(
            context, appWidgetId * 10 + 1, manageIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        headerViews.setOnClickPendingIntent(R.id.widget_tasks_header, managePI)

        manager.partiallyUpdateAppWidget(appWidgetId, headerViews)
        
        // 2. Refrescar el listado interno de tareas
        manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_tasks_list)
    }

    private fun handleClick(context: Context, intent: Intent) {
        val clickAction = intent.getStringExtra("action")
        val taskId = intent.getIntExtra("taskId", 0)
        if (clickAction != "COMPLETE_TASK" || taskId <= 0) return

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val currentToggling = prefs.getStringSet("widget_toggling_tasks", emptySet())?.toMutableSet() ?: mutableSetOf()
        currentToggling.add(taskId.toString())
        prefs.edit().putStringSet("widget_toggling_tasks", currentToggling).commit()
        
        val manager = AppWidgetManager.getInstance(context)
        val allIds = allAppWidgetIds(context)
        for (id in allIds) {
            manager.notifyAppWidgetViewDataChanged(id, R.id.widget_tasks_list)
        }

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val sm = SessionManager(context)
                val token = sm.authTokenFlow.firstOrNull() ?: return@launch
                RetrofitClient.setToken(token)
                val resp = RetrofitClient.apiService.completeTask(CompleteTaskRequest(taskId, true))
                if (!resp.isSuccessful) {
                    Log.e(TAG, "completeTask failed: ${resp.code()}")
                }
            } finally {
                val updatedToggling = prefs.getStringSet("widget_toggling_tasks", emptySet())?.toMutableSet() ?: mutableSetOf()
                updatedToggling.remove(taskId.toString())
                prefs.edit().putStringSet("widget_toggling_tasks", updatedToggling).commit()
                fetchAndRefreshBlocking(context, allIds)
            }
        }
    }

    private fun fetchAndRefresh(context: Context, appWidgetIds: IntArray, pendingResult: PendingResult? = null) {
        if (appWidgetIds.isEmpty()) {
            pendingResult?.finish()
            return
        }
        CoroutineScope(Dispatchers.IO).launch {
            try {
                fetchAndRefreshBlocking(context, appWidgetIds)
            } finally {
                pendingResult?.finish()
            }
        }
    }

    private suspend fun fetchAndRefreshBlocking(context: Context, appWidgetIds: IntArray) {
        val sm = SessionManager(context)
        val token = sm.authTokenFlow.firstOrNull() ?: return
        RetrofitClient.setToken(token)

        val tasksResp = RetrofitClient.apiService.getTasks(null, null, true)
        val listsResp = RetrofitClient.apiService.getTaskLists()
        if (!tasksResp.isSuccessful || !listsResp.isSuccessful) {
            Log.e(TAG, "Fetch failed tasks=${tasksResp.code()} lists=${listsResp.code()}")
            return
        }

        val pendingTasks = (tasksResp.body() ?: emptyList()).filter { it.completed_at == null }
        val apiLists = (listsResp.body() ?: emptyList()).filter { it.widget != false }
        val allLists = listOf(globalListSentinel()) + apiLists

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val gson = Gson()
        prefs.edit()
            .putString(PREFS_KEY_ALL_TASKS, gson.toJson(pendingTasks))
            .putString(PREFS_KEY_ALL_LISTS, gson.toJson(allLists))
            .commit()

        for (id in appWidgetIds) {
            val currentId = prefs.getInt(listIdKey(id), 0)
            if (allLists.none { it.id == currentId }) {
                prefs.edit().putInt(listIdKey(id), 0).commit()
            }
        }

        val manager = AppWidgetManager.getInstance(context)
        for (id in appWidgetIds) {
            renderFullWidget(context, manager, id)
            manager.notifyAppWidgetViewDataChanged(id, R.id.widget_tasks_list)
        }
    }

    private fun renderFullWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
        val views = RemoteViews(context.packageName, R.layout.widget_tasks)
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val listId = prefs.getInt(listIdKey(appWidgetId), 0)
        val lists = readLists(prefs)
        val tasks = readTasks(prefs)

        val currentList = lists.firstOrNull { it.id == listId }
            ?: lists.firstOrNull()
            ?: globalListSentinel()

        applyHeader(views, currentList, tasks)

        val serviceIntent = Intent(context, TasksWidgetRemoteViewsService::class.java).apply {
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            data = Uri.parse("tasks://widget/$appWidgetId")
        }
        views.setRemoteAdapter(R.id.widget_tasks_list, serviceIntent)
        views.setEmptyView(R.id.widget_tasks_list, R.id.widget_tasks_empty)

        applyClickListeners(context, views, appWidgetId, currentList.id)

        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    private fun buildHeaderRemoteViews(
        context: Context,
        list: TaskListResponse,
        allTasks: List<TaskResponse>
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_tasks)
        applyHeader(views, list, allTasks)
        return views
    }

    private fun applyHeader(views: RemoteViews, list: TaskListResponse, allTasks: List<TaskResponse>) {
        views.setTextViewText(R.id.widget_tasks_title, list.name)
        if (list.id == 0) {
            views.setViewVisibility(R.id.widget_tasks_dot, View.INVISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_tasks_dot, View.VISIBLE)
            views.setInt(R.id.widget_tasks_dot, "setColorFilter", parseColorSafe(list.color))
        }
        val count = if (list.id == 0) allTasks.size else allTasks.count { it.task_list_id == list.id }
        views.setTextViewText(R.id.widget_tasks_count, count.toString())
    }

    private fun applyClickListeners(context: Context, views: RemoteViews, appWidgetId: Int, currentListId: Int) {
        val manageIntent = Intent(context, MainActivity::class.java).apply {
            data = Uri.parse("planify://tasks?list_id=$currentListId")
        }
        val managePI = PendingIntent.getActivity(
            context, appWidgetId * 10 + 1, manageIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        views.setOnClickPendingIntent(R.id.widget_tasks_header, managePI)

        views.setOnClickPendingIntent(
            R.id.widget_tasks_next,
            navPendingIntent(context, appWidgetId, ACTION_NEXT_LIST, appWidgetId * 10 + 2)
        )
        views.setOnClickPendingIntent(
            R.id.widget_tasks_prev,
            navPendingIntent(context, appWidgetId, ACTION_PREV_LIST, appWidgetId * 10 + 3)
        )

        val clickTemplateIntent = Intent(context, TasksWidgetProvider::class.java).apply {
            action = ACTION_WIDGET_CLICK
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        }
        val clickTemplate = PendingIntent.getBroadcast(
            context, appWidgetId * 10 + 4, clickTemplateIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )
        views.setPendingIntentTemplate(R.id.widget_tasks_list, clickTemplate)
    }

    private fun navPendingIntent(context: Context, appWidgetId: Int, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, TasksWidgetProvider::class.java).apply {
            this.action = action
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
            data = Uri.parse("tasks://$action/$appWidgetId")
        }
        return PendingIntent.getBroadcast(
            context, requestCode, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun allAppWidgetIds(context: Context): IntArray {
        val manager = AppWidgetManager.getInstance(context)
        return manager.getAppWidgetIds(ComponentName(context, TasksWidgetProvider::class.java))
    }

    private fun globalListSentinel(): TaskListResponse =
        TaskListResponse(0, DEFAULT_LIST_NAME, "", "", "", "", "")

    private fun parseColorSafe(hex: String?): Int = try {
        android.graphics.Color.parseColor(hex ?: DEFAULT_COLOR)
    } catch (e: Exception) {
        android.graphics.Color.parseColor(DEFAULT_COLOR)
    }

    private fun listIdKey(appWidgetId: Int) = "widget_${appWidgetId}_listId"
}

internal fun readLists(prefs: SharedPreferences): List<TaskListResponse> {
    val json = prefs.getString(PREFS_KEY_ALL_LISTS, null) ?: return emptyList()
    val type = object : TypeToken<List<TaskListResponse>>() {}.type
    return Gson().fromJson(json, type) ?: emptyList()
}

internal fun readTasks(prefs: SharedPreferences): List<TaskResponse> {
    val json = prefs.getString(PREFS_KEY_ALL_TASKS, null) ?: return emptyList()
    val type = object : TypeToken<List<TaskResponse>>() {}.type
    return Gson().fromJson(json, type) ?: emptyList()
}

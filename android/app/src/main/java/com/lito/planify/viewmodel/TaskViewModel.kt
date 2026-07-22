package com.lito.planify.viewmodel

import android.app.Application
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lito.planify.data.api.*
import com.lito.planify.data.api.util.NetworkUtils.getErrorMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

class TaskViewModel(application: Application) : AndroidViewModel(application) {

    private val _tasks = MutableStateFlow<List<TaskResponse>>(emptyList())
    val tasks: StateFlow<List<TaskResponse>> = _tasks

    private val _togglingTasks = MutableStateFlow<Set<Int>>(emptySet())
    val togglingTasks: StateFlow<Set<Int>> = _togglingTasks

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private var lastFetchedId: Int? = -2 

    private fun notifyWidgetDataChanged() {
        val app = getApplication<Application>()
        val clearIntent = Intent("com.lito.planify.widget.ACTION_CLEAR_CACHE")
        clearIntent.component = ComponentName(app, com.lito.planify.widget.TasksWidgetProvider::class.java)
        app.sendBroadcast(clearIntent)
        
        val appWidgetManager = AppWidgetManager.getInstance(app)
        val componentName = ComponentName(app, com.lito.planify.widget.TasksWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, com.lito.planify.R.id.widget_tasks_list)
    }

    fun fetchTasks(taskListId: Int? = null, search: String? = null, force: Boolean = false) {
        val effectiveId = if (taskListId != null && taskListId > 0) taskListId else null
        val currentIdFlag = effectiveId ?: 0
        
        if (!force && currentIdFlag == lastFetchedId && search == null) return

        lastFetchedId = currentIdFlag

        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.getTasks(effectiveId, search)
                if (response.isSuccessful) {
                    _tasks.value = response.body() ?: emptyList()
                } else {
                    _error.value = response.getErrorMessage()
                }
            } catch (e: Exception) {
                _error.value = "Error: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun createTask(taskListId: Int?, title: String) {
        val tId = taskListId ?: 0
        val exists = _tasks.value.any { it.title.trim().equals(title.trim(), ignoreCase = true) && it.task_list_id == tId }
        if (exists) {
            _error.value = getApplication<Application>().getString(com.lito.planify.R.string.error_task_exists)
            return
        }

        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.createTask(
                    CreateTaskRequest(tId, title)
                )
                if (response.isSuccessful) {
                    notifyWidgetDataChanged()
                    fetchTasks(if(tId > 0) tId else null, force = true)
                } else {
                    _error.value = response.getErrorMessage()
                }
            } catch (e: Exception) {
                _error.value = "Error: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun updateTask(id: Int, taskListId: Int?, title: String) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.updateTask(
                    UpdateTaskRequest(id, title)
                )
                if (response.isSuccessful) {
                    notifyWidgetDataChanged()
                    fetchTasks(taskListId, force = true)
                } else {
                    _error.value = response.getErrorMessage()
                }
            } catch (e: Exception) {
                _error.value = "Error: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }
    
    fun completeTask(id: Int, taskListId: Int?, completed: Boolean) {
        viewModelScope.launch {
            _togglingTasks.value += id
            try {
                val response = RetrofitClient.apiService.completeTask(
                    CompleteTaskRequest(id, completed)
                )
                if (response.isSuccessful) {
                    notifyWidgetDataChanged()
                    fetchTasks(taskListId, force = true)
                } else {
                    _error.value = response.getErrorMessage()
                }
            } catch (e: Exception) {
                _error.value = "Error: ${e.message}"
            } finally {
                _togglingTasks.value -= id
            }
        }
    }

    fun reorderTask(taskId: Int, targetPosition: Int, taskListId: Int?) {
        viewModelScope.launch {
            val previous = _tasks.value
            val reordered = previous.toMutableList().apply {
                val index = indexOfFirst { it.id == taskId }
                if (index < 0) return@apply
                val task = removeAt(index)
                add(targetPosition.coerceIn(0, size), task)
            }
            _tasks.value = reordered

            try {
                val response = RetrofitClient.apiService.orderTask(OrderTaskRequest(taskId, targetPosition))
                if (!response.isSuccessful) {
                    _tasks.value = previous
                    _error.value = response.getErrorMessage()
                } else {
                    notifyWidgetDataChanged()
                    fetchTasks(taskListId = taskListId, force = true)
                }
            } catch (e: Exception) {
                _tasks.value = previous
                _error.value = "No se pudo reordenar la tarea: ${e.message}"
            }
        }
    }

    fun deleteTask(id: Int, taskListId: Int?) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.deleteTask(DeleteRequest(id))
                if (response.isSuccessful) {
                    notifyWidgetDataChanged()
                    fetchTasks(taskListId, force = true)
                } else {
                    _error.value = response.getErrorMessage()
                }
            } catch (e: Exception) {
                _error.value = "Error: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun clearError() {
        _error.value = null
    }
}

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

class TaskListViewModel(application: Application) : AndroidViewModel(application) {

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

    private val _taskLists = MutableStateFlow<List<TaskListResponse>>(emptyList())
    val taskLists: StateFlow<List<TaskListResponse>> = _taskLists
    
    private val _taskListUsers = MutableStateFlow<List<TaskListUserResponse>>(emptyList())
    val taskListUsers: StateFlow<List<TaskListUserResponse>> = _taskListUsers

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    fun fetchTaskListUsers(taskListId: Int) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.getTaskListUsers(taskListId)
                if (response.isSuccessful) {
                    _taskListUsers.value = response.body() ?: emptyList()
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

    fun removeTaskListUser(taskListId: Int, userId: Int) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.removeTaskListUser(DeleteTaskListUserRequest(taskListId, userId))
                if (response.isSuccessful) {
                    fetchTaskListUsers(taskListId)
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

    private var hasFetchedTaskLists = false

    fun fetchTaskLists(force: Boolean = false) {
        if (!force && hasFetchedTaskLists && _taskLists.value.isNotEmpty()) return

        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.getTaskLists()
                if (response.isSuccessful) {
                    _taskLists.value = response.body() ?: emptyList()
                    hasFetchedTaskLists = true
                    notifyWidgetDataChanged()
                } else {
                    _error.value = response.getErrorMessage()
                }
            } catch (e: Exception) {
                _error.value = "Network error: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun createTaskList(name: String, color: String? = null, sortOrder: String? = null, widget: Boolean? = true, onSuccess: (Int, String) -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.createTaskList(CreateTaskListRequest(name, color, sortOrder, widget))
                if (response.isSuccessful && response.body() != null) {
                    val newList = response.body()!!
                    fetchTaskLists(force = true)
                    notifyWidgetDataChanged()
                    onSuccess(newList.id, newList.name)
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

    fun addTaskListUser(taskListId: Int, email: String) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.createTaskListUser(CreateTaskListUserRequest(taskListId, email))
                if (response.isSuccessful) {
                    fetchTaskListUsers(taskListId)
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

    fun updateTaskList(id: Int, name: String, color: String, sortOrder: String, widget: Boolean? = true, onSuccess: (() -> Unit)? = null) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.updateTaskList(UpdateTaskListRequest(id, name, color, sortOrder, widget))
                if (response.isSuccessful) {
                    fetchTaskLists(force = true)
                    notifyWidgetDataChanged()
                    onSuccess?.invoke()
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

    fun deleteTaskList(id: Int, onSuccess: (() -> Unit)? = null) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.deleteTaskList(com.lito.planify.data.api.DeleteRequest(id))
                if (response.isSuccessful) {
                    fetchTaskLists(force = true)
                    notifyWidgetDataChanged()
                    onSuccess?.invoke()
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

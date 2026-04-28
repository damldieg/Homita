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

class CalendarViewModel(application: Application) : AndroidViewModel(application) {

    private fun notifyWidgetDataChanged() {
        val app = getApplication<Application>()
        val clearIntent = Intent("com.lito.planify.widget.ACTION_CLEAR_CACHE")
        clearIntent.component = ComponentName(app, com.lito.planify.widget.CalendarWidgetProvider::class.java)
        app.sendBroadcast(clearIntent)
        
        val appWidgetManager = AppWidgetManager.getInstance(app)
        val componentName = ComponentName(app, com.lito.planify.widget.CalendarWidgetProvider::class.java)
        val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
        appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetIds, com.lito.planify.R.id.widget_event_list)
    }

    private val _calendars = MutableStateFlow<List<CalendarResponse>>(emptyList())
    val calendars: StateFlow<List<CalendarResponse>> = _calendars
    
    private val _calendarUsers = MutableStateFlow<List<CalendarUserResponse>>(emptyList())
    val calendarUsers: StateFlow<List<CalendarUserResponse>> = _calendarUsers

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    fun fetchCalendarUsers(calendarId: Int) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.getCalendarUsers(calendarId)
                if (response.isSuccessful) {
                    _calendarUsers.value = response.body() ?: emptyList()
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

    fun removeCalendarUser(calendarId: Int, userId: Int) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.removeCalendarUser(DeleteCalendarUserRequest(calendarId, userId))
                if (response.isSuccessful) {
                    fetchCalendarUsers(calendarId)
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

    private var hasFetchedCalendars = false

    fun fetchCalendars(force: Boolean = false) {
        if (!force && hasFetchedCalendars && _calendars.value.isNotEmpty()) return
        
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.getCalendars()
                if (response.isSuccessful) {
                    _calendars.value = response.body() ?: emptyList()
                    hasFetchedCalendars = true
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

    fun createCalendar(name: String, color: String? = null, widget: Boolean? = true, onSuccess: (Int, String) -> Unit) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.createCalendar(CreateCalendarRequest(name, color, widget))
                if (response.isSuccessful && response.body() != null) {
                    val newCal = response.body()!!
                    fetchCalendars(force = true)
                    notifyWidgetDataChanged()
                    onSuccess(newCal.id, newCal.name)
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

    fun addCalendarUser(calendarId: Int, email: String) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.createCalendarUser(CreateCalendarUserRequest(calendarId, email))
                if (response.isSuccessful) {
                    fetchCalendarUsers(calendarId)
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

    fun updateCalendar(id: Int, name: String, color: String, widget: Boolean? = true, onSuccess: (() -> Unit)? = null) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.updateCalendar(UpdateCalendarRequest(id, name, color, widget))
                if (response.isSuccessful) {
                    fetchCalendars(force = true)
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

    fun deleteCalendar(id: Int, onSuccess: (() -> Unit)? = null) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.deleteCalendar(com.lito.planify.data.api.DeleteRequest(id))
                if (response.isSuccessful) {
                    fetchCalendars(force = true)
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

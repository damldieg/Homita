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

class EventViewModel(application: Application) : AndroidViewModel(application) {

    private val _upcomingEvents = MutableStateFlow<List<EventResponse>>(emptyList())
    val upcomingEvents: StateFlow<List<EventResponse>> = _upcomingEvents

    private val _pastEvents = MutableStateFlow<List<EventResponse>>(emptyList())
    val pastEvents: StateFlow<List<EventResponse>> = _pastEvents

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private var lastFetchedId: Int? = -2 

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

    fun fetchEvents(calendarId: Int? = null, search: String? = null, force: Boolean = false) {
        val effectiveId = if (calendarId != null && calendarId > 0) calendarId else null
        val currentIdFlag = effectiveId ?: 0
        
        if (!force && currentIdFlag == lastFetchedId && search == null) return

        lastFetchedId = currentIdFlag

        viewModelScope.launch {
            _isLoading.value = true
            try {
                // Ajustamos System.currentTimeMillis() que es UTC, a la hora local para que el backend (que asume que enviamos UTC pero el timestamp en DB es texto local) lo entienda
                val nowMillis = System.currentTimeMillis()
                val offset = java.util.TimeZone.getDefault().getOffset(nowMillis)
                val localNowSeconds = ((nowMillis + offset) / 1000).toString()
                
                // Fetch upcoming events
                val upcomingResponse = RetrofitClient.apiService.getEvents(effectiveId, search, startDate = localNowSeconds)
                if (upcomingResponse.isSuccessful) {
                    val events = upcomingResponse.body() ?: emptyList()
                    _upcomingEvents.value = events
                    events.forEach { event ->
                        com.lito.planify.util.AlarmHelper.scheduleAlarm(getApplication(), event)
                    }
                } else {
                    _error.value = upcomingResponse.getErrorMessage()
                }

                // Fetch past events
                val pastResponse = RetrofitClient.apiService.getEvents(effectiveId, search, endDate = localNowSeconds, orderMode = "DESC")
                if (pastResponse.isSuccessful) {
                    _pastEvents.value = pastResponse.body() ?: emptyList()
                } else {
                    if (_error.value == null) _error.value = pastResponse.getErrorMessage()
                }
            } catch (e: Exception) {
                _error.value = "Error: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    fun createEvent(calendarId: Int, title: String, dateAt: String, text: String?, alarm: Int? = null) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.createEvent(
                    CreateEventRequest(calendarId, text, title, dateAt, alarm)
                )
                if (response.isSuccessful) {
                    response.body()?.let { com.lito.planify.util.AlarmHelper.scheduleAlarm(getApplication(), it) }
                    notifyWidgetDataChanged()
                    fetchEvents(calendarId, force = true)
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

    fun updateEvent(id: Int, calendarId: Int, title: String, dateAt: String, alarm: Int? = null) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.updateEvent(
                    UpdateEventRequest(id, title, dateAt, alarm)
                )
                if (response.isSuccessful) {
                    response.body()?.let { com.lito.planify.util.AlarmHelper.scheduleAlarm(getApplication(), it) }
                    notifyWidgetDataChanged()
                    fetchEvents(calendarId, force = true)
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

    fun setEventAlarm(id: Int, calendarId: Int, alarm: Int?) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.setEventAlarm(
                    SetEventAlarmRequest(id, alarm)
                )
                if (response.isSuccessful) {
                    response.body()?.let { com.lito.planify.util.AlarmHelper.scheduleAlarm(getApplication(), it) }
                    notifyWidgetDataChanged()
                    fetchEvents(calendarId, force = true)
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

    fun deleteEvent(id: Int, calendarId: Int) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.deleteEvent(DeleteRequest(id))
                if (response.isSuccessful) {
                    com.lito.planify.util.AlarmHelper.cancelAlarm(getApplication(), id)
                    notifyWidgetDataChanged()
                    fetchEvents(calendarId, force = true)
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

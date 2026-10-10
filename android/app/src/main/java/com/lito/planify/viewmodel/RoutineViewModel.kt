package com.lito.planify.viewmodel

import android.app.Application
import android.content.Intent
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.lito.planify.data.api.*
import com.lito.planify.data.api.util.NetworkUtils.getErrorMessage
import com.lito.planify.util.AlarmHelper
import com.lito.planify.widget.RoutineWidgetProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.isActive
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class RoutineViewModel(application: Application) : AndroidViewModel(application) {
    private val _routines = MutableStateFlow<List<RoutineResponse>>(emptyList())
    val routines: StateFlow<List<RoutineResponse>> = _routines
    private val _sessions = MutableStateFlow<List<EventResponse>>(emptyList())
    val sessions: StateFlow<List<EventResponse>> = _sessions
    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading
    private val _isSaving = MutableStateFlow(false)
    val isSaving: StateFlow<Boolean> = _isSaving
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error
    private var sessionVersion = 0
    private var readVersion = 0

    fun reset() {
        sessionVersion++
        viewModelScope.coroutineContext.cancelChildren()
        _routines.value = emptyList()
        _sessions.value = emptyList()
        _error.value = null
        _isLoading.value = false
        _isSaving.value = false
    }

    fun fetchRoutines() {
        if (_isSaving.value) return
        val version = sessionVersion
        val read = ++readVersion
        viewModelScope.launch {
            _isLoading.value = true
            try {
                loadRoutines(version, read)
                refreshAlarmsAndWidget()
            } catch (e: Exception) {
                if (version == sessionVersion && read == readVersion && e !is CancellationException) _error.value = "Error: ${e.message}"
            } finally {
                if (version == sessionVersion && read == readVersion) _isLoading.value = false
            }
        }
    }

    private suspend fun loadRoutines(version: Int, read: Int) {
        val response = RetrofitClient.apiService.getRoutines()
        if (version != sessionVersion || read != readVersion) throw CancellationException("Request superseded")
        if (!response.isSuccessful) throw IllegalStateException(response.getErrorMessage())
        // Sesiones desde el inicio del mes para la vista mensual y la próxima sesión de cada rutina.
        val monthStart = java.time.YearMonth.now().atDay(1).atStartOfDay().toEpochSecond(java.time.ZoneOffset.UTC).toString()
        val sessionsResponse = RetrofitClient.apiService.getEvents(startDate = monthStart, routine = true)
        if (version != sessionVersion || read != readVersion) throw CancellationException("Request superseded")
        if (!sessionsResponse.isSuccessful) throw IllegalStateException(sessionsResponse.getErrorMessage())
        _routines.value = response.body() ?: emptyList()
        _sessions.value = sessionsResponse.body() ?: emptyList()
    }

    fun saveRoutine(initial: RoutineResponse?, request: CreateRoutineRequest) {
        mutate {
            if (initial == null) {
                val response = RetrofitClient.apiService.createRoutine(request)
                if (!response.isSuccessful) throw IllegalStateException(response.getErrorMessage())
            } else {
                val response = RetrofitClient.apiService.updateRoutine(
                    UpdateRoutineRequest(initial.id, request.title, request.days, request.time, request.start_date, request.end_date, request.active)
                )
                if (!response.isSuccessful) throw IllegalStateException(response.getErrorMessage())
                cancelRoutineAlarms(initial.id)
                if (request.alarm != initial.alarm) {
                    val alarmResponse = RetrofitClient.apiService.setRoutineAlarm(SetRoutineAlarmRequest(initial.id, request.alarm))
                    if (!alarmResponse.isSuccessful) {
                        throw IllegalStateException("Rutina guardada; no se pudo cambiar el aviso: ${alarmResponse.getErrorMessage()}")
                    }
                }
            }
        }
    }

    fun deleteRoutine(id: Int) {
        mutate {
            val response = RetrofitClient.apiService.deleteRoutine(DeleteRequest(id))
            if (!response.isSuccessful) throw IllegalStateException(response.getErrorMessage())
            cancelRoutineAlarms(id)
        }
    }

    private fun mutate(operation: suspend () -> Unit) {
        if (_isSaving.value) return
        _isSaving.value = true
        readVersion++
        _isLoading.value = false
        _error.value = null
        val version = sessionVersion
        viewModelScope.launch {
            try {
                operation()
                if (version != sessionVersion) throw CancellationException("Session changed")
                loadRoutines(version, ++readVersion)
            } catch (e: Exception) {
                if (version == sessionVersion && e !is CancellationException) _error.value = e.message ?: "No se pudo guardar la rutina"
            } finally {
                if (version == sessionVersion) {
                    if (isActive) refreshAlarmsAndWidget()
                    _isSaving.value = false
                }
            }
        }
    }

    private suspend fun cancelRoutineAlarms(id: Int) = withContext(Dispatchers.IO) {
        AlarmHelper.cancelRoutineAlarms(getApplication(), id)
    }

    private suspend fun refreshAlarmsAndWidget() {
        val app = getApplication<Application>()
        AlarmHelper.synchronizeAlarms(app)
        app.sendBroadcast(Intent(app, RoutineWidgetProvider::class.java).apply {
            action = "com.lito.planify.widget.ACTION_CLEAR_CACHE"
        })
    }

    fun clearError() { _error.value = null }
}

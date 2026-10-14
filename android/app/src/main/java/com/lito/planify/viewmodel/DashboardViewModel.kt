package com.lito.planify.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lito.planify.data.api.DashboardConfigResponse
import com.lito.planify.data.api.DashboardUpdateRequest
import com.lito.planify.data.api.RetrofitClient
import com.lito.planify.data.api.util.NetworkUtils.getErrorMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import retrofit2.Response

/** Qué calendarios y listas del usuario se muestran en el dashboard de pared. */
class DashboardViewModel : ViewModel() {

    private val _config = MutableStateFlow<DashboardConfigResponse?>(null)
    val config: StateFlow<DashboardConfigResponse?> = _config

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    fun fetchConfig() = run { RetrofitClient.apiService.getDashboard() }

    fun save(calendarIds: List<Int>, taskListIds: List<Int>) =
        run { RetrofitClient.apiService.updateDashboard(DashboardUpdateRequest(calendarIds, taskListIds)) }

    fun reset() {
        _config.value = null
        _error.value = null
    }

    fun clearError() {
        _error.value = null
    }

    private fun run(call: suspend () -> Response<DashboardConfigResponse>) {
        viewModelScope.launch {
            try {
                val response = call()
                if (response.isSuccessful) _config.value = response.body() else _error.value = response.getErrorMessage()
            } catch (e: Exception) {
                _error.value = "Error: ${e.message}"
            }
        }
    }
}

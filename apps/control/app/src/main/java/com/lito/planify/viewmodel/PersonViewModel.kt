package com.lito.planify.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lito.planify.data.api.DeleteRequest
import com.lito.planify.data.api.PersonRequest
import com.lito.planify.data.api.PersonResponse
import com.lito.planify.data.api.RetrofitClient
import com.lito.planify.data.api.util.NetworkUtils.getErrorMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import retrofit2.Response

/** Personas visibles para el usuario: las suyas y las de quienes comparten calendario con él. */
class PersonViewModel : ViewModel() {

    private val _persons = MutableStateFlow<List<PersonResponse>>(emptyList())
    val persons: StateFlow<List<PersonResponse>> = _persons

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    fun fetchPersons() = run { RetrofitClient.apiService.getPersons().also { if (it.isSuccessful) _persons.value = it.body().orEmpty() } }

    fun savePerson(id: Int?, name: String, color: String) = run(refresh = true) {
        val request = PersonRequest(id, name, color)
        if (id == null) RetrofitClient.apiService.createPerson(request) else RetrofitClient.apiService.updatePerson(request)
    }

    fun deletePerson(id: Int) = run(refresh = true) { RetrofitClient.apiService.deletePerson(DeleteRequest(id)) }

    fun reset() {
        _persons.value = emptyList()
        _error.value = null
    }

    fun clearError() {
        _error.value = null
    }

    private fun run(refresh: Boolean = false, call: suspend () -> Response<*>) {
        viewModelScope.launch {
            _isLoading.value = true
            try {
                val response = call()
                if (!response.isSuccessful) _error.value = response.getErrorMessage()
                else if (refresh) fetchPersons()
            } catch (e: Exception) {
                _error.value = "Error: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }
}

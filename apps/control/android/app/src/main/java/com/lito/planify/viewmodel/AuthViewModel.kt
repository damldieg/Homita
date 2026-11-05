package com.lito.planify.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.lito.planify.data.api.ConfigResponse
import com.lito.planify.data.api.RetrofitClient
import com.lito.planify.data.api.util.NetworkUtils.getErrorMessage
import com.lito.planify.data.local.SessionManager
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch

class AuthViewModel(private val sessionManager: SessionManager) : ViewModel() {

    private val _config = MutableStateFlow<ConfigResponse?>(null)
    val config: StateFlow<ConfigResponse?> = _config

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading

    init {
        fetchConfig()
    }

    private fun fetchConfig() {
        viewModelScope.launch {
            try {
                val response = RetrofitClient.apiService.getConfig()
                if (response.isSuccessful) {
                    _config.value = response.body()
                }
            } catch (e: Exception) {
                _error.value = "Failed to load config: ${e.message}"
            }
        }
    }

    fun login(email: String, password: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _error.value = null
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.authenticate(com.lito.planify.data.api.AuthRequest(email, password))
                if (response.isSuccessful && response.body() != null) {
                    val user = response.body()!!
                    val validToken = user.token ?: sessionManager.authTokenFlow.firstOrNull() ?: ""
                    sessionManager.saveSession(validToken, user.name, user.email)
                    RetrofitClient.setToken(validToken)
                    onSuccess()
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

    fun register(name: String, email: String, password: String, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _error.value = null
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.register(com.lito.planify.data.api.RegisterRequest(name, email, password))
                if (response.isSuccessful && response.body() != null) {
                    val user = response.body()!!
                    val validToken = user.token ?: sessionManager.authTokenFlow.firstOrNull() ?: ""
                    sessionManager.saveSession(validToken, user.name, user.email)
                    RetrofitClient.setToken(validToken)
                    onSuccess()
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

    fun updateProfile(name: String, email: String, password: String?, onSuccess: () -> Unit) {
        viewModelScope.launch {
            _error.value = null
            _isLoading.value = true
            try {
                val response = RetrofitClient.apiService.updateProfile(com.lito.planify.data.api.UpdateProfileRequest(name, email, password))
                if (response.isSuccessful && response.body() != null) {
                    val user = response.body()!!
                    // Preserve existing token if server hides it in response
                    val validToken = user.token ?: sessionManager.authTokenFlow.firstOrNull() ?: ""
                    sessionManager.saveSession(validToken, user.name, user.email)
                    onSuccess()
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

    fun logout(onSuccess: () -> Unit) {
        viewModelScope.launch {
            sessionManager.clearSession()
            RetrofitClient.setToken(null)
            onSuccess()
        }
    }

    fun clearError() {
        _error.value = null
    }
}

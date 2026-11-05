package com.lito.planify.data.api.util

import com.google.gson.Gson
import retrofit2.Response

object NetworkUtils {
    fun <T> Response<T>.getErrorMessage(): String {
        return try {
            val errorBody = this.errorBody()?.string()
            val map = Gson().fromJson(errorBody, Map::class.java)
            map["error"]?.toString() ?: "Unknown error"
        } catch (e: Exception) {
            "An error occurred"
        }
    }
}

package com.dld.homita.dashboard.data

import com.dld.homita.dashboard.BuildConfig
import okhttp3.OkHttpClient
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.Body
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.POST
import retrofit2.http.Query
import retrofit2.http.Url
import java.util.concurrent.TimeUnit

/** Homita (solo lectura: autenticación y listados del dashboard) y Open-Meteo. */
interface Api {
    @POST("user/auth")
    suspend fun auth(@Body request: AuthRequest): Response<UserResponse>

    /** Renueva el JWT con el refresh_token guardado. 401 = el refresh_token ya no vale: hay que volver a entrar. */
    @POST("user/refresh")
    suspend fun refresh(@Body request: RefreshRequest): Response<SessionResponse>

    /**
     * `start_date`/`end_date`: hora local expresada como segundos epoch en UTC, igual que la app. Sin `end_date`
     * (null) no hay límite: todos los eventos desde `start_date`.
     */
    @GET("event")
    suspend fun events(
        @Header("Authorization") auth: String,
        @Query("start_date") start: Long,
        @Query("end_date") end: Long?,
        @Query("routine") routine: Boolean,
        @Query("timezone") timezone: String,
        @Query("dashboard") dashboard: Boolean = true
    ): Response<List<Event>>

    @GET("task")
    suspend fun tasks(@Header("Authorization") auth: String, @Query("dashboard") dashboard: Boolean = true): Response<List<Task>>

    /** Menú de hoy del hogar del marco: sin `X-Home-Id` (el servidor usa el hogar por defecto de la cuenta). */
    @GET("meal/today")
    suspend fun mealsToday(@Header("Authorization") auth: String): Response<MealsToday>

    @GET
    suspend fun forecast(@Url url: String): Response<Forecast>

    @GET
    suspend fun geocode(@Url url: String): Response<GeoResponse>

    companion object {
        val client: Api by lazy {
            val http = OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .build()
            Retrofit.Builder()
                .baseUrl(BuildConfig.BASE_URL)
                .client(http)
                .addConverterFactory(GsonConverterFactory.create())
                .build()
                .create(Api::class.java)
        }

        /** Ocho días (Q1: la segunda página de 8 a 14 se quita) y la sensación térmica, actual y por horas. */
        fun forecastUrl(location: Location) = "https://api.open-meteo.com/v1/forecast" +
            "?latitude=${location.latitude}&longitude=${location.longitude}&timezone=auto&past_days=1&forecast_days=8" +
            "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day,apparent_temperature" +
            "&hourly=temperature_2m,precipitation_probability,precipitation,weather_code,is_day,apparent_temperature" +
            "&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,sunrise,sunset"

        fun geocodeUrl(query: String) = "https://geocoding-api.open-meteo.com/v1/search?count=8&language=es&format=json&name=" +
            java.net.URLEncoder.encode(query, "UTF-8")
    }
}

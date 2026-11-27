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
import java.util.concurrent.TimeUnit

/** Código de vinculación (`POST /home/display/link-start`): el código se muestra; el secreto de sondeo no. */
data class DisplayLinkStart(val code: String, val poll_secret: String, val expires_at: String)

data class DisplayPollRequest(val poll_secret: String)

/** Sondeo (`POST /home/display/link-poll`): pending, expired o ready con la sesión de la pantalla. */
data class DisplayPoll(
    val status: String,
    val token: String? = null,
    val refresh_token: String? = null,
    val display: DisplayRef? = null
)

data class DisplayRef(val id: Int, val home_id: Int, val name: String)

/** Configuración de la pantalla (`GET /display/config`): la que manda el hogar desde el móvil. */
data class DisplayConfig(
    val id: Int,
    val home_id: Int,
    val name: String,
    val settings: DisplaySettings? = null,
    val calendar_ids: List<Int>? = null,
    val task_list_ids: List<Int>? = null
)

/** Respuesta de `GET /display/update`: si `update` es true, hay una versión nueva para el canal de la pantalla. */
data class UpdateCheck(
    val channel: String,
    val update: Boolean,
    val version_code: Int? = null,
    val version_name: String? = null,
    val sha256: String? = null,
    val size: Long? = null,
    val url: String? = null
)

/** Ajustes de la pantalla. Brillo null = automático; horario y ubicación como en la app. */
data class DisplaySettings(
    val brightness: Double? = null,
    val schedule: Schedule? = null,
    val location: Location? = null
)

/** Endpoints de la pantalla del hogar (dashboard-pantalla-hogar). Vinculación sin sesión; configuración con la suya. */
interface DisplayApi {
    @POST("home/display/link-start")
    suspend fun linkStart(): Response<DisplayLinkStart>

    @POST("home/display/link-poll")
    suspend fun linkPoll(@Body request: DisplayPollRequest): Response<DisplayPoll>

    @GET("display/config")
    suspend fun config(
        @Header("Authorization") auth: String,
        @Header("X-Display-App-Version") appVersion: String? = null,
        @Header("X-Display-App-Name") appName: String? = null,
        @Header("X-Display-Update-Result") updateResult: String? = null
    ): Response<DisplayConfig>

    /** Comprobación de actualización (0051): canal y, si hay versión nueva, la URL firmada del APK. */
    @GET("display/update")
    suspend fun update(
        @Header("Authorization") auth: String,
        @Header("X-Display-App-Version") appVersion: String? = null,
        @Header("X-Display-App-Name") appName: String? = null,
        @Header("X-Display-Update-Result") updateResult: String? = null
    ): Response<UpdateCheck>

    companion object {
        val client: DisplayApi by lazy {
            val http = OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .readTimeout(30, TimeUnit.SECONDS)
                .build()
            Retrofit.Builder()
                .baseUrl(BuildConfig.BASE_URL)
                .client(http)
                .addConverterFactory(GsonConverterFactory.create())
                .build()
                .create(DisplayApi::class.java)
        }
    }
}

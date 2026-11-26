package com.dld.homita.dashboard.data

import com.google.gson.JsonParser
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import retrofit2.Response
import java.io.IOException
import java.util.Base64

/** La sesión no se puede renovar: hay que volver a entrar. La pantalla cierra sesión y muestra el login. */
class SessionExpired : IOException("La sesión ha caducado")

/**
 * Lectura del `exp` del JWT para decidir cuándo renovar. No valida la firma: solo decide si conviene pedir un JWT
 * nuevo; quien valida es el servidor.
 */
object JwtExpiry {
    /** Segundos epoch de caducidad del JWT, o null si no se puede leer (token mal formado o sin `exp`). */
    fun expiresAt(token: String): Long? = try {
        val payload = token.split(".").getOrNull(1) ?: return null
        val json = String(Base64.getUrlDecoder().decode(payload), Charsets.UTF_8)
        JsonParser.parseString(json).asJsonObject.get("exp")?.takeIf { it.isJsonPrimitive }?.asLong
    } catch (e: Exception) {
        null
    }

    /**
     * Renovar si al JWT le quedan menos de [MARGIN_SECONDS] o no se puede leer su caducidad. Un JWT lejano no se
     * toca: la renovación proactiva solo evita que caduque mientras la pantalla está encendida.
     */
    fun needsRenewal(token: String, nowEpochSeconds: Long): Boolean {
        val exp = expiresAt(token) ?: return true
        return exp - nowEpochSeconds < MARGIN_SECONDS
    }

    const val MARGIN_SECONDS = 24 * 3600L
}

/**
 * Renovación de la sesión del dashboard con el refresh_token de GoTrue (`POST /user/refresh`).
 *
 * - [renew] pide un JWT nuevo. Un solo refresco a la vez (mutex): si otra petición ya lo renovó mientras esperábamos
 *   (`failedToken` ya no es el actual), devuelve ese JWT sin volver a pedirlo.
 * - [authorized] ejecuta una petición con el JWT actual; ante un 401 renueva una vez y la repite.
 *
 * Solo un rechazo del servidor (400/401) o la falta de refresh_token cuenta como sesión caducada. Un fallo de red o
 * 5xx deja la sesión como está: la pantalla sigue con su caché y reintenta en el siguiente ciclo.
 */
class Session(
    private val store: TokenStore,
    private val refreshCall: suspend (String) -> Response<SessionResponse>,
    private val nowEpochSeconds: () -> Long = { System.currentTimeMillis() / 1000 },
) {
    sealed interface Outcome {
        data class Renewed(val token: String) : Outcome
        data object Rejected : Outcome
        data object Unavailable : Outcome
    }

    private val mutex = Mutex()

    suspend fun renew(failedToken: String? = null): Outcome = mutex.withLock {
        val current = store.token ?: return@withLock Outcome.Rejected
        if (failedToken != null && current != failedToken) return@withLock Outcome.Renewed(current)
        val refresh = store.refreshToken ?: return@withLock Outcome.Rejected
        try {
            val response = refreshCall(refresh)
            val body = response.body()
            when {
                response.isSuccessful && body?.token != null -> {
                    store.token = body.token
                    // GoTrue rota el refresh_token: el nuevo sustituye al anterior (que ya no vale).
                    store.refreshToken = body.refresh_token ?: refresh
                    Outcome.Renewed(body.token)
                }
                response.code() == 400 || response.code() == 401 -> Outcome.Rejected
                else -> Outcome.Unavailable
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Outcome.Unavailable
        }
    }

    /** Si el JWT toca caducar y hay con qué renovarlo. Requiere hora válida (la que lee [nowEpochSeconds]). */
    fun needsProactiveRenewal(): Boolean {
        val token = store.token ?: return false
        if (store.refreshToken == null) return false
        return JwtExpiry.needsRenewal(token, nowEpochSeconds())
    }

    /**
     * Ejecuta [request] con el JWT actual. Si devuelve 401, renueva y repite una vez. Sin sesión renovable devuelve
     * [SessionExpired]; si la renovación no llega, el 401 original (sin cerrar nada).
     */
    suspend fun <T> authorized(request: suspend (token: String) -> Result<T>): Result<T> {
        val token = store.token ?: return Result.failure(SessionExpired())
        val first = request(token)
        if (first.exceptionOrNull()?.let { it is HttpError && it.unauthorized } != true) return first
        return when (val outcome = renew(token)) {
            is Outcome.Renewed -> request(outcome.token)
            Outcome.Rejected -> Result.failure(SessionExpired())
            Outcome.Unavailable -> Result.failure(IOException("No se pudo renovar la sesión"))
        }
    }
}

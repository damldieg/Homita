package com.dld.homita.dashboard.data

import java.time.LocalDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** Estado de la vinculación de la pantalla con un hogar (dashboard-pantalla-hogar). */
sealed interface PairingState {
    /** Sin código todavía (o caducado): se pide uno nuevo. */
    data object Idle : PairingState

    /** Código a la vista; se sondea cada pocos segundos hasta que el móvil lo confirme o caduque. */
    data class Waiting(val code: String, val secret: String, val expiresAtMillis: Long) : PairingState

    /** Vinculada: la sesión de la pantalla y el hogar al que pertenece. */
    data class Linked(val token: String, val refreshToken: String?, val displayId: Int, val homeId: Int) : PairingState

    /** No se pudo pedir el código (sin red o error del servidor): se reintenta. */
    data object Failed : PairingState
}

/** Las dos llamadas de la vinculación; el ViewModel las conecta con la API. */
interface PairingApi {
    suspend fun linkStart(): Result<DisplayLinkStart>
    suspend fun linkPoll(secret: String): Result<DisplayPoll>
}

/**
 * Máquina de estados de la vinculación. Lógica pura: sin Android ni red propia, para poder probarla.
 * Un fallo de red al sondear no cambia el estado (se sigue esperando); un 404 del sondeo (secreto desconocido o ya
 * entregado) vuelve a Idle para pedir otro código.
 */
class Pairing(private val api: PairingApi, private val nowMillis: () -> Long = System::currentTimeMillis) {
    suspend fun start(): PairingState = api.linkStart().fold(
        onSuccess = { PairingState.Waiting(it.code, it.poll_secret, expiresAt(it.expires_at)) },
        onFailure = { PairingState.Failed }
    )

    suspend fun poll(waiting: PairingState.Waiting): PairingState {
        if (nowMillis() >= waiting.expiresAtMillis) return PairingState.Idle
        return api.linkPoll(waiting.secret).fold(
            onSuccess = { poll ->
                when (poll.status) {
                    "ready" -> {
                        val display = poll.display
                        val token = poll.token
                        if (display == null || token == null) PairingState.Failed
                        else PairingState.Linked(token, poll.refresh_token, display.id, display.home_id)
                    }
                    "expired" -> PairingState.Idle
                    else -> waiting
                }
            },
            onFailure = { error -> if (error is HttpError && error.code == 404) PairingState.Idle else waiting }
        )
    }

    companion object {
        private val SQL_TIME = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")

        /** Caducidad del código (`yyyy-MM-dd HH:mm:ss` en UTC) en milisegundos epoch. */
        fun expiresAt(raw: String): Long = LocalDateTime.parse(raw, SQL_TIME).toInstant(ZoneOffset.UTC).toEpochMilli()
    }
}

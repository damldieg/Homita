package com.dld.homita.dashboard.data

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

/** Vinculación de la pantalla (dashboard-pantalla-hogar): máquina de estados con la API falsa. */
class PairingTest {
    /** API falsa: los sondeos salen de una cola; un fallo de red se simula con un IOException. */
    private class FakeApi(private val polls: ArrayDeque<Result<DisplayPoll>>, private val start: Result<DisplayLinkStart>) : PairingApi {
        override suspend fun linkStart(): Result<DisplayLinkStart> = start
        override suspend fun linkPoll(secret: String): Result<DisplayPoll> = polls.removeFirst()
    }

    private val code = DisplayLinkStart("123456", "secreto", "2026-11-27 12:10:00")
    private val expiresMillis = Pairing.expiresAt("2026-11-27 12:10:00")

    @Test
    fun `el codigo caduca a la hora indicada en UTC`() {
        assertEquals(1_795_781_400_000L, expiresMillis)
    }

    @Test
    fun `pendiente, luego listo con la sesion y el hogar`() = runBlocking {
        val api = FakeApi(
            ArrayDeque(listOf(
                Result.success(DisplayPoll("pending")),
                Result.success(DisplayPoll("ready", "jwt", "rt", DisplayRef(9, 1, "Salón"))),
            )),
            Result.success(code),
        )
        val pairing = Pairing(api, nowMillis = { expiresMillis - 60_000 })
        val waiting = pairing.start() as PairingState.Waiting
        assertEquals("123456", waiting.code)
        assertEquals(waiting, pairing.poll(waiting))
        assertEquals(PairingState.Linked("jwt", "rt", 9, 1), pairing.poll(waiting))
    }

    @Test
    fun `sin red al sondear se sigue esperando`() = runBlocking {
        val api = FakeApi(ArrayDeque(listOf(Result.failure(IOException("sin red")))), Result.success(code))
        val pairing = Pairing(api, nowMillis = { expiresMillis - 60_000 })
        val waiting = pairing.start() as PairingState.Waiting
        assertEquals(waiting, pairing.poll(waiting))
    }

    @Test
    fun `404 del sondeo pide otro codigo y caducado tambien`() = runBlocking {
        val notFound = HttpError(404)
        val api = FakeApi(ArrayDeque(listOf(Result.failure(notFound))), Result.success(code))
        val pairing = Pairing(api, nowMillis = { expiresMillis - 60_000 })
        val waiting = pairing.start() as PairingState.Waiting
        assertEquals(PairingState.Idle, pairing.poll(waiting))

        val expiredApi = FakeApi(ArrayDeque(), Result.success(code))
        val late = Pairing(expiredApi, nowMillis = { expiresMillis + 1 })
        assertEquals(PairingState.Idle, late.poll(waiting))
    }

    @Test
    fun `el servidor dice expired → Idle`() = runBlocking {
        val api = FakeApi(ArrayDeque(listOf(Result.success(DisplayPoll("expired")))), Result.success(code))
        val pairing = Pairing(api, nowMillis = { expiresMillis - 60_000 })
        val waiting = pairing.start() as PairingState.Waiting
        assertEquals(PairingState.Idle, pairing.poll(waiting))
    }

    @Test
    fun `sin codigo por red o servidor → Failed`() = runBlocking {
        val api = FakeApi(ArrayDeque(), Result.failure(IOException("caído")))
        assertTrue(Pairing(api).start() is PairingState.Failed)
    }

    @Test
    fun `listo sin sesion o sin hogar no se da por vinculado`() = runBlocking {
        val api = FakeApi(ArrayDeque(listOf(Result.success(DisplayPoll("ready")))), Result.success(code))
        val pairing = Pairing(api, nowMillis = { expiresMillis - 60_000 })
        val waiting = pairing.start() as PairingState.Waiting
        assertEquals(PairingState.Failed, pairing.poll(waiting))
    }
}

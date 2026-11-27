package com.dld.homita.dashboard.data

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import retrofit2.Response
import java.io.IOException
import java.util.Base64

/** Renovación de sesión (dashboard-sesion): decisión de renovar y reintento tras 401. Sin red ni Android. */
class SessionTest {
    private val now = 1_800_000_000L

    /** Un JWT de prueba con el `exp` dado (la firma no se mira). */
    private fun jwt(exp: Long?): String {
        val enc = Base64.getUrlEncoder().withoutPadding()
        val header = enc.encodeToString("""{"alg":"HS256"}""".toByteArray())
        val payload = enc.encodeToString((if (exp == null) """{"sub":"u"}""" else """{"sub":"u","exp":$exp}""").toByteArray())
        return "$header.$payload.firma"
    }

    private class FakeStore(override var token: String?, override var refreshToken: String?) : TokenStore

    private fun session(
        store: TokenStore,
        refresh: suspend (String) -> Response<SessionResponse>,
    ) = Session(store, refresh, nowEpochSeconds = { now })

    private fun ok(token: String, refresh: String) = Response.success(SessionResponse(token, refresh))
    private fun status(code: Int) = Response.error<SessionResponse>(code, "".toResponseBody())

    // --- Decisión de renovar ---

    @Test
    fun `JWT lejano no se renueva`() {
        assertFalse(JwtExpiry.needsRenewal(jwt(now + 6 * 24 * 3600), now))
    }

    @Test
    fun `JWT a menos de 24 horas se renueva`() {
        assertTrue(JwtExpiry.needsRenewal(jwt(now + 3600), now))
    }

    @Test
    fun `JWT caducado se renueva`() {
        assertTrue(JwtExpiry.needsRenewal(jwt(now - 60), now))
    }

    @Test
    fun `JWT sin exp o mal formado se renueva`() {
        assertTrue(JwtExpiry.needsRenewal(jwt(null), now))
        assertTrue(JwtExpiry.needsRenewal("no-es-un-jwt", now))
    }

    @Test
    fun `renovación proactiva exige refresh_token y JWT próximo a caducar`() {
        val near = jwt(now + 3600)
        assertTrue(session(FakeStore(near, "rt")) { error("no se llama") }.needsProactiveRenewal())
        assertFalse(session(FakeStore(near, null)) { error("no se llama") }.needsProactiveRenewal())
        assertFalse(session(FakeStore(jwt(now + 6 * 24 * 3600), "rt")) { error("no se llama") }.needsProactiveRenewal())
    }

    // --- Renovación y reintento ---

    @Test
    fun `401 renueva una vez, repite la petición y guarda el refresh_token nuevo`() = runBlocking {
        val store = FakeStore("viejo", "rt-1")
        var refreshCalls = 0
        val s = session(store) { refresh ->
            refreshCalls++
            assertEquals("rt-1", refresh)
            ok("nuevo", "rt-2")
        }
        val tokensUsados = mutableListOf<String>()
        val result = s.authorized { token ->
            tokensUsados += token
            if (token == "viejo") Result.failure(HttpError(401)) else Result.success("datos")
        }
        assertEquals("datos", result.getOrThrow())
        assertEquals(listOf("viejo", "nuevo"), tokensUsados)
        assertEquals(1, refreshCalls)
        assertEquals("nuevo", store.token)
        assertEquals("rt-2", store.refreshToken)
    }

    @Test
    fun `refresh_token rechazado cuenta como sesión caducada`() = runBlocking {
        val store = FakeStore("viejo", "rt-1")
        val result = session(store) { status(401) }.authorized { Result.failure<String>(HttpError(401)) }
        assertTrue(result.exceptionOrNull() is SessionExpired)
        assertEquals("viejo", store.token)
    }

    @Test
    fun `sin refresh_token guardado el 401 es sesión caducada sin llamar al servidor`() = runBlocking {
        var calls = 0
        val result = session(FakeStore("viejo", null)) { calls++; ok("x", "y") }
            .authorized { Result.failure<String>(HttpError(401)) }
        assertTrue(result.exceptionOrNull() is SessionExpired)
        assertEquals(0, calls)
    }

    @Test
    fun `error de red en la renovación no cierra la sesión`() = runBlocking {
        val store = FakeStore("viejo", "rt-1")
        val s = session(store) { throw IOException("sin red") }
        val result = s.authorized { Result.failure<String>(HttpError(401)) }
        val error = result.exceptionOrNull()
        assertFalse(error is SessionExpired)
        assertFalse(error!!.isUnauthorized)
        assertEquals("viejo", store.token)
        assertEquals("rt-1", store.refreshToken)
    }

    @Test
    fun `5xx en la renovación tampoco cierra la sesión`() = runBlocking {
        val store = FakeStore("viejo", "rt-1")
        val outcome = session(store) { status(503) }.renew("viejo")
        assertTrue(outcome is Session.Outcome.Unavailable)
        assertEquals("viejo", store.token)
    }

    @Test
    fun `un refresco ya hecho por otra petición no se vuelve a pedir`() = runBlocking {
        val store = FakeStore("viejo", "rt-1")
        var calls = 0
        val s = session(store) { calls++; ok("nuevo", "rt-2") }
        assertTrue(s.renew("viejo") is Session.Outcome.Renewed)
        // Otra petición que recibió el 401 del JWT viejo llega después: usa el nuevo sin pedir otro refresco.
        val outcome = s.renew("viejo")
        assertEquals("nuevo", (outcome as Session.Outcome.Renewed).token)
        assertEquals(1, calls)
    }

    @Test
    fun `refrescos concurrentes con el mismo JWT caducado piden un solo refresco`() = runBlocking {
        val store = FakeStore("viejo", "rt-1")
        var calls = 0
        val gate = CompletableDeferred<Unit>()
        val s = session(store) { calls++; gate.await(); ok("nuevo", "rt-2") }
        val a = async { s.renew("viejo") }
        val b = async { s.renew("viejo") }
        gate.complete(Unit)
        assertTrue(a.await() is Session.Outcome.Renewed)
        assertTrue(b.await() is Session.Outcome.Renewed)
        assertEquals(1, calls)
    }

    @Test
    fun `un cierre de sesión durante el refresco no reescribe la sesión`() = runBlocking {
        val store = FakeStore("viejo", "rt-1")
        val started = CompletableDeferred<Unit>()
        val gate = CompletableDeferred<Unit>()
        val s = session(store) { started.complete(Unit); gate.await(); ok("nuevo", "rt-2") }
        val job = async { s.renew() }
        started.await()
        store.token = null
        store.refreshToken = null
        gate.complete(Unit)
        assertTrue(job.await() is Session.Outcome.Rejected)
        assertNull(store.token)
        assertNull(store.refreshToken)
    }

    @Test
    fun `un 401 tras renovar no se trata como sesión caducada`() = runBlocking {
        val store = FakeStore("viejo", "rt-1")
        val s = session(store) { ok("nuevo", "rt-2") }
        val result = s.authorized { Result.failure<Unit>(HttpError(401)) }
        assertTrue(result.isFailure)
        assertFalse(result.exceptionOrNull() is SessionExpired)
        assertFalse(result.exceptionOrNull()?.let { it is HttpError && it.unauthorized } == true)
    }
}

package com.dld.homita.dashboard.update

import com.dld.homita.dashboard.data.HttpError
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Request
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/** Descarga reanudable del APK (dashboard-actualizacion-remota): Range, 200 frente a 206, 416 y el archivo parcial. Sin red. */
class ApkDownloaderTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val payload = ByteArray(100) { it.toByte() }

    /** Cliente falso: responde [respond] y guarda la cabecera Range de cada petición. */
    private class Fake(val respond: (Request) -> Response) {
        val ranges = mutableListOf<String?>()
        val client = OkHttpClient.Builder().addInterceptor { chain ->
            ranges += chain.request().header("Range")
            respond(chain.request())
        }.build()
    }

    private fun response(request: Request, code: Int, body: ByteArray = ByteArray(0)) = Response.Builder()
        .request(request).protocol(Protocol.HTTP_1_1).code(code).message("")
        .body(body.toResponseBody("application/vnd.android.package-archive".toMediaType())).build()

    @Test
    fun descargaCompletaCuandoNoHayParcial() {
        val fake = Fake { response(it, 200, payload) }
        val part = File(folder.root, "homita-3.apk.part")
        ApkDownloader(fake.client).download("https://x/y.apk", payload.size.toLong(), part)
        assertArrayEquals(payload, part.readBytes())
        assertEquals(listOf<String?>(null), fake.ranges)
    }

    @Test
    fun reanudaConRangeYAnadeSiElServidorRespondeConParcial() {
        val part = File(folder.root, "homita-3.apk.part").apply { writeBytes(payload.copyOfRange(0, 40)) }
        val fake = Fake { response(it, 206, payload.copyOfRange(40, 100)) }
        ApkDownloader(fake.client).download("https://x/y.apk", payload.size.toLong(), part)
        assertEquals(listOf("bytes=40-"), fake.ranges)
        assertArrayEquals(payload, part.readBytes())
    }

    @Test
    fun siElServidorIgnoraElRangoSeReescribeDesdeCero() {
        val part = File(folder.root, "homita-3.apk.part").apply { writeBytes(payload.copyOfRange(0, 40)) }
        val fake = Fake { response(it, 200, payload) }
        ApkDownloader(fake.client).download("https://x/y.apk", payload.size.toLong(), part)
        assertArrayEquals(payload, part.readBytes())
    }

    @Test
    fun un416BorraElParcialYFalla() {
        val part = File(folder.root, "homita-3.apk.part").apply { writeBytes(payload.copyOfRange(0, 40)) }
        val fake = Fake { response(it, 416) }
        assertThrows(java.io.IOException::class.java) {
            ApkDownloader(fake.client).download("https://x/y.apk", payload.size.toLong(), part)
        }
        assertFalse(part.exists())
    }

    @Test
    fun unErrorHttpConservaElParcialParaReanudar() {
        val part = File(folder.root, "homita-3.apk.part").apply { writeBytes(payload.copyOfRange(0, 40)) }
        val fake = Fake { response(it, 403) }
        val error = assertThrows(HttpError::class.java) {
            ApkDownloader(fake.client).download("https://x/y.apk", payload.size.toLong(), part)
        }
        assertEquals(403, error.code)
        assertTrue(part.exists())
        assertEquals(40L, part.length())
    }

    @Test
    fun unParcialMayorQueElTamanoSeReinicia() {
        val part = File(folder.root, "homita-3.apk.part").apply { writeBytes(ByteArray(150)) }
        val fake = Fake { response(it, 200, payload) }
        ApkDownloader(fake.client).download("https://x/y.apk", payload.size.toLong(), part)
        assertEquals(listOf<String?>(null), fake.ranges)
        assertArrayEquals(payload, part.readBytes())
    }
}

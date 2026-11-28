package com.dld.homita.dashboard.data

import com.google.gson.Gson
import com.google.gson.reflect.TypeToken
import java.io.File

/**
 * Un marcado de la compra pendiente de enviar (dashboard-menu-compra, fase B). [requestId] es la clave de cliente que
 * hace el reenvío idempotente en el servidor (0055).
 */
data class ShoppingCheck(val itemId: Long, val checked: Boolean, val requestId: String, val createdAt: Long)

/** Cuerpo de `PATCH /shopping/item/check` (0055): solo marcar o desmarcar (pending ↔ checked). */
data class ShoppingCheckRequest(val id: Long, val state: String, val client_request_id: String)

/**
 * Cola en disco de los marcados que salieron de la ventana de «Deshacer» y aún no se han enviado. Sobrevive a reinicios y
 * a la falta de red; se vacía en orden de llegada. Un fallo de escritura no rompe la pantalla.
 */
class ShoppingCheckQueue(private val file: File) {
    private val gson = Gson()
    private val listType = object : TypeToken<List<ShoppingCheck>>() {}.type

    @Synchronized
    fun all(): List<ShoppingCheck> = runCatching {
        if (file.exists()) gson.fromJson<List<ShoppingCheck>>(file.readText(), listType).orEmpty() else emptyList()
    }.getOrDefault(emptyList())

    @Synchronized
    fun add(check: ShoppingCheck) = write(all() + check)

    @Synchronized
    fun remove(requestId: String) = write(all().filterNot { it.requestId == requestId })

    private fun write(items: List<ShoppingCheck>) {
        runCatching {
            file.parentFile?.mkdirs()
            val tmp = File(file.parentFile, file.name + ".tmp")
            tmp.writeText(gson.toJson(items))
            tmp.renameTo(file)
        }
    }
}

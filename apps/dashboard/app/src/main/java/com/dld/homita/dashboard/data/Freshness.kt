package com.dld.homita.dashboard.data

/**
 * Estado de los datos en la barra (U7): «Actualizado hace 2 h» si la copia tiene más de [STALE_MINUTES] o no hay red.
 * Lógica pura para poder probarla sin Android.
 */
object Freshness {
    const val STALE_MINUTES = 15L

    /**
     * Texto de la barra, o null si todo está al día. [fetchedAt] en epoch ms de la última descarga buena; [online]
     * dice si la última petición funcionó; [connected], si hay red.
     */
    fun label(fetchedAt: Long?, nowMillis: Long, online: Boolean, connected: Boolean): String? {
        val parts = mutableListOf<String>()
        if (!online || !connected) parts += "Sin conexión"
        if (fetchedAt != null) {
            val age = nowMillis - fetchedAt
            if (age >= STALE_MINUTES * 60_000L) parts += "Actualizado hace ${ago(age)}"
        }
        return parts.takeIf { it.isNotEmpty() }?.joinToString(" · ")
    }

    /** «15 min», «2 h», «3 días». */
    fun ago(ageMillis: Long): String {
        val minutes = ageMillis / 60_000L
        return when {
            minutes < 60 -> "$minutes min"
            minutes < 24 * 60 -> "${minutes / 60} h"
            minutes < 2 * 24 * 60 -> "1 día"
            else -> "${minutes / (24 * 60)} días"
        }
    }
}

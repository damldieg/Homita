package com.dld.homita.dashboard.data

import java.math.BigDecimal
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/** Semana del menú (`GET /meal/plan`, 0044-0048): solo lo que la pantalla muestra. `status`: draft | accepted. */
data class MealPlanWeekResponse(
    val week_start: String? = null,
    val status: String? = null,
    val items: List<MealPlanWeekItem>? = null
)

data class MealPlanWeekItem(
    val day: String,
    val slot: String,
    val position: Int = 0,
    val kind: String? = null,
    val title: String? = null
)

/**
 * Perfil del menú, solo los campos que usa la pantalla (`GET /meal/profile`). La respuesta trae alergias, dieta y otros
 * datos de salud: aquí no se declaran, así que nunca llegan a la caché en disco ni a los logs.
 */
data class MealProfileSafe(
    val week_start_day: Int? = null,
    val slots: List<MealProfileSlot>? = null
)

data class MealProfileSlot(
    val slot: String? = null,
    val enabled: Boolean = false
)

/** Compra del hogar (`GET /shopping`, 0044/0046): solo lo que el marco enseña. */
data class ShoppingListResponse(
    val revision: Int = 0,
    val items: List<ShoppingWebItem>? = null
)

data class ShoppingWebItem(
    val id: Long = 0,
    val label: String? = null,
    val quantity: Double? = null,
    val unit: String? = null,
    val section: String? = null,
    val origin: String? = null,
    val state: String? = null,
    val sources: List<ShoppingWebSource>? = null
)

/** Plato que aporta a un artículo de origen menú («para qué plato es»). */
data class ShoppingWebSource(val name: String? = null)

/** Rejilla de la semana: días × franjas. Lo que se ve es lo que hay en el servidor. */
object MealWeekGrid {
    /** Franjas en el orden del día, como MealSlotKind.order de iOS. */
    val SLOT_ORDER = listOf("breakfast", "midmorning", "lunch", "snack", "dinner")

    private val ISO = DateTimeFormatter.ISO_LOCAL_DATE

    /** Inicio de la semana de [date] según el primer día del hogar (1 = lunes … 7 = domingo, como `week_start_day`). */
    fun weekStartOf(date: LocalDate, startDay: Int = 1): LocalDate {
        val start = DayOfWeek.of(startDay.coerceIn(1, 7))
        val back = (date.dayOfWeek.value - start.value + 7) % 7
        return date.minusDays(back.toLong())
    }

    /** Lunes de la semana de [date]. */
    fun mondayOf(date: LocalDate): LocalDate = weekStartOf(date, 1)

    /** Los siete días de la semana que empieza en [start], en orden. */
    fun days(start: LocalDate): List<LocalDate> = (0L..6L).map { start.plusDays(it) }

    /** Franjas que tienen algo en la semana, en el orden del día. */
    fun slots(items: List<MealPlanWeekItem>): List<String> {
        val present = items.map { it.slot }.toSet()
        return SLOT_ORDER.filter { it in present } + present.filterNot { it in SLOT_ORDER }.sorted()
    }

    /** Franjas que se pintan: habilitadas en el perfil (si lo hay) y con alguna casilla en la semana. */
    fun visibleSlots(items: List<MealPlanWeekItem>, enabled: Set<String>?): List<String> {
        val present = items.map { it.slot }.toSet()
        return SLOT_ORDER.filter { it in present && (enabled == null || it in enabled) }
    }

    /** Lo que va en una casilla (varios platos separados por «·»), o null si está vacía. */
    fun cell(items: List<MealPlanWeekItem>, day: LocalDate, slot: String): String? =
        items.filter { it.day == day.format(ISO) && it.slot == slot }
            .sortedBy { it.position }
            .mapNotNull { it.title?.trim()?.takeIf { t -> t.isNotEmpty() } }
            .takeIf { it.isNotEmpty() }
            ?.joinToString(" · ")
}

/** Resumen de la compra: lo que queda, lo comprado y de dónde viene. «Ya lo tenéis» no cuenta como pendiente. */
data class ShoppingSummary(val pending: Int, val done: Int, val skipped: Int, val fromMenu: Int, val manual: Int) {
    val total: Int get() = pending + done
}

/** Secciones de la compra en el orden de la tienda, con su nombre en español (como la app de control). */
object ShoppingSections {
    private val ORDER = listOf(
        "verdura", "fruta", "carne", "embutido", "pescado", "marisco", "lacteos", "huevos", "legumbres",
        "cereales", "panaderia", "despensa", "aceites", "especias", "bebidas", "congelados", "otros"
    )

    fun title(section: String): String = when (section) {
        "verdura" -> "Verdura"
        "fruta" -> "Fruta"
        "carne" -> "Carne"
        "embutido" -> "Embutido"
        "pescado" -> "Pescado"
        "marisco" -> "Marisco"
        "lacteos" -> "Lácteos"
        "huevos" -> "Huevos"
        "legumbres" -> "Legumbres"
        "cereales" -> "Cereales"
        "panaderia" -> "Panadería"
        "despensa" -> "Despensa"
        "aceites" -> "Aceites"
        "especias" -> "Especias"
        "bebidas" -> "Bebidas"
        "congelados" -> "Congelados"
        else -> "Otros"
    }

    /** Un artículo está comprado si su estado es «checked». */
    fun isDone(item: ShoppingWebItem): Boolean = item.state == "checked"

    /** Los que se listan: los «ya lo tengo» solo cuentan en el resumen. */
    fun listed(items: List<ShoppingWebItem>): List<ShoppingWebItem> = items.filter { it.state != "skipped" }

    /** Artículos listados, agrupados por sección en el orden de la tienda; pendientes primero y luego por nombre. */
    fun group(items: List<ShoppingWebItem>): List<Pair<String, List<ShoppingWebItem>>> {
        val bySection = listed(items).groupBy { item -> item.section?.takeIf { it in ORDER } ?: "otros" }
        return ORDER.mapNotNull { section ->
            bySection[section]?.let { section to it.sortedWith(compareBy({ isDone(it) }, { it.label.orEmpty() })) }
        }
    }

    /** Reparte las secciones enteras en [count] columnas, equilibrando las filas (cada sección cuenta una cabecera). */
    fun columns(groups: List<Pair<String, List<ShoppingWebItem>>>, count: Int = 3): List<List<Pair<String, List<ShoppingWebItem>>>> {
        val cols = List(count) { mutableListOf<Pair<String, List<ShoppingWebItem>>>() }
        val rows = IntArray(count)
        groups.forEach { group ->
            val target = rows.indices.minBy { rows[it] }
            cols[target].add(group)
            rows[target] += group.second.size + 1
        }
        return cols
    }

    fun summary(items: List<ShoppingWebItem>): ShoppingSummary {
        val listedItems = listed(items)
        val done = listedItems.count { isDone(it) }
        return ShoppingSummary(
            pending = listedItems.size - done,
            done = done,
            skipped = items.count { it.state == "skipped" },
            fromMenu = listedItems.count { it.origin == "menu" },
            manual = listedItems.count { it.origin != "menu" }
        )
    }

    /** «Para: Lentejas, Ensalada» con los platos distintos de un artículo de menú; null si es a mano. */
    fun forWhom(item: ShoppingWebItem): String? {
        if (item.origin != "menu") return null
        return item.sources.orEmpty().mapNotNull { it.name?.trim()?.takeIf { n -> n.isNotEmpty() } }.distinct()
            .takeIf { it.isNotEmpty() }?.joinToString(", ")
    }

    /** Cantidad legible con coma decimal («0,5 kg», «2 ud»); sin cantidad, null. */
    fun quantity(item: ShoppingWebItem): String? {
        val q = item.quantity ?: return null
        val number = BigDecimal.valueOf(q).stripTrailingZeros().toPlainString().replace('.', ',')
        return listOfNotNull(number, item.unit?.takeIf { it.isNotBlank() }).joinToString(" ")
    }
}

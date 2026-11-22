package com.dld.homita.dashboard.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.FilterAlt
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.dld.homita.dashboard.UiState
import com.dld.homita.dashboard.data.TaskPriority
import com.dld.homita.dashboard.data.TaskPriorityView
import com.dld.homita.dashboard.data.TaskSort
import com.dld.homita.dashboard.ui.theme.Palette
import com.dld.homita.dashboard.ui.theme.Type

/** Cambios de orden y filtro de la pantalla de tareas (0037): los guarda el ViewModel en Store. */
class TaskViewCallbacks(
    val onSort: (TaskSort) -> Unit,
    val onFilter: (TaskPriority?) -> Unit
)

/**
 * Todas las listas del dashboard, una columna por lista (con desplazamiento lateral si no caben). Arriba, el orden
 * (Lista | Prioridad) y el filtro por prioridad; se aplican en cliente sobre lo que hay en caché.
 */
@Composable
fun TasksScreen(state: UiState, callbacks: TaskViewCallbacks) {
    val all = state.content?.tasks.orEmpty()
    val visible = TaskPriorityView.apply(all, state.taskSort, state.taskFilter)
    val lists = visible.groupBy { it.task_list_id }.values.toList()
    ScreenPadding {
        Column(Modifier.fillMaxSize()) {
            TaskViewBar(state.taskSort, state.taskFilter, callbacks)
            if (lists.isEmpty()) {
                if (all.isEmpty() || state.taskFilter == null) {
                    EmptyState(Icons.Outlined.TaskAlt, Palette.Online, "Todo hecho", "No quedan tareas pendientes en las listas del dashboard", Modifier.fillMaxSize(), large = true)
                } else {
                    EmptyState(
                        Icons.Outlined.FilterAlt,
                        priorityColor(state.taskFilter),
                        "Nada con prioridad ${state.taskFilter.label.lowercase()}",
                        "Toca «Todas» para ver el resto de tareas",
                        Modifier.fillMaxSize(),
                        large = true
                    )
                }
                return@Column
            }
            val width = if (lists.size <= 4) null else 480
            Row(
                Modifier.fillMaxSize().then(if (width != null) Modifier.horizontalScroll(rememberScrollState()) else Modifier),
                horizontalArrangement = Arrangement.spacedBy(32.dp)
            ) {
                lists.forEach { tasks ->
                    val first = tasks.first()
                    Panel((if (width != null) Modifier.width(width.dp) else Modifier.weight(1f)).fillMaxHeight()) {
                        CardHeader(first.task_list_name.orEmpty(), Icons.Outlined.Checklist, parseColor(first.task_list_color), count = tasks.size)
                        Column(Modifier.padding(top = 8.dp).fadingScroll(rememberScrollState())) {
                            tasks.forEach { TaskRow(it) }
                        }
                    }
                }
            }
        }
    }
}

/** Barra de la cabecera: orden y filtro con chips táctiles (píxeles nativos, Density(1f)). */
@Composable
private fun TaskViewBar(sort: TaskSort, filter: TaskPriority?, callbacks: TaskViewCallbacks) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().padding(bottom = 24.dp)
    ) {
        Text("ORDEN", style = Type.Label, modifier = Modifier.padding(end = 4.dp))
        TaskSort.entries.forEach { option ->
            Chip(option.label, selected = option == sort, tint = Palette.Ink) { callbacks.onSort(option) }
        }
        Text("PRIORIDAD", style = Type.Label, modifier = Modifier.padding(start = 28.dp, end = 4.dp))
        Chip("Todas", selected = filter == null, tint = Palette.Ink) { callbacks.onFilter(null) }
        TaskPriority.entries.forEach { option ->
            Chip(option.label, selected = option == filter, tint = priorityColor(option)) { callbacks.onFilter(option) }
        }
    }
}

/** Chip seleccionable: relleno con [tint] si está activo; si no, contorno suave. Alto mínimo táctil de 64 px. */
@Composable
private fun Chip(text: String, selected: Boolean, tint: Color, onClick: () -> Unit) {
    Text(
        text,
        style = Type.Small.copy(
            color = if (selected) Color.White else Palette.Ink,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium
        ),
        maxLines = 1,
        modifier = Modifier
            .heightIn(min = 64.dp)
            .background(if (selected) tint else Palette.Card, CircleShape)
            .clickable(onClick = onClick)
            .padding(horizontal = 26.dp, vertical = 16.dp)
    )
}

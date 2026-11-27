package com.dld.homita.dashboard.ui

import androidx.compose.foundation.horizontalScroll
import androidx.compose.runtime.Composable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Checklist
import androidx.compose.material.icons.outlined.TaskAlt
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.dld.homita.dashboard.UiState
import com.dld.homita.dashboard.data.Task
import com.dld.homita.dashboard.data.TaskPriorityView
import com.dld.homita.dashboard.data.isDone
import com.dld.homita.dashboard.ui.theme.Palette

/**
 * Todas las listas del dashboard, una columna por lista (con desplazamiento lateral si no caben). Dentro de cada lista,
 * orden fijo por prioridad (alta, media, baja) y, en cada tarea, sus personas (U8, C5).
 */
@Composable
fun TasksScreen(state: UiState, onToggle: (Task) -> Unit) {
    val all = state.shownContent?.tasks.orEmpty()
    val lists = all.groupBy { it.task_list_id }.values.map { TaskPriorityView.sortWithinList(it) }
    ScreenPadding {
        if (lists.isEmpty()) {
            EmptyState(Icons.Outlined.TaskAlt, Palette.Online, "Todo hecho", "No quedan tareas pendientes en las listas del dashboard", Modifier.fillMaxSize(), large = true)
            return@ScreenPadding
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
                        tasks.forEach { task ->
                            TaskRow(task, done = task.isDone(state.pending[task.id] ?: state.queued[task.id]), onToggle = { onToggle(task) })
                        }
                    }
                }
            }
        }
    }
}

package com.lito.planify.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.PauseCircle
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lito.planify.R
import com.lito.planify.data.api.RoutineResponse
import com.lito.planify.ui.components.*
import com.lito.planify.util.DateTimeUtils
import com.lito.planify.viewmodel.CalendarViewModel
import com.lito.planify.viewmodel.RoutineViewModel
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale

@Composable
fun RoutinesScreen(
    viewModel: RoutineViewModel,
    calendarViewModel: CalendarViewModel
) {
    val routines by viewModel.routines.collectAsState()
    val sessions by viewModel.sessions.collectAsState()
    val calendars by calendarViewModel.calendars.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isSaving by viewModel.isSaving.collectAsState()
    val error by viewModel.error.collectAsState()
    val context = LocalContext.current
    val prefs = remember { context.getSharedPreferences("planify_prefs", android.content.Context.MODE_PRIVATE) }

    var selectedCalendarFilterId by remember {
        val savedId = prefs.getInt("selected_routine_calendar_filter", -1)
        mutableStateOf<Int?>(if (savedId != -1) savedId else null)
    }
    var showCreateDialog by remember { mutableStateOf(false) }
    var selectedRoutineToEdit by remember { mutableStateOf<RoutineResponse?>(null) }

    LaunchedEffect(Unit) {
        calendarViewModel.fetchCalendars()
        viewModel.fetchRoutines()
    }

    val visibleRoutines = routines.filter { selectedCalendarFilterId == null || it.calendar_id == selectedCalendarFilterId }
    val visibleSessions = sessions.filter { selectedCalendarFilterId == null || it.calendar_id == selectedCalendarFilterId }
    val (activeRoutines, pausedRoutines) = visibleRoutines.partition { it.active }
    val calendarColor: (Int, String?) -> String? = { id, fallback -> calendars.find { it.id == id }?.color ?: fallback }
    val dotColors = visibleSessions
        .groupBy { DateTimeUtils.parseLocalDate(it.date_at) ?: LocalDate.now() }
        .mapValues { (_, events) -> events.map { parseHexColor(calendarColor(it.calendar_id, it.calendar_color)) } }
    val nextSession: (RoutineResponse) -> String? = { routine ->
        sessions.firstOrNull { it.routine_id == routine.id && !it.date_at.isPast() }?.let { DateTimeUtils.getRelativeTime(context, it.date_at) }
    }
    val pausedLabel = stringResource(R.string.routine_paused)
    val subtitleOf: (RoutineResponse) -> String = { routine ->
        listOfNotNull(
            routine.days.sorted().joinToString(" ") { weekdayLabel(it) },
            if (selectedCalendarFilterId == null) calendars.find { it.id == routine.calendar_id }?.name ?: routine.calendar_name else null
        ).joinToString("  ·  ")
    }

    Column(modifier = Modifier.fillMaxSize()) {
        LazyRow(
            modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            item {
                PlanifyFilterChip(
                    label = stringResource(R.string.events_filter_all),
                    isSelected = selectedCalendarFilterId == null,
                    onClick = {
                        selectedCalendarFilterId = null
                        prefs.edit().putInt("selected_routine_calendar_filter", -1).apply()
                    }
                )
            }
            itemsIndexed(calendars) { _, cal ->
                PlanifyFilterChip(
                    label = cal.name,
                    isSelected = selectedCalendarFilterId == cal.id,
                    colorHex = cal.color,
                    onClick = {
                        selectedCalendarFilterId = cal.id
                        prefs.edit().putInt("selected_routine_calendar_filter", cal.id).apply()
                    }
                )
            }
        }

        error?.let { message ->
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.fillMaxWidth().clickable { viewModel.clearError() }.padding(horizontal = 24.dp, vertical = 6.dp)
            )
        }

        PlanifyContentContainer(topPadding = 0.dp) {
            PlanifyPullToRefreshBox(
                isRefreshing = isLoading,
                onRefresh = { viewModel.fetchRoutines() },
                modifier = Modifier.fillMaxSize()
            ) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 16.dp)
                ) {
                    item(key = "hero") {
                        MonthCalendarCard(
                            eventColorsByDate = dotColors,
                            modifier = Modifier.padding(horizontal = 16.dp).padding(top = 6.dp)
                        )
                    }

                    if (calendars.isNotEmpty()) {
                        item(key = "add") {
                            val addColor = parseHexColor(calendars.find { it.id == selectedCalendarFilterId }?.color)
                            Row(
                                modifier = Modifier
                                    .padding(start = 16.dp, end = 16.dp, top = 16.dp)
                                    .fillMaxWidth()
                                    .glass(CircleShape)
                                    .clickable(enabled = !isSaving) { showCreateDialog = true }
                                    .padding(start = 22.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = stringResource(R.string.routine_new),
                                    style = MaterialTheme.typography.bodyLarge,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    modifier = Modifier.weight(1f)
                                )
                                Box(
                                    modifier = Modifier.size(44.dp).background(addColor, CircleShape),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(Icons.Default.Add, null, tint = Color.White)
                                }
                            }
                        }
                    }

                    if (activeRoutines.isNotEmpty()) {
                        item(key = "active-spacer") { Spacer(Modifier.height(22.dp)) }
                    }
                    itemsIndexed(activeRoutines, key = { _, r -> "active-${r.id}" }) { index, routine ->
                        PlanifyEventRow(
                            title = routine.title,
                            time = routine.time,
                            subtitle = subtitleOf(routine),
                            relativeTime = nextSession(routine),
                            colorHex = calendarColor(routine.calendar_id, routine.calendar_color),
                            hasAlarm = routine.alarm != null,
                            index = index,
                            groupCount = activeRoutines.size,
                            onClick = { if (!isSaving) selectedRoutineToEdit = routine }
                        )
                    }

                    if (pausedRoutines.isNotEmpty()) {
                        item(key = "paused-label") {
                            GlassSectionHeader(
                                icon = Icons.Default.PauseCircle,
                                title = stringResource(R.string.routine_section_paused),
                                count = pausedRoutines.size,
                                modifier = Modifier.padding(top = 28.dp, bottom = 12.dp)
                            )
                        }
                        itemsIndexed(pausedRoutines, key = { _, r -> "paused-${r.id}" }) { index, routine ->
                            PlanifyEventRow(
                                title = routine.title,
                                time = routine.time,
                                subtitle = subtitleOf(routine),
                                relativeTime = pausedLabel,
                                colorHex = calendarColor(routine.calendar_id, routine.calendar_color),
                                hasAlarm = routine.alarm != null,
                                isPast = true,
                                index = index,
                                groupCount = pausedRoutines.size,
                                onClick = { if (!isSaving) selectedRoutineToEdit = routine }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showCreateDialog) {
        RoutineFormDialog(
            initial = null,
            calendars = calendars,
            initialCalendarId = selectedCalendarFilterId,
            onDismiss = { showCreateDialog = false },
            onConfirm = { request ->
                viewModel.saveRoutine(null, request)
                showCreateDialog = false
            }
        )
    }

    selectedRoutineToEdit?.let { routine ->
        RoutineFormDialog(
            initial = routine,
            calendars = calendars,
            initialCalendarId = routine.calendar_id,
            onDismiss = { selectedRoutineToEdit = null },
            onConfirm = { request ->
                viewModel.saveRoutine(routine, request)
                selectedRoutineToEdit = null
            },
            onDelete = {
                viewModel.deleteRoutine(routine.id)
                selectedRoutineToEdit = null
            }
        )
    }
}

private fun String.isPast(): Boolean =
    try { java.time.LocalDateTime.parse(this.replace(" ", "T")).isBefore(java.time.LocalDateTime.now()) } catch (e: Exception) { false }

private fun weekdayLabel(day: Int): String =
    DayOfWeek.of(day).getDisplayName(TextStyle.SHORT, Locale.getDefault()).replace(".", "").replaceFirstChar { it.uppercaseChar() }

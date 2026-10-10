package com.lito.planify.ui.screens

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Repeat
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.lito.planify.R
import com.lito.planify.data.api.CalendarResponse
import com.lito.planify.data.api.CreateRoutineRequest
import com.lito.planify.data.api.RoutineResponse
import com.lito.planify.ui.components.*
import com.lito.planify.viewmodel.CalendarViewModel
import com.lito.planify.viewmodel.RoutineViewModel
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

@Composable
fun RoutinesScreen(
    viewModel: RoutineViewModel,
    calendarViewModel: CalendarViewModel,
    initialRoutineId: Int? = null,
    onNavigate: (String) -> Unit
) {
    val routines by viewModel.routines.collectAsState()
    val calendars by calendarViewModel.calendars.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isSaving by viewModel.isSaving.collectAsState()
    val error by viewModel.error.collectAsState()
    var showCreate by rememberSaveable { mutableStateOf(false) }
    var editingId by rememberSaveable { mutableStateOf<Int?>(null) }
    var openedInitial by rememberSaveable(initialRoutineId) { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        calendarViewModel.fetchCalendars(force = true)
        viewModel.fetchRoutines()
    }
    LaunchedEffect(routines, initialRoutineId) {
        if (!openedInitial && initialRoutineId != null && routines.any { it.id == initialRoutineId }) {
            editingId = initialRoutineId
            openedInitial = true
        }
    }

    GlassNavScaffold(currentRoute = "routines", onNavigate = onNavigate) {
        Column(Modifier.fillMaxSize()) {
            PlanifyHeader {
                Row(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(stringResource(R.string.routines_title), style = MaterialTheme.typography.headlineLarge, modifier = Modifier.weight(1f))
                    IconButton(onClick = { showCreate = true }, enabled = calendars.isNotEmpty() && !isSaving) {
                        Icon(Icons.Default.Add, contentDescription = stringResource(R.string.routine_new))
                    }
                }
            }
            error?.let { message ->
                TextButton(onClick = viewModel::clearError, modifier = Modifier.fillMaxWidth()) {
                    Text(message, color = MaterialTheme.colorScheme.error)
                }
            }
            PlanifyPullToRefreshBox(isRefreshing = isLoading, onRefresh = viewModel::fetchRoutines, modifier = Modifier.weight(1f)) {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(start = 16.dp, end = 16.dp, bottom = 150.dp)) {
                    if (routines.isEmpty() && !isLoading) {
                        item {
                            Column(
                                modifier = Modifier.fillParentMaxSize().padding(24.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(12.dp, Alignment.CenterVertically)
                            ) {
                                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surfaceVariant) {
                                    Icon(
                                        if (calendars.isEmpty()) Icons.Default.DateRange else Icons.Default.Repeat,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                        modifier = Modifier.padding(16.dp).size(28.dp)
                                    )
                                }
                                Text(
                                    stringResource(if (calendars.isEmpty()) R.string.routines_no_calendar else R.string.routines_empty),
                                    style = MaterialTheme.typography.titleMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                if (calendars.isEmpty()) {
                                    TextButton(onClick = { onNavigate("calendars") }) { Text(stringResource(R.string.nav_calendars)) }
                                }
                            }
                        }
                    }
                    itemsIndexed(routines, key = { _, routine -> routine.id }) { index, routine ->
                        Row(
                            Modifier.fillMaxWidth().glassGroupRow(index, routines.size)
                                .clickable(enabled = !isSaving) { editingId = routine.id }.padding(horizontal = 18.dp, vertical = 14.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                                Text(routine.title, style = MaterialTheme.typography.titleMedium)
                                Text(routine.calendar_name ?: calendars.find { it.id == routine.calendar_id }?.name.orEmpty(), color = parseHexColor(routine.calendar_color))
                                Text("${routine.days.sorted().joinToString(" · ") { weekdayLabel(it) }} · ${routine.time}", style = MaterialTheme.typography.bodyMedium)
                                Text(
                                    "${routine.start_date} → ${routine.end_date ?: stringResource(R.string.routine_no_end)}",
                                    style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant
                                )
                                Text(stringResource(if (routine.active) R.string.routine_active else R.string.routine_inactive), style = MaterialTheme.typography.labelMedium)
                            }
                            Switch(
                                checked = routine.active, enabled = !isSaving,
                                onCheckedChange = { viewModel.setActive(routine, it) },
                                modifier = Modifier.semantics { contentDescription = routine.title }
                            )
                        }
                    }
                }
            }
        }
    }

    val initial = routines.find { it.id == editingId }
    if (showCreate || initial != null) {
        key(initial?.id) {
            RoutineFormDialog(
                initial = initial, calendars = calendars, isSaving = isSaving, error = error,
                onDismiss = { if (!isSaving) { showCreate = false; editingId = null; viewModel.clearError() } },
                onSave = { request -> viewModel.saveRoutine(initial, request) { showCreate = false; editingId = null } },
                onDelete = { initial?.let { routine -> viewModel.deleteRoutine(routine.id) { editingId = null } } }
            )
        }
    }
}

private fun weekdayLabel(day: Int): String =
    DayOfWeek.of(day).getDisplayName(TextStyle.SHORT, Locale.getDefault()).replaceFirstChar { it.uppercaseChar() }

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
private fun RoutineFormDialog(
    initial: RoutineResponse?,
    calendars: List<CalendarResponse>,
    isSaving: Boolean,
    error: String?,
    onDismiss: () -> Unit,
    onSave: (CreateRoutineRequest) -> Unit,
    onDelete: () -> Unit
) {
    val context = LocalContext.current
    var title by rememberSaveable { mutableStateOf(initial?.title.orEmpty()) }
    var calendarId by rememberSaveable { mutableStateOf(initial?.calendar_id ?: calendars.firstOrNull()?.id ?: 0) }
    var days by rememberSaveable { mutableStateOf(initial?.days ?: emptyList<Int>()) }
    var time by rememberSaveable { mutableStateOf(initial?.time ?: "18:00") }
    var startDate by rememberSaveable { mutableStateOf(initial?.start_date ?: LocalDate.now().toString()) }
    var endDate by rememberSaveable { mutableStateOf(initial?.end_date) }
    var active by rememberSaveable { mutableStateOf(initial?.active ?: true) }
    var alarm by rememberSaveable { mutableStateOf(initial?.alarm) }
    var calendarExpanded by remember { mutableStateOf(false) }
    var alarmExpanded by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    fun pickDate(value: String, onDate: (String) -> Unit) {
        val date = LocalDate.parse(value)
        DatePickerDialog(context, { _, year, month, day -> onDate(LocalDate.of(year, month + 1, day).toString()) }, date.year, date.monthValue - 1, date.dayOfMonth).show()
    }

    val validDates = endDate == null || endDate!! >= startDate
    val canSave = title.isNotBlank() && days.isNotEmpty() && calendars.any { it.id == calendarId } && validDates
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(
            Modifier.fillMaxWidth().imePadding().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(stringResource(if (initial == null) R.string.routine_new else R.string.routine_edit), style = MaterialTheme.typography.headlineSmall)
            Text(stringResource(R.string.routine_future_only), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            CustomTextField(value = title, onValueChange = { title = it }, label = stringResource(R.string.label_title), modifier = Modifier.fillMaxWidth(), enabled = !isSaving, singleLine = true)
            ExposedDropdownMenuBox(expanded = calendarExpanded, onExpandedChange = { if (initial == null && !isSaving) calendarExpanded = !calendarExpanded }) {
                CustomTextField(
                    value = calendars.find { it.id == calendarId }?.name ?: initial?.calendar_name.orEmpty(), onValueChange = {}, readOnly = true,
                    label = stringResource(R.string.routine_calendar), enabled = initial == null && !isSaving,
                    modifier = Modifier.menuAnchor().fillMaxWidth(), trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(calendarExpanded) }
                )
                ExposedDropdownMenu(expanded = calendarExpanded, onDismissRequest = { calendarExpanded = false }) {
                    calendars.forEach { calendar -> DropdownMenuItem(text = { Text(calendar.name) }, onClick = { calendarId = calendar.id; calendarExpanded = false }) }
                }
            }
            Text(stringResource(R.string.routine_days), style = MaterialTheme.typography.titleSmall)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                (1..7).forEach { day ->
                    val fullName = DayOfWeek.of(day).getDisplayName(TextStyle.FULL, Locale.getDefault())
                    FilterChip(
                        selected = day in days, enabled = !isSaving,
                        onClick = { days = if (day in days) days - day else (days + day).sorted() },
                        label = { Text(weekdayLabel(day)) }, modifier = Modifier.semantics { contentDescription = fullName }
                    )
                }
            }
            OutlinedButton(onClick = {
                val selected = LocalTime.parse(time)
                TimePickerDialog(context, { _, hour, minute -> time = LocalTime.of(hour, minute).format(DateTimeFormatter.ofPattern("HH:mm")) }, selected.hour, selected.minute, true).show()
            }, enabled = !isSaving, modifier = Modifier.fillMaxWidth()) { Text("${stringResource(R.string.routine_time)}: $time") }
            OutlinedButton(onClick = { pickDate(startDate) { startDate = it } }, enabled = !isSaving, modifier = Modifier.fillMaxWidth()) { Text("${stringResource(R.string.routine_start)}: $startDate") }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(checked = endDate != null, enabled = !isSaving, onCheckedChange = { endDate = if (it) startDate else null })
                Text(stringResource(R.string.routine_has_end))
            }
            endDate?.let { end ->
                OutlinedButton(onClick = { pickDate(end) { endDate = it } }, enabled = !isSaving, modifier = Modifier.fillMaxWidth()) { Text("${stringResource(R.string.routine_end)}: $end") }
            }
            if (!validDates) Text(stringResource(R.string.routine_invalid_dates), color = MaterialTheme.colorScheme.error)
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.routine_active), Modifier.weight(1f))
                Switch(checked = active, enabled = !isSaving, onCheckedChange = { active = it })
            }
            val alarmOptions = listOf(
                null to stringResource(R.string.alarm_no), 0 to stringResource(R.string.alarm_0),
                10 to stringResource(R.string.alarm_10), 20 to stringResource(R.string.alarm_20),
                30 to stringResource(R.string.alarm_30), 40 to stringResource(R.string.alarm_40), 60 to stringResource(R.string.alarm_60)
            )
            ExposedDropdownMenuBox(expanded = alarmExpanded, onExpandedChange = { if (!isSaving) alarmExpanded = !alarmExpanded }) {
                CustomTextField(
                    value = alarmOptions.find { it.first == alarm }?.second ?: stringResource(R.string.alarm_no), onValueChange = {}, readOnly = true, enabled = !isSaving,
                    label = stringResource(R.string.routine_personal_alarm), trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(alarmExpanded) }, modifier = Modifier.menuAnchor().fillMaxWidth()
                )
                ExposedDropdownMenu(expanded = alarmExpanded, onDismissRequest = { alarmExpanded = false }) {
                    alarmOptions.forEach { option -> DropdownMenuItem(text = { Text(option.second) }, onClick = { alarm = option.first; alarmExpanded = false }) }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (initial != null) IconButton(onClick = { confirmDelete = true }, enabled = !isSaving) { Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.routine_delete), tint = MaterialTheme.colorScheme.error) }
                OutlinedActionButton(text = stringResource(R.string.generic_cancel), onClick = onDismiss, enabled = !isSaving, modifier = Modifier.weight(1f))
                PrimaryButton(text = stringResource(R.string.generic_save), enabled = canSave && !isSaving, modifier = Modifier.weight(1f), onClick = {
                    onSave(CreateRoutineRequest(calendarId, title.trim(), days.sorted(), time, startDate, endDate, active, alarm))
                })
            }
        }
    }
    if (confirmDelete) {
        AlertDialog(
            onDismissRequest = { if (!isSaving) confirmDelete = false },
            title = { Text(stringResource(R.string.routine_delete)) }, text = { Text(stringResource(R.string.routine_delete_confirm)) },
            confirmButton = { TextButton(onClick = { confirmDelete = false; onDelete() }, enabled = !isSaving) { Text(stringResource(R.string.routine_delete)) } },
            dismissButton = { TextButton(onClick = { confirmDelete = false }, enabled = !isSaving) { Text(stringResource(R.string.generic_cancel)) } }
        )
    }
}

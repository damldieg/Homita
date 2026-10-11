package com.lito.planify.ui.screens

import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.text.style.TextOverflow
import java.time.LocalDate
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.lito.planify.R
import com.lito.planify.data.api.EventResponse
import com.lito.planify.ui.components.*
import com.lito.planify.util.DateTimeUtils
import com.lito.planify.viewmodel.CalendarViewModel
import com.lito.planify.viewmodel.EventViewModel
import com.lito.planify.viewmodel.PersonViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventListScreen(
    calendarId: Int,
    calendarName: String,
    viewModel: EventViewModel,
    calendarViewModel: CalendarViewModel,
    personViewModel: PersonViewModel,
    isStandalone: Boolean = false,
    onBack: (() -> Unit)? = null,
    onNavigateToCalendars: (() -> Unit)? = null,
    onNavigateToTasks: (() -> Unit)? = null,
    onNavigateToProfile: (() -> Unit)? = null
) {
    val upcomingEvents by viewModel.upcomingEvents.collectAsState()
    val pastEvents by viewModel.pastEvents.collectAsState()
    val calendars by calendarViewModel.calendars.collectAsState()
    val persons by personViewModel.persons.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    val isGlobal = calendarId == 0
    val context = androidx.compose.ui.platform.LocalContext.current
    val prefs = remember { context.getSharedPreferences("planify_prefs", android.content.Context.MODE_PRIVATE) }
    
    var selectedCalendarFilterId by remember { 
        val savedId = prefs.getInt("selected_calendar_filter", -1)
        mutableStateOf<Int?>(if (savedId != -1) savedId else null)
    }
    
    var showCreateDialog by remember { mutableStateOf(false) }
    var selectedEventToEdit by remember { mutableStateOf<EventResponse?>(null) }
    var showEditCalendarDialog by remember { mutableStateOf(false) }

    if (isStandalone && onBack != null) {
        androidx.activity.compose.BackHandler(onBack = onBack)
    }

    LaunchedEffect(isGlobal) {
        if (isGlobal) {
            calendarViewModel.fetchCalendars()
        }
        personViewModel.fetchPersons()
    }

    LaunchedEffect(calendarId, selectedCalendarFilterId) {
        val effectiveId = if (isGlobal) selectedCalendarFilterId else calendarId
        viewModel.fetchEvents(calendarId = effectiveId, force = true)
    }

    if (isStandalone) {
        GlassNavScaffold(
            currentRoute = "calendars",
            onNavigate = { route ->
                when (route) {
                    "calendars" -> onNavigateToCalendars?.invoke()
                    "tasks" -> onNavigateToTasks?.invoke()
                    "profile" -> onNavigateToProfile?.invoke()
                }
            }
        ) {
            Box(modifier = Modifier.fillMaxSize()) {
                EventListContent(
                    calendarId = calendarId,
                    calendarName = calendarName,
                    isStandalone = true,
                    isGlobal = false,
                    selectedCalendarFilterId = null,
                    onSetFilter = {},
                    calendarsList = calendars,
                    upcomingEvents = upcomingEvents,
                    pastEvents = pastEvents,
                    isRefreshing = isLoading,
                    onRefresh = { viewModel.fetchEvents(calendarId = calendarId, force = true) },
                    onShowEditCalendar = { showEditCalendarDialog = true },
                    onShowCreateEvent = { showCreateDialog = true },
                    onEditEvent = { selectedEventToEdit = it }
                )
            }
        }
    } else {
        Box(modifier = Modifier.fillMaxSize()) {
            EventListContent(
                calendarId = calendarId,
                calendarName = calendarName,
                isStandalone = false,
                isGlobal = true,
                selectedCalendarFilterId = selectedCalendarFilterId,
                onSetFilter = { 
                    selectedCalendarFilterId = it 
                    prefs.edit().putInt("selected_calendar_filter", it ?: -1).apply()
                },
                calendarsList = calendars,
                upcomingEvents = upcomingEvents,
                pastEvents = pastEvents,
                isRefreshing = isLoading,
                onRefresh = { viewModel.fetchEvents(calendarId = selectedCalendarFilterId, force = true) },
                onShowEditCalendar = {},
                onShowCreateEvent = { showCreateDialog = true },
                onEditEvent = { selectedEventToEdit = it }
            )
        }
    }

    val refreshCalendarId = if (isGlobal) (selectedCalendarFilterId ?: 0) else calendarId

    if (showCreateDialog) {
        val activeCalId = if (isGlobal) {
            selectedCalendarFilterId ?: calendars.firstOrNull()?.id ?: 0
        } else {
            calendarId
        }
        EventFormDialog(
            calendarId = activeCalId,
            calendars = if (isGlobal) calendars else emptyList(),
            persons = persons,
            onDismiss = { showCreateDialog = false },
            onConfirm = { selectedCalId, eventTitle, eventDateAt, aiText, alarm, personIds ->
                viewModel.createEvent(selectedCalId, eventTitle, eventDateAt, aiText, alarm, personIds, refreshCalendarId)
                showCreateDialog = false
            }
        )
    }

    selectedEventToEdit?.let { event ->
        EventFormDialog(
            calendarId = event.calendar_id,
            initialEvent = event,
            persons = persons,
            onDismiss = { selectedEventToEdit = null },
            onConfirm = { _, eventTitle, eventDateAt, _, alarm, personIds ->
                viewModel.updateEvent(event.id, refreshCalendarId, eventTitle, eventDateAt, alarm, personIds)
                selectedEventToEdit = null
            },
            onDelete = {
                viewModel.deleteEvent(event.id, refreshCalendarId)
                selectedEventToEdit = null
            },
            isEdit = true
        )
    }

    val calendarUsers by calendarViewModel.calendarUsers.collectAsState()

    LaunchedEffect(showEditCalendarDialog) {
        if (showEditCalendarDialog && isStandalone) {
            calendarViewModel.fetchCalendarUsers(calendarId)
        }
    }

    if (showEditCalendarDialog && isStandalone) {
        val currentCal = calendars.find { it.id == calendarId }
        currentCal?.let { cal ->
            CreateCalendarDialog(
                initialName = cal.name,
                initialColor = cal.color,
                initialWidget = cal.widget ?: true,
                users = calendarUsers,
                onInviteUser = { email -> calendarViewModel.addCalendarUser(cal.id, email) },
                onRemoveUser = { userId -> calendarViewModel.removeCalendarUser(cal.id, userId) },
                onDismiss = { showEditCalendarDialog = false },
                onConfirm = { name, color, widget ->
                    calendarViewModel.updateCalendar(cal.id, name, color, widget) {
                        viewModel.fetchEvents(calendarId = cal.id, force = true)
                    }
                    showEditCalendarDialog = false
                },
                onDelete = {
                    calendarViewModel.deleteCalendar(cal.id) {
                        onBack?.invoke()
                    }
                    showEditCalendarDialog = false
                },
                isEdit = true
            )
        }
    }
}

@Composable
fun EventListContent(
    calendarId: Int,
    calendarName: String,
    isStandalone: Boolean,
    isGlobal: Boolean,
    selectedCalendarFilterId: Int?,
    onSetFilter: (Int?) -> Unit,
    calendarsList: List<com.lito.planify.data.api.CalendarResponse>,
    upcomingEvents: List<EventResponse>,
    pastEvents: List<EventResponse>,
    isRefreshing: Boolean,
    onRefresh: () -> Unit,
    onShowEditCalendar: () -> Unit,
    onShowCreateEvent: () -> Unit,
    onEditEvent: (EventResponse) -> Unit
) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    Column(modifier = Modifier.fillMaxSize()) {
        val activeCal = calendarsList.find { it.id == calendarId }
        val displayCalendarName = activeCal?.name ?: calendarName
        val listColor = parseHexColor(activeCal?.color)
        val addColor = if (isGlobal) parseHexColor(calendarsList.find { it.id == selectedCalendarFilterId }?.color) else listColor
        val calendarColor: (EventResponse) -> String? = { event -> calendarsList.find { it.id == event.calendar_id }?.color ?: event.calendar_color }

        if (isStandalone) {
            PlanifyHeader {
                Row(
                    modifier = Modifier.padding(top = 8.dp, start = 24.dp, end = 16.dp, bottom = 8.dp).fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(modifier = Modifier.size(14.dp).background(listColor, CircleShape))
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = displayCalendarName,
                        style = MaterialTheme.typography.headlineLarge,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f)
                    )
                    IconButton(onClick = onShowEditCalendar, modifier = Modifier.glass(CircleShape)) {
                        Icon(Icons.Default.Settings, null, tint = MaterialTheme.colorScheme.onSurface)
                    }
                }
            }
        }

        if (isGlobal) {
            LazyRow(
                modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                item {
                    PlanifyFilterChip(
                        label = stringResource(R.string.events_filter_all),
                        isSelected = selectedCalendarFilterId == null,
                        onClick = { onSetFilter(null) }
                    )
                }
                itemsIndexed(calendarsList) { _, cal ->
                    PlanifyFilterChip(
                        label = cal.name,
                        isSelected = selectedCalendarFilterId == cal.id,
                        colorHex = cal.color,
                        onClick = { onSetFilter(cal.id) }
                    )
                }
            }
        }

        val subtitleOf: (EventResponse) -> String? = { event ->
            listOfNotNull(
                event.persons.orEmpty().joinToString(", ") { it.name }.ifEmpty { null },
                if (isGlobal) calendarsList.find { it.id == event.calendar_id }?.name ?: event.calendar_name else null
            ).joinToString("  ·  ").ifEmpty { null }
        }

        val dateOf: (EventResponse) -> LocalDate = { DateTimeUtils.parseLocalDate(it.date_at) ?: LocalDate.now() }
        val upcomingGroups = upcomingEvents.groupBy(dateOf)
        val pastGroups = pastEvents.groupBy(dateOf)
        val dotColors = (upcomingEvents + pastEvents).groupBy(dateOf).mapValues { (_, events) -> events.map { parseHexColor(calendarColor(it)) } }
        val canAdd = !isGlobal || calendarsList.isNotEmpty()

        // Posición en la lista de la cabecera de cada día, para saltar desde el mini calendario.
        val dayIndex = remember(upcomingGroups, pastGroups, canAdd) {
            val map = mutableMapOf<LocalDate, Int>()
            var index = if (canAdd) 2 else 1
            upcomingGroups.forEach { (date, events) -> map[date] = index; index += events.size + 1 }
            if (pastGroups.isNotEmpty()) index++
            pastGroups.forEach { (date, events) -> map.putIfAbsent(date, index); index += events.size + 1 }
            map
        }

        PlanifyContentContainer(topPadding = 0.dp) {
            PlanifyPullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = onRefresh,
                modifier = Modifier.fillMaxSize()
            ) {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 16.dp)
                ) {
                    item(key = "hero") {
                        Column(modifier = Modifier.padding(horizontal = 16.dp).padding(top = 6.dp)) {
                            if (!isStandalone) {
                                Text(
                                    text = LocalDate.now()
                                        .format(java.time.format.DateTimeFormatter.ofPattern("EEE d MMM", currentLocale()))
                                        .replace(".", "")
                                        .replaceFirstChar { it.uppercaseChar() },
                                    style = MaterialTheme.typography.displayMedium,
                                    color = MaterialTheme.colorScheme.onSurface,
                                    modifier = Modifier.padding(start = 8.dp, top = 6.dp, bottom = 14.dp)
                                )
                            }
                            MonthCalendarCard(
                                eventColorsByDate = dotColors,
                                onDayClick = { date ->
                                    dayIndex[date]?.let { scope.launch { listState.animateScrollToItem(it) } }
                                }
                            )
                        }
                    }

                    if (canAdd) {
                        item(key = "add") {
                            Row(
                                modifier = Modifier
                                    .padding(start = 16.dp, end = 16.dp, top = 16.dp)
                                    .fillMaxWidth()
                                    .glass(CircleShape)
                                    .clickable { onShowCreateEvent() }
                                    .padding(start = 22.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = stringResource(R.string.calendars_new_event),
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

                    upcomingGroups.forEach { (date, events) ->
                        item(key = "up-day-$date") {
                            DayPill(date = date, modifier = Modifier.padding(start = 24.dp, top = 22.dp, bottom = 10.dp))
                        }
                        itemsIndexed(events, key = { _, e -> "up-${e.id}" }) { index, event ->
                            PlanifyEventRow(
                                title = event.title,
                                time = DateTimeUtils.formatTime(event.date_at),
                                subtitle = subtitleOf(event),
                                relativeTime = DateTimeUtils.getRelativeTime(context, event.date_at),
                                colorHex = calendarColor(event),
                                hasAlarm = event.alarm != null,
                                index = index,
                                groupCount = events.size,
                                onClick = { onEditEvent(event) }
                            )
                        }
                    }

                    if (pastGroups.isNotEmpty()) {
                        item(key = "past-label") {
                            GlassSectionHeader(
                                icon = Icons.Default.History,
                                title = stringResource(R.string.event_section_past_title),
                                count = pastEvents.size,
                                modifier = Modifier.padding(top = 28.dp)
                            )
                        }
                        pastGroups.forEach { (date, events) ->
                            item(key = "past-day-$date") {
                                DayPill(date = date, modifier = Modifier.padding(start = 24.dp, top = 22.dp, bottom = 10.dp))
                            }
                            itemsIndexed(events, key = { _, e -> "past-${e.id}" }) { index, event ->
                                PlanifyEventRow(
                                    title = event.title,
                                    time = DateTimeUtils.formatTime(event.date_at),
                                    subtitle = subtitleOf(event),
                                    relativeTime = DateTimeUtils.getRelativeTime(context, event.date_at),
                                    colorHex = calendarColor(event),
                                    hasAlarm = event.alarm != null,
                                    isPast = true,
                                    index = index,
                                    groupCount = events.size,
                                    onClick = { onEditEvent(event) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

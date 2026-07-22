package com.lito.planify.ui.screens

import androidx.compose.animation.*
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
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
import com.lito.planify.ui.theme.OutlineDimColor
import com.lito.planify.util.DateTimeUtils
import com.lito.planify.viewmodel.CalendarViewModel
import com.lito.planify.viewmodel.EventViewModel
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EventListScreen(
    calendarId: Int,
    calendarName: String,
    viewModel: EventViewModel,
    calendarViewModel: CalendarViewModel,
    isStandalone: Boolean = false,
    onBack: (() -> Unit)? = null,
    onNavigateToCalendars: (() -> Unit)? = null,
    onNavigateToTasks: (() -> Unit)? = null,
    onNavigateToProfile: (() -> Unit)? = null
) {
    val upcomingEvents by viewModel.upcomingEvents.collectAsState()
    val pastEvents by viewModel.pastEvents.collectAsState()
    val calendars by calendarViewModel.calendars.collectAsState()
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
    }

    LaunchedEffect(calendarId, selectedCalendarFilterId) {
        val effectiveId = if (isGlobal) selectedCalendarFilterId else calendarId
        viewModel.fetchEvents(calendarId = effectiveId, force = false)
    }

    if (isStandalone) {
        Scaffold(
            containerColor = MaterialTheme.colorScheme.background,
            bottomBar = {
                GlassBottomNavBar(
                    currentRoute = "calendars",
                    onNavigate = { route ->
                        when (route) {
                            "calendars" -> onNavigateToCalendars?.invoke()
                            "tasks" -> onNavigateToTasks?.invoke()
                            "profile" -> onNavigateToProfile?.invoke()
                        }
                    }
                )
            }
        ) { padding ->
            Box(modifier = Modifier.fillMaxSize().padding(padding)) {
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

    if (showCreateDialog) {
        val activeCalId = if (isGlobal) {
            selectedCalendarFilterId ?: calendars.firstOrNull()?.id ?: 0
        } else {
            calendarId
        }
        EventFormDialog(
            calendarId = activeCalId,
            onDismiss = { showCreateDialog = false },
            onConfirm = { selectedCalId, eventTitle, eventDateAt, aiText, alarm ->
                viewModel.createEvent(selectedCalId, eventTitle, eventDateAt, aiText, alarm)
                showCreateDialog = false
            }
        )
    }

    selectedEventToEdit?.let { event ->
        EventFormDialog(
            calendarId = event.calendar_id,
            initialEvent = event,
            onDismiss = { selectedEventToEdit = null },
            onConfirm = { selectedCalId, eventTitle, eventDateAt, _, alarm ->
                viewModel.updateEvent(event.id, selectedCalId, eventTitle, eventDateAt, alarm)
                selectedEventToEdit = null
            },
            onDelete = {
                viewModel.deleteEvent(event.id, if (isGlobal) (selectedCalendarFilterId ?: 0) else calendarId)
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
    Column(modifier = Modifier.fillMaxSize()) {
        val activeCal = calendarsList.find { it.id == calendarId }
        val displayCalendarName = activeCal?.name ?: calendarName
        val colorHex = activeCal?.color ?: "#4B4D99"
        val listColor = try { Color(android.graphics.Color.parseColor(colorHex)) } catch (e: Exception) { Color(0xFF4B4D99) }

        if (isStandalone) {
            PlanifyHeader {
                Row(
                    modifier = Modifier.padding(top = 0.dp, start = 24.dp, end = 20.dp, bottom = 16.dp).fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(modifier = Modifier.size(14.dp).background(listColor, androidx.compose.foundation.shape.CircleShape))
                    Spacer(modifier = Modifier.width(12.dp))
                    Text(
                        text = displayCalendarName, 
                        style = MaterialTheme.typography.titleLarge.copy(fontFamily = androidx.compose.ui.text.font.FontFamily.Serif, fontSize = 34.sp)
                    )
                    Spacer(modifier = Modifier.weight(1f))
                    IconButton(onClick = onShowEditCalendar) { Icon(Icons.Default.Settings, null, tint = MaterialTheme.colorScheme.onSurface) }
                }
                HorizontalDivider(thickness = 0.5.dp, color = OutlineDimColor)
            }
        }

        if (isGlobal) {
            Surface(color = Color.White, modifier = Modifier.fillMaxWidth()) {
                Column {
                    HorizontalDivider(thickness = 0.5.dp, color = OutlineDimColor)
                    LazyRow(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                        contentPadding = PaddingValues(horizontal = 20.dp),
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
                    HorizontalDivider(thickness = 0.5.dp, color = OutlineDimColor)
                }
            }
        }

        PlanifyContentContainer(topPadding = 0.dp) {
            PlanifyPullToRefreshBox(
                isRefreshing = isRefreshing,
                onRefresh = onRefresh,
                modifier = Modifier.fillMaxSize()
            ) {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(bottom = 120.dp)
                ) {
                    val canAdd = if (isGlobal) selectedCalendarFilterId != null else true
                    if (canAdd) {
                    item {
                        Column(modifier = Modifier.background(Color.White)) {
                            Row(
                                modifier = Modifier
                                    .padding(horizontal = 20.dp, vertical = 12.dp)
                                    .fillMaxWidth()
                                    .clickable { onShowCreateEvent() },
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Text(
                                    text = stringResource(R.string.calendars_new_event), 
                                    color = Color(0xFF757575), 
                                    fontSize = 16.sp,
                                    modifier = Modifier.weight(1f).padding(vertical = 14.dp) // Padding to simulate TextField height
                                )
                                
                                FloatingActionButton(
                                    onClick = onShowCreateEvent,
                                    containerColor = listColor,
                                    contentColor = Color.White,
                                    shape = androidx.compose.foundation.shape.CircleShape,
                                    modifier = Modifier.size(40.dp),
                                    elevation = FloatingActionButtonDefaults.elevation(0.dp)
                                ) { 
                                    Icon(Icons.Default.Add, null) 
                                }
                            }
                            HorizontalDivider(thickness = 0.5.dp, color = OutlineDimColor)
                        }
                    }
                }
                
                if (upcomingEvents.isNotEmpty()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(Color(0xFFF7F5F2))
                                .padding(horizontal = 20.dp, vertical = 18.dp)
                        ) {
                            Text(
                                text = "${stringResource(R.string.event_section_upcoming)} · ${upcomingEvents.size}",
                                style = MaterialTheme.typography.labelSmall.copy(
                                    fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                                    fontSize = 12.sp,
                                    letterSpacing = 1.2.sp
                                ),
                                color = Color(0xFF757575)
                            )
                        }
                    }
                    itemsIndexed(upcomingEvents) { _, event ->
                        val updatedColor = calendarsList.find { it.id == event.calendar_id }?.color ?: event.calendar_color
                        PlanifyEventRow(
                            title = event.title,
                            dateInfo = DateTimeUtils.formatEventDate(event.date_at),
                            relativeTime = DateTimeUtils.getRelativeTime(context, event.date_at),
                            colorHex = updatedColor,
                            hasAlarm = event.alarm != null,
                            onClick = { onEditEvent(event) }
                        )
                    }
                }

                if (pastEvents.isNotEmpty()) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .background(Color(0xFFF7F5F2))
                                .padding(horizontal = 20.dp, vertical = 18.dp)
                        ) {
                            Text(
                                text = "${stringResource(R.string.event_section_past)} · ${pastEvents.size}",
                                style = MaterialTheme.typography.labelSmall.copy(
                                    fontWeight = androidx.compose.ui.text.font.FontWeight.Bold,
                                    fontSize = 12.sp,
                                    letterSpacing = 1.2.sp
                                ),
                                color = Color(0xFF757575)
                            )
                        }
                    }
                    itemsIndexed(pastEvents) { _, event ->
                        val updatedColor = calendarsList.find { it.id == event.calendar_id }?.color ?: event.calendar_color
                        PlanifyEventRow(
                            title = event.title,
                            dateInfo = DateTimeUtils.formatEventDate(event.date_at),
                            relativeTime = DateTimeUtils.getRelativeTime(context, event.date_at),
                            colorHex = updatedColor,
                            hasAlarm = event.alarm != null,
                            onClick = { onEditEvent(event) }
                        )
                    }
                }
                }
            }
        }
    }
}

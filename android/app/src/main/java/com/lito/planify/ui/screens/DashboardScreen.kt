package com.lito.planify.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.lito.planify.R
import com.lito.planify.ui.components.*
import com.lito.planify.viewmodel.CalendarViewModel

@Composable
fun DashboardScreen(
    viewModel: CalendarViewModel,
    onNavigateToCalendar: (Int, String) -> Unit
) {
    val calendars by viewModel.calendars.collectAsState()
    val isLoading by viewModel.isLoading.collectAsState()
    var showCreateDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { viewModel.fetchCalendars() }

    PlanifyContentContainer {
        PlanifyPullToRefreshBox(
            isRefreshing = isLoading,
            onRefresh = { viewModel.fetchCalendars() },
            modifier = Modifier.fillMaxSize()
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = 120.dp)
            ) {
                itemsIndexed(calendars) { _, calendar ->
                    PlanifyRowItem(
                        title = calendar.name,
                        count = calendar.upcoming_event_count ?: 0,
                        colorHex = calendar.color,
                        onClick = { onNavigateToCalendar(calendar.id, calendar.name) }
                    )
                }
                item {
                    PlanifyDashedCard(
                        text = stringResource(R.string.calendars_new),
                        onClick = { showCreateDialog = true }
                    )
                }
            }
        }
    }

    if (showCreateDialog) {
        CreateCalendarDialog(
            onDismiss = { showCreateDialog = false },
            onConfirm = { name, color, widget ->
                viewModel.createCalendar(name, color, widget) { id, calName ->
                    showCreateDialog = false
                    onNavigateToCalendar(id, calName)
                }
            }
        )
    }
}

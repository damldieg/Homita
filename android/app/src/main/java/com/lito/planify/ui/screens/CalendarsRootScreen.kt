package com.lito.planify.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.*
import androidx.compose.material3.TabRowDefaults.tabIndicatorOffset
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import com.lito.planify.R
import com.lito.planify.ui.components.GlassBottomNavBar
import com.lito.planify.ui.theme.OutlineDimColor
import com.lito.planify.viewmodel.CalendarViewModel
import com.lito.planify.viewmodel.EventViewModel

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun CalendarsRootScreen(
    calendarViewModel: CalendarViewModel,
    eventViewModel: EventViewModel,
    onNavigateToTasks: () -> Unit,
    onNavigateToProfile: () -> Unit,
    onNavigateToCalendarDetail: (Int, String) -> Unit,
    initialTab: Int = 0
) {
    val pagerState = rememberPagerState(initialPage = initialTab, pageCount = { 2 })
    val coroutineScope = rememberCoroutineScope()
    val selectedTab = pagerState.currentPage
    
    BackHandler(enabled = selectedTab != 0) {
        coroutineScope.launch {
            pagerState.animateScrollToPage(0)
        }
    }
    
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            GlassBottomNavBar(
                currentRoute = "calendars",
                onNavigate = { route ->
                    when (route) {
                        "calendars" -> coroutineScope.launch { pagerState.animateScrollToPage(0) }
                        "tasks" -> onNavigateToTasks()
                        "profile" -> onNavigateToProfile()
                    }
                }
            )
        }
    ) { padding ->
        // We handle the TOP padding manually by NOT applying padding.calculateTopPadding() here
        Column(
            modifier = Modifier
                .padding(bottom = padding.calculateBottomPadding())
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
        ) {
            // The white header (Tabs) now includes the status bar area
            Surface(
                color = Color.White,
                shadowElevation = 0.dp
            ) {
                TabRow(
                    selectedTabIndex = selectedTab,
                    containerColor = Color.White,
                    contentColor = MaterialTheme.colorScheme.primary,
                    divider = {}, 
                    indicator = { tabPositions ->
                        TabRowDefaults.SecondaryIndicator(
                            Modifier.tabIndicatorOffset(tabPositions[selectedTab]),
                            height = 3.dp,
                            color = MaterialTheme.colorScheme.primary
                        )
                    },
                    modifier = Modifier
                        .statusBarsPadding() // This pushes tabs below status bar but keeps background white
                        .height(64.dp)
                ) {
                    val tabStyle = MaterialTheme.typography.labelLarge.copy(
                        fontSize = 15.sp,
                        letterSpacing = 0.1.sp
                    )
                    Tab(
                        selected = selectedTab == 0,
                        onClick = { coroutineScope.launch { pagerState.animateScrollToPage(0) } },
                        text = { 
                            Text(
                                stringResource(R.string.calendars_tab_events), 
                                style = tabStyle, 
                                fontWeight = if(selectedTab == 0) androidx.compose.ui.text.font.FontWeight.Bold else androidx.compose.ui.text.font.FontWeight.Medium
                            ) 
                        },
                        selectedContentColor = MaterialTheme.colorScheme.primary,
                        unselectedContentColor = Color(0xFF757575)
                    )
                    Tab(
                        selected = selectedTab == 1,
                        onClick = { coroutineScope.launch { pagerState.animateScrollToPage(1) } },
                        text = { 
                            Text(
                                stringResource(R.string.calendars_tab_all), 
                                style = tabStyle, 
                                fontWeight = if(selectedTab == 1) androidx.compose.ui.text.font.FontWeight.Bold else androidx.compose.ui.text.font.FontWeight.Medium
                            ) 
                        },
                        selectedContentColor = MaterialTheme.colorScheme.primary,
                        unselectedContentColor = Color(0xFF757575)
                    )
                }
            }
            
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.weight(1f).fillMaxWidth()
            ) { page ->
                when (page) {
                    0 -> EventListScreen(
                        calendarId = 0,
                        calendarName = "Global",
                        viewModel = eventViewModel,
                        calendarViewModel = calendarViewModel
                    )
                    1 -> DashboardScreen(
                        viewModel = calendarViewModel,
                        onNavigateToCalendar = onNavigateToCalendarDetail
                    )
                }
            }
        }
    }
}

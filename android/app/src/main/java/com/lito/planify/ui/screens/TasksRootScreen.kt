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
import com.lito.planify.viewmodel.TaskListViewModel
import com.lito.planify.viewmodel.TaskViewModel

@OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
fun TasksRootScreen(
    taskListViewModel: TaskListViewModel,
    taskViewModel: TaskViewModel,
    onNavigateToCalendars: () -> Unit,
    onNavigateToProfile: () -> Unit,
    onNavigateToTaskListDetail: (Int, String) -> Unit,
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
                currentRoute = "tasks",
                onNavigate = { route ->
                    when (route) {
                        "tasks" -> coroutineScope.launch { pagerState.animateScrollToPage(0) }
                        "calendars" -> onNavigateToCalendars()
                        "profile" -> onNavigateToProfile()
                    }
                }
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .padding(bottom = padding.calculateBottomPadding())
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
        ) {
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
                        .statusBarsPadding()
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
                                stringResource(R.string.tasks_tab_all), 
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
                                stringResource(R.string.tasks_tab_lists), 
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
                    0 -> TasksScreen(taskListId = 0, taskListName = "Global", viewModel = taskViewModel, taskListViewModel = taskListViewModel)
                    1 -> TaskListsScreen(taskListViewModel, onNavigateToTaskListDetail)
                }
            }
        }
    }
}

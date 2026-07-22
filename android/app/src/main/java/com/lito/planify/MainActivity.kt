package com.lito.planify

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.*
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavType
import androidx.navigation.compose.*
import androidx.navigation.navArgument
import com.lito.planify.data.api.RetrofitClient
import com.lito.planify.data.local.SessionManager
import com.lito.planify.ui.screens.*
import com.lito.planify.ui.theme.PlanifyTheme
import com.lito.planify.viewmodel.*
import com.lito.planify.viewmodel.factory.ViewModelFactory
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.runBlocking

class MainActivity : ComponentActivity() {
    private var currentIntentState = mutableStateOf<android.content.Intent?>(null)

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        currentIntentState.value = intent
    }

    override fun onResume() {
        super.onResume()
        val updateTasksIntent = android.content.Intent(this, com.lito.planify.widget.TasksWidgetProvider::class.java).apply {
            action = "com.lito.planify.widget.ACTION_CLEAR_CACHE"
        }
        sendBroadcast(updateTasksIntent)

        val updateEventsIntent = android.content.Intent(this, com.lito.planify.widget.CalendarWidgetProvider::class.java).apply {
            action = "com.lito.planify.widget.ACTION_CLEAR_CACHE"
        }
        sendBroadcast(updateEventsIntent)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        currentIntentState.value = intent
        
        com.lito.planify.util.AlarmHelper.createNotificationChannel(this)
        com.lito.planify.util.AlarmHelper.scheduleWidgetUpdate(this)

        // Ensure no system ActionBar or Title is shown
        actionBar?.hide()
        
        enableEdgeToEdge()

        val sessionManager = SessionManager(this)
        val authToken = runBlocking { sessionManager.authTokenFlow.firstOrNull() }
        RetrofitClient.setToken(authToken)

        setContent {
            val currentIntent by currentIntentState
            PlanifyTheme {
                val navController = rememberNavController()
                val factory = ViewModelFactory(application, sessionManager)
                
                val authViewModel: AuthViewModel = viewModel(factory = factory)
                val calendarViewModel: CalendarViewModel = viewModel(factory = factory)
                val eventViewModel: EventViewModel = viewModel(factory = factory)
                val taskListViewModel: TaskListViewModel = viewModel(factory = factory)
                val taskViewModel: TaskViewModel = viewModel(factory = factory)

                LaunchedEffect(currentIntent) {
                    val intent = currentIntent
                    if (intent != null) {
                        if (intent.data?.scheme == "planify" && intent.data?.host == "tasks") {
                            val listIdStr = intent.data?.getQueryParameter("list_id")
                            if (listIdStr != null) {
                                try {
                                    val listId = listIdStr.toInt()
                                    val prefs = getSharedPreferences("planify_prefs", android.content.Context.MODE_PRIVATE)
                                    prefs.edit().putInt("selected_list_filter", if (listId > 0) listId else -1).apply()
                                } catch (e: Exception) { }
                            }
                            
                            // We check if we are not already at the tasks global screen
                            if (navController.currentDestination?.route != "tasks") {
                                navController.navigate("tasks") {
                                    popUpTo("calendars") { inclusive = false }
                                }
                            }
                        } else if (intent.data?.scheme == "calendar" && (intent.data?.host == "global_events" || intent.data?.host == "open_main_from_list")) {
                            val prefs = getSharedPreferences("planify_prefs", android.content.Context.MODE_PRIVATE)
                            prefs.edit().putInt("selected_calendar_filter", -1).apply()
                            
                            if (navController.currentDestination?.route != "calendars") {
                                navController.navigate("calendars") {
                                    popUpTo(0)
                                }
                            }
                        }
                    }
                }

                val startDestination = if (authToken != null) {
                    val isGlobalTasksIntent = currentIntent?.data?.scheme == "planify" && currentIntent?.data?.host == "tasks"
                    val isGlobalEventsIntent = currentIntent?.data?.scheme == "calendar" && 
                            (currentIntent?.data?.host == "global_events" || currentIntent?.data?.host == "open_main_from_list")
                            
                    if (isGlobalTasksIntent) {
                        val listIdStr = currentIntent?.data?.getQueryParameter("list_id")
                        if (listIdStr != null) {
                            try {
                                val listId = listIdStr.toInt()
                                val prefs = getSharedPreferences("planify_prefs", android.content.Context.MODE_PRIVATE)
                                prefs.edit().putInt("selected_list_filter", if (listId > 0) listId else -1).apply()
                            } catch (e: Exception) { }
                        }
                        "tasks"
                    } else if (isGlobalEventsIntent) {
                        val prefs = getSharedPreferences("planify_prefs", android.content.Context.MODE_PRIVATE)
                        prefs.edit().putInt("selected_calendar_filter", -1).apply()
                        "calendars"
                    } else {
                        "calendars"
                    }
                } else "welcome"

                NavHost(navController = navController, startDestination = startDestination) {
                    composable("welcome") {
                        WelcomeScreen(
                            onNavigateToLogin = { navController.navigate("login") },
                            onNavigateToRegister = { navController.navigate("register") }
                        )
                    }
                    composable("login") {
                        LoginScreen(
                            viewModel = authViewModel,
                            onNavigateBack = { navController.popBackStack() },
                            onSuccess = { 
                                navController.navigate("calendars") { 
                                    popUpTo("welcome") { inclusive = true } 
                                } 
                            },
                            onNavigateToRegister = { navController.navigate("register") }
                        )
                    }
                    composable("register") {
                        RegisterScreen(
                            viewModel = authViewModel,
                            onNavigateBack = { navController.popBackStack() },
                            onSuccess = { 
                                navController.navigate("calendars") { 
                                    popUpTo("welcome") { inclusive = true } 
                                } 
                            }
                        )
                    }
                    
                    // --- Main Tabs ---
                    composable("tasks") { backStackEntry ->
                        val initialTab = backStackEntry.savedStateHandle.get<Int>("initialTab") ?: 0
                        TasksRootScreen(
                            taskListViewModel = taskListViewModel,
                            taskViewModel = taskViewModel,
                            onNavigateToCalendars = { navController.navigate("calendars") { popUpTo(0) } },
                            onNavigateToProfile = { navController.navigate("profile") { popUpTo(0) } },
                            onNavigateToTaskListDetail = { id, name -> navController.navigate("task_list/$id/$name") },
                            initialTab = initialTab
                        )
                    }
                    composable("calendars") { backStackEntry ->
                        val initialTab = backStackEntry.savedStateHandle.get<Int>("initialTab") ?: 0
                        CalendarsRootScreen(
                            calendarViewModel = calendarViewModel,
                            eventViewModel = eventViewModel,
                            onNavigateToTasks = { navController.navigate("tasks") { popUpTo(0) } },
                            onNavigateToProfile = { navController.navigate("profile") { popUpTo(0) } },
                            onNavigateToCalendarDetail = { id, name -> navController.navigate("calendar/$id/$name") },
                            initialTab = initialTab
                        )
                    }
                    composable("profile") {
                        ProfileScreen(
                            viewModel = authViewModel,
                            sessionManager = sessionManager,
                            onLogout = { navController.navigate("welcome") { popUpTo(0) } },
                            onNavigateToTasks = { navController.navigate("tasks") { popUpTo(0) } },
                            onNavigateToCalendars = { navController.navigate("calendars") { popUpTo(0) } }
                        )
                    }

                    // --- Details ---
                    composable(
                        "task_list/{id}/{name}",
                        arguments = listOf(
                            navArgument("id") { type = NavType.IntType },
                            navArgument("name") { type = NavType.StringType }
                        )
                    ) { backStackEntry ->
                        val id = backStackEntry.arguments?.getInt("id") ?: 0
                        val name = backStackEntry.arguments?.getString("name") ?: ""
                        TasksScreen(
                            taskListId = id,
                            taskListName = name,
                            viewModel = taskViewModel,
                            taskListViewModel = taskListViewModel,
                            isStandalone = true,
                            onBack = { 
                                navController.previousBackStackEntry?.savedStateHandle?.set("initialTab", 1)
                                navController.popBackStack()
                            },
                            onNavigateToTasks = { navController.navigate("tasks") { popUpTo("tasks") { inclusive = true } } },
                            onNavigateToCalendars = { navController.navigate("calendars") { popUpTo(0) } },
                            onNavigateToProfile = { navController.navigate("profile") { popUpTo(0) } }
                        )
                    }
                    composable(
                        "calendar/{id}/{name}",
                        arguments = listOf(
                            navArgument("id") { type = NavType.IntType },
                            navArgument("name") { type = NavType.StringType }
                        )
                    ) { backStackEntry ->
                        val id = backStackEntry.arguments?.getInt("id") ?: 0
                        val name = backStackEntry.arguments?.getString("name") ?: ""
                        EventListScreen(
                            calendarId = id,
                            calendarName = name,
                            viewModel = eventViewModel,
                            calendarViewModel = calendarViewModel,
                            isStandalone = true,
                            onBack = { 
                                navController.previousBackStackEntry?.savedStateHandle?.set("initialTab", 1)
                                navController.popBackStack()
                            },
                            onNavigateToCalendars = { navController.navigate("calendars") { popUpTo("calendars") { inclusive = true } } },
                            onNavigateToTasks = { navController.navigate("tasks") { popUpTo(0) } },
                            onNavigateToProfile = { navController.navigate("profile") { popUpTo(0) } }
                        )
                    }
                }
            }
        }
    }
}

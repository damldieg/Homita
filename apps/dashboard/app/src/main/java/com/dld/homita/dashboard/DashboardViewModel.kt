package com.dld.homita.dashboard

import android.app.Application
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.dld.homita.dashboard.data.Api
import com.dld.homita.dashboard.data.AuthRequest
import com.dld.homita.dashboard.data.Content
import com.dld.homita.dashboard.data.Forecast
import com.dld.homita.dashboard.data.RefreshRequest
import com.dld.homita.dashboard.data.GeoResult
import com.dld.homita.dashboard.data.Location
import com.dld.homita.dashboard.data.MealsToday
import com.dld.homita.dashboard.data.ReferenceClock
import com.dld.homita.dashboard.data.Schedule
import com.dld.homita.dashboard.data.Session
import com.dld.homita.dashboard.data.SessionExpired
import com.dld.homita.dashboard.data.Store
import com.dld.homita.dashboard.data.TaskPriority
import com.dld.homita.dashboard.data.TaskSort
import com.dld.homita.dashboard.data.Week
import com.dld.homita.dashboard.data.cache.DiskCache
import com.dld.homita.dashboard.data.isUnauthorized
import com.dld.homita.dashboard.data.repository.CalendarRepository
import com.dld.homita.dashboard.data.repository.ContentRepository
import com.dld.homita.dashboard.data.repository.MealRepository
import com.dld.homita.dashboard.data.repository.WeatherRepository
import com.dld.homita.dashboard.power.ScreenSchedule
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.io.File
import java.time.LocalDateTime

data class UiState(
    val token: String? = null,
    val email: String? = null,
    val now: LocalDateTime = LocalDateTime.now(),
    /** false mientras el reloj no se haya sincronizado (el RTC vuelve a la fecha de fábrica). */
    val clockValid: Boolean = false,
    val content: Content? = null,
    val forecast: Forecast? = null,
    /** Menú de hoy (`/meal/today`); null si no hay copia. La tarjeta lo oculta si es de otro día o no hay plan. */
    val meals: MealsToday? = null,
    val location: Location? = null,
    val schedule: Schedule = Schedule(),
    val brightness: Float? = null,
    /** Orden y filtro por prioridad de la pantalla de tareas (0037), guardados en Store. */
    val taskSort: TaskSort = TaskSort.LIST,
    val taskFilter: TaskPriority? = null,
    /** false si el último intento de sincronizar falló: se muestra lo que hay en caché. */
    val online: Boolean = true,
    /** Hay una red con salida a Internet (sin ella, el login muestra la espera y "Ir a Ajustes"). */
    val connected: Boolean = false,
    /** Sincronización manual en curso (botón de la barra lateral). */
    val syncing: Boolean = false,
    /** Semanas del calendario descargadas bajo demanda, por su lunes. */
    val weeks: Map<LocalDate, Week> = emptyMap(),
    val loginError: String? = null,
    /** La sesión caducó y no se pudo renovar: el login lo dice en vez de quedarse mudo. */
    val sessionExpired: Boolean = false,
    val loggingIn: Boolean = false,
    val geoResults: List<GeoResult> = emptyList(),
    val geoSearching: Boolean = false,
    /** Tocar el reloj nocturno enseña el dashboard hasta esta hora. */
    val peekUntil: LocalDateTime? = null,
    /** Reloj nocturno pedido con la luna de la barra lateral: hasta que se toque o hasta el siguiente encendido. */
    val nightUntil: LocalDateTime? = null
) {
    /** Reloj nocturno: fuera de horario (salvo mientras se mira el dashboard un momento) o pedido con la luna. */
    val night: Boolean
        get() = clockValid && token != null && (
            (nightUntil != null && now.isBefore(nightUntil)) ||
                (ScreenSchedule.isNight(schedule, now) && (peekUntil == null || !now.isBefore(peekUntil)))
            )
}

class DashboardViewModel(application: Application) : AndroidViewModel(application) {
    private val store = Store(application)
    private val api = Api.client
    private val cache = DiskCache(File(application.filesDir, "cache"))
    private val contentRepository = ContentRepository(api, cache)
    private val weatherRepository = WeatherRepository(api, cache)
    private val calendarRepository = CalendarRepository(api, cache)
    private val mealRepository = MealRepository(api, cache)
    private val clock = ReferenceClock(BuildConfig.BUILD_TIME, { store.lastValidTime }, { store.lastValidTime = it })
    private val session = Session(store, { refresh -> api.refresh(RefreshRequest(refresh)) })

    private val _state = MutableStateFlow(
        clock.current().let { time ->
            UiState(
                token = store.token,
                email = store.email,
                now = time.now,
                clockValid = time.valid,
                content = contentRepository.content.value?.value,
                forecast = weatherRepository.forecast.value?.value,
                meals = mealRepository.meals.value,
                weeks = calendarRepository.weeks.value,
                location = store.location,
                schedule = store.schedule,
                brightness = store.brightness,
                taskSort = store.taskSort,
                taskFilter = store.taskFilter
            )
        }
    )
    val state: StateFlow<UiState> = _state

    private val connectivity = application.getSystemService(ConnectivityManager::class.java)
    private val networkCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) =
            setConnected(capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))

        override fun onLost(network: Network) = setConnected(false)
    }

    init {
        // Los repositorios publican la copia en disco y cada descarga buena: la pantalla siempre tiene lo último.
        viewModelScope.launch { contentRepository.content.collect { c -> _state.update { it.copy(content = c?.value) } } }
        viewModelScope.launch { weatherRepository.forecast.collect { f -> _state.update { it.copy(forecast = f?.value) } } }
        viewModelScope.launch { mealRepository.meals.collect { m -> _state.update { it.copy(meals = m) } } }
        viewModelScope.launch { calendarRepository.weeks.collect { w -> _state.update { it.copy(weeks = w) } } }
        setConnected(connectivity.getNetworkCapabilities(connectivity.activeNetwork)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) == true)
        connectivity.registerDefaultNetworkCallback(networkCallback)
    }

    override fun onCleared() {
        connectivity.unregisterNetworkCallback(networkCallback)
    }

    /** Al recuperar la red se sincroniza enseguida, sin esperar al siguiente ciclo. */
    private fun setConnected(connected: Boolean) {
        val was = _state.value.connected
        _state.update { it.copy(connected = connected) }
        if (connected && !was) refreshNow()
    }

    /** Bucle mientras la actividad está visible: reloj cada minuto; contenido y tiempo cuando caducan (5 y 30 min). */
    suspend fun run() {
        while (true) {
            tick()
            if (_state.value.clockValid) {
                // dashboard-sesion: renovar antes de que el JWT caduque (y al arrancar, si ya toca).
                if (session.needsProactiveRenewal() && session.renew() is Session.Outcome.Rejected) logout(expired = true)
                if (contentRepository.isStale()) refreshContent()
                if (weatherRepository.isStale()) refreshWeather()
                if (mealRepository.isStale(_state.value.now.toLocalDate())) refreshMeals()
            }
            delay(60_000 - System.currentTimeMillis() % 60_000 + 50)
        }
    }

    private fun tick() {
        val time = clock.current()
        _state.update { it.copy(now = time.now, clockValid = time.valid) }
    }

    /** Fuerza la sincronización (al recuperar la red, tras iniciar sesión...). */
    fun refreshNow() {
        viewModelScope.launch {
            tick()
            if (!_state.value.clockValid) return@launch
            refreshContent()
            refreshWeather()
            refreshMeals()
        }
    }

    /** Sin hora válida no se pide nada: las fechas de la petición serían las de fábrica. */
    private suspend fun refreshContent() {
        if (_state.value.token == null) return
        report(session.authorized { contentRepository.refresh(it, LocalDate.now()) })
    }

    /**
     * El menú es opcional: si falla (sin permiso `menu.view`, hogar ambiguo, red) la tarjeta se queda con la copia o se
     * oculta, sin marcar el dashboard como sin conexión. Solo un 401 cierra la sesión.
     */
    private suspend fun refreshMeals() {
        if (_state.value.token == null) return
        val result = session.authorized { mealRepository.refresh(it, _state.value.now.toLocalDate()) }
        if (result.exceptionOrNull() is SessionExpired || result.exceptionOrNull()?.isUnauthorized == true) logout(expired = true)
    }

    private suspend fun refreshWeather() {
        val location = _state.value.location ?: return
        report(weatherRepository.refresh(location))
    }

    /** Carga la semana del calendario que empieza en [monday] si no está en caché o ha caducado. */
    fun loadWeek(monday: LocalDate) {
        if (_state.value.token == null) return
        if (!calendarRepository.isStale(monday)) return
        viewModelScope.launch { report(session.authorized { calendarRepository.refresh(it, monday) }) }
    }

    /** Orden de la pantalla de tareas (en cliente, sobre la caché). */
    fun setTaskSort(sort: TaskSort) {
        store.taskSort = sort
        _state.update { it.copy(taskSort = sort) }
    }

    /** Filtro por prioridad de la pantalla de tareas; null = todas. */
    fun setTaskFilter(filter: TaskPriority?) {
        store.taskFilter = filter
        _state.update { it.copy(taskFilter = filter) }
    }

    /**
     * Botón de sincronizar: vuelve a pedir el contenido de Hoy, las semanas del calendario ya cargadas y el
     * tiempo, aunque no hayan caducado. Dura al menos un segundo para que se vea el giro.
     */
    fun syncAll() {
        if (_state.value.syncing) return
        viewModelScope.launch {
            _state.update { it.copy(syncing = true) }
            val started = System.currentTimeMillis()
            tick()
            if (_state.value.clockValid) {
                refreshContent()
                if (_state.value.token != null) {
                    calendarRepository.loaded().forEach { monday -> report(session.authorized { calendarRepository.refresh(it, monday) }) }
                }
                refreshWeather()
                refreshMeals()
            }
            delay((1000 - (System.currentTimeMillis() - started)).coerceAtLeast(0))
            _state.update { it.copy(syncing = false) }
        }
    }

    /** Estado de la conexión según la última petición. Si falla, la pantalla sigue con la copia en caché. */
    private fun report(result: Result<*>) {
        if (_state.value.token == null) return
        val error = result.exceptionOrNull()
        when {
            error == null -> _state.update { it.copy(online = true) }
            error is SessionExpired || error.isUnauthorized -> logout(expired = true)
            else -> _state.update { it.copy(online = false) }
        }
    }

    fun login(email: String, password: String) {
        _state.update { it.copy(loggingIn = true, loginError = null) }
        viewModelScope.launch {
            try {
                val response = api.auth(AuthRequest(email.trim(), password))
                val token = response.body()?.token
                if (!response.isSuccessful || token == null) {
                    _state.update { it.copy(loggingIn = false, loginError = "Email o contraseña incorrectos") }
                    return@launch
                }
                store.token = token
                store.refreshToken = response.body()?.refresh_token
                store.email = email.trim()
                _state.update { it.copy(token = token, email = email.trim(), loggingIn = false, sessionExpired = false) }
                refreshNow()
            } catch (e: Exception) {
                _state.update { it.copy(loggingIn = false, loginError = "Sin conexión con el servidor") }
            }
        }
    }

    /** [expired]: la sesión caducó y no se pudo renovar; el login lo explica. */
    fun logout(expired: Boolean = false) {
        store.logout()
        contentRepository.clear()
        calendarRepository.clear()
        mealRepository.clear()
        _state.update { it.copy(token = null, sessionExpired = expired) }
    }

    fun searchLocation(query: String) {
        if (query.isBlank()) return
        _state.update { it.copy(geoSearching = true) }
        viewModelScope.launch {
            val results = runCatching { api.geocode(Api.geocodeUrl(query.trim())).body()?.results }.getOrNull().orEmpty()
            _state.update { it.copy(geoResults = results, geoSearching = false) }
        }
    }

    fun selectLocation(result: GeoResult) {
        val location = Location(
            name = result.name,
            detail = listOfNotNull(result.admin1, result.country).joinToString(", "),
            latitude = result.latitude,
            longitude = result.longitude
        )
        store.location = location
        weatherRepository.clear()
        _state.update { it.copy(location = location, geoResults = emptyList()) }
        viewModelScope.launch { refreshWeather() }
    }

    fun setSchedule(schedule: Schedule) {
        store.schedule = schedule
        _state.update { it.copy(schedule = schedule) }
        ScreenSchedule.reschedule(getApplication())
    }

    /**
     * Desde el reloj nocturno: vuelve el dashboard. Fuera de horario, solo durante [ScreenSchedule.GRACE_MINUTES];
     * el reloj pedido con la luna se quita del todo.
     */
    fun peek() {
        _state.update { it.copy(peekUntil = LocalDateTime.now().plusMinutes(ScreenSchedule.GRACE_MINUTES), nightUntil = null) }
    }

    /**
     * La luna de la barra lateral. Con el horario y el reloj nocturno activos, pasa al reloj (hasta que se toque o
     * hasta el siguiente encendido) y devuelve true; si no, false y la pantalla se apaga de verdad.
     */
    fun nightNow(): Boolean {
        val schedule = _state.value.schedule
        if (!schedule.enabled || schedule.screenOff || !_state.value.clockValid) return false
        _state.update { it.copy(nightUntil = ScreenSchedule.nextOn(schedule, it.now), peekUntil = null) }
        return true
    }

    fun setBrightness(value: Float?) {
        store.brightness = value
        _state.update { it.copy(brightness = value) }
    }
}

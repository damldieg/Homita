package com.dld.homita.dashboard

import android.app.Application
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.dld.homita.dashboard.data.Api
import com.dld.homita.dashboard.data.Diagnostics
import com.dld.homita.dashboard.data.HttpError
import com.dld.homita.dashboard.data.DisplayApi
import com.dld.homita.dashboard.data.DisplayConfig
import com.dld.homita.dashboard.data.DisplayPoll
import com.dld.homita.dashboard.data.DisplayPollRequest
import com.dld.homita.dashboard.data.DisplayLinkStart
import com.dld.homita.dashboard.data.Pairing
import com.dld.homita.dashboard.data.PairingApi
import com.dld.homita.dashboard.data.PairingState
import com.dld.homita.dashboard.data.bodyOrThrow
import com.dld.homita.dashboard.data.repository.bearer
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
    /** Hora de la última descarga buena del contenido de Hoy (epoch ms), para «Actualizado hace X» (U7). */
    val contentFetchedAt: Long? = null,
    /** Avisos de vencimiento cerrados (N4), guardados en Store. */
    val dismissedDue: Set<String> = emptySet(),
    /** Vinculación de la pantalla con el hogar (sin sesión): código a la vista o estado de espera. */
    val pairing: PairingState = PairingState.Idle,
    /** Acceso técnico (formulario de email y contraseña), tras cinco toques en el logo (Q4). */
    val technical: Boolean = false,
    /** Último resultado de cada dato remoto, para Ajustes → Diagnóstico (N6). */
    val diagnostics: Map<String, Diagnostics.Entry> = emptyMap(),
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
    private val diagnostics = Diagnostics()
    private val displayApi = DisplayApi.client
    private var configFetchedAt = 0L
    private val logoTaps = ArrayDeque<Long>()
    private val pairing = Pairing(object : PairingApi {
        override suspend fun linkStart(): Result<DisplayLinkStart> = runCatching { displayApi.linkStart().bodyOrThrow() }
        override suspend fun linkPoll(secret: String): Result<DisplayPoll> =
            runCatching { displayApi.linkPoll(DisplayPollRequest(secret)).bodyOrThrow() }
    })

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
                dismissedDue = store.dismissedDue
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
        viewModelScope.launch { contentRepository.content.collect { c -> _state.update { it.copy(content = c?.value, contentFetchedAt = c?.fetchedAt) } } }
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
                // Pantalla del hogar: su configuración se relee cada 5 minutos (lo que decide el móvil)
                if (store.displayId != null && System.currentTimeMillis() - configFetchedAt >= CONFIG_MAX_AGE_MS) refreshDisplayConfig()
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
        recordDiagnostic("menú de hoy", result)
        if (result.exceptionOrNull() is SessionExpired || result.exceptionOrNull()?.isUnauthorized == true) logout(expired = true)
    }

    /** Relee la configuración de la pantalla (horario, brillo, ubicación) y la aplica. Sin red, queda la última. */
    private suspend fun refreshDisplayConfig() {
        if (store.displayId == null || _state.value.token == null) return
        val result = session.authorized { token -> runCatching { displayApi.config(bearer(token)).bodyOrThrow() } }
        recordDiagnostic("configuración de la pantalla", result)
        val error = result.exceptionOrNull()
        // 401: la sesión ya no vale. 404: el hogar revocó la pantalla (su configuración ya no existe): vuelve a vincularse.
        if (error is SessionExpired || error?.isUnauthorized == true || (error is HttpError && error.code == 404)) {
            logout(expired = true)
            return
        }
        result.onSuccess { applyDisplayConfig(it) }
    }

    /** La configuración del hogar manda: brillo, horario y ubicación de la pantalla se guardan como los de la app. */
    private fun applyDisplayConfig(config: DisplayConfig) {
        configFetchedAt = System.currentTimeMillis()
        val settings = config.settings ?: return
        store.brightness = settings.brightness?.toFloat()?.coerceIn(0.05f, 1f)
        settings.schedule?.let { store.schedule = it }
        settings.location?.let { store.location = it }
        _state.update { it.copy(brightness = store.brightness, schedule = store.schedule, location = store.location) }
        ScreenSchedule.reschedule(getApplication())
        // Una selección nueva de calendarios o listas cambia el contenido: se descarga ya, sin esperar a caducar
        refreshNow()
    }

    private fun recordDiagnostic(endpoint: String, result: Result<*>) {
        diagnostics.record(endpoint, result)
        _state.update { it.copy(diagnostics = diagnostics.snapshot()) }
    }

    /**
     * Vinculación de la pantalla (sin sesión): pide código y sondea cada 3 s hasta que el móvil lo confirma. Mientras
     * hay sesión no hace nada; sin red espera.
     */
    suspend fun runPairing() {
        while (true) {
            if (_state.value.token == null && _state.value.connected) {
                val current = _state.value.pairing
                val next = when (current) {
                    is PairingState.Waiting -> pairing.poll(current)
                    is PairingState.Linked -> pairing.start()
                    else -> pairing.start()
                }
                if (next is PairingState.Linked) {
                    store.token = next.token
                    store.refreshToken = next.refreshToken
                    store.displayId = next.displayId
                    store.email = null
                    _state.update { it.copy(token = next.token, email = null, pairing = PairingState.Idle, sessionExpired = false) }
                    refreshNow()
                    refreshDisplayConfig()
                } else {
                    _state.update { it.copy(pairing = next) }
                }
            }
            delay(PAIRING_POLL_MS)
        }
    }

    /**
     * Cinco toques en el logo en menos de tres segundos muestran el formulario de email y contraseña (modo técnico, Q4).
     */
    fun logoTap() {
        // En el formulario técnico, un toque vuelve al código de vinculación
        if (_state.value.technical) {
            _state.update { it.copy(technical = false) }
            return
        }
        val now = System.currentTimeMillis()
        logoTaps.addLast(now)
        while (logoTaps.isNotEmpty() && now - logoTaps.first() > TECHNICAL_TAP_WINDOW_MS) logoTaps.removeFirst()
        if (logoTaps.size >= TECHNICAL_TAPS) {
            logoTaps.clear()
            _state.update { it.copy(technical = !it.technical) }
        }
    }

    private suspend fun refreshWeather() {
        val location = _state.value.location ?: return
        report(weatherRepository.refresh(location), "tiempo")
    }

    /** Carga la semana del calendario que empieza en [monday] si no está en caché o ha caducado. */
    fun loadWeek(monday: LocalDate) {
        if (_state.value.token == null) return
        if (!calendarRepository.isStale(monday)) return
        viewModelScope.launch { report(session.authorized { calendarRepository.refresh(it, monday) }, "calendario") }
    }

    /** Cierra el aviso de vencimiento de [key] (N4): no vuelve tras reiniciar el marco. */
    fun dismissDue(key: String) {
        val dismissed = _state.value.dismissedDue + key
        store.dismissedDue = dismissed
        _state.update { it.copy(dismissedDue = store.dismissedDue) }
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
                    calendarRepository.loaded().forEach { monday -> report(session.authorized { calendarRepository.refresh(it, monday) }, "calendario") }
                }
                refreshWeather()
                refreshMeals()
            }
            delay((1000 - (System.currentTimeMillis() - started)).coerceAtLeast(0))
            _state.update { it.copy(syncing = false) }
        }
    }

    /** Estado de la conexión según la última petición. Si falla, la pantalla sigue con la copia en caché. */
    private fun report(result: Result<*>, endpoint: String = "eventos y tareas") {
        if (_state.value.token == null) return
        recordDiagnostic(endpoint, result)
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
        configFetchedAt = 0L
        _state.update { it.copy(token = null, sessionExpired = expired, pairing = PairingState.Idle) }
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

    private companion object {
        /** La configuración de la pantalla se relee cada 5 minutos. */
        const val CONFIG_MAX_AGE_MS = 5 * 60_000L
        /** Intervalo de sondeo de la vinculación. */
        const val PAIRING_POLL_MS = 3_000L
        /** Toques en el logo para el modo técnico, dentro de la ventana. */
        const val TECHNICAL_TAPS = 5
        const val TECHNICAL_TAP_WINDOW_MS = 3_000L
    }
}

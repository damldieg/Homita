package com.dld.homita.dashboard.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.dld.homita.dashboard.UiState
import com.dld.homita.dashboard.ui.theme.Palette
import com.dld.homita.dashboard.ui.theme.Type

/**
 * El tiempo a pantalla completa: 24 horas (de 4 antes de la actual a 19 después, con iconos) y 8 días (Q1: la segunda
 * página se quita). Se abre tocando la tarjeta del tiempo de Hoy; «atrás» o 2 minutos sin tocar vuelven a Hoy.
 */
@Composable
fun WeatherScreen(state: UiState) {
    val forecast = state.forecast
    val location = state.location
    ScreenPadding {
        if (forecast == null || location == null) {
            Text(if (location == null) "Elige una ubicación en Ajustes" else "Cargando previsión…", style = Type.Large.copy(color = Palette.InkMuted))
            return@ScreenPadding
        }
        Column(Modifier.fillMaxSize()) {
            WeatherCard(forecast, location.name, state.now, days = 8, modifier = Modifier.fillMaxSize())
        }
    }
}

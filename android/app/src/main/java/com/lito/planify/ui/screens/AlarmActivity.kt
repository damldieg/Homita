package com.lito.planify.ui.screens

import android.app.KeyguardManager
import android.content.Context
import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Alarm
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import com.lito.planify.ui.components.currentLocale
import com.lito.planify.R
import com.lito.planify.ui.theme.PlanifyTheme
import com.lito.planify.util.AlarmHelper
import com.lito.planify.ui.theme.*

class AlarmActivity : ComponentActivity() {
    private var ringtone: Ringtone? = null
    private var vibrator: Vibrator? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            keyguardManager.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_ALLOW_LOCK_WHILE_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }

        val eventTitle = intent.getStringExtra("eventTitle") ?: "Evento"
        val calendarName = intent.getStringExtra("calendarName")
        val calendarColorHex = intent.getStringExtra("calendarColor") ?: "#0B57D0"
        val calendarColor = try { Color(android.graphics.Color.parseColor(calendarColorHex)) } catch(e: Exception) { PrimaryColor }

        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        ringtone = RingtoneManager.getRingtone(applicationContext, alarmUri)
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            ringtone?.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        }
        ringtone?.play()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as android.os.VibratorManager
            vibrator = vibratorManager.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        
        vibrator?.vibrate(VibrationEffect.createWaveform(longArrayOf(0, 500, 500), 0))

        setContent {
            PlanifyTheme {
                var currentTime by remember { mutableLongStateOf(System.currentTimeMillis()) }
                LaunchedEffect(Unit) {
                    while (true) {
                        delay(1000)
                        currentTime = System.currentTimeMillis()
                    }
                }
                
                val locale = currentLocale()
                val timeStr = SimpleDateFormat("H:mm", locale).format(Date(currentTime))
                val dateStr = SimpleDateFormat("EEEE, d 'de' MMMM", locale).format(Date(currentTime)).replaceFirstChar { it.uppercase() }

                Surface(
                    modifier = Modifier.fillMaxSize().background(BackgroundBrush),
                    color = Color.Transparent
                ) {
                    Column(modifier = Modifier.fillMaxSize().systemBarsPadding()) {
                        Spacer(modifier = Modifier.height(80.dp))
                        
                        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                            Text(
                                text = timeStr,
                                style = MaterialTheme.typography.displayLarge.copy(
                                    fontSize = 96.sp,
                                    lineHeight = 96.sp,
                                    fontWeight = FontWeight.Black
                                ),
                                color = OnSurfaceColor
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = dateStr,
                                style = MaterialTheme.typography.bodyLarge,
                                color = OnSurfaceVariantColor
                            )
                        }
                        
                        Spacer(modifier = Modifier.weight(1f))
                        
                        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                            Box(
                                modifier = Modifier.size(180.dp),
                                contentAlignment = Alignment.Center
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(160.dp)
                                        .background(Brush.radialGradient(listOf(calendarColor.copy(alpha = 0.3f), Color.Transparent)), CircleShape)
                                )
                                Box(
                                    modifier = Modifier
                                        .size(100.dp)
                                        .background(calendarColor, CircleShape),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        Icons.Default.Alarm,
                                        contentDescription = null,
                                        tint = Color.White,
                                        modifier = Modifier.size(50.dp)
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.height(24.dp))
                            Text(
                                text = eventTitle,
                                style = MaterialTheme.typography.headlineMedium.copy(
                                    fontSize = 28.sp
                                ),
                                color = OnSurfaceColor,
                                textAlign = TextAlign.Center,
                                modifier = Modifier.padding(horizontal = 24.dp)
                            )
                            if (calendarName != null) {
                                Text(
                                    text = calendarName,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = OnSurfaceVariantColor,
                                    modifier = Modifier.padding(top = 8.dp)
                                )
                            }
                        }
                        
                        Spacer(modifier = Modifier.weight(1f))
                        
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(24.dp)
                                .padding(bottom = 24.dp),
                            horizontalArrangement = Arrangement.Center
                        ) {
                            Button(
                                onClick = { finish() },
                                modifier = Modifier.weight(1f).height(56.dp),
                                shape = CircleShape,
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = OnSurfaceColor,
                                    contentColor = Color.White
                                )
                            ) {
                                Icon(Icons.Default.Stop, contentDescription = null, modifier = Modifier.size(16.dp))
                                Spacer(modifier = Modifier.width(8.dp))
                                Text(stringResource(R.string.alarm_stop), fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        ringtone?.stop()
        vibrator?.cancel()
    }
}

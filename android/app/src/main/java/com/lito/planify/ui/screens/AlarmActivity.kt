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
import java.util.Locale
import com.lito.planify.R
import com.lito.planify.ui.theme.PlanifyTheme
import com.lito.planify.util.AlarmHelper

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
        val calendarColor = try { Color(android.graphics.Color.parseColor(calendarColorHex)) } catch(e: Exception) { Color(0xFF0B57D0) }

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
        
        val pattern = longArrayOf(0, 500, 500)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }

        setContent {
            PlanifyTheme {
                var currentTime by remember { mutableLongStateOf(System.currentTimeMillis()) }
                LaunchedEffect(Unit) {
                    while (true) {
                        delay(1000)
                        currentTime = System.currentTimeMillis()
                    }
                }
                
                val timeStr = SimpleDateFormat("H:mm", Locale.getDefault()).format(Date(currentTime))
                val dateStr = SimpleDateFormat("EEEE, d 'de' MMMM", Locale.getDefault()).format(Date(currentTime)).replaceFirstChar { it.uppercase() }

                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = Color(0xFFF9F9F9)
                ) {
                    Column(modifier = Modifier.fillMaxSize()) {
                        Spacer(modifier = Modifier.height(80.dp))
                        
                        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                            Text(
                                text = timeStr,
                                style = MaterialTheme.typography.displayLarge.copy(
                                    fontSize = 80.sp,
                                    fontFamily = FontFamily.Serif,
                                    fontWeight = FontWeight.Light
                                ),
                                color = Color(0xFF1D1B20)
                            )
                            Spacer(modifier = Modifier.height(8.dp))
                            Text(
                                text = dateStr,
                                style = MaterialTheme.typography.bodyLarge,
                                color = Color(0xFF757575)
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
                                    fontFamily = FontFamily.Serif,
                                    fontSize = 28.sp
                                ),
                                color = Color(0xFF1D1B20),
                                textAlign = TextAlign.Center,
                                modifier = Modifier.padding(horizontal = 24.dp)
                            )
                            if (calendarName != null) {
                                Text(
                                    text = calendarName,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = Color(0xFF757575),
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
                                shape = RoundedCornerShape(16.dp),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = Color(0xFF1D1B20),
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

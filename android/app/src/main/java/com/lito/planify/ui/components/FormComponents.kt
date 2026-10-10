package com.lito.planify.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.outlined.Notifications
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.lito.planify.R
import com.lito.planify.ui.theme.*
import kotlinx.coroutines.launch
import java.time.DayOfWeek
import java.time.format.TextStyle
import java.util.Locale

/**
 * Hoja inferior común a todos los formularios: título, contenido y botonera
 * (borrar · cancelar · guardar). Sin [confirmText] solo muestra "Cerrar".
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlanifyFormSheet(
    title: String,
    onDismiss: () -> Unit,
    confirmText: String? = null,
    confirmEnabled: Boolean = true,
    onConfirm: () -> Unit = {},
    onDelete: (() -> Unit)? = null,
    enabled: Boolean = true,
    content: @Composable ColumnScope.() -> Unit
) {
    var showDeleteConfirm by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()

    fun closeWithAnimation(action: () -> Unit) {
        scope.launch { sheetState.hide() }.invokeOnCompletion { if (!sheetState.isVisible) action() }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        dragHandle = { BottomSheetDefaults.DragHandle(width = 36.dp, height = 4.dp, color = OutlineColor) },
        containerColor = MaterialTheme.colorScheme.surface,
        shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Text(text = title, style = MaterialTheme.typography.headlineSmall, color = OnSurfaceColor)

            content()

            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.padding(top = 8.dp).fillMaxWidth()
            ) {
                if (confirmText == null) {
                    OutlinedActionButton(text = stringResource(R.string.generic_close), onClick = { closeWithAnimation(onDismiss) }, modifier = Modifier.fillMaxWidth())
                } else {
                    if (onDelete != null) {
                        IconButton(onClick = { showDeleteConfirm = true }, enabled = enabled, modifier = Modifier.size(48.dp)) {
                            Icon(Icons.Default.Delete, contentDescription = stringResource(R.string.generic_delete), tint = MaterialTheme.colorScheme.error)
                        }
                    }
                    OutlinedActionButton(text = stringResource(R.string.generic_cancel), onClick = { closeWithAnimation(onDismiss) }, enabled = enabled, modifier = Modifier.weight(1f))
                    PrimaryButton(text = confirmText, onClick = { closeWithAnimation(onConfirm) }, enabled = enabled && confirmEnabled, modifier = Modifier.weight(1f))
                }
            }
        }
    }

    if (showDeleteConfirm && onDelete != null) {
        AlertDialog(
            onDismissRequest = { showDeleteConfirm = false },
            containerColor = MaterialTheme.colorScheme.surface,
            title = { Text(stringResource(R.string.delete_confirm_title)) },
            text = { Text(stringResource(R.string.delete_confirm_text)) },
            confirmButton = {
                TextButton(onClick = {
                    showDeleteConfirm = false
                    closeWithAnimation(onDelete)
                }) {
                    Text(stringResource(R.string.generic_delete), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirm = false }) {
                    Text(stringResource(R.string.generic_cancel))
                }
            }
        )
    }
}

/** Etiqueta pequeña sobre controles que no son campos de texto (color, días...). */
@Composable
fun FormLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.labelLarge,
        color = OnSurfaceVariantColor,
        modifier = Modifier.padding(start = 4.dp, top = 4.dp, bottom = 2.dp)
    )
}

/** Campo de solo lectura que abre un selector (fecha, hora...). */
@Composable
fun FormPickerField(
    label: String,
    value: String,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true
) {
    Box(modifier = modifier) {
        CustomTextField(
            value = value,
            onValueChange = {},
            label = label,
            readOnly = true,
            enabled = enabled,
            leadingIcon = { Icon(icon, null, tint = OnSurfaceVariantColor) }
        )
        Box(
            modifier = Modifier
                .matchParentSize()
                .padding(top = 8.dp)
                .clip(RoundedCornerShape(12.dp))
                .clickable(enabled = enabled, onClick = onClick)
        )
    }
}

/** Desplegable con el mismo aspecto que los campos de texto. [colorOf] pinta un punto de color por opción. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun <T> FormSelectField(
    label: String,
    selected: T,
    options: List<Pair<T, String>>,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    icon: ImageVector? = null,
    colorOf: ((T) -> Color)? = null
) {
    var expanded by remember { mutableStateOf(false) }
    val dot: @Composable (T) -> Unit = { Box(Modifier.size(12.dp).background(colorOf!!(it), CircleShape)) }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { if (enabled) expanded = !expanded },
        modifier = modifier
    ) {
        CustomTextField(
            value = options.find { it.first == selected }?.second.orEmpty(),
            onValueChange = {},
            label = label,
            readOnly = true,
            enabled = enabled,
            leadingIcon = when {
                colorOf != null -> { { dot(selected) } }
                icon != null -> { { Icon(icon, null, tint = OnSurfaceVariantColor) } }
                else -> null
            },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            modifier = Modifier.menuAnchor().fillMaxWidth()
        )
        ExposedDropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
            modifier = Modifier.background(MaterialTheme.colorScheme.surface)
        ) {
            options.forEach { (value, text) ->
                DropdownMenuItem(
                    text = { Text(text) },
                    leadingIcon = colorOf?.let { { dot(value) } },
                    onClick = {
                        onSelect(value)
                        expanded = false
                    }
                )
            }
        }
    }
}

/** Fila con interruptor sobre fondo suave, igual en todos los formularios. */
@Composable
fun FormSwitchRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    icon: ImageVector? = null,
    enabled: Boolean = true
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(RoundedCornerShape(12.dp))
            .background(PillFillColor)
            .clickable(enabled = enabled) { onCheckedChange(!checked) }
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = OnSurfaceVariantColor, modifier = Modifier.size(22.dp))
        }
        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.SemiBold),
            color = OnSurfaceColor,
            modifier = Modifier.weight(1f)
        )
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            enabled = enabled,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = PrimaryColor,
                uncheckedThumbColor = Color.White,
                uncheckedTrackColor = OutlineColor,
                uncheckedBorderColor = Color.Transparent
            )
        )
    }
}

/** Selector de aviso compartido por eventos y rutinas. */
@Composable
fun AlarmSelectField(alarm: Int?, onChange: (Int?) -> Unit, enabled: Boolean = true) {
    FormSelectField(
        label = stringResource(R.string.label_alarm),
        selected = alarm,
        options = listOf(
            null to stringResource(R.string.alarm_no),
            0 to stringResource(R.string.alarm_0),
            10 to stringResource(R.string.alarm_10),
            20 to stringResource(R.string.alarm_20),
            30 to stringResource(R.string.alarm_30),
            40 to stringResource(R.string.alarm_40),
            60 to stringResource(R.string.alarm_60)
        ),
        onSelect = onChange,
        enabled = enabled,
        icon = Icons.Outlined.Notifications
    )
}

/** Días de la semana (ISO 1-7) como círculos seleccionables. */
@Composable
fun WeekdaySelector(days: List<Int>, onChange: (List<Int>) -> Unit, enabled: Boolean = true) {
    val locale = Locale.getDefault()
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        (1..7).forEach { day ->
            val selected = day in days
            val dayOfWeek = DayOfWeek.of(day)
            Box(
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(if (selected) PrimaryColor else PillFillColor)
                    .clickable(enabled = enabled) { onChange(if (selected) days - day else (days + day).sorted()) }
                    .semantics { contentDescription = dayOfWeek.getDisplayName(TextStyle.FULL, locale) },
                contentAlignment = Alignment.Center
            ) {
                Text(
                    text = dayOfWeek.getDisplayName(TextStyle.NARROW, locale).uppercase(locale),
                    style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Bold),
                    color = if (selected) Color.White else OnSurfaceVariantColor
                )
            }
        }
    }
}

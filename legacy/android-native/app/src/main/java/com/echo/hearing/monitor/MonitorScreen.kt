package com.echo.hearing.monitor

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.echo.hearing.ui.components.*
import com.echo.hearing.ui.theme.*
import java.util.Locale
import kotlin.math.roundToInt

private enum class MonitorSubScreen {
    MAIN,
    EXPOSURE_HISTORY,
    EXPOSURE_DETAILS,
    SETTINGS
}

@Composable
fun MonitorScreen(
    vm: MonitorViewModel,
    modifier: Modifier = Modifier,
    openSettingsInitially: Boolean = false
) {
    val s by vm.state.collectAsState()
    val context = LocalContext.current
    var subScreen by remember { mutableStateOf(if (openSettingsInitially) MonitorSubScreen.SETTINGS else MonitorSubScreen.MAIN) }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) vm.start() else vm.onPermissionDenied()
    }
    val startOrAsk = {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            vm.start()
        } else {
            permission.launch(Manifest.permission.RECORD_AUDIO)
        }
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(EchoBg)
    ) {
        when (subScreen) {
            MonitorSubScreen.MAIN -> MonitorMainScreen(
                s = s,
                vm = vm,
                onStartOrAsk = startOrAsk,
                onOpenHistory = { subScreen = MonitorSubScreen.EXPOSURE_HISTORY },
                onOpenDetails = { subScreen = MonitorSubScreen.EXPOSURE_DETAILS },
                onOpenSettings = { subScreen = MonitorSubScreen.SETTINGS }
            )

            MonitorSubScreen.EXPOSURE_HISTORY -> ExposureHistoryScreen(
                s = s,
                onBack = { subScreen = MonitorSubScreen.MAIN }
            )

            MonitorSubScreen.EXPOSURE_DETAILS -> ExposureDetailsScreen(
                s = s,
                onBack = { subScreen = MonitorSubScreen.MAIN }
            )

            MonitorSubScreen.SETTINGS -> MonitoringSettingsScreen(
                s = s,
                vm = vm,
                onBack = { subScreen = MonitorSubScreen.MAIN }
            )
        }
    }
}

@Composable
private fun MonitorMainScreen(
    s: MonitorUiState,
    vm: MonitorViewModel,
    onStartOrAsk: () -> Unit,
    onOpenHistory: () -> Unit,
    onOpenDetails: () -> Unit,
    onOpenSettings: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Sound Monitoring",
            actions = {
                EchoStatusPill(
                    label = if (s.running) "Live Oboe DSP" else "Sample data",
                    icon = if (s.running) Icons.Filled.GraphicEq else Icons.Outlined.Info,
                    containerColor = if (s.running) EmeraldSoft else EchoSurfaceAlt,
                    borderColor = if (s.running) Emerald500 else EchoPillBorder,
                    contentColor = if (s.running) Emerald500 else EchoPrimary
                )
            }
        )

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // Live Sound Monitor Card (Image 4)
            EchoCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "Live Sound Monitor",
                        color = EchoNavy,
                        fontSize = 18.sp,
                        fontWeight = FontWeight.Bold
                    )
                    EchoStatusPill(
                        label = if (s.running) "Live DSP" else "Sample data",
                        icon = Icons.Outlined.Info
                    )
                }

                Spacer(modifier = Modifier.height(14.dp))

                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp)
                ) {
                    Icon(
                        imageVector = if (s.running) Icons.Filled.Mic else Icons.Outlined.Mic,
                        contentDescription = null,
                        tint = if (s.running) Emerald500 else EchoPrimary,
                        modifier = Modifier.size(34.dp)
                    )
                    Column {
                        Text(
                            text = if (s.running) "Monitoring Active" else "Moderate Level",
                            color = if (s.running) Emerald500 else EchoPrimary,
                            fontSize = 24.sp,
                            fontWeight = FontWeight.ExtraBold
                        )
                        Text(
                            text = if (s.running) s.status.lineSequence().firstOrNull() ?: "Live audio active"
                            else "Comfortable ambient environment",
                            color = EchoTextMuted,
                            fontSize = 13.5.sp
                        )
                    }
                }

                Spacer(modifier = Modifier.height(16.dp))
                HorizontalDivider(color = EchoBorder)
                Spacer(modifier = Modifier.height(12.dp))

                // Real Oboe DSP Route, Volume Trim, Processed/Baseline A/B & Start/Stop
                DevicePicker("Microphone", s.inputs, s.inputId, !s.running, vm::selectInput)
                Spacer(modifier = Modifier.height(8.dp))
                DevicePicker("Output (earbuds)", s.outputs, s.outputId, !s.running, vm::selectOutput)
                Spacer(modifier = Modifier.height(8.dp))

                LabeledSlider(
                    label = "Volume trim: ${(s.monitorLevel * 100).roundToInt()}% (max 50%)",
                    value = s.monitorLevel,
                    range = 0f..MonitorLimits.MAX_MONITOR_LEVEL,
                    steps = 49,
                    onChange = vm::setMonitorLevel
                )

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Processed Mode (A/B)", color = EchoNavy, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
                        Text(
                            if (s.processed) "ECHO 4-band DSP + EQ active" else "Baseline (raw bypass)",
                            color = EchoTextMuted,
                            fontSize = 12.sp
                        )
                    }
                    Switch(
                        checked = s.processed,
                        onCheckedChange = vm::setProcessed,
                        colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = EchoPrimary)
                    )
                }

                Spacer(modifier = Modifier.height(10.dp))

                if (s.running) {
                    EchoPrimaryButton(
                        text = "Stop Monitor",
                        icon = Icons.Default.Stop,
                        containerColor = Rose500,
                        onClick = { vm.stop() }
                    )
                } else {
                    EchoPrimaryButton(
                        text = "Start Live Monitor",
                        icon = Icons.Default.PlayArrow,
                        onClick = onStartOrAsk
                    )
                }

                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = s.status,
                    color = if (s.running) EchoPrimary else EchoTextMuted,
                    fontSize = 12.sp,
                    lineHeight = 17.sp
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Start with low phone and earbud volume. Prototype only; not a hearing aid. Digital limits are not calibrated to dB SPL.",
                    color = Amber500,
                    fontSize = 11.5.sp,
                    lineHeight = 16.sp
                )
            }

            // Three signature pill buttons from Image 4
            EchoOutlinedPillButton(
                text = "View Exposure History",
                icon = Icons.Outlined.History,
                onClick = onOpenHistory
            )
            EchoOutlinedPillButton(
                text = "Exposure Details",
                icon = Icons.Outlined.Assessment,
                onClick = onOpenDetails
            )
            EchoOutlinedPillButton(
                text = "Monitoring Settings (DSP, EQ, Audiogram & A/B Log)",
                icon = Icons.Outlined.Settings,
                onClick = onOpenSettings
            )
        }
    }
}

@Composable
private fun ExposureHistoryScreen(
    s: MonitorUiState,
    onBack: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Exposure History",
            onBack = onBack,
            actions = { EchoStatusPill(label = if (s.trials.isEmpty()) "Sample data" else "${s.trials.size} logs") }
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Text("Recent Ambient Exposure (Sample)", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(8.dp))
                val samples = listOf(
                    "Today · 09:30 AM · Quiet Room · Comfortable",
                    "Today · 11:15 AM · Commute · Moderate Level",
                    "Yesterday · 06:00 PM · Cafe · Moderate Level"
                )
                samples.forEach { item ->
                    Text("• $item", color = EchoTextMuted, fontSize = 13.5.sp, lineHeight = 22.sp)
                }
            }

            EchoCard {
                Text("Saved Speech Clarity A/B Logs", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(8.dp))
                if (s.trials.isEmpty()) {
                    Text(
                        "No clarity trials logged yet. Open Monitoring Settings → Speech clarity A/B log to record Processed vs Baseline word scores.",
                        color = EchoTextMuted,
                        fontSize = 13.sp,
                        lineHeight = 19.sp
                    )
                } else {
                    s.trials.forEach { row ->
                        Text("• $row", color = EchoNavy, fontSize = 12.5.sp, lineHeight = 20.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun ExposureDetailsScreen(
    s: MonitorUiState,
    onBack: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(
            title = "Exposure Details",
            onBack = onBack,
            actions = { EchoStatusPill(label = if (s.running) "Live" else "Sample data") }
        )
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            EchoCard {
                Text("Audio Stream & DSP Pipeline", color = EchoNavy, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(10.dp))
                DetailRow("Monitor State", if (s.running) "Running (Oboe Full-Duplex)" else "Stopped")
                DetailRow("Processing Mode", if (s.processed) "Processed (4-band LR4 + EQ)" else "Baseline (Bypass)")
                DetailRow("Volume Trim", "${(s.monitorLevel * 100).roundToInt()}% (capped at 50%)")
                DetailRow("Noise Gate", if (s.gateEnabled) "On (${s.gateThresholdDb.roundToInt()} dBFS)" else "Off")
                DetailRow("Adaptive Denoiser", if (s.denoiserEnabled) "On (max ${s.denoiserStrengthDb.roundToInt()} dB)" else "Off")
                DetailRow("Speech Compression", if (s.compressionEnabled) "On (${String.format(Locale.US, "%.1f:1", s.compressionRatio)})" else "Off")
            }

            EchoCard {
                Text("Stream Diagnostics", color = EchoNavy, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                Spacer(modifier = Modifier.height(6.dp))
                Text(s.status, color = EchoTextMuted, fontSize = 13.sp, lineHeight = 19.sp)
            }
        }
    }
}

@Composable
private fun DetailRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 5.dp),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, color = EchoTextMuted, fontSize = 13.5.sp)
        Text(value, color = EchoNavy, fontSize = 13.5.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun MonitoringSettingsScreen(
    s: MonitorUiState,
    vm: MonitorViewModel,
    onBack: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        EchoTopBar(title = "Monitoring Settings", onBack = onBack)
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(20.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Section("Noise and speech processing", initiallyOpen = true) {
                ToggleRow("Noise gate (quiet-period hiss)", s.gateEnabled, vm::setGateEnabled)
                if (s.gateEnabled) {
                    LabeledSlider(
                        "Threshold: ${s.gateThresholdDb.roundToInt()} dBFS",
                        s.gateThresholdDb,
                        MonitorLimits.MIN_GATE_THRESHOLD_DB..MonitorLimits.MAX_GATE_THRESHOLD_DB,
                        35,
                        vm::setGateThreshold
                    )
                }
                ToggleRow("Adaptive noise reduction (experimental)", s.denoiserEnabled, vm::setDenoiserEnabled)
                if (s.denoiserEnabled) {
                    LabeledSlider(
                        "Max attenuation: ${s.denoiserStrengthDb.roundToInt()} dB",
                        s.denoiserStrengthDb,
                        0f..MonitorLimits.MAX_DENOISER_DB,
                        17,
                        vm::setDenoiserStrength
                    )
                }
                ToggleRow("Speech compression (4-band)", s.compressionEnabled, vm::setCompressionEnabled)
                if (s.compressionEnabled) {
                    LabeledSlider(
                        String.format(Locale.US, "Ratio: %.1f:1", s.compressionRatio),
                        s.compressionRatio,
                        1f..3f,
                        19
                    ) { vm.setCompressionRatio((it * 10).roundToInt() / 10f) }
                }
            }

            Section("Hearing profile (6-band per-ear EQ)") {
                Text(
                    "Fitting gain offsets, ±6 dB per band. Use only gains from an audiogram-based fitting.",
                    color = EchoTextMuted,
                    fontSize = 12.sp
                )
                listOf("Left ear", "Right ear").forEachIndexed { ear, name ->
                    Text(name, color = EchoPrimary, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    MonitorLimits.EQ_CENTERS_HZ.forEachIndexed { band, hz ->
                        LabeledSlider(
                            "${freq(hz)}: ${String.format(Locale.US, "%+.1f", s.gains[ear][band])} dB",
                            s.gains[ear][band],
                            -MonitorLimits.MAX_GAIN_DB..MonitorLimits.MAX_GAIN_DB,
                            23
                        ) { vm.setGain(ear, band, (it * 2).roundToInt() / 2f) }
                    }
                }
            }

            Section("Audiogram and verification record") {
                Text(
                    "Reference only: thresholds do not change any gain. Enter dB HL from a professional audiogram, or import the latest ECHO screening (uncalibrated).",
                    color = EchoTextMuted,
                    fontSize = 12.sp
                )
                EchoOutlinedPillButton(
                    text = "Import latest screening",
                    icon = Icons.Outlined.Download,
                    onClick = vm::importLatestScreening
                )
                if (s.importMessage.isNotEmpty()) {
                    Text(s.importMessage, fontSize = 12.sp, color = EchoPrimary)
                }
                listOf("Left ear", "Right ear").forEachIndexed { ear, name ->
                    Text("$name (dB HL)", color = EchoPrimary, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                    MonitorLimits.EQ_CENTERS_HZ.toList().chunked(3).forEachIndexed { rowIdx, chunk ->
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            chunk.forEachIndexed { i, hz ->
                                val band = rowIdx * 3 + i
                                OutlinedTextField(
                                    value = s.thresholds[ear][band],
                                    onValueChange = { vm.setThreshold(ear, band, it) },
                                    label = { Text(freq(hz)) },
                                    singleLine = true,
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                                    modifier = Modifier.weight(1f)
                                )
                            }
                        }
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(s.realEarVerified, vm::setRealEarVerified)
                    Text("External real-ear measurement reviewed", color = EchoNavy, fontSize = 13.sp)
                }
                OutlinedTextField(
                    value = s.realEarNotes,
                    onValueChange = vm::setRealEarNotes,
                    label = { Text("Date, equipment, target, measured dB SPL") },
                    minLines = 2,
                    modifier = Modifier.fillMaxWidth()
                )
            }

            Section("Speech clarity A/B log") {
                Text(
                    "Read the same unseen word list in Processed and Baseline mode, then log how many words were understood. Manual comparison, not a validated test.",
                    color = EchoTextMuted,
                    fontSize = 12.sp
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    MonitorLimits.ENVIRONMENTS.forEach { env ->
                        EchoChoiceChip(
                            label = env,
                            selected = s.environment == env,
                            onClick = { vm.setEnvironment(env) }
                        )
                    }
                }
                var correct by remember { mutableStateOf("") }
                var total by remember { mutableStateOf("10") }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        correct, { correct = it.filter(Char::isDigit) }, label = { Text("Correct") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.weight(1f)
                    )
                    OutlinedTextField(
                        total, { total = it.filter(Char::isDigit) }, label = { Text("List size") }, singleLine = true,
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.weight(1f)
                    )
                }
                EchoPrimaryButton(
                    text = "Save ${if (s.processed) "processed" else "baseline"} score",
                    onClick = { if (vm.saveTrial(correct, total)) correct = "" }
                )
                if (s.trialMessage.isNotEmpty()) {
                    Text(s.trialMessage, color = Amber500, fontSize = 12.sp)
                }
                s.trials.take(10).forEach {
                    Text(it, fontSize = 12.sp, color = EchoTextMuted)
                }
            }

            TextButton(onClick = vm::resetDefaults, modifier = Modifier.fillMaxWidth()) {
                Text("Reset to cautious defaults", color = EchoPrimary)
            }
        }
    }
}

private fun freq(hz: Int) = if (hz >= 1000) "${hz / 1000} kHz" else "$hz Hz"

@Composable
private fun Section(title: String, initiallyOpen: Boolean = false, content: @Composable ColumnScope.() -> Unit) {
    var open by remember { mutableStateOf(initiallyOpen) }
    EchoCard {
        Row(
            Modifier.fillMaxWidth().clickable { open = !open },
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(title, color = EchoNavy, fontSize = 15.5.sp, fontWeight = FontWeight.Bold)
            Text(if (open) "−" else "+", color = EchoPrimary, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        }
        if (open) {
            Spacer(modifier = Modifier.height(10.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp), content = content)
        }
    }
}

@Composable
private fun ToggleRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(label, color = EchoNavy, fontSize = 14.sp, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onChange,
            colors = SwitchDefaults.colors(checkedThumbColor = Color.White, checkedTrackColor = EchoPrimary)
        )
    }
}

@Composable
private fun LabeledSlider(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    steps: Int,
    onChange: (Float) -> Unit
) {
    Column {
        Text(label, fontSize = 13.sp, color = EchoTextMuted)
        Slider(
            value = value.coerceIn(range),
            onValueChange = onChange,
            valueRange = range,
            steps = steps,
            colors = SliderDefaults.colors(
                thumbColor = EchoPrimary,
                activeTrackColor = EchoPrimary,
                inactiveTrackColor = EchoPrimarySoft
            )
        )
    }
}

@Composable
private fun DevicePicker(
    label: String,
    options: List<DeviceOption>,
    selectedId: Int?,
    enabled: Boolean,
    onSelect: (Int) -> Unit
) {
    var open by remember { mutableStateOf(false) }
    val current = options.firstOrNull { it.id == selectedId }?.label ?: "Choose…"
    Column {
        Text(label, fontSize = 12.sp, color = EchoTextMuted)
        Spacer(modifier = Modifier.height(4.dp))
        OutlinedButton(
            onClick = { open = true },
            enabled = enabled && options.isNotEmpty(),
            shape = RoundedCornerShape(12.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(current, maxLines = 1, color = EchoNavy)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            options.forEach { o ->
                DropdownMenuItem(text = { Text(o.label) }, onClick = { onSelect(o.id); open = false })
            }
        }
    }
}

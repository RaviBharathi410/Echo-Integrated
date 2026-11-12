package com.echo.hearing.ui.components

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.echo.hearing.domain.model.AudiometricFrequencies
import com.echo.hearing.domain.model.Ear
import com.echo.hearing.domain.model.ThresholdResult
import com.echo.hearing.ui.theme.*
import kotlin.math.log2

/**
 * Standard audiogram-style visualization composable.
 *
 * Implements clinical audiogram conventions:
 * - Octave logarithmic frequency spacing on X-axis (250Hz - 8000Hz).
 * - Inverted vertical axis: 0 dBFS at the top, 80 dBFS at the bottom.
 * - Right ear: Red 'O' glyphs, solid line (ASHA / ANSI standard).
 * - Left ear: Blue 'X' glyphs, dashed line (ASHA / ANSI standard).
 * - Shaded region for normal screening range (0 to 25 dBFS).
 * - Explicit, honest labeling that values are digital dBFS, NOT calibrated dB HL.
 */
@Composable
fun AudiogramView(
    thresholdResults: List<ThresholdResult>,
    modifier: Modifier = Modifier,
    frequencies: List<Int> = listOf(250, 500, 1000, 2000, 4000, 8000),
    minLevelDb: Int = 0,
    maxLevelDb: Int = 80
) {
    val leftEarResults = thresholdResults.filter { it.ear == Ear.LEFT }
    val rightEarResults = thresholdResults.filter { it.ear == Ear.RIGHT }

    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(18.dp))
            .background(EchoSurface)
            .border(1.dp, EchoBorder, RoundedCornerShape(18.dp))
            .padding(16.dp)
    ) {
        // Chart Header
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column {
                Text(
                    text = "AUDIOGRAM SCREENING PROFILE",
                    style = MaterialTheme.typography.labelSmall.copy(
                        fontWeight = FontWeight.Bold,
                        color = EchoNavy,
                        letterSpacing = 1.sp
                    )
                )
                Text(
                    text = "Digital Attenuation (dBFS)",
                    style = MaterialTheme.typography.bodySmall.copy(color = EchoTextMuted)
                )
            }

            // Legend
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                // Right Ear Legend
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(
                        modifier = Modifier
                            .size(10.dp)
                            .border(2.dp, Color(0xFFDC2626), RoundedCornerShape(50))
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Right (O)", color = Color(0xFFDC2626), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }

                // Left Ear Legend
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("✕", color = EchoPrimary, fontSize = 12.sp, fontWeight = FontWeight.ExtraBold)
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Left (X)", color = EchoPrimary, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                }
            }
        }

        Spacer(modifier = Modifier.height(16.dp))

        // Audiogram Canvas
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(260.dp)
        ) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val paddingLeft = 40.dp.toPx()
                val paddingRight = 20.dp.toPx()
                val paddingTop = 25.dp.toPx()
                val paddingBottom = 30.dp.toPx()

                val chartWidth = size.width - paddingLeft - paddingRight
                val chartHeight = size.height - paddingTop - paddingBottom

                // Frequency X coordinate mapping (log2 scale)
                val minFreqLog = log2(frequencies.first().toFloat())
                val maxFreqLog = log2(frequencies.last().toFloat())

                fun freqToX(freq: Int): Float {
                    val log = log2(freq.toFloat())
                    val ratio = (log - minFreqLog) / (maxFreqLog - minFreqLog)
                    return paddingLeft + ratio * chartWidth
                }

                // Level Y coordinate mapping: INVERTED (0 at top, 80 at bottom)
                fun levelToY(levelDb: Int): Float {
                    val clamped = levelDb.coerceIn(minLevelDb, maxLevelDb)
                    val ratio = (clamped - minLevelDb).toFloat() / (maxLevelDb - minLevelDb)
                    return paddingTop + ratio * chartHeight
                }

                // 1. Shaded Normal Screening Range (0 - 25 dBFS)
                val normalThresholdDb = 25
                val normalY = levelToY(normalThresholdDb)
                drawRect(
                    color = Color(0xFF10B981).copy(alpha = 0.10f),
                    topLeft = Offset(paddingLeft, paddingTop),
                    size = Size(chartWidth, normalY - paddingTop)
                )

                // 2. Draw Horizontal Grid Lines (Levels 0, 20, 40, 60, 80 dBFS)
                val levelSteps = listOf(0, 20, 40, 60, 80)
                levelSteps.forEach { level ->
                    val y = levelToY(level)
                    drawLine(
                        color = if (level == 25) Color(0xFF10B981).copy(alpha = 0.4f) else EchoBorder,
                        start = Offset(paddingLeft, y),
                        end = Offset(paddingLeft + chartWidth, y),
                        strokeWidth = if (level == 0) 1.5.dp.toPx() else 1.dp.toPx(),
                        pathEffect = if (level == 25) PathEffect.dashPathEffect(floatArrayOf(6f, 6f)) else null
                    )

                    // Y-axis label text
                    drawContext.canvas.nativeCanvas.apply {
                        val paint = android.graphics.Paint().apply {
                            color = android.graphics.Color.parseColor("#5B7083")
                            textSize = 24f
                            textAlign = android.graphics.Paint.Align.RIGHT
                            isAntiAlias = true
                        }
                        drawText("$level", paddingLeft - 8.dp.toPx(), y + 8f, paint)
                    }
                }

                // 3. Draw Vertical Grid Lines (Frequencies)
                frequencies.forEach { freq ->
                    val x = freqToX(freq)
                    drawLine(
                        color = EchoBorder,
                        start = Offset(x, paddingTop),
                        end = Offset(x, paddingTop + chartHeight),
                        strokeWidth = 1.dp.toPx()
                    )

                    // X-axis frequency labels
                    drawContext.canvas.nativeCanvas.apply {
                        val paint = android.graphics.Paint().apply {
                            color = android.graphics.Color.parseColor("#5B7083")
                            textSize = 24f
                            textAlign = android.graphics.Paint.Align.CENTER
                            isAntiAlias = true
                        }
                        val label = if (freq >= 1000) "${freq / 1000}k" else "$freq"
                        drawText(label, x, size.height - 8.dp.toPx(), paint)
                    }
                }

                // 4. Draw Right Ear Data (Red 'O' circles and red line)
                if (rightEarResults.isNotEmpty()) {
                    val sortedRight = rightEarResults.sortedBy { it.frequencyHz }
                    val rightPath = Path()
                    var first = true

                    sortedRight.forEach { res ->
                        val x = freqToX(res.frequencyHz)
                        val y = levelToY(res.thresholdDb)
                        if (first) {
                            rightPath.moveTo(x, y)
                            first = false
                        } else {
                            rightPath.lineTo(x, y)
                        }
                    }

                    // Connecting line
                    drawPath(
                        path = rightPath,
                        color = Color(0xFFDC2626),
                        style = Stroke(width = 2.5.dp.toPx())
                    )

                    // Points (Red 'O' Circles)
                    sortedRight.forEach { res ->
                        val x = freqToX(res.frequencyHz)
                        val y = levelToY(res.thresholdDb)

                        // Outer ring
                        drawCircle(
                            color = EchoSurface,
                            radius = 6.dp.toPx(),
                            center = Offset(x, y)
                        )
                        drawCircle(
                            color = Color(0xFFDC2626),
                            radius = 5.dp.toPx(),
                            center = Offset(x, y),
                            style = Stroke(width = 2.dp.toPx())
                        )
                    }
                }

                // 5. Draw Left Ear Data (Blue 'X' glyphs and dashed blue line)
                if (leftEarResults.isNotEmpty()) {
                    val sortedLeft = leftEarResults.sortedBy { it.frequencyHz }
                    val leftPath = Path()
                    var first = true

                    sortedLeft.forEach { res ->
                        val x = freqToX(res.frequencyHz)
                        val y = levelToY(res.thresholdDb)
                        if (first) {
                            leftPath.moveTo(x, y)
                            first = false
                        } else {
                            leftPath.lineTo(x, y)
                        }
                    }

                    // Dashed connecting line
                    drawPath(
                        path = leftPath,
                        color = EchoPrimary,
                        style = Stroke(
                            width = 2.5.dp.toPx(),
                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(10f, 6f))
                        )
                    )

                    // Points (Blue 'X' Glyphs)
                    sortedLeft.forEach { res ->
                        val x = freqToX(res.frequencyHz)
                        val y = levelToY(res.thresholdDb)
                        val halfSize = 5.dp.toPx()

                        // Background mask
                        drawCircle(
                            color = EchoSurface,
                            radius = 7.dp.toPx(),
                            center = Offset(x, y)
                        )

                        // Draw X arms
                        drawLine(
                            color = EchoPrimary,
                            start = Offset(x - halfSize, y - halfSize),
                            end = Offset(x + halfSize, y + halfSize),
                            strokeWidth = 2.5.dp.toPx()
                        )
                        drawLine(
                            color = EchoPrimary,
                            start = Offset(x - halfSize, y + halfSize),
                            end = Offset(x + halfSize, y - halfSize),
                            strokeWidth = 2.5.dp.toPx()
                        )
                    }
                }
            }
        }

        Spacer(modifier = Modifier.height(8.dp))

        // Normal Screening Range Legend Note
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                modifier = Modifier
                    .size(10.dp)
                    .background(Color(0xFF10B981).copy(alpha = 0.3f), RoundedCornerShape(2.dp))
            )
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                "Shaded: ≤ 25 dBFS provisional screening zone",
                color = EchoTextMuted,
                fontSize = 11.sp
            )
        }
    }
}

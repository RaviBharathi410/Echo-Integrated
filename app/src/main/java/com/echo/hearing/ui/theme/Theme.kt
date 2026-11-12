package com.echo.hearing.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// Light Clinical Blue / Ice-White Palette (matching ECHO UI)
val EchoBg = Color(0xFFF3F7FC)
val EchoSurface = Color(0xFFFFFFFF)
val EchoSurfaceAlt = Color(0xFFEAF2FC)
val EchoSurfaceMuted = Color(0xFFF7FAFE)
val EchoPrimary = Color(0xFF1565C0)
val EchoPrimaryDark = Color(0xFF0E4DA4)
val EchoPrimarySoft = Color(0xFFDFECFA)
val EchoBorder = Color(0xFFDCE7F5)
val EchoPillBorder = Color(0xFF6EA8E8)
val EchoNavy = Color(0xFF0E2439)
val EchoTextMuted = Color(0xFF5B7083)
val EchoTextLight = Color(0xFF8395A7)

// Semantic status accents
val Emerald500 = Color(0xFF10B981)
val EmeraldSoft = Color(0xFFE7F8F2)
val Amber500 = Color(0xFFD97706)
val AmberSoft = Color(0xFFFEF3C7)
val Rose500 = Color(0xFFDC2626)
val RoseSoft = Color(0xFFFEE2E2)
val Sky500 = Color(0xFF0284C7)

// Legacy aliases retained for compatibility
val Slate950 = EchoBg
val Slate900 = EchoSurface
val Slate800 = EchoBorder
val Slate700 = EchoPillBorder
val Slate600 = EchoTextMuted
val Slate500 = EchoTextMuted
val Slate400 = EchoTextMuted
val Slate300 = EchoBorder
val Slate200 = EchoSurfaceAlt
val Slate100 = EchoNavy
val Cyan400 = EchoPrimary

private val EchoLightColorScheme = lightColorScheme(
    primary = EchoPrimary,
    onPrimary = Color.White,
    primaryContainer = EchoPrimarySoft,
    onPrimaryContainer = EchoPrimaryDark,
    secondary = Sky500,
    onSecondary = Color.White,
    background = EchoBg,
    onBackground = EchoNavy,
    surface = EchoSurface,
    onSurface = EchoNavy,
    surfaceVariant = EchoSurfaceAlt,
    onSurfaceVariant = EchoTextMuted,
    outline = EchoPillBorder,
    outlineVariant = EchoBorder,
    error = Rose500,
    onError = Color.White
)

@Composable
fun EchoTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = EchoLightColorScheme,
        content = content
    )
}

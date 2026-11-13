import 'package:echo_hearing/app/theme/echo_colors.dart';
import 'package:flutter/material.dart';

class EchoTheme {
  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: EchoColors.primary,
      onPrimary: Colors.white,
      primaryContainer: EchoColors.primarySoft,
      onPrimaryContainer: EchoColors.navy,
      secondary: EchoColors.pillBorder,
      surface: EchoColors.surface,
      onSurface: EchoColors.navy,
      surfaceContainerHighest: EchoColors.surfaceAlt,
      onSurfaceVariant: EchoColors.muted,
      outline: EchoColors.border,
      error: EchoColors.rose,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: EchoColors.bg,
      dividerColor: EchoColors.border,
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: EchoColors.navy,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: EchoColors.navy,
        ),
        titleMedium: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: EchoColors.navy,
        ),
        bodyLarge: TextStyle(
          fontSize: 15,
          color: EchoColors.navy,
          height: 1.45,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: EchoColors.muted,
          height: 1.45,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: EchoColors.muted,
          height: 1.4,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EchoColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EchoColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EchoColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: EchoColors.primary, width: 1.5),
        ),
      ),
    );
  }
}


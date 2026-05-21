import 'package:flutter/material.dart';

@immutable
class AeroRideThemeTokens extends ThemeExtension<AeroRideThemeTokens> {
  final Color primaryDarkBlue;
  final Color accentTealStart;
  final Color accentTealEnd;
  final Color successGreen;
  final Color warningOrange;
  final Color surface;
  final Color softSurface;
  final Color mutedBorder;

  const AeroRideThemeTokens({
    required this.primaryDarkBlue,
    required this.accentTealStart,
    required this.accentTealEnd,
    required this.successGreen,
    required this.warningOrange,
    required this.surface,
    required this.softSurface,
    required this.mutedBorder,
  });

  const AeroRideThemeTokens.light()
    : primaryDarkBlue = const Color(0xFF0D2B52),
      accentTealStart = const Color(0xFF00A4BA),
      accentTealEnd = const Color(0xFF14B8A6),
      successGreen = const Color(0xFF10B981),
      warningOrange = const Color(0xFFF59E0B),
      surface = Colors.white,
      softSurface = const Color(0xFFF1F5F9),
      mutedBorder = const Color(0xFFE2E8F0);

  LinearGradient get oceanGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0D2B52), Color(0xFF00A4BA), Color(0xFF14B8A6)],
  );

  LinearGradient get tealGradient => const LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF00A4BA), Color(0xFF14B8A6)],
  );

  @override
  AeroRideThemeTokens copyWith({
    Color? primaryDarkBlue,
    Color? accentTealStart,
    Color? accentTealEnd,
    Color? successGreen,
    Color? warningOrange,
    Color? surface,
    Color? softSurface,
    Color? mutedBorder,
  }) {
    return AeroRideThemeTokens(
      primaryDarkBlue: primaryDarkBlue ?? this.primaryDarkBlue,
      accentTealStart: accentTealStart ?? this.accentTealStart,
      accentTealEnd: accentTealEnd ?? this.accentTealEnd,
      successGreen: successGreen ?? this.successGreen,
      warningOrange: warningOrange ?? this.warningOrange,
      surface: surface ?? this.surface,
      softSurface: softSurface ?? this.softSurface,
      mutedBorder: mutedBorder ?? this.mutedBorder,
    );
  }

  @override
  AeroRideThemeTokens lerp(
    ThemeExtension<AeroRideThemeTokens>? other,
    double t,
  ) {
    if (other is! AeroRideThemeTokens) return this;
    return AeroRideThemeTokens(
      primaryDarkBlue: Color.lerp(primaryDarkBlue, other.primaryDarkBlue, t)!,
      accentTealStart: Color.lerp(accentTealStart, other.accentTealStart, t)!,
      accentTealEnd: Color.lerp(accentTealEnd, other.accentTealEnd, t)!,
      successGreen: Color.lerp(successGreen, other.successGreen, t)!,
      warningOrange: Color.lerp(warningOrange, other.warningOrange, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      softSurface: Color.lerp(softSurface, other.softSurface, t)!,
      mutedBorder: Color.lerp(mutedBorder, other.mutedBorder, t)!,
    );
  }
}

class AeroRideTheme {
  static const tokens = AeroRideThemeTokens.light();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: tokens.primaryDarkBlue,
      primary: tokens.primaryDarkBlue,
      secondary: tokens.accentTealEnd,
      surface: tokens.surface,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.softSurface,
      extensions: const [tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.surface,
        foregroundColor: tokens.primaryDarkBlue,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0D2B52),
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 8,
        shadowColor: const Color(0x140D2B52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: tokens.softSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: tokens.mutedBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: tokens.mutedBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: tokens.primaryDarkBlue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
      ),
    );
  }
}

extension AeroRideThemeContext on BuildContext {
  AeroRideThemeTokens get aeroTokens =>
      Theme.of(this).extension<AeroRideThemeTokens>() ?? AeroRideTheme.tokens;
}

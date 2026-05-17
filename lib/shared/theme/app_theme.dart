// lib/shared/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Palette ────────────────────────────────────────────────────────────────
  static const _primary    = Color(0xFF00C853); // vibrant green
  static const _surface    = Color(0xFF0A0A0A); // near-black
  static const _card       = Color(0xFF141414); // slightly lighter
  static const _cardMid    = Color(0xFF1C1C1C); // input fill
  static const _authentic  = Color(0xFF00C853); // green — AUTHENTIC
  static const _tampered   = Color(0xFFFF1744); // red  — TAMPERED
  static const _divider    = Color(0xFF2A2A2A);
  static const _textSub    = Color(0xFF8A8A8A);

  // ── Text styles ────────────────────────────────────────────────────────────

  /// Merriweather — headings, event names, hero text
  static TextStyle merri({
    double fontSize = 16,
    FontWeight fontWeight = FontWeight.w700,
    Color color = Colors.white,
    double? letterSpacing,
    double? height,
  }) =>
      GoogleFonts.merriweather(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
        height: height,
      );

  /// Open Sans — labels, body, form fields
  static TextStyle sans({
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w400,
    Color color = Colors.white,
    double? letterSpacing,
  }) =>
      GoogleFonts.openSans(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        letterSpacing: letterSpacing,
      );

  // ── Theme ──────────────────────────────────────────────────────────────────
  static ThemeData dark() {
    final base = ThemeData.dark();

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary:   _primary,
        secondary: _primary,
        surface:   _surface,
        error:     _tampered,
      ),
      scaffoldBackgroundColor: _surface,
      cardColor: _card,

      // Text theme defaults to Open Sans body + Merriweather display
      textTheme: GoogleFonts.openSansTextTheme(base.textTheme).copyWith(
        displayLarge:   GoogleFonts.merriweather(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white),
        displayMedium:  GoogleFonts.merriweather(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
        displaySmall:   GoogleFonts.merriweather(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        headlineLarge:  GoogleFonts.merriweather(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        headlineMedium: GoogleFonts.merriweather(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
        headlineSmall:  GoogleFonts.merriweather(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        titleLarge:     GoogleFonts.openSans(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
        titleMedium:    GoogleFonts.openSans(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
        titleSmall:     GoogleFonts.openSans(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
        bodyLarge:      GoogleFonts.openSans(fontSize: 15, fontWeight: FontWeight.w400, color: Colors.white),
        bodyMedium:     GoogleFonts.openSans(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.white),
        bodySmall:      GoogleFonts.openSans(fontSize: 11, fontWeight: FontWeight.w400, color: _textSub),
        labelLarge:     GoogleFonts.openSans(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
        labelMedium:    GoogleFonts.openSans(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Colors.white),
        labelSmall:     GoogleFonts.openSans(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.8, color: _textSub),
      ),

      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _card,
        indicatorColor: _primary.withOpacity(0.15),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.openSans(color: _primary, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: GoogleFonts.merriweather(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _primary,
          foregroundColor: Colors.black,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: GoogleFonts.openSans(fontWeight: FontWeight.w700, fontSize: 14),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _cardMid,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.openSans(color: const Color(0xFF555555), fontSize: 13),
        labelStyle: GoogleFonts.openSans(color: _textSub, fontSize: 13),
        errorStyle: GoogleFonts.openSans(color: _tampered, fontSize: 11),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _tampered),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _tampered, width: 1.5),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: _cardMid,
        selectedColor: _primary,
        side: const BorderSide(color: _divider),
        labelStyle: GoogleFonts.openSans(fontSize: 12, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      dividerTheme: const DividerThemeData(color: _divider, space: 1),
    );
  }

  // ── Semantic helpers ───────────────────────────────────────────────────────
  static const authenticColor = _authentic;
  static const tamperedColor  = _tampered;
  static const primaryColor   = _primary;
  static const cardColor      = _card;
  static const cardMidColor   = _cardMid;
  static const dividerColor   = _divider;
  static const subTextColor   = _textSub;
}
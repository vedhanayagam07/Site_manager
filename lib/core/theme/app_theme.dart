import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color roseGold = Color(0xFFC68E65);
  static const Color roseGoldLight = Color(0xFFD9A785);

  static const Color darkBg = Color(0xFF090B12);
  static const Color cardBg = Color(0xFF151821);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
        headlineLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5),
        headlineMedium: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.2),
        titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600, letterSpacing: 0.5),
        bodyLarge: GoogleFonts.inter(),
        bodyMedium: GoogleFonts.inter(color: Colors.white70),
      ),

      scaffoldBackgroundColor: darkBg,

      colorScheme: const ColorScheme.dark(
        primary: roseGold,
        secondary: roseGoldLight,
        surface: cardBg,
        onPrimary: Colors.white,
        error: Color(0xFFE57373),
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: Colors.white,
        ),
      ),

      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: 0.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: roseGold.withValues(alpha: 0.15),
            width: 1.2,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF12141C),
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        labelStyle: TextStyle(color: roseGold.withValues(alpha: 0.6)),
        floatingLabelStyle: const TextStyle(color: roseGold, fontWeight: FontWeight.bold),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: roseGold.withValues(alpha: 0.15), width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: roseGold.withValues(alpha: 0.15), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: roseGold, width: 2.0),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFE57373), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: const BorderSide(color: Color(0xFFE57373), width: 2.0),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: roseGold,
          foregroundColor: Colors.white,
          elevation: 6,
          shadowColor: roseGold.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: BorderSide(color: roseGoldLight.withValues(alpha: 0.4), width: 1),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 55),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: roseGold,
          elevation: 2,
          side: BorderSide(color: roseGold.withValues(alpha: 0.5), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 55),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return darkTheme; // Default to dark theme for premium commercial consistency
  }
}
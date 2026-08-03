import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppleTheme {
  static const Color background = Color(0xFFF4F4F7);
  static const Color cardBackground = Colors.white;
  static const Color primaryText = Color(0xFF1D1D1F);
  static const Color secondaryText = Color(0xFF86868B);
  static const Color border = Color(0xFFE5E5EA);

  // Apple Accent Colors
  static const Color appleEmerald = Color(0xFF00C7BE);
  static const Color appleGreen = Color(0xFF34C759);
  static const Color appleRose = Color(0xFFFF3B30);
  static const Color appleBlue = Color(0xFF007AFF);
  static const Color appleIndigo = Color(0xFF5856D6);
  static const Color appleOrange = Color(0xFFFF9500);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      primaryColor: appleBlue,
      colorScheme: ColorScheme.fromSeed(
        seedColor: appleBlue,
        surface: cardBackground,
      ),
      textTheme: GoogleFonts.interTextTheme().copyWith(
        displayLarge: GoogleFonts.inter(
          color: primaryText,
          fontSize: 32,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.8,
        ),
        titleLarge: GoogleFonts.inter(
          color: primaryText,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleMedium: GoogleFonts.inter(
          color: primaryText,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: GoogleFonts.inter(
          color: primaryText,
          fontSize: 15,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: GoogleFonts.inter(
          color: secondaryText,
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: primaryText),
        titleTextStyle: GoogleFonts.inter(
          color: primaryText,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
    );
  }

  // Soft Apple Card BoxShadow
  static List<BoxShadow> softShadow = [
    BoxShadow(
      color: Colors.black.withOpacity(0.03),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];
}

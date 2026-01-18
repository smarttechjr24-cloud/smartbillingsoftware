import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Centralized application theme configuration.
/// Implements a "Light Professional" color palette inspired by modern fintech apps.
class AppTheme {
  // Private constructor to prevent instantiation
  AppTheme._();

  // ===========================================================================
  // COLORS
  // ===========================================================================
  
  static const Color primary = Color(0xFF1976D2); // Professional Blue
  static const Color accent = Color(0xFF1565C0); // Darker Blue for gradients/hover
  static const Color secondary = Color(0xFF42A5F5); // Lighter Blue
  
  static const Color background = Color(0xFFF5F7FA); // Light Gray Background
  static const Color surface = Color(0xFFFFFFFF); // White Card Surface
  
  static const Color success = Color(0xFF2E7D32); // Green
  static const Color warning = Color(0xFFED6C02); // Orange
  static const Color danger = Color(0xFFD32F2F); // Red
  static const Color info = Color(0xFF0288D1); // Light Blue
  
  static const Color textPrimary = Color(0xFF212121); // Almost Black
  static const Color textSecondary = Color(0xFF757575); // Grey
  static const Color textHint = Color(0xFF9E9E9E); // Light Grey
  
  static const Color border = Color(0xFFE0E0E0); // Divider color
  static const Color shadow = Color(0x1A000000); // Subtle shadow

  // ===========================================================================
  // TEXT STYLES
  // ===========================================================================

  static TextStyle get headlineLarge => GoogleFonts.inter(
    fontSize: 24,
    fontWeight: FontWeight.bold,
    color: textPrimary,
  );

  static TextStyle get headlineMedium => GoogleFonts.inter(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get titleLarge => GoogleFonts.inter(
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get titleMedium => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    color: textPrimary,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.normal,
    color: textSecondary,
  );

  static TextStyle get labelLarge => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  // ===========================================================================
  // DECORATIONS
  // ===========================================================================

  static BoxDecoration get cardDecoration => BoxDecoration(
    color: surface,
    borderRadius: BorderRadius.circular(12),
    boxShadow: const [
      BoxShadow(
        color: shadow,
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
  );

  static InputDecoration inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: bodyMedium.copyWith(color: textHint),
    filled: true,
    fillColor: surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: primary, width: 2),
    ),
  );
}

import 'package:flutter/material.dart';

final ThemeData appTheme = ThemeData(
  useMaterial3: true, // Enables modern Material You design
  fontFamily: 'Poppins', // Optional: add to pubspec.yaml if you want this font
  // ====== Color Scheme ======
  colorScheme: const ColorScheme.light(
    primary: Color(0xFF0D47A1), // Deep navy blue
    onPrimary: Colors.white,
    secondary: Color(0xFF1565C0), // Bright blue accent
    onSecondary: Colors.white,
    error: Color(0xFFD32F2F),
    onError: Colors.white,
    background: Color(0xFFF5F7FA),
    onBackground: Color(0xFF1A1A1A),
    surface: Colors.white,
    onSurface: Color(0xFF1A1A1A),
  ),

  scaffoldBackgroundColor: const Color(0xFFF5F7FA),

  // ===== App Bar =====
  appBarTheme: const AppBarTheme(
    elevation: 0,
    centerTitle: true,
    backgroundColor: Color(0xFF0D47A1),
    foregroundColor: Colors.white,
    titleTextStyle: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.bold,
      letterSpacing: 0.5,
    ),
    iconTheme: IconThemeData(color: Colors.white),
  ),

  // ===== Buttons =====
  elevatedButtonTheme: ElevatedButtonThemeData(
    style:
        ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1565C0),
          foregroundColor: Colors.white,
          elevation: 3,
          minimumSize: const Size(130, 45),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ).copyWith(
          overlayColor: MaterialStateProperty.all(
            Colors.blue.shade900.withOpacity(0.15),
          ),
        ),
  ),

  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      side: const BorderSide(color: Color(0xFF1565C0), width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      foregroundColor: const Color(0xFF1565C0),
      textStyle: const TextStyle(fontWeight: FontWeight.w600),
    ),
  ),

  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: const Color(0xFF1565C0),
      textStyle: const TextStyle(fontWeight: FontWeight.bold),
    ),
  ),

  // ===== Input Fields =====
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    hintStyle: TextStyle(color: Colors.grey.shade500),
    labelStyle: const TextStyle(fontWeight: FontWeight.w600),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: Colors.grey.shade300),
    ),
    focusedBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Color(0xFF1565C0), width: 1.5),
    ),
    errorBorder: const OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(10)),
      borderSide: BorderSide(color: Color(0xFFD32F2F), width: 1.2),
    ),
  ),

  // ===== Cards =====

  // ===== Floating Action Button =====
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: Color(0xFF1565C0),
    foregroundColor: Colors.white,
    elevation: 4,
  ),

  // ===== Text Styles =====
  textTheme: TextTheme(
    headlineLarge: const TextStyle(
      fontSize: 26,
      fontWeight: FontWeight.bold,
      color: Color(0xFF0D47A1),
    ),
    headlineMedium: const TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.bold,
      color: Color(0xFF0D47A1),
    ),
    bodyLarge: TextStyle(fontSize: 16, color: Colors.grey.shade800),
    bodyMedium: TextStyle(fontSize: 14, color: Colors.grey.shade700),
    labelLarge: const TextStyle(
      fontWeight: FontWeight.w600,
      color: Color(0xFF1565C0),
    ),
  ),

  // ===== Divider =====
  dividerTheme: DividerThemeData(
    color: Colors.grey.shade300,
    thickness: 1,
    indent: 16,
    endIndent: 16,
  ),

  // ===== Bottom Navigation Bar =====
  bottomNavigationBarTheme: const BottomNavigationBarThemeData(
    backgroundColor: Colors.white,
    selectedItemColor: Color(0xFF0D47A1),
    unselectedItemColor: Colors.grey,
    type: BottomNavigationBarType.fixed,
    showUnselectedLabels: true,
  ),
);

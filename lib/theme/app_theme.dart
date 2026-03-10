import 'package:flutter/material.dart';

/// App color palette matching the Android app
class AppColors {
  // Primary colors
  static const Color primaryPurple = Color(0xFF7C3AED);
  static const Color primaryPurpleDark = Color(0xFF5B21B6);
  static const Color coralPrimary = Color(0xFFFF6B6B);
  static const Color tealSecondary = Color(0xFF4ECDC4);
  static const Color heartSalmon = Color(0xFFFA8072);

  // Background colors
  static const Color backgroundLight = Color(0xFFF9FAFB);
  static const Color surfaceLight = Colors.white;
  static const Color backgroundDark = Color(0xFF1A1A2E);
  static const Color surfaceDark = Color(0xFF16213E);

  // Text colors
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textMuted = Color(0xFF9CA3AF);

  // Category gradient colors
  static const Map<String, List<Color>> categoryGradients = {
    'food': [Color(0xFF7C3AED), Color(0xFF8B5CF6)],
    'finance': [Color(0xFF22C55E), Color(0xFF4ADE80)],
    'wellness': [Color(0xFF8B5CF6), Color(0xFFA78BFA)],
    'career': [Color(0xFF6366F1), Color(0xFF818CF8)],
    'home': [Color(0xFF60A5FA), Color(0xFF93C5FD)],
    'travel': [Color(0xFFEC4899), Color(0xFFF472B6)],
    'tech': [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    'gaming': [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
    'entertainment': [Color(0xFFA78BFA), Color(0xFFC4B5FD)],
    'shopping': [Color(0xFF0EA5E9), Color(0xFF38BDF8)],
    'style': [Color(0xFFF472B6), Color(0xFFF9A8D4)],
    'books': [Color(0xFF34D399), Color(0xFF6EE7B7)],
    'growth': [Color(0xFF84CC16), Color(0xFFA3E635)],
    'projects': [Color(0xFFF59E0B), Color(0xFFFBBF24)],
    'creativity': [Color(0xFFEF4444), Color(0xFFF87171)],
    'sports': [Color(0xFF06B6D4), Color(0xFF22D3EE)],
    'other': [Color(0xFF94A3B8), Color(0xFFCBD5E1)],
  };

 }

/// App theme configuration
class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryPurple,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      iconTheme: const IconThemeData(size: 18),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.primaryPurple, width: 2),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.primaryPurple,
        unselectedItemColor: AppColors.textMuted,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryPurple,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: AppColors.backgroundDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceDark,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

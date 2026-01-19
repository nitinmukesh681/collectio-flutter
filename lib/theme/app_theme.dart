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
    'food': [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
    'finance': [Color(0xFF4ECDC4), Color(0xFF44A08D)],
    'wellness': [Color(0xFFA8E6CF), Color(0xFF88D8B0)],
    'career': [Color(0xFF667EEA), Color(0xFF764BA2)],
    'home': [Color(0xFFFFC3A0), Color(0xFFFFAFBD)],
    'travel': [Color(0xFF00B4DB), Color(0xFF0083B0)],
    'tech': [Color(0xFF4158D0), Color(0xFFC850C0)],
    'gaming': [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
    'entertainment': [Color(0xFFFC466B), Color(0xFF3F5EFB)],
    'shopping': [Color(0xFFFF9A9E), Color(0xFFFECFEF)],
    'style': [Color(0xFFFDCB82), Color(0xFFFFE5B4)],
    'books': [Color(0xFF667EEA), Color(0xFF764BA2)],
    'growth': [Color(0xFF11998E), Color(0xFF38EF7D)],
    'projects': [Color(0xFF536976), Color(0xFF292E49)],
    'creativity': [Color(0xFFE91E63), Color(0xFFFF5722)],
    'sports': [Color(0xFF1E90FF), Color(0xFF00BFFF)],
    'other': [Color(0xFF7C3AED), Color(0xFF5B21B6)],
  };
}

/// App theme configuration
class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primaryPurple,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.backgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceLight,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryPurple,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
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

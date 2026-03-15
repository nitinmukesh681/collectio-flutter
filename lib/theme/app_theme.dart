import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App color palette matching the Android app
class AppColors {
  // Primary colors
  static const Color primaryPurple = Color(0xFF7C3AED);
  static const Color primaryPurpleDark = Color(0xFF5B21B6);
  static const Color coralPrimary = Color(0xFFFF6B6B);
  static const Color tealSecondary = Color(0xFF4ECDC4);
  static const Color heartSalmon = Color(0xFFFA8072);

  // Background colors
  static const Color backgroundLight = Color(0xFFFFFFFF);
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
    final baseScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primaryPurple,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      visualDensity: VisualDensity.compact,
      fontFamily: GoogleFonts.poppins().fontFamily,
      textTheme: GoogleFonts.poppinsTextTheme().copyWith(
        // Ensure all text styles use Poppins
        bodyLarge: GoogleFonts.poppins(),
        bodyMedium: GoogleFonts.poppins(),
        bodySmall: GoogleFonts.poppins(),
        displayLarge: GoogleFonts.poppins(),
        displayMedium: GoogleFonts.poppins(),
        displaySmall: GoogleFonts.poppins(),
        headlineLarge: GoogleFonts.poppins(),
        headlineMedium: GoogleFonts.poppins(),
        headlineSmall: GoogleFonts.poppins(),
        titleLarge: GoogleFonts.poppins(),
        titleMedium: GoogleFonts.poppins(),
        titleSmall: GoogleFonts.poppins(),
        labelLarge: GoogleFonts.poppins(),
        labelMedium: GoogleFonts.poppins(),
        labelSmall: GoogleFonts.poppins(),
      ),
      colorScheme: baseScheme.copyWith(
        background: Colors.white,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      canvasColor: Colors.white,
      cardColor: Colors.white,
      dialogBackgroundColor: Colors.white,
      dividerTheme: const DividerThemeData(
        color: Color(0xFFE5E7EB),
        thickness: 1,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 14,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
        ),
        titleTextStyle: GoogleFonts.poppins(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
          height: 1.25,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        elevation: 10,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        textStyle: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.poppins(
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
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primaryPurple,
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w800),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: Color(0xFFE5E7EB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primaryPurple.withOpacity(0.10),
        selectedColor: AppColors.primaryPurple,
        secondarySelectedColor: AppColors.primaryPurple,
        disabledColor: const Color(0xFFF3F4F6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        secondaryLabelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w600,
          color: AppColors.textMuted,
        ),
        labelStyle: GoogleFonts.poppins(
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
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

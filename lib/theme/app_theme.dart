import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system — clean, editorial, restrained
class AppColors {
  // Core palette
  static const Color primary = Color(0xFF4338CA);       // Dark indigo
  static const Color primaryDark = Color(0xFF3730A3);
  static const Color secondary = Color(0xFF0F172A);      // Near-black
  static const Color tertiary = Color(0xFFB95F00);        // Warm accent
  static const Color heartSalmon = Color(0xFFEF4444);     // Red for likes
  static const Color lightIndigo = Color(0xFF818CF8);

  // Keep old name aliases so existing code doesn't break
  static const Color primaryPurple = primary;
  static const Color primaryPurpleDark = primaryDark;
  static const Color coralPrimary = Color(0xFFFF6B6B);
  static const Color tealSecondary = Color(0xFF4ECDC4);

  // Backgrounds — neutral off-white (cleaner than slate-tinted grays)
  static const Color backgroundSurface = Color(0xFFFAFAFA);
  static const Color backgroundLight = Colors.white;
  static const Color surfaceLight = Colors.white;
  static const Color surfaceMuted = Color(0xFFF5F5F5);
  static const Color divider = Color(0xFFE8E8E8);
  static const Color chipBg = Color(0xFFF5F5F5);

  // Text
  static const Color textPrimary = Color(0xFF0F172A);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textMuted = Color(0xFF94A3B8);
  /// Collection / item description body copy (darker than textSecondary).
  static const Color collectionDescription = Color(0xFF334155);

  // Gradients — only for collaboration cards / category fallbacks
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const LinearGradient primaryGradientVertical = LinearGradient(
    colors: [Color(0xFF4338CA), Color(0xFF6366F1)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Shadows
  static const List<BoxShadow> cardShadow = [
    BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 2)),
  ];
  static const List<BoxShadow> elevatedShadow = [
    BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, 4)),
  ];
  /// Profile header sheet — separates white block from page background.
  static const List<BoxShadow> profileHeaderShadow = [
    BoxShadow(color: Color(0x10000000), blurRadius: 20, offset: Offset(0, 6)),
    BoxShadow(color: Color(0x06000000), blurRadius: 1, offset: Offset(0, 1)),
  ];
  /// Soft shadow around collection cover cards (all sides).
  static const List<BoxShadow> collectionCoverShadow = [
    BoxShadow(color: Color(0x1F000000), blurRadius: 16, spreadRadius: 0, offset: Offset.zero),
    BoxShadow(color: Color(0x0A000000), blurRadius: 6, spreadRadius: 1, offset: Offset.zero),
  ];

  // Radii
  static const double radiusSmall = 8.0;
  static const double radiusCard = 10.0;
  static const double radiusLarge = 14.0;

  // Category gradients
  // Fallback gradients for collections without cover images — uses design palette
  static const Map<String, List<Color>> categoryGradients = {
    'food': [Color(0xFF4338CA), Color(0xFF6366F1)],       // deep indigo
    'finance': [Color(0xFF0F172A), Color(0xFF1E293B)],     // navy
    'wellness': [Color(0xFF818CF8), Color(0xFFA5B4FC)],    // light indigo
    'career': [Color(0xFF0F172A), Color(0xFF334155)],      // navy
    'home': [Color(0xFF4338CA), Color(0xFF6366F1)],        // indigo
    'travel': [Color(0xFF0F172A), Color(0xFF1E293B)],      // navy
    'tech': [Color(0xFF818CF8), Color(0xFFA5B4FC)],        // light indigo
    'gaming': [Color(0xFF4338CA), Color(0xFF6366F1)],      // indigo
    'entertainment': [Color(0xFF0F172A), Color(0xFF334155)], // navy
    'shopping': [Color(0xFFB95F00), Color(0xFFD97706)],    // brown/amber
    'style': [Color(0xFF818CF8), Color(0xFFA5B4FC)],       // light indigo
    'books': [Color(0xFFB95F00), Color(0xFFD97706)],       // brown/amber
    'growth': [Color(0xFF818CF8), Color(0xFFA5B4FC)],      // light indigo
    'projects': [Color(0xFFB95F00), Color(0xFFD97706)],    // brown/amber
    'creativity': [Color(0xFF4338CA), Color(0xFF6366F1)],  // indigo
    'sports': [Color(0xFF0F172A), Color(0xFF334155)],      // navy
    'other': [Color(0xFF94A3B8), Color(0xFFCBD5E1)],       // neutral grey
  };

  // Category label / browse tile accent colors
  static const Map<String, Color> categoryLabelColors = {
    'food': primary,
    'travel': secondary,
    'tech': lightIndigo,
    'shopping': tertiary,
    'finance': secondary,
    'wellness': lightIndigo,
    'career': secondary,
    'home': primary,
    'gaming': primary,
    'entertainment': secondary,
    'books': tertiary,
    'growth': lightIndigo,
    'projects': tertiary,
    'creativity': primary,
    'sports': secondary,
    'style': lightIndigo,
    'other': textMuted,
  };

  static Color categoryLabelColor(String categoryName) =>
      categoryLabelColors[categoryName] ?? primary;

  // Helpers (keep for existing code that uses them)
  static Widget gradientIcon(IconData icon, {double size = 18}) {
    return ShaderMask(
      shaderCallback: (bounds) => primaryGradient.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Icon(icon, color: Colors.white, size: size),
    );
  }
  static Widget gradientText(String text, TextStyle style) {
    return ShaderMask(
      shaderCallback: (bounds) => primaryGradient.createShader(bounds),
      blendMode: BlendMode.srcIn,
      child: Text(text, style: style.copyWith(color: Colors.white)),
    );
  }
}

class AppTextStyles {
  AppTextStyles._();

  static TextStyle collectionDescription({
    double fontSize = 14,
    double height = 1.4,
  }) {
    return GoogleFonts.plusJakartaSans(
      fontSize: fontSize,
      fontWeight: FontWeight.w500,
      color: AppColors.collectionDescription,
      height: height,
    );
  }
}

class AppTheme {
  static ThemeData get lightTheme {
    final textTheme = GoogleFonts.plusJakartaSansTextTheme();

    return ThemeData(
      useMaterial3: true,
      fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
      textTheme: textTheme,
      colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: Brightness.light).copyWith(surface: Colors.white),
      scaffoldBackgroundColor: AppColors.backgroundSurface,
      canvasColor: Colors.white,
      cardColor: Colors.white,
      dividerTheme: const DividerThemeData(color: AppColors.divider, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusCard)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppColors.radiusLarge))),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusSmall)),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusCard)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusSmall)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusSmall)),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radiusSmall), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radiusSmall), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppColors.radiusSmall), borderSide: const BorderSide(color: AppColors.primary, width: 2)),
        hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontWeight: FontWeight.w500),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceMuted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide.none),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15),
        unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500, fontSize: 15),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Standardized Brand Logo for 'finds'
/// Features a dual-dot motif with a warm accent color to symbolize discovery.
class BrandLogo extends StatelessWidget {
  final double fontSize;
  final double iconSize;
  final Color? color;
  final bool useAccentDot;

  const BrandLogo({
    super.key,
    this.fontSize = 26,
    this.iconSize = 8,
    this.color,
    this.useAccentDot = true,
  });

  @override
  Widget build(BuildContext context) {
    final primaryBrandColor = color ?? AppColors.primary;
    // Use the warm tertiary color for the second dot to give it a "discovery" accent
    final secondaryDotColor = (useAccentDot && color == null) ? AppColors.tertiary : primaryBrandColor;
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Signature Dots with refined spacing and subtle depth
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(iconSize, primaryBrandColor),
            SizedBox(width: iconSize * 0.6),
            _buildDot(iconSize, secondaryDotColor),
          ],
        ),
        SizedBox(width: iconSize * 1.5),
        // Premium Editorial Typography
        Text(
          'finds',
          style: GoogleFonts.plusJakartaSans(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: color ?? AppColors.textPrimary,
            letterSpacing: -1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildDot(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.15),
            blurRadius: size * 0.4,
            offset: Offset(0, size * 0.2),
          ),
        ],
      ),
    );
  }
}

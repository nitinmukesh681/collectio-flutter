import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Default avatar shown when a user has no profile photo.
class AvatarFallback extends StatelessWidget {
  final String name;
  final double size;

  const AvatarFallback({
    super.key,
    required this.name,
    this.size = 44,
  });

  String get _initial {
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.divider,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initial,
        style: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

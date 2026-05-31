import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AvatarFallback extends StatelessWidget {
  final String name;
  final double size;

  const AvatarFallback({
    super.key,
    required this.name,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isNotEmpty
        ? name.trim().split(' ').map((e) => e[0].toUpperCase()).take(2).join()
        : '?';

    // Consistent color based on name hash
    final colors = [
      const Color(0xFF4338CA), // indigo
      const Color(0xFF0F172A), // navy
      const Color(0xFFB95F00), // amber
      const Color(0xFF0D9488), // teal
      const Color(0xFFBE185D), // pink
      const Color(0xFF6D28D9), // purple
    ];
    final color = colors[name.hashCode.abs() % colors.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: GoogleFonts.plusJakartaSans(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

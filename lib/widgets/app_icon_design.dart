import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class AppIconDesign extends StatelessWidget {
  final double size;
  const AppIconDesign({super.key, this.size = 200});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(size * 0.22), // Squircle-ish
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: size * 0.1,
            offset: Offset(0, size * 0.05),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Subtle texture or inner glow
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(size * 0.22),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1.5,
                ),
              ),
            ),
          ),
          // The "Finds" signature dots
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDot(size * 0.18),
                SizedBox(width: size * 0.08),
                _buildDot(size * 0.18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDot(double dotSize) {
    return Container(
      width: dotSize,
      height: dotSize,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: dotSize * 0.4,
            offset: Offset(0, dotSize * 0.2),
          ),
        ],
      ),
    );
  }
}

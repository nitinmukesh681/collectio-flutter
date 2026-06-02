import 'package:flutter/material.dart';
import '../models/category_type.dart';
import 'category_icons.dart';

/// Gradient cover fallback with a category-relevant Phosphor icon.
class CollectionCoverPlaceholder extends StatelessWidget {
  const CollectionCoverPlaceholder({
    super.key,
    required this.category,
    required this.seed,
    required this.gradientColors,
    this.iconSize = 44,
    this.iconOpacity = 0.55,
    this.borderRadius,
  });

  final CategoryType category;
  final String seed;
  final List<Color> gradientColors;
  final double iconSize;
  final double iconOpacity;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: CategoryPhosphorIcon(
          category: category,
          seed: seed,
          size: iconSize,
          color: Colors.white.withValues(alpha: iconOpacity),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/collection_entity.dart';
import '../models/category_type.dart';
import '../theme/app_theme.dart';

/// A beautiful grid card widget for displaying collections in a 2-column grid.
class CollectionGridCard extends StatelessWidget {
  final CollectionEntity collection;
  final VoidCallback? onTap;

  const CollectionGridCard({
    super.key,
    required this.collection,
    this.onTap,
  });

  IconData _categoryIcon() {
    switch (collection.category) {
      case CategoryType.food:
        return Icons.restaurant;
      case CategoryType.finance:
        return Icons.attach_money;
      case CategoryType.wellness:
        return Icons.spa;
      case CategoryType.career:
        return Icons.work_outline;
      case CategoryType.home:
        return Icons.home_outlined;
      case CategoryType.travel:
        return Icons.flight_takeoff;
      case CategoryType.tech:
        return Icons.computer;
      case CategoryType.gaming:
        return Icons.sports_esports;
      case CategoryType.entertainment:
        return Icons.movie_outlined;
      case CategoryType.shopping:
        return Icons.shopping_bag_outlined;
      case CategoryType.style:
        return Icons.checkroom;
      case CategoryType.books:
        return Icons.menu_book;
      case CategoryType.growth:
        return Icons.trending_up;
      case CategoryType.projects:
        return Icons.build;
      case CategoryType.creativity:
        return Icons.brush;
      case CategoryType.sports:
        return Icons.sports_soccer;
      case CategoryType.other:
        return Icons.category_outlined;
    }
  }

  Future<String?> _resolveCoverUrl() async {
    final candidate = (collection.coverImageUrl != null && collection.coverImageUrl!.isNotEmpty)
        ? collection.coverImageUrl!.trim()
        : (collection.previewImageUrls.isNotEmpty ? collection.previewImageUrls.first.trim() : '');
    if (candidate.isEmpty) return null;
    if (!(candidate.startsWith('http://') || candidate.startsWith('https://') || candidate.startsWith('gs://'))) {
      return null;
    }
    if (candidate.startsWith('gs://')) {
      try {
        return await FirebaseStorage.instance.refFromURL(candidate).getDownloadURL();
      } catch (_) {
        return null;
      }
    }
    return candidate;
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = AppColors.categoryGradients[collection.category.name] ??
        AppColors.categoryGradients['other']!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image / Gradient section
            Expanded(
              flex: 5,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  FutureBuilder<String?>(
                    future: _resolveCoverUrl(),
                    builder: (context, snap) {
                      final url = snap.data;
                      if (url == null || url.isEmpty) {
                        return Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: gradientColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              _categoryIcon(),
                              size: 36,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        );
                      }

                      return CachedNetworkImage(
                        imageUrl: url,
                        fit: BoxFit.cover,
                        placeholder: (context, _) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: gradientColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                        errorWidget: (context, _, __) => Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: gradientColors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              _categoryIcon(),
                              size: 36,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Gradient Overlay for bottom cover card readability
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.15),
                          Colors.transparent,
                          Colors.black.withOpacity(0.35),
                        ],
                      ),
                    ),
                  ),
                  // Likes Badge (top-right)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            collection.isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 11,
                            color: AppColors.heartSalmon,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${collection.likes}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.heartSalmon,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Info / text section
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category Pill text
                    Text(
                      collection.category.displayName.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: gradientColors[0],
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Title
                    Expanded(
                      child: Text(
                        collection.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Items Count & Privacy indicator
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${collection.itemCount} items',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!collection.isPublic)
                          const Icon(
                            Icons.lock_outline_rounded,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

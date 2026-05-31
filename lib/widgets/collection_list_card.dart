import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/collection_entity.dart';
import '../models/category_type.dart';
import '../theme/app_theme.dart';
import '../screens/collection_detail_screen.dart';

class CollectionListCard extends StatelessWidget {
  final CollectionEntity collection;
  final String currentUserId;
  final bool profileStyle;

  const CollectionListCard({
    super.key,
    required this.collection,
    required this.currentUserId,
    this.profileStyle = false,
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
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CollectionDetailScreen(
              collectionId: collection.id,
              currentUserId: currentUserId,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          border: Border.all(color: AppColors.divider),
          boxShadow: const [
            BoxShadow(
              color: Color(0x06000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: Cover Image/Gradient
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 80,
                height: 80,
                child: FutureBuilder<String?>(
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
                            size: 24,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      );
                    }

                    return CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
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
                            size: 24,
                            color: Colors.white.withOpacity(0.9),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 14),
            // Right: Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: gradientColors[0].withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          collection.category.displayName.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: gradientColors[0],
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            collection.isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 13,
                            color: AppColors.heartSalmon,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${collection.likes}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.heartSalmon,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    collection.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (collection.description != null && collection.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      collection.description!.trim(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '${collection.itemCount} items',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

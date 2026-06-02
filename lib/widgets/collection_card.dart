import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/collection_entity.dart';
import '../theme/app_theme.dart';
import '../utils/collection_cover_placeholder.dart';
import '../utils/category_icons.dart';

/// Collection card widget for displaying collections in lists
class CollectionCard extends StatelessWidget {
  final CollectionEntity collection;
  final VoidCallback? onTap;

  const CollectionCard({
    super.key,
    required this.collection,
    this.onTap,
  });

  static const List<Shadow> _coverTextShadow = [
    Shadow(color: Color(0x99000000), blurRadius: 10, offset: Offset(0, 1)),
  ];

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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover image or gradient
              AspectRatio(
                aspectRatio: 16 / 8,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    FutureBuilder<String?>(
                      future: _resolveCoverUrl(),
                      builder: (context, snap) {
                        final url = snap.data;
                        if (url == null || url.isEmpty) {
                          return CollectionCoverPlaceholder(
                            category: collection.category,
                            seed: collectionCoverSeed(
                              collectionId: collection.id,
                              title: collection.title,
                            ),
                            gradientColors: gradientColors,
                            iconSize: 48,
                            iconOpacity: 0.9,
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
                          errorWidget: (context, _, __) => CollectionCoverPlaceholder(
                            category: collection.category,
                            seed: collectionCoverSeed(
                              collectionId: collection.id,
                              title: collection.title,
                            ),
                            gradientColors: gradientColors,
                            iconSize: 48,
                            iconOpacity: 0.9,
                          ),
                        );
                      },
                    ),
                    // Category pill (top-left)
                    Positioned(
                      left: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          collection.category.displayName.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: gradientColors[0],
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                    // Like badge (top-right)
                    Positioned(
                      right: 12,
                      top: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              collection.isLiked ? Icons.favorite : Icons.favorite_border,
                              size: 14,
                              color: AppColors.heartSalmon,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${collection.likes}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.heartSalmon,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Title + metadata (bottom)
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collection.title,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.1,
                              shadows: _coverTextShadow,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Text(
                                '${collection.itemCount} items',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.85),
                                  fontWeight: FontWeight.w600,
                                  shadows: _coverTextShadow,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

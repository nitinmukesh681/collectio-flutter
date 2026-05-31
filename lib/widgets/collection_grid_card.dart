import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/collection_entity.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';

/// Profile grid card: full-bleed cover image with bottom gradient overlay.
class CollectionGridCard extends StatefulWidget {
  final CollectionEntity collection;
  final VoidCallback? onTap;

  const CollectionGridCard({super.key, required this.collection, this.onTap});

  @override
  State<CollectionGridCard> createState() => _CollectionGridCardState();
}

class _CollectionGridCardState extends State<CollectionGridCard> {
  late Future<String?> _coverUrlFuture;

  @override
  void initState() {
    super.initState();
    _coverUrlFuture = _resolveCoverUrl();
  }

  @override
  void didUpdateWidget(CollectionGridCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection.id != widget.collection.id) {
      _coverUrlFuture = _resolveCoverUrl();
    }
  }

  Future<String?> _resolveCoverUrl() async {
    final c = widget.collection;
    final candidate = (c.coverImageUrl != null && c.coverImageUrl!.isNotEmpty)
        ? c.coverImageUrl!.trim()
        : (c.previewImageUrls.isNotEmpty ? c.previewImageUrls.first.trim() : '');
    if (candidate.isEmpty) return null;
    if (candidate.startsWith('gs://')) {
      try {
        return await FirebaseStorage.instance.refFromURL(candidate).getDownloadURL();
      } catch (_) {
        return null;
      }
    }
    if (candidate.startsWith('http')) return candidate;
    return null;
  }

  IconData _visibilityIcon() {
    final c = widget.collection;
    if (c.visibility == CollectionVisibility.private || !c.isPublic) {
      return Icons.lock_outline_rounded;
    }
    if (c.visibility == CollectionVisibility.followers) {
      return Icons.people_outline_rounded;
    }
    return Icons.public_rounded;
  }

  /// Category accent on the dark image overlay — same hue as [AppColors.categoryLabelColor],
  /// lifted slightly when the base color is too dark to read on the gradient.
  Color _categoryLabelOnOverlay(String categoryName) {
    final base = AppColors.categoryLabelColor(categoryName);
    final hsl = HSLColor.fromColor(base);
    if (hsl.lightness < 0.55) {
      return hsl.withLightness(0.68).toColor();
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final gradientColors =
        AppColors.categoryGradients[collection.category.name] ??
        AppColors.categoryGradients['other']!;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.collectionCoverShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
          aspectRatio: 0.72,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder<String?>(
                future: _coverUrlFuture,
                builder: (context, snap) {
                  final url = snap.data;
                  if (url != null && url.isNotEmpty) {
                    return CachedNetworkImage(
                      imageUrl: url,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _fallbackCover(gradientColors),
                    );
                  }
                  return _fallbackCover(gradientColors);
                },
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.35, 0.65, 1.0],
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.35),
                      Colors.black.withValues(alpha: 0.78),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      collection.category.displayName.toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _categoryLabelOnOverlay(collection.category.name),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      collection.title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.12,
                        letterSpacing: -0.35,
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
                            fontWeight: FontWeight.w500,
                            color: Colors.white.withValues(alpha: 0.92),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '•',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                        Icon(
                          _visibilityIcon(),
                          size: 14,
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _fallbackCover(List<Color> colors) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          categoryIcon(widget.collection.category),
          size: 40,
          color: Colors.white.withValues(alpha: 0.55),
        ),
      ),
    );
  }
}

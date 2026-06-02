import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/collection_entity.dart';
import '../utils/collection_cover_placeholder.dart';
import '../utils/category_icons.dart';
import '../theme/app_theme.dart';

class CollaborationCard extends StatefulWidget {
  final CollectionEntity collection;
  final VoidCallback onTap;

  const CollaborationCard({super.key, required this.collection, required this.onTap});

  @override
  State<CollaborationCard> createState() => _CollaborationCardState();
}

class _CollaborationCardState extends State<CollaborationCard> {
  static const double _cardWidth = 220;
  static const double _cardHeight = 260;
  static const double _cardRadius = 18;

  late Future<String?> _coverUrlFuture;

  @override
  void initState() {
    super.initState();
    _coverUrlFuture = _resolveCoverUrl();
  }

  @override
  void didUpdateWidget(CollaborationCard oldWidget) {
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

  Widget _fallbackCover(List<Color> gradientColors) {
    return CollectionCoverPlaceholder(
      category: widget.collection.category,
      seed: collectionCoverSeed(
        collectionId: widget.collection.id,
        title: widget.collection.title,
      ),
      gradientColors: gradientColors,
      iconSize: 36,
    );
  }

  String? _locationLabel(CollectionEntity collection) {
    final raw = collection.googleMapsUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.contains('query=')) {
      try {
        final query = Uri.parse(raw).queryParameters['query'];
        if (query != null && query.isNotEmpty) {
          return Uri.decodeComponent(query.replaceAll('+', ' '));
        }
      } catch (_) {}
    }
    final placeMatch = RegExp(r'/place/([^/]+)').firstMatch(raw);
    if (placeMatch != null) {
      return Uri.decodeComponent(placeMatch.group(1)!).replaceAll('+', ' ');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final gradientColors =
        AppColors.categoryGradients[collection.category.name] ??
        AppColors.categoryGradients['other']!;
    final location = _locationLabel(collection);

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: _cardWidth,
        height: _cardHeight,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_cardRadius),
          boxShadow: AppColors.collectionCoverShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_cardRadius),
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
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.08),
                      Colors.black.withValues(alpha: 0.72),
                    ],
                    stops: const [0.45, 0.72, 1.0],
                  ),
                ),
              ),
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'COLLECTING',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.8,
                    ),
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
                      collection.title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        height: 1.15,
                        letterSpacing: -0.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (location != null) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Transform.translate(
                            offset: const Offset(-2, 0),
                            child: const Icon(Icons.location_on, size: 14, color: Colors.white),
                          ),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              location,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
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

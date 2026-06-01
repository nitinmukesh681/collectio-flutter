import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/collection_entity.dart';
import '../models/category_type.dart';
import '../theme/app_theme.dart';

class CollaborationCard extends StatefulWidget {
  final CollectionEntity collection;
  final VoidCallback onTap;

  const CollaborationCard({super.key, required this.collection, required this.onTap});

  @override
  State<CollaborationCard> createState() => _CollaborationCardState();
}

class _CollaborationCardState extends State<CollaborationCard> {
  static const double _cardRadius = 16;
  static const double _buttonRadius = 14;

  late Future<String?> _coverUrlFuture;

  @override
  void initState() {
    super.initState();
    _coverUrlFuture = _resolveCoverUrl();
  }

  @override
  void didUpdateWidget(CollaborationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection.id != widget.collection.id) _coverUrlFuture = _resolveCoverUrl();
  }

  Future<String?> _resolveCoverUrl() async {
    final c = widget.collection;
    final candidate = (c.coverImageUrl != null && c.coverImageUrl!.isNotEmpty)
        ? c.coverImageUrl!.trim()
        : (c.previewImageUrls.isNotEmpty ? c.previewImageUrls.first.trim() : '');
    if (candidate.isEmpty) return null;
    if (candidate.startsWith('gs://')) {
      try { return await FirebaseStorage.instance.refFromURL(candidate).getDownloadURL(); } catch (_) { return null; }
    }
    if (candidate.startsWith('http')) return candidate;
    return null;
  }

  IconData _categoryIcon() {
    switch (widget.collection.category) {
      case CategoryType.food: return Icons.restaurant;
      case CategoryType.finance: return Icons.attach_money;
      case CategoryType.wellness: return Icons.spa;
      case CategoryType.career: return Icons.work_outline;
      case CategoryType.home: return Icons.home_outlined;
      case CategoryType.travel: return Icons.flight_takeoff;
      case CategoryType.tech: return Icons.computer;
      case CategoryType.gaming: return Icons.sports_esports;
      case CategoryType.entertainment: return Icons.movie_outlined;
      case CategoryType.shopping: return Icons.shopping_bag_outlined;
      case CategoryType.style: return Icons.checkroom;
      case CategoryType.books: return Icons.menu_book;
      case CategoryType.growth: return Icons.trending_up;
      case CategoryType.projects: return Icons.build;
      case CategoryType.creativity: return Icons.brush;
      case CategoryType.sports: return Icons.sports_soccer;
      case CategoryType.other: return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final gradientColors = AppColors.categoryGradients[collection.category.name] ?? AppColors.categoryGradients['other']!;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        width: 260,
        margin: const EdgeInsets.only(right: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: AppColors.divider, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(_cardRadius)),
              child: SizedBox(
                height: 150,
                width: double.infinity,
                child: FutureBuilder<String?>(
                  future: _coverUrlFuture,
                  builder: (context, snap) {
                    final url = snap.data;
                    if (url != null && url.isNotEmpty) {
                      return CachedNetworkImage(
                        imageUrl: url, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _fallbackCover(gradientColors),
                      );
                    }
                    return _fallbackCover(gradientColors);
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    collection.title,
                    style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.2),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  if (collection.description != null && collection.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      collection.description!,
                      style: AppTextStyles.collectionDescription(fontSize: 13, height: 1.3),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: widget.onTap,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_buttonRadius)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: Text('Contribute', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14)),
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

  Widget _fallbackCover(List<Color> gradientColors) {
    return Container(
      decoration: BoxDecoration(gradient: LinearGradient(colors: gradientColors, begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Center(child: Icon(_categoryIcon(), size: 48, color: Colors.white.withOpacity(0.5))),
    );
  }
}

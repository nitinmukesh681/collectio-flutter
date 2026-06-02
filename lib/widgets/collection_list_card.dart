import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/collection_entity.dart';
import '../theme/app_theme.dart';
import '../utils/category_icons.dart';
import '../screens/collection_detail_screen.dart';

class CollectionListCard extends StatelessWidget {
  final CollectionEntity collection;
  final String currentUserId;
  final bool profileStyle;
  final bool collaborationStyle;

  const CollectionListCard({
    super.key,
    required this.collection,
    required this.currentUserId,
    this.profileStyle = false,
    this.collaborationStyle = false,
  });

  Future<String?> _resolveCover() async {
    final candidate = (collection.coverImageUrl != null && collection.coverImageUrl!.isNotEmpty)
        ? collection.coverImageUrl!.trim()
        : (collection.previewImageUrls.isNotEmpty ? collection.previewImageUrls.first.trim() : '');
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

  String _visibilityLabel() {
    if (collection.visibility == CollectionVisibility.followers) {
      return 'Followers';
    }
    return collection.isPublic ? 'Public' : 'Private';
  }

  @override
  Widget build(BuildContext context) {
    if (profileStyle) return _buildProfileCard(context);
    return _buildListCard(context);
  }

  Widget _buildCoverThumbnail(List<Color> gradientColors, {double size = 88}) {
    final thumbRadius = collaborationStyle ? 14.0 : 10.0;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(thumbRadius),
        boxShadow: collaborationStyle ? null : AppColors.collectionCoverShadow,
      ),
      child: ClipRRect(
      borderRadius: BorderRadius.circular(thumbRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: FutureBuilder<String?>(
          future: _resolveCover(),
          builder: (context, snap) {
            final url = snap.data;
            if (url != null && url.isNotEmpty) {
              return CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _defaultCover(gradientColors),
              );
            }
            return _defaultCover(gradientColors);
          },
        ),
      ),
    ),
    );
  }

  Widget _defaultCover(List<Color> gradientColors) {
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
          categoryIcon(collection.category),
          size: 32,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }

  Widget _buildCategoryLabel() {
    return Text(
      collection.category.displayName.toUpperCase(),
      style: GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: AppColors.categoryLabelColor(collection.category.name),
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    final gradientColors = AppColors.categoryGradients[collection.category.name] ??
        AppColors.categoryGradients['other']!;

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildCoverThumbnail(gradientColors, size: 80),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCategoryLabel(),
                  const SizedBox(height: 6),
                  Text(
                    collection.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.15,
                      letterSpacing: -0.35,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${collection.itemCount} items • ${_visibilityLabel()}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
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

  Widget _buildListCard(BuildContext context) {
    final gradientColors = AppColors.categoryGradients[collection.category.name] ??
        AppColors.categoryGradients['other']!;
    final description = collection.description?.trim();
    final thumbSize = collaborationStyle ? 80.0 : 88.0;

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        margin: EdgeInsets.only(bottom: collaborationStyle ? 12 : 16),
        padding: EdgeInsets.all(collaborationStyle ? 14 : 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(collaborationStyle ? 16 : AppColors.radiusLarge),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildCoverThumbnail(gradientColors, size: thumbSize),
            SizedBox(width: collaborationStyle ? 14 : 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildCategoryLabel(),
                  SizedBox(height: collaborationStyle ? 4 : 6),
                  Text(
                    collection.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: collaborationStyle ? 18 : 19,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.15,
                      letterSpacing: -0.35,
                    ),
                    maxLines: collaborationStyle ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    SizedBox(height: collaborationStyle ? 4 : 6),
                    Text(
                      description,
                      style: AppTextStyles.collectionDescription(
                        fontSize: collaborationStyle ? 13 : 14,
                        height: 1.4,
                      ),
                      maxLines: collaborationStyle ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: collaborationStyle ? 22 : 24,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CollectionDetailScreen(
          collectionId: collection.id,
          currentUserId: currentUserId,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/collection_entity.dart';
import '../models/category_type.dart';
import '../theme/app_theme.dart';
import 'user_avatar.dart';

class FeedCollectionCard extends StatelessWidget {
  final CollectionEntity collection;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback? onUserTap;

  const FeedCollectionCard({
    super.key,
    required this.collection,
    required this.onTap,
    required this.onLike,
    required this.onSave,
    this.onUserTap,
  });

  Future<String?> _resolveCoverUrl() async {
    final c = collection;
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

  @override
  Widget build(BuildContext context) {
    final gradientColors =
        AppColors.categoryGradients[collection.category.name] ??
        AppColors.categoryGradients['other']!;
    final description = collection.description?.trim();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('collections').doc(collection.id).snapshots(),
      builder: (context, snap) {
        final remoteCount = snap.data?.data()?['itemCount'];
        final remoteLikes = snap.data?.data()?['likes'];
        final itemCount = (remoteCount is int) ? remoteCount : collection.itemCount;
        final likes = (remoteLikes is int) ? remoteLikes : collection.likes;

        return GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppColors.cardShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: onUserTap,
                        child: UserAvatar(
                          userId: collection.userId,
                          avatarUrl: collection.userAvatarUrl,
                          name: collection.userName,
                          size: 42,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: onUserTap,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                collection.userName,
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                timeago
                                    .format(DateTime.fromMillisecondsSinceEpoch(collection.createdAt))
                                    .toUpperCase(),
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 11,
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Share.share(
                          'Check out ${collection.title} on Finds: https://collectio-b6b15.web.app/collection/${collection.id}',
                        ),
                        icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: AspectRatio(
                    aspectRatio: 16 / 10,
                    child: FutureBuilder<String?>(
                      future: _resolveCoverUrl(),
                      builder: (context, coverSnap) {
                        final url = coverSnap.data;
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
                  ),
                ),
              ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collection.title,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1.15,
                          letterSpacing: -0.35,
                        ),
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: AppTextStyles.collectionDescription(
                            fontSize: 14,
                            height: 1.45,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                  child: Row(
                    children: [
                      _buildStatColumn('$itemCount', 'ITEMS'),
                      const SizedBox(width: 20),
                      _buildStatColumn('$likes', 'LIKES'),
                      const Spacer(),
                      _buildActionButton(
                        icon: Icons.share_outlined,
                        onTap: () => Share.share(
                          'Check out ${collection.title} on Finds: https://collectio-b6b15.web.app/collection/${collection.id}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildActionButton(
                        icon: collection.isSaved
                            ? Icons.bookmark_rounded
                            : Icons.bookmark_border_rounded,
                        onTap: onSave,
                        filled: collection.isSaved,
                        fillColor: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      _buildActionButton(
                        icon: collection.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        onTap: onLike,
                        filled: collection.isLiked,
                        fillColor: AppColors.heartSalmon,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fallbackCover(List<Color> gradientColors) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(_categoryIcon(), size: 44, color: Colors.white.withValues(alpha: 0.55)),
      ),
    );
  }

  Widget _buildStatColumn(String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColors.textMuted,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    bool filled = false,
    Color? fillColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: filled ? (fillColor ?? AppColors.primary) : Colors.white,
          shape: BoxShape.circle,
          border: filled ? null : Border.all(color: AppColors.divider, width: 1.2),
        ),
        child: Icon(
          icon,
          size: 20,
          color: filled ? Colors.white : AppColors.textPrimary,
        ),
      ),
    );
  }
}

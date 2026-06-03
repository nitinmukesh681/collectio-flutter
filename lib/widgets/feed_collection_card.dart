import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../models/collection_entity.dart';
import '../utils/collection_cover_placeholder.dart';
import '../utils/category_icons.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_utils.dart';
import '../utils/avatar_display_utils.dart';
import '../providers/auth_provider.dart';
import 'user_avatar.dart';

class FeedCollectionCard extends StatelessWidget {
  final CollectionEntity collection;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback? onUserTap;
  final VoidCallback? onReport;
  final bool isOwnCollection;

  const FeedCollectionCard({
    super.key,
    required this.collection,
    required this.onTap,
    required this.onLike,
    required this.onSave,
    this.onUserTap,
    this.onReport,
    this.isOwnCollection = false,
  });

  static const Color _reportColor = AppColors.heartSalmon;

  void _showReportDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Report collection?',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'This collection will be reviewed by our team. Thank you for helping keep the community safe.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              'Cancel',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              onReport?.call();
            },
            child: Text(
              'Report',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                color: _reportColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

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

  Widget _fallbackCover(List<Color> gradientColors) {
    return CollectionCoverPlaceholder(
      category: collection.category,
      seed: collectionCoverSeed(
        collectionId: collection.id,
        title: collection.title,
      ),
      gradientColors: gradientColors,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final avatarUrl = displayAvatarUrl(
      storedAvatarUrl: collection.userAvatarUrl,
      subjectUserId: collection.userId,
      currentUserId: auth.userId,
      currentUserAvatarUrl: auth.userEntity?.avatarUrl,
    );
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
              borderRadius: BorderRadius.circular(20),
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
                          avatarUrl: avatarUrl,
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
                      PopupMenuButton<String>(
                        padding: EdgeInsets.zero,
                        offset: const Offset(0, 40),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        icon: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
                        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                        onSelected: (value) {
                          if (value != 'report') return;
                          if (isOwnCollection) {
                            SnackBarUtils.showInfoSnackBar(
                              context,
                              "You can't report your own collection",
                            );
                            return;
                          }
                          if (onReport != null) {
                            _showReportDialog(context);
                          } else {
                            SnackBarUtils.showInfoSnackBar(
                              context,
                              'Sign in to report this collection',
                            );
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'report',
                            child: Row(
                              children: [
                                const Icon(Icons.flag_outlined, color: _reportColor, size: 20),
                                const SizedBox(width: 12),
                                Text(
                                  'Report',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
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

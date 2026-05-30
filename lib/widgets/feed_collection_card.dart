import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../models/collection_entity.dart';
import '../models/collection_item_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'avatar_fallback.dart';

class FeedCollectionCard extends StatelessWidget {
  final CollectionEntity collection;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onSave;
  final VoidCallback? onUserTap;

  const FeedCollectionCard({
    super.key, required this.collection, required this.onTap,
    required this.onLike, required this.onSave, this.onUserTap,
  });

  Future<String?> _resolveAvatarUrl() async {
    final svc = FirestoreService();
    String? raw = collection.userAvatarUrl;
    if (raw == null || raw.trim().isEmpty) {
      try { raw = (await svc.getUser(collection.userId))?.avatarUrl; } catch (_) {}
    }
    if (raw == null || raw.isEmpty) return null;
    final t = raw.trim();
    if (t.startsWith('gs://')) { try { return await FirebaseStorage.instance.refFromURL(t).getDownloadURL(); } catch (_) { return null; } }
    if (t.startsWith('http')) return t;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final svc = FirestoreService();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('collections').doc(collection.id).snapshots(),
      builder: (context, snap) {
        final remoteCount = snap.data?.data()?['itemCount'];
        final itemCount = (remoteCount is int) ? remoteCount : collection.itemCount;

        return GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar + name + save
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: onUserTap,
                      child: SizedBox(
                        width: 44, height: 44,
                        child: ClipOval(
                          child: FutureBuilder<String?>(
                            future: _resolveAvatarUrl(),
                            builder: (context, s) {
                              final url = s.data;
                              if (url != null && url.isNotEmpty) {
                                return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _avatar());
                              }
                              return _avatar();
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: onUserTap,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('@${collection.userName}',
                              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 15, color: AppColors.textPrimary)),
                            Text('Published ${timeago.format(DateTime.fromMillisecondsSinceEpoch(collection.createdAt))}',
                              style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: onSave,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8, top: 2),
                        child: Icon(
                          collection.isSaved
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                          size: 24,
                          color: collection.isSaved
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Title - Changed from w800 to w700 to be slightly less bold than main headers
                Text(collection.title,
                  style: GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2, letterSpacing: -0.3)),

                const SizedBox(height: 16),

                // Numbered items
                StreamBuilder<List<CollectionItemEntity>>(
                  stream: svc.getCollectionItemsPreviewStream(collection.id, limit: 3),
                  builder: (context, snapshot) {
                    final items = snapshot.data ?? [];
                    if (items.isEmpty) return const SizedBox.shrink();
                    return Column(
                      children: [
                        for (int i = 0; i < items.length; i++) ...[
                          _itemRow(items[i], i + 1),
                          if (i < items.length - 1) const SizedBox(height: 10),
                        ],
                      ],
                    );
                  },
                ),

                const SizedBox(height: 18),

                // Footer
                Row(
                  children: [
                    GestureDetector(
                      onTap: onLike,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          collection.isLiked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 22,
                          color: collection.isLiked
                              ? AppColors.heartSalmon
                              : AppColors.textPrimary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${collection.likes}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 20),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('comments')
                          .where('collectionId', isEqualTo: collection.id)
                          .snapshots(),
                      builder: (context, commentSnap) {
                        final commentCount = commentSnap.data?.docs.length ?? 0;
                        return Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            size: 22,
                            color: AppColors.textPrimary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '$commentCount',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ]);
                      },
                    ),
                    const SizedBox(width: 20),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.inventory_2_outlined,
                          size: 22,
                          color: AppColors.textPrimary,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '$itemCount',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => Share.share(
                        'Check out ${collection.title} on Finds: https://collectio-b6b15.web.app/collection/${collection.id}',
                      ),
                      child: const Icon(
                        Icons.share_outlined,
                        size: 22,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _avatar() => AvatarFallback(name: collection.userName, size: 44);

  Widget _itemRow(CollectionItemEntity item, int rank) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Text(
            rank.toString().padLeft(2, '0'),
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              fontSize: 15,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.title,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:share_plus/share_plus.dart';
import '../models/collection_entity.dart';
import '../models/collection_item_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'package:timeago/timeago.dart' as timeago;

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

  @override
  Widget build(BuildContext context) {
    final firestoreService = FirestoreService();
    final coverUrl = (collection.coverImageUrl != null && collection.coverImageUrl!.isNotEmpty)
        ? collection.coverImageUrl
        : (collection.previewImageUrls.isNotEmpty ? collection.previewImageUrls.first : null);
    final hasCoverImage = coverUrl != null && coverUrl.isNotEmpty;

    Future<String?> resolveAvatarUrl() async {
      String? raw = collection.userAvatarUrl;
      if (raw == null || raw.trim().isEmpty) {
        try {
          final owner = await firestoreService.getUser(collection.userId);
          raw = owner?.avatarUrl;
        } catch (e) {
          debugPrint('Failed to fetch owner avatar for ${collection.userId}: $e');
          raw = null;
        }
      }
      if (raw == null || raw.isEmpty) return null;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      if (trimmed.startsWith('gs://')) {
        try {
          return await FirebaseStorage.instance.refFromURL(trimmed).getDownloadURL();
        } catch (e) {
          debugPrint('Failed to resolve gs:// avatar url: $trimmed, error: $e');
          return null;
        }
      }
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
      return null;
    }

    final gradientColors = AppColors.categoryGradients[collection.category.name] ??
        AppColors.categoryGradients['other']!;

    Future<String?> resolveCoverUrl() async {
      final raw = coverUrl;
      if (raw == null || raw.isEmpty) return null;
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return null;
      if (!(trimmed.startsWith('http://') || trimmed.startsWith('https://') || trimmed.startsWith('gs://'))) {
        return null;
      }
      if (trimmed.startsWith('gs://')) {
        try {
          return await FirebaseStorage.instance.refFromURL(trimmed).getDownloadURL();
        } catch (e) {
          debugPrint('Failed to resolve gs:// cover url: $trimmed, error: $e');
          return null;
        }
      }
      return trimmed;
    }
    
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('collections').doc(collection.id).snapshots(),
      builder: (context, snap) {
        final remoteCount = snap.data?.data()?['itemCount'];
        final itemCount = (remoteCount is int) ? remoteCount : collection.itemCount;

        return GestureDetector(
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                if (hasCoverImage)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 230,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: FutureBuilder<String?>(
                        future: resolveCoverUrl(),
                        builder: (context, snap) {
                          final resolved = snap.data;
                          if (resolved == null || resolved.isEmpty) {
                            return Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: gradientColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            );
                          }
                          return CachedNetworkImage(
                            imageUrl: resolved,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) {
                              debugPrint('Cover image failed: $url, error: $error');
                              return Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: gradientColors,
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(top: hasCoverImage ? 192 : 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    // Header: User Info
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: onUserTap,
                            child: SizedBox(
                              width: 34,
                              height: 34,
                              child: ClipOval(
                                child: FutureBuilder<String?>(
                                  future: resolveAvatarUrl(),
                                  builder: (context, snap) {
                                    final url = snap.data;
                                    if (url == null || url.isEmpty) {
                                      return Container(
                                        color: AppColors.primaryPurple.withOpacity(0.1),
                                        alignment: Alignment.center,
                                        child: Text(
                                          collection.userName.isNotEmpty
                                              ? collection.userName[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            color: AppColors.primaryPurple,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      );
                                    }

                                    return CachedNetworkImage(
                                      imageUrl: url,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) {
                                        return Container(
                                          color: AppColors.primaryPurple.withOpacity(0.1),
                                          alignment: Alignment.center,
                                          child: Text(
                                            collection.userName.isNotEmpty
                                                ? collection.userName[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              color: AppColors.primaryPurple,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        );
                                      },
                                    );
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
                                  Text(
                                    '@${collection.userName}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    timeago.format(DateTime.fromMillisecondsSinceEpoch(collection.createdAt)),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: onSave,
                            icon: Icon(
                              collection.isSaved ? Icons.bookmark : Icons.bookmark_border,
                              color: collection.isSaved ? AppColors.primaryPurple : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 4),

                    // Title & Description
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collection.title,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                            ),
                          ),
                          if (collection.description != null && collection.description!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              collection.description!,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.black87,
                                height: 1.4,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 6),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            ...collection.tags.take(3).map(
                                  (tag) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _buildCategoryChip('#$tag'),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Container(
                        height: 1,
                        color: const Color(0xFFE5E7EB),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Short preview of items
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: FutureBuilder<List<CollectionItemEntity>>(
                        future: firestoreService.getCollectionItemsPreview(collection.id, limit: 2),
                        builder: (context, snapshot) {
                          final items = snapshot.data ?? const <CollectionItemEntity>[];
                          if (items.isEmpty) {
                            return const SizedBox.shrink();
                          }

                          final remaining = (itemCount - items.length);

                          return Column(
                            children: [
                              for (int i = 0; i < items.length; i++)
                                Padding(
                                  padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 10),
                                  child: _buildPreviewRow(items[i], i + 1),
                                ),
                              if (remaining > 0) ...[
                                const SizedBox(height: 8),
                                Center(
                                  child: Text(
                                    '+$remaining more items',
                                    style: const TextStyle(
                                      color: Colors.black87,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 6),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                      child: Container(
                        height: 1,
                        color: const Color(0xFFE5E7EB),
                      ),
                    ),

                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: GestureDetector(
                                onTap: onLike,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      collection.isLiked ? Icons.favorite : Icons.favorite_border,
                                      color: collection.isLiked ? AppColors.heartSalmon : Colors.black87,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '${collection.likes}',
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.inventory_2_outlined, size: 20, color: Colors.black87),
                                  const SizedBox(width: 6),
                                  Text(
                                    '$itemCount items',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: IconButton(
                                onPressed: () {
                                  Share.share(
                                    'Check out ${collection.title} on Finds: https://collectio-b6b15.web.app/collection/${collection.id}',
                                  );
                                },
                                icon: const Icon(Icons.share_outlined, color: Colors.black87),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
          ),
        );
      },
    );
  }
  
  Widget _buildImageGrid(List<String> images) {
    if (images.length == 1) {
      return _buildRoundedImage(images[0]);
    } else if (images.length == 2) {
      return Row(
        children: [
          Expanded(child: _buildRoundedImage(images[0])),
          const SizedBox(width: 8),
          Expanded(child: _buildRoundedImage(images[1])),
        ],
      );
    } else {
      // 3 or more images
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildRoundedImage(images[0]),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: Column(
              children: [
                Expanded(child: _buildRoundedImage(images[1])),
                const SizedBox(height: 8),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildRoundedImage(images[2]),
                      if (images.length > 3)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              '+${images.length - 3}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
  }

  Widget _buildRoundedImage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (context, imageUrl, error) {
          return Container(
            color: const Color(0xFFF3F4F6),
            child: Center(
              child: const Icon(Icons.image_outlined, color: AppColors.textMuted, size: 28),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreviewRow(CollectionItemEntity item, int rank) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 18,
            child: Text(
              '$rank',
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.primaryPurple,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (item.rating > 0) ...[
                      const SizedBox(width: 8),
                      _buildRatingBadge(item.rating),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingBadge(double rating) {
    // Check if rating is old scale (0-5) or new scale (0-10)
    final displayScore = rating <= 5 ? rating * 2 : rating;
    final label = (displayScore % 1 == 0) ? displayScore.toStringAsFixed(0) : displayScore.toStringAsFixed(1);

    Color badgeColor;
    if (displayScore < 4) {
      badgeColor = Colors.red[700] ?? Colors.red;
    } else if (displayScore < 7) {
      badgeColor = Colors.amber[800] ?? Colors.amber;
    } else {
      badgeColor = Colors.green[700] ?? Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 11, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              color: badgeColor,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.primaryPurple.withOpacity(0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.primaryPurple,
        ),
      ),
    );
  }
}

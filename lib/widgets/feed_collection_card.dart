import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../models/collection_entity.dart';
import '../theme/app_theme.dart';
import 'package:timeago/timeago.dart' as timeago;

class FeedCollectionCard extends StatelessWidget {
  final CollectionEntity collection;
  final VoidCallback onTap;
  final VoidCallback onLike;
  final VoidCallback onSave;

  const FeedCollectionCard({
    super.key,
    required this.collection,
    required this.onTap,
    required this.onLike,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    // Ensure we have preview images (fallback to empty list if null)
    final previewImages = collection.previewImageUrls;
    final hasImages = previewImages.isNotEmpty;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: User Info
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.primaryPurple.withOpacity(0.1),
                    backgroundImage: collection.userAvatarUrl != null
                        ? CachedNetworkImageProvider(collection.userAvatarUrl!)
                        : null,
                    child: collection.userAvatarUrl == null
                        ? Text(
                            collection.userName[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primaryPurple,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '@${collection.userName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          timeago.format(
                            DateTime.fromMillisecondsSinceEpoch(collection.createdAt),
                          ),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_horiz, color: Colors.grey),
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'share',
                        child: Row(
                          children: [
                            Icon(Icons.share_outlined, size: 20, color: Colors.grey),
                            SizedBox(width: 12),
                            Text('Share'),
                          ],
                        ),
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'share') {
                        Share.share(
                          'Check out ${collection.title} on Finds: https://collectio-b6b15.web.app/collection/${collection.id}',
                        );
                      }
                    },
                  ),
                ],
              ),
            ),

            // Title & Description
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800, // Extra bold for premium feel
                      height: 1.2,
                    ),
                  ),
                  if (collection.description != null && collection.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      collection.description!,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 16),

            // Images Grid
            // Layout: 
            // If 1 image: Full width
            // If 2 images: 50/50 split vertical
            // If 3+ images: Big one left (66%), two stacked right (33%)
            if (hasImages)
              SizedBox(
                height: 280, // Fixed height for the grid
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildImageGrid(previewImages),
                ),
              )
            else if (collection.coverImageUrl != null)
              Container(
                height: 220,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: CachedNetworkImageProvider(collection.coverImageUrl!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Footer: Chips & Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  // Tags chips
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Main category chip
                          _buildChip(collection.category.name),
                          // Additional tags
                          ...collection.tags.take(2).map((tag) => 
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: _buildChip(tag),
                            )
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Actions
                  Row(
                    children: [
                      GestureDetector( // Like
                        onTap: onLike,
                        child: Row(
                          children: [
                            Icon(
                              collection.isLiked ? Icons.favorite : Icons.favorite_border,
                              color: collection.isLiked ? AppColors.heartSalmon : Colors.grey[600],
                              size: 22,
                            ),
                            if (collection.likes > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '${collection.likes}',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      GestureDetector( // Save
                        onTap: onSave,
                        child: Icon(
                          collection.isSaved ? Icons.bookmark : Icons.bookmark_border,
                          color: collection.isSaved ? AppColors.primaryPurple : Colors.grey[600],
                          size: 22,
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
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        image: DecorationImage(
          image: CachedNetworkImageProvider(url),
          fit: BoxFit.cover,
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.grey[700],
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

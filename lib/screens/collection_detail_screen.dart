import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../models/collection_entity.dart';
import '../models/collection_item_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'add_item_screen.dart';
import 'create_collection_screen.dart';
import 'user_profile_screen.dart';

class CollectionDetailScreen extends StatefulWidget {
  final String collectionId;
  final String currentUserId;

  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
    required this.currentUserId,
  });

  @override
  State<CollectionDetailScreen> createState() => _CollectionDetailScreenState();
}

class _CollectionDetailScreenState extends State<CollectionDetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  CollectionEntity? _collection;
  List<CollectionItemEntity> _items = [];
  bool _isLoading = true;
  bool _isOwner = false;
  String _searchQuery = '';
  bool _showSearch = false;
  String _currentUserName = '';

  @override
  void initState() {
    super.initState();
    _loadCollection();
    _loadCurrentUserName();
  }

  Future<void> _loadCurrentUserName() async {
    final user = await _firestoreService.getUser(widget.currentUserId);
    if (user != null && mounted) {
      setState(() => _currentUserName = user.userName);
    }
  }

  Future<void> _loadCollection() async {
    setState(() => _isLoading = true);
    try {
      final collection = await _firestoreService.getCollection(widget.collectionId);
      if (collection != null) {
        setState(() {
          _collection = collection.copyWith(
            isLiked: collection.likedBy.contains(widget.currentUserId),
          );
          _isOwner = collection.userId == widget.currentUserId;
        });
      }
    } catch (e) {
      debugPrint('Error loading collection: $e');
    }
    setState(() => _isLoading = false);

  }

  Future<void> _toggleLike() async {
    if (_collection == null) return;
    final wasLiked = _collection!.isLiked;
    
    setState(() {
      _collection = _collection!.copyWith(
        isLiked: !wasLiked,
        likes: wasLiked ? _collection!.likes - 1 : _collection!.likes + 1,
      );
    });

    try {
      if (wasLiked) {
        await _firestoreService.unlikeCollection(widget.collectionId, widget.currentUserId);
      } else {
        await _firestoreService.likeCollection(widget.collectionId, widget.currentUserId);
      }
    } catch (e) {
      // Revert on error
      setState(() {
        _collection = _collection!.copyWith(
          isLiked: wasLiked,
          likes: wasLiked ? _collection!.likes + 1 : _collection!.likes - 1,
        );
      });
    }
  }

  Future<void> _toggleSave() async {
    if (_collection == null) return;
    final wasSaved = _collection!.isSaved;
    
    setState(() {
      _collection = _collection!.copyWith(
        isSaved: !wasSaved,
        saveCount: wasSaved ? _collection!.saveCount - 1 : _collection!.saveCount + 1,
      );
    });

    try {
      if (wasSaved) {
        await _firestoreService.unsaveCollection(widget.collectionId, widget.currentUserId);
      } else {
        await _firestoreService.saveCollection(widget.collectionId, widget.currentUserId);
      }
    } catch (e) {
      // Revert on error
      setState(() {
        _collection = _collection!.copyWith(
          isSaved: wasSaved,
          saveCount: wasSaved ? _collection!.saveCount + 1 : _collection!.saveCount - 1,
        );
      });
    }
  }

  void _shareCollection() {
    if (_collection == null) return;
    Share.share(
      'Check out ${_collection!.title} on Finds: https://collectio-b6b15.web.app/collection/${_collection!.id}',
    );
  }

  void _navigateToAddItem([CollectionItemEntity? itemToEdit]) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddItemScreen(
          collectionId: widget.collectionId,
          userId: widget.currentUserId,
          userName: _currentUserName,
          existingItem: itemToEdit,
        ),
      ),
    ).then((result) {
      if (result == true) {
        // Item was added/edited, reload collection to update count
        _loadCollection();
      }
    });
  }

  void _navigateToEditCollection() {
    if (_collection == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCollectionScreen(
          userId: widget.currentUserId,
          userName: _currentUserName,
          existingCollection: _collection,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _loadCollection();
      }
    });
  }

  Future<void> _duplicateCollection() async {
    if (_collection == null) return;
    
    final shouldCopy = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Copy Collection?'),
        content: Text('This will create a copy of "${_collection!.title}" in your profile.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
            child: const Text('Copy'),
          ),
        ],
      ),
    );

    if (shouldCopy != true || !mounted) return;

    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Copying collection...')),
      );
      
      await _firestoreService.duplicateCollection(
        originalCollectionId: widget.collectionId,
        newOwnerId: widget.currentUserId,
        newOwnerName: _currentUserName,
        newTitle: '${_collection!.title} (Copy)',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Collection copied to your profile!')),
        );
      }
    } catch (e) {
      debugPrint('Error duplicating: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _deleteItem(CollectionItemEntity item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Item?'),
        content: Text('Are you sure you want to delete "${item.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _firestoreService.deleteItem(widget.collectionId, item.id);
    }
  }

  Future<void> _toggleItemLike(CollectionItemEntity item) async {
    final isLiked = item.likedBy.contains(widget.currentUserId);
    try {
      await _firestoreService.toggleItemLike(item.id, widget.currentUserId);
    } catch (e) {
      debugPrint('Error toggling item like: $e');
    }
  }

  void _navigateToUserProfile(String userId) {
    if (userId == widget.currentUserId) return; // Don't navigate to own profile
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: userId,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }

  List<CollectionItemEntity> get _filteredItems {
    if (_searchQuery.isEmpty) return _items;
    final query = _searchQuery.toLowerCase();
    return _items.where((item) {
      return item.title.toLowerCase().contains(query) ||
          (item.description?.toLowerCase().contains(query) ?? false);

    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_collection == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Collection not found')),
      );
    }

    final collection = _collection!;
    final hasCoverImage = collection.coverImageUrl != null && collection.coverImageUrl!.isNotEmpty;
    final gradientColors = AppColors.categoryGradients[collection.category.name] ?? 
        AppColors.categoryGradients['other']!;

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // Hero header with cover image
          SliverAppBar(
            expandedHeight: hasCoverImage ? 220 : 0,
            pinned: true,
            backgroundColor: hasCoverImage ? Colors.transparent : Colors.white,
            leading: _buildCircleButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.pop(context),
            ),
            actions: [
              _buildCircleButton(
                icon: Icons.search,
                onTap: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) _searchQuery = '';
                  });
                },
              ),
              _buildCircleButton(
                icon: Icons.share_outlined,
                onTap: _shareCollection,
              ),
              if (_isOwner)
                PopupMenuButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                  ),
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit collection')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') {
                      _navigateToEditCollection();
                    } else if (value == 'delete') {
                      _showDeleteDialog();
                    }
                  },
                ),

              const SizedBox(width: 8),
            ],
            flexibleSpace: hasCoverImage
                ? FlexibleSpaceBar(
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: collection.coverImageUrl!,
                          fit: BoxFit.cover,
                        ),
                        // Bottom rounded overlay
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 32,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),

          // Collection info
          SliverToBoxAdapter(
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User info row
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          // Navigate to user profile
                        },
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.primaryPurple.withOpacity(0.2),
                              backgroundImage: collection.userAvatarUrl != null
                                  ? CachedNetworkImageProvider(collection.userAvatarUrl!)
                                  : null,
                              child: collection.userAvatarUrl == null
                                  ? Text(
                                      collection.userName[0].toUpperCase(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryPurple,
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  collection.userName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                Text(
                                  _getTimeAgo(collection.createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (!_isOwner)
                        OutlinedButton(
                          onPressed: () {
                            // Follow user
                          },
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: const Text('Follow'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    collection.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  // Description
                  if (collection.description != null && collection.description!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      collection.description!,
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],

                  // Tags
                  if (collection.tags.isNotEmpty || collection.isOpenForContribution) ...[
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...collection.tags.map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryPurple.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '#${tag.toLowerCase()}',
                            style: const TextStyle(
                              color: AppColors.primaryPurple,
                              fontSize: 12,
                            ),
                          ),
                        )),
                        if (collection.isOpenForContribution)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.primaryPurpleDark,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'OPEN',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],

                  // Stats row
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _buildStatChip(Icons.favorite, '${collection.likes} likes', AppColors.heartSalmon),
                      const SizedBox(width: 18),
                      _buildStatChip(Icons.inventory_2_outlined, '${collection.itemCount} items', Colors.grey[700]!),
                      const SizedBox(width: 18),
                      _buildStatChip(
                        Icons.language,
                        collection.isPublic ? 'Public' : 'Private',
                        Colors.grey[700]!,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Search bar (if active)
          if (_showSearch)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search items...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _showSearch = false;
                          _searchQuery = '';
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),
            ),

          // Items header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              child: Row(
                children: [
                  Text(
                    'Items (${_filteredItems.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_isOwner || collection.isOpenForContribution)
                    TextButton.icon(
                      onPressed: () => _navigateToAddItem(),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add'),
                    ),

                ],
              ),
            ),
          ),

          // Items list
          StreamBuilder<List<CollectionItemEntity>>(
            stream: _firestoreService.getCollectionItems(widget.collectionId),
            builder: (context, snapshot) {
              if (snapshot.hasData) {
                _items = snapshot.data!;
              }

              final items = _filteredItems;

              if (items.isEmpty) {
                return const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No items yet', style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final item = items[index];
                    return _buildItemCard(item, index + 1);
                  },
                  childCount: items.length,
                ),
              );
            },
          ),

          // Bottom padding for action bar
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),

      // Bottom action bar
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleLike,
                icon: Icon(
                  collection.isLiked ? Icons.favorite : Icons.favorite_border,
                  color: collection.isLiked ? AppColors.heartSalmon : Colors.black,
                  size: 18,
                ),
                label: const Text('Like'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleSave,
                icon: Icon(
                  collection.isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: collection.isSaved ? AppColors.primaryPurple : Colors.black,
                  size: 18,
                ),
                label: const Text('Save'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _duplicateCollection,
                icon: const Icon(Icons.copy, size: 18),
                label: const Text('Copy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            if (_isOwner || collection.isOpenForContribution) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 52,
                child: ElevatedButton(
                  onPressed: () => _navigateToAddItem(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Icon(Icons.add, size: 22),
                ),
              ),
            ],
          ],

        ),
      ),
    );
  }

  Widget _buildCircleButton({required IconData icon, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
      ],
    );
  }

  Widget _buildItemCard(CollectionItemEntity item, int rank) {
    final hasImage = item.imageUrls.isNotEmpty;
    final isLiked = item.likedBy.contains(widget.currentUserId);
    final canEdit = _isOwner || item.userId == widget.currentUserId;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          if (hasImage)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: CachedNetworkImage(
                  imageUrl: item.imageUrls.first,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[200],
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ),
            ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Rank and title
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.primaryPurple.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '$rank',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryPurple,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.rating > 0) ...[
                            const SizedBox(height: 4),
                            RatingBarIndicator(
                              rating: item.rating,
                              itemSize: 16,
                              itemBuilder: (context, _) => const Icon(
                                Icons.star,
                                color: Colors.amber,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                // Description
                if (item.description != null && item.description!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    item.description!,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],

                // Links
                if (item.googleMapsUrl != null || item.websiteUrl != null) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (item.googleMapsUrl != null)
                        _buildLinkChip(Icons.map, 'Maps', item.googleMapsUrl!),
                      if (item.websiteUrl != null)
                        _buildLinkChip(Icons.link, 'Website', item.websiteUrl!),
                    ],
                  ),
                ],

                // Action buttons
                const SizedBox(height: 12),
                Row(
                  children: [
                    // Like button
                    GestureDetector(
                      onTap: () => _toggleItemLike(item),
                      child: Row(
                        children: [
                          Icon(
                            isLiked ? Icons.favorite : Icons.favorite_border,
                            size: 20,
                            color: isLiked ? AppColors.heartSalmon : Colors.grey[600],
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${item.likes}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    // Edit button (only for owner or item creator)
                    if (canEdit)
                      GestureDetector(
                        onTap: () => _navigateToAddItem(item),
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined, size: 20, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text('Edit', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          ],
                        ),
                      ),
                    if (canEdit) const SizedBox(width: 24),
                    // Delete button (only for owner)
                    if (_isOwner)
                      GestureDetector(
                        onTap: () => _deleteItem(item),
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 20, color: Colors.grey[600]),
                            const SizedBox(width: 4),
                            Text('Delete', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

  }

  Widget _buildLinkChip(IconData icon, String label, String url) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primaryPurple.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.primaryPurple),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.primaryPurple,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Collection?'),
        content: const Text('This will permanently delete the collection and all its items.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _firestoreService.deleteCollection(
                widget.collectionId,
                widget.currentUserId,
              );
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _getTimeAgo(int timestamp) {
    final now = DateTime.now();
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = now.difference(date);

    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}y ago';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}mo ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'now';
    }
  }
}

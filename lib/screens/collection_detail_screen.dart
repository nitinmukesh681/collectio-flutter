import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/collection_entity.dart';
import '../models/collection_item_entity.dart';
import '../models/user_entity.dart';
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
  List<UserEntity> _contributorUsers = [];
  bool _isLoading = true;
  bool _isOwner = false;
  String _searchQuery = '';
  final Set<String> _expandedItemIds = <String>{};
  bool _showSearch = false;
  String _currentUserName = '';

  bool _isFollowing = false;
  bool _isAddToCollectionsLoading = false;
  bool _isUnauthorized = false;
  
  @override
  void initState() {
    super.initState();
    _loadCollection();
    _loadCurrentUserName();
  }

  Widget _buildRatingBadge(double rating, {double fontSize = 12}) {
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: fontSize, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              color: badgeColor,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIconChip({required IconData icon, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF111827).withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: Colors.black87),
      ),
    );
  }

  Widget _buildTrailingChips(CollectionItemEntity item) {
    if (item.rating <= 0) return const SizedBox.shrink();
    return _buildRatingBadge(item.rating, fontSize: 12);
  }

  double _trailingUnitReservedWidth(CollectionItemEntity item) {
    // Reserve enough right-side width so title/description never render under the
    // trailing unit (chips + menu). Keep this tight so there's no excessive whitespace.
    const menuWidth = 20.0;
    const gapBetweenChipsAndMenu = 8.0;
    const leftPaddingBeforeTrailing = 8.0;

    // Approximate chip widths (they are fairly consistent due to fixed padding).
    const ratingChipWidth = 54.0;
    final hasRating = item.rating > 0;

    double chipsWidth = 0;
    if (hasRating) chipsWidth += ratingChipWidth;

    final total = leftPaddingBeforeTrailing + chipsWidth + gapBetweenChipsAndMenu + menuWidth;
    // Never reserve less than the menu + gaps.
    return total < 44 ? 44 : total;
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
        final isFollowing = await _firestoreService.isFollowing(
          widget.currentUserId, 
          collection.userId
        );

        final isOwner = collection.userId == widget.currentUserId;
        final canView = _canViewCollection(collection, isOwner: isOwner, isFollowing: isFollowing);
        
        if (mounted) {
          setState(() {
            _collection = collection.copyWith(
              isLiked: collection.likedBy.contains(widget.currentUserId),
              isSaved: collection.savedBy.contains(widget.currentUserId),
            );
            _isOwner = isOwner;
            _isFollowing = isFollowing;
            _isUnauthorized = !canView;
          });
        }

        await _loadContributors(collection);
      }
    } catch (e) {
      debugPrint('Error loading collection: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadContributors(CollectionEntity collection) async {
    final rawIds = collection.contributorIds;
    if (rawIds.isEmpty) {
      if (mounted) setState(() => _contributorUsers = []);
      return;
    }

    final ids = rawIds.where((id) => id.trim().isNotEmpty && id != collection.userId).toList();
    if (ids.isEmpty) {
      if (mounted) setState(() => _contributorUsers = []);
      return;
    }

    try {
      final users = await _firestoreService.getUsersByIds(ids);
      if (mounted) {
        setState(() {
          _contributorUsers = users;
        });
      }
    } catch (e) {
      debugPrint('Error loading contributors: $e');
    }
  }

  void _showContributorsSheet(CollectionEntity collection) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final users = _contributorUsers;
        final ownerName = collection.userName;
        final rawOwnerAvatar = collection.userAvatarUrl;

        Widget buildAvatar({required String name, required String? avatarUrl}) {
          final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
          return ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: (avatarUrl != null && avatarUrl.trim().isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: avatarUrl,
                    width: 36,
                    height: 36,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 36,
                      height: 36,
                      color: AppColors.primaryPurple.withOpacity(0.2),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: AppColors.primaryPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 36,
                      height: 36,
                      color: AppColors.primaryPurple.withOpacity(0.2),
                      alignment: Alignment.center,
                      child: Text(
                        initials,
                        style: const TextStyle(
                          color: AppColors.primaryPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                : Container(
                    width: 36,
                    height: 36,
                    color: AppColors.primaryPurple.withOpacity(0.2),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: AppColors.primaryPurple,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
          );
        }

        Widget buildOwnerTile() {
          if (rawOwnerAvatar == null || rawOwnerAvatar.trim().isEmpty) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: buildAvatar(name: ownerName, avatarUrl: null),
              title: Text(
                '@$ownerName',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Owner', style: Theme.of(context).textTheme.bodySmall),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(
                      userId: collection.userId,
                      currentUserId: widget.currentUserId,
                    ),
                  ),
                );
              },
            );
          }

          final trimmed = rawOwnerAvatar!.trim();
          if (!trimmed.startsWith('gs://')) {
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: buildAvatar(name: ownerName, avatarUrl: trimmed),
              title: Text(
                '@$ownerName',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Owner', style: Theme.of(context).textTheme.bodySmall),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(
                      userId: collection.userId,
                      currentUserId: widget.currentUserId,
                    ),
                  ),
                );
              },
            );
          }

          return FutureBuilder<String>(
            future: FirebaseStorage.instance.refFromURL(trimmed).getDownloadURL(),
            builder: (context, snapshot) {
              final resolved = snapshot.data;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: buildAvatar(name: ownerName, avatarUrl: resolved),
                title: Text(
                  '@$ownerName',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('Owner', style: Theme.of(context).textTheme.bodySmall),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserProfileScreen(
                        userId: collection.userId,
                        currentUserId: widget.currentUserId,
                      ),
                    ),
                  );
                },
              );
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Contributors',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.55,
                  child: ListView.separated(
                    itemCount: users.length + 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == 0) return buildOwnerTile();

                      final u = users[index - 1];
                      final name = u.userName;
                      final avatarUrl = u.avatarUrl;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: buildAvatar(name: name, avatarUrl: avatarUrl),
                        title: Text(
                          '@$name',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                userId: u.id,
                                currentUserId: widget.currentUserId,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _canViewCollection(
    CollectionEntity c, {
    required bool isOwner,
    required bool isFollowing,
  }) {
    if (isOwner) return true;

    // Public collections are always viewable.
    if (c.isPublic || c.visibility == CollectionVisibility.public) return true;

    // Followers-only visibility.
    if (c.visibility == CollectionVisibility.followers) {
      return isFollowing;
    }

    // Private collections: allow collaborators/editors/viewers.
    final uid = widget.currentUserId;
    if (c.editors.contains(uid) || c.viewers.contains(uid)) return true;
    for (final collab in c.collaborators) {
      final id = collab['userId'];
      if (id is String && id == uid) return true;
    }
    return false;
  }

  Future<void> _toggleFollowUser() async {
    if (_collection == null) return;
    final targetUserId = _collection!.userId;
 
    final wasFollowing = _isFollowing;

    // Optimistic update
    setState(() => _isFollowing = !wasFollowing);

    try {
      if (wasFollowing) {
        await _firestoreService.unfollowUser(widget.currentUserId, targetUserId);
      } else {
        await _firestoreService.followUser(
          widget.currentUserId,
          targetUserId,
          _currentUserName,
        );
      }
    } catch (e) {
      // Revert
      if (mounted) setState(() => _isFollowing = wasFollowing);
      debugPrint('Error toggling follow: $e');
    }
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
      await _firestoreService.toggleCollectionLike(widget.collectionId, widget.currentUserId);
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
      await _firestoreService.toggleCollectionSave(widget.collectionId, widget.currentUserId);
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

  Future<void> _showAddToCollectionsDialog(CollectionItemEntity item) async {
    if (_isAddToCollectionsLoading) return;

    setState(() => _isAddToCollectionsLoading = true);
    List<CollectionEntity> myCollections = [];
    try {
      myCollections = await _firestoreService.getUserCollections(widget.currentUserId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load collections: $e')),
        );
      }
      setState(() => _isAddToCollectionsLoading = false);
      return;
    }
    if (!mounted) return;
    setState(() => _isAddToCollectionsLoading = false);

    final selected = <String>{};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: const Text('Add to collections'),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: myCollections.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final c = myCollections[index];
                  final isChecked = selected.contains(c.id);
                  return InkWell(
                    onTap: () {
                      setStateDialog(() {
                        if (isChecked) {
                          selected.remove(c.id);
                        } else {
                          selected.add(c.id);
                        }
                      });
                    },
                    child: Row(
                      children: [
                        Checkbox(
                          value: isChecked,
                          onChanged: (value) {
                            setStateDialog(() {
                              if (value == true) {
                                selected.add(c.id);
                              } else {
                                selected.remove(c.id);
                              }
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            c.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true),
                child: const Text('Add'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || selected.isEmpty) return;
    if (!mounted) return;

    try {
      for (final collectionId in selected) {
        final newItem = CollectionItemEntity(
          id: '',
          collectionId: collectionId,
          userId: widget.currentUserId,
          userName: _currentUserName,
          title: item.title,
          description: item.description,
          rating: item.rating,
          imageUrls: item.imageUrls,
          googleMapsUrl: item.googleMapsUrl,
          websiteUrl: item.websiteUrl,
          likes: 0,
          likedBy: const [],
        );
        await _firestoreService.addCollectionItem(collectionId, newItem);
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Added to collections')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add to collections: $e')),
        );
      }
    }
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
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
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
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _firestoreService.deleteItem(widget.collectionId, item.id);
    }
  }

  Future<void> _toggleItemLike(CollectionItemEntity item) async {
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

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Collection?'),
        content: const Text('This will permanently delete the collection and all its items.'),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () async {
              Navigator.pop(context);
              await _firestoreService.deleteCollection(
                widget.collectionId,
                widget.currentUserId,
              );
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isUnauthorized) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_left),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('This collection is private'),
        ),
      );
    }

    if (_collection == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Collection not found')),
      );
    }

    final collection = _collection!;
    bool isValidCoverUrl(String? raw) {
      if (raw == null) return false;
      final v = raw.trim();
      if (v.isEmpty) return false;
      return v.startsWith('http://') || v.startsWith('https://') || v.startsWith('gs://');
    }

    final hasCoverImage = isValidCoverUrl(collection.coverImageUrl);
    final gradientColors = AppColors.categoryGradients[collection.category.name] ?? 
        AppColors.categoryGradients['other']!;

    Future<String?> resolveOwnerAvatarUrl() async {
      String? raw = collection.userAvatarUrl;
      if (raw == null || raw.trim().isEmpty) {
        try {
          final owner = await _firestoreService.getUser(collection.userId);
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
          debugPrint('Failed to resolve gs:// owner avatar url: $trimmed, error: $e');
          return null;
        }
      }
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return trimmed;
      }
      return null;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          // Hero header with cover image
          SliverAppBar(
            expandedHeight: hasCoverImage ? 260 : kToolbarHeight,
            pinned: true,
            backgroundColor: hasCoverImage ? Colors.transparent : Colors.white,
            leadingWidth: 56,
            leading: Center(
              child: _buildCircleButton(
                icon: Icons.keyboard_arrow_left,
                onTap: () => Navigator.pop(context),
              ),
            ),
            actions: [
              _buildCircleButton(
                icon: Icons.search_rounded,
                onTap: () {
                  setState(() {
                    _showSearch = !_showSearch;
                    if (!_showSearch) _searchQuery = '';
                  });
                },
              ),
              _buildCircleButton(
                icon: Icons.share,
                onTap: _shareCollection,
              ),
              Theme(
                data: Theme.of(context).copyWith(
                  iconButtonTheme: IconButtonThemeData(
                    style: IconButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(40, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.more_horiz, color: Colors.white, size: 22),
                  ),
                  itemBuilder: (context) => [
                    if (_isOwner)
                      const PopupMenuItem(value: 'edit', child: Text('Edit collection')),
                    if (_isOwner)
                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    if (!_isOwner)
                      const PopupMenuItem(value: 'add_to_new', child: Text('Add to new collection')),
                  ],
                  onSelected: (value) {
                    if (value == 'edit') {
                      _navigateToEditCollection();
                    } else if (value == 'delete') {
                      _showDeleteDialog();
                    } else if (value == 'add_to_new') {
                      _duplicateCollection();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
            ],
            flexibleSpace: hasCoverImage
                ? FlexibleSpaceBar(
                    background: Stack(
                    fit: StackFit.expand,
                    children: [
                      FutureBuilder<String?>(
                        future: () async {
                          final raw = collection.coverImageUrl;
                          if (raw == null || raw.isEmpty) return null;
                          if (raw.startsWith('gs://')) {
                            try {
                              return await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
                            } catch (_) {
                              return null;
                            }
                          }
                          return raw;
                        }(),
                        builder: (context, snap) {
                          final url = snap.data;
                          if (url == null || url.isEmpty) {
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
                          return ClipPath(
                            clipper: const _CoverBottomCurveClipper(),
                            child: CachedNetworkImage(
                              imageUrl: url,
                              fit: BoxFit.cover,
                              errorWidget: (context, u, error) {
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
                            ),
                          );
                        },
                      ),
                      // Overlay gradient
                      ClipPath(
                        clipper: const _CoverBottomCurveClipper(),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.25),
                                Colors.black.withOpacity(0.7),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Rounded white sheet header (inside the app bar)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 32,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.zero,
              ),
              padding: EdgeInsets.fromLTRB(18, hasCoverImage ? 2 : 10, 18, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User info row
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => UserProfileScreen(
                                userId: collection.userId,
                                currentUserId: widget.currentUserId,
                              ),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              height: 40,
                              child: ClipOval(
                                child: FutureBuilder<String?>(
                                  future: resolveOwnerAvatarUrl(),
                                  builder: (context, snap) {
                                    final url = snap.data;
                                    final initials = collection.userName.isNotEmpty ? collection.userName[0].toUpperCase() : '?';
                                    if (url == null || url.isEmpty) {
                                      return Container(
                                        color: AppColors.primaryPurple.withOpacity(0.2),
                                        alignment: Alignment.center,
                                        child: Text(
                                          initials,
                                          style: const TextStyle(
                                            color: AppColors.primaryPurple,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 18,
                                          ),
                                        ),
                                      );
                                    }

                                    return CachedNetworkImage(
                                      imageUrl: url,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) {
                                        return Container(
                                          color: AppColors.primaryPurple.withOpacity(0.2),
                                          alignment: Alignment.center,
                                          child: Text(
                                            initials,
                                            style: const TextStyle(
                                              color: AppColors.primaryPurple,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 18,
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => UserProfileScreen(
                                              userId: collection.userId,
                                              currentUserId: widget.currentUserId,
                                            ),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        '@${collection.userName}',
                                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ),
                                    if (_contributorUsers.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () => _showContributorsSheet(collection),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          child: Text(
                                            '+ ${_contributorUsers.length} others',
                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: AppColors.primaryPurple,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(
                                  _getTimeAgo(collection.createdAt),
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: Colors.black87,
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
                          onPressed: _toggleFollowUser,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _isFollowing
                                ? AppColors.primaryPurple.withOpacity(0.08)
                                : Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                            side: const BorderSide(color: AppColors.primaryPurple),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          child: Text(
                            _isFollowing ? 'Following' : 'Follow',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.primaryPurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Title
                  Text(
                    collection.title,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  // Description
                  if (collection.description != null && collection.description!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      collection.description!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 15,
                        color: Colors.black87,
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
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                            child: Text(
                              'OPEN',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                      _buildStatChip(Icons.favorite_rounded, '${collection.likes} likes', AppColors.heartSalmon),
                      const SizedBox(width: 18),
                      _buildStatChip(Icons.grid_view_rounded, '${collection.itemCount} items', Colors.black87),
                      const SizedBox(width: 18),
                      _buildStatChip(Icons.public_rounded, collection.isPublic ? 'Public' : 'Private', Colors.black87),
                      const Spacer(),
                      if ((collection.websiteUrl ?? '').trim().isNotEmpty) ...[
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            var raw = (collection.websiteUrl ?? '').trim();
                            if (raw.isEmpty) return;
                            if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
                              raw = 'https://$raw';
                            }
                            final uri = Uri.tryParse(raw);
                            if (uri == null) return;
                            try {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not open link')),
                                );
                              }
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.link_rounded, size: 18, color: Colors.black87),
                          ),
                        ),
                      ],
                      if ((collection.googleMapsUrl ?? '').trim().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            final raw = (collection.googleMapsUrl ?? '').trim();
                            if (raw.isEmpty) return;
                            final uri = Uri.tryParse(raw);
                            if (uri == null) return;
                            try {
                              await launchUrl(uri, mode: LaunchMode.externalApplication);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Could not open location')),
                                );
                              }
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Icons.location_on_rounded, size: 18, color: Colors.black87),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 18),
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
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.close_rounded),
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
                    fillColor: Theme.of(context).inputDecorationTheme.fillColor,
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
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
                return SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.inventory_2_rounded, size: 64, color: AppColors.textMuted),
                        const SizedBox(height: 16),
                        Text(
                          'No items yet',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
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
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleLike,
                icon: Icon(
                  collection.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: collection.isLiked ? AppColors.heartSalmon : Colors.black,
                  size: 18,
                ),
                label: const Text('Like'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  foregroundColor: Colors.black87,
                  backgroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _toggleSave,
                icon: Icon(
                  collection.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                  color: collection.isSaved ? AppColors.primaryPurple : Colors.black,
                  size: 18,
                ),
                label: const Text('Save'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                  foregroundColor: Colors.black87,
                  backgroundColor: Colors.white,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _duplicateCollection,
                icon: const Icon(Icons.copy_all_rounded, size: 18),
                label: const Text('Copy'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryPurple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
              ),
            ),
            if (_isOwner || collection.isOpenForContribution) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _navigateToAddItem(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    foregroundColor: Colors.black87,
                    backgroundColor: Colors.white,
                    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
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
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildItemCard(CollectionItemEntity item, int rank) {
    final canEdit = _isOwner || item.userId == widget.currentUserId;
    // Keep item rows compact and prevent text from flowing under trailing actions.
    const titleMaxLines = 3;
    const descriptionMaxLines = 2;
    final isExpanded = _expandedItemIds.contains(item.id);
    const leadingWidth = 28.0;
    const leadingGap = 12.0;
    final trailingTextInset = _trailingUnitReservedWidth(item);
    const expandedHeaderTopPad = 2.0;
    const imageMaxHeight = 240.0;

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isExpanded) {
            _expandedItemIds.remove(item.id);
          } else {
            _expandedItemIds.add(item.id);
          }
        });
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFF1F5F9)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: leadingWidth,
                  child: Padding(
                    padding: const EdgeInsets.only(top: expandedHeaderTopPad),
                    child: Text(
                      '$rank',
                      textAlign: TextAlign.center,
                      softWrap: false,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primaryPurple,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: leadingGap),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: expandedHeaderTopPad, right: 10),
                    child: Text(
                      item.title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
                        height: 1.2,
                      ),
                      maxLines: isExpanded ? null : titleMaxLines,
                      softWrap: true,
                      overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: expandedHeaderTopPad),
                  child: _buildTrailingChips(item),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: expandedHeaderTopPad),
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    onSelected: (value) {
                      if (value == 'edit') {
                        _navigateToAddItem(item);
                      } else if (value == 'delete') {
                        _deleteItem(item);
                      } else if (value == 'add_to_collections') {
                        _showAddToCollectionsDialog(item);
                      } else if (value == 'open_link') {
                        var raw = (item.websiteUrl ?? '').trim();
                        if (raw.isEmpty) return;
                        if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
                          raw = 'https://$raw';
                        }
                        final uri = Uri.tryParse(raw);
                        if (uri == null) return;
                        launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not open link')),
                          );
                        });
                      } else if (value == 'open_location') {
                        final raw = (item.googleMapsUrl ?? '').trim();
                        if (raw.isEmpty) return;
                        final uri = Uri.tryParse(raw);
                        if (uri == null) return;
                        launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not open location')),
                          );
                        });
                      }
                    },
                    itemBuilder: (context) => [
                      if ((item.websiteUrl ?? '').trim().isNotEmpty)
                        const PopupMenuItem(
                          value: 'open_link',
                          child: Row(
                            children: [
                              Icon(Icons.link_rounded, size: 18, color: Colors.black87),
                              SizedBox(width: 10),
                              Text('Link'),
                            ],
                          ),
                        ),
                      if ((item.googleMapsUrl ?? '').trim().isNotEmpty)
                        const PopupMenuItem(
                          value: 'open_location',
                          child: Row(
                            children: [
                              Icon(Icons.location_on_rounded,
                                  size: 18, color: Colors.black87),
                              SizedBox(width: 10),
                              Text('Location'),
                            ],
                          ),
                        ),
                      if (canEdit)
                        const PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_rounded, size: 18, color: Colors.black87),
                              SizedBox(width: 10),
                              Text('Edit'),
                            ],
                          ),
                        ),
                      if (_isOwner)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete_rounded, size: 18, color: Colors.red[700]),
                              const SizedBox(width: 10),
                              const Text('Delete'),
                            ],
                          ),
                        ),
                      const PopupMenuItem(
                        value: 'add_to_collections',
                        child: Row(
                          children: [
                            Icon(Icons.add_rounded, size: 18, color: Colors.black87),
                            SizedBox(width: 10),
                            Text('Add to another collection'),
                          ],
                        ),
                      ),
                    ],
                    child: const Icon(Icons.more_horiz, size: 20, color: Colors.black87),
                  ),
                ),
              ],
            ),
            if (item.description != null && item.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: EdgeInsets.only(
                  left: leadingWidth + leadingGap,
                  right: trailingTextInset,
                ),
                child: Text(
                  item.description!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        FontWeight.lerp(FontWeight.w400, FontWeight.w500, 0.5) ??
                        FontWeight.w500,
                    color: Colors.black87,
                    height: 1.25,
                  ),
                  maxLines: isExpanded ? null : descriptionMaxLines,
                  overflow: isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                ),
              ),
            ],
            if (isExpanded && item.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.only(
                  left: leadingWidth + leadingGap,
                  right: trailingTextInset,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: imageMaxHeight),
                    child: PageView.builder(
                      itemCount: item.imageUrls.length,
                      itemBuilder: (context, index) {
                        final url = item.imageUrls[index];
                        return Container(
                          color: Colors.white,
                          alignment: Alignment.center,
                          child: CachedNetworkImage(
                            imageUrl: url,
                            fit: BoxFit.contain,
                            placeholder: (context, _) => Container(
                              color: const Color(0xFFF3F4F6),
                              alignment: Alignment.center,
                              child: const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                            errorWidget: (context, _, __) => Container(
                              color: const Color(0xFFF3F4F6),
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.textMuted,
                                size: 20,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
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

class _CoverBottomCurveClipper extends CustomClipper<Path> {
  const _CoverBottomCurveClipper();

  @override
  Path getClip(Size size) {
    const curveDepth = 26.0;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height - curveDepth);
    // Bottom edge curves upward at the center (concave shape)
    path.quadraticBezierTo(size.width / 2, size.height, 0, size.height - curveDepth);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

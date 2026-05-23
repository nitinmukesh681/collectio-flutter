import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import '../models/collection_entity.dart';
import '../models/collection_item_entity.dart';
import '../models/comment_entity.dart';
import '../models/user_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_utils.dart';
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

class _CollectionDetailScreenState extends State<CollectionDetailScreen> with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();
  CollectionEntity? _collection;
  List<CollectionItemEntity> _items = [];
  List<UserEntity> _contributorUsers = [];
  bool _isLoading = true;
  bool _isOwner = false;
  String _searchQuery = '';
  // ignore: unused_field
  final Set<String> _expandedItemIds = <String>{};
  bool _showSearch = false;
  String _currentUserName = '';

  bool _isFollowing = false;
  bool _isAddToCollectionsLoading = false;
  bool _isUnauthorized = false;

  late TabController _tabController;
  final TextEditingController _commentController = TextEditingController();
  String? _replyingTo; // comment ID being replied to

  StreamSubscription<CollectionEntity?>? _collectionSubscription;
  Stream<List<CollectionItemEntity>>? _itemsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _itemsStream = _firestoreService.getCollectionItems(widget.collectionId);
    _setupCollectionStream();
    _loadCurrentUserName();
  }

  void _setupCollectionStream() {
    _collectionSubscription = _firestoreService.getCollectionStream(widget.collectionId).listen(
      (collection) async {
        if (mounted) {
          if (collection == null) {
            // Collection was deleted, navigate back
            debugPrint('Collection deleted, navigating back');
            await _collectionSubscription?.cancel();
            Navigator.of(context).pop();
            return;
          }
          
          final isFollowing = await _firestoreService.isFollowing(
            widget.currentUserId, 
            collection.userId
          );

          final isOwner = collection.userId == widget.currentUserId;
          final canView = _canViewCollection(collection, isOwner: isOwner, isFollowing: isFollowing);
          
          setState(() {
            _collection = collection.copyWith(
              isLiked: collection.likedBy.contains(widget.currentUserId),
              isSaved: collection.savedBy.contains(widget.currentUserId),
            );
            _isOwner = isOwner;
            _isFollowing = isFollowing;
            _isUnauthorized = !canView;
            _isLoading = false;
          });

          await _loadContributors(collection);
        }
      },
      onError: (error) {
        debugPrint('Error in collection stream: $error');
        if (mounted) setState(() => _isLoading = false);
      }
    );
  }

  Widget _buildRatingBadge(double rating, {double fontSize = 12}) {
    final displayScore = rating;
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
            style: GoogleFonts.plusJakartaSans(
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

  // ignore: unused_element
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

  // ignore: unused_element
  Widget _buildTrailingChips(CollectionItemEntity item) {
    if (item.rating <= 0) return const SizedBox.shrink();
    return _buildRatingBadge(item.rating, fontSize: 12);
  }

  // ignore: unused_element
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

  @override
  void dispose() {
    _collectionSubscription?.cancel();
    _tabController.dispose();
    _commentController.dispose();
    super.dispose();
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

  // ignore: unused_element
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
                        style: GoogleFonts.plusJakartaSans(
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
                        style: GoogleFonts.plusJakartaSans(
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
                      style: GoogleFonts.plusJakartaSans(
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
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Owner', style: GoogleFonts.plusJakartaSans(fontSize: 12)),
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
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('Owner', style: GoogleFonts.plusJakartaSans(fontSize: 12)),
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
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
                subtitle: Text('Owner', style: GoogleFonts.plusJakartaSans(fontSize: 12)),
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
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800),
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
                          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
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

  // ignore: unused_element
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
        // Collection updates are now handled by the real-time stream
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
        SnackBarUtils.showErrorSnackBar(context, 'Could not load collections: $e');
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
            title: Text('Add to collections', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
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
                            style: GoogleFonts.plusJakartaSans(color: Colors.black87),
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
                child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true),
                child: Text('Add', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
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
        SnackBarUtils.showSuccessSnackBar(context, 'Added to collections');
      }
    } catch (e) {
      if (context.mounted) {
        SnackBarUtils.showErrorSnackBar(context, 'Could not add to collections: $e');
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
        // Collection updates are now handled by the real-time stream
      }
    });
  }

  Future<void> _duplicateCollection() async {
    if (_collection == null) return;
    
    final shouldCopy = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Copy Collection?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('This will create a copy of "${_collection!.title}" in your profile.', style: GoogleFonts.plusJakartaSans()),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryPurple),
            child: Text('Copy', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (shouldCopy != true || !mounted) return;

    try {
      SnackBarUtils.showInfoSnackBar(context, 'Copying collection...');
      
      await _firestoreService.duplicateCollection(
        originalCollectionId: widget.collectionId,
        newOwnerId: widget.currentUserId,
        newOwnerName: _currentUserName,
        newTitle: '${_collection!.title} (Copy)',
      );

      if (mounted) {
        SnackBarUtils.showSuccessSnackBar(context, 'Collection copied to your profile!');
      }
    } catch (e) {
      debugPrint('Error duplicating: $e');
      if (mounted) {
        SnackBarUtils.showErrorSnackBar(context, 'Error: $e');
      }
    }
  }

  Future<void> _deleteItem(CollectionItemEntity item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Item?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to delete "${item.title}"?', style: GoogleFonts.plusJakartaSans()),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _firestoreService.deleteItem(widget.collectionId, item.id);
    }
  }

  // ignore: unused_element
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
        title: Text('Delete Collection?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('This will permanently delete the collection and all its items.', style: GoogleFonts.plusJakartaSans()),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              
              try {
                // Show loading indicator
                if (mounted) {
                  SnackBarUtils.showInfoSnackBar(context, 'Deleting collection...');
                }
                
                await _firestoreService.deleteCollection(
                  widget.collectionId,
                  widget.currentUserId,
                );
                
                // Show success message and navigate back
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  SnackBarUtils.showSuccessSnackBar(context, 'Collection deleted successfully');
                  
                  // Cancel stream subscription to prevent conflicts
                  await _collectionSubscription?.cancel();
                  
                  // Navigate back to previous screen with fallback
                  try {
                    Navigator.of(context).pop();
                  } catch (e) {
                    debugPrint('Navigation error: $e');
                    // Fallback: try to navigate after a short delay
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (mounted) {
                        try {
                          Navigator.of(context).pop();
                        } catch (e2) {
                          debugPrint('Fallback navigation failed: $e2');
                          // Last resort: push to home screen
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            '/',
                            (route) => false,
                          );
                        }
                      }
                    });
                  }
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  SnackBarUtils.showErrorSnackBar(context, 'Error deleting collection: $e');
                }
              }
            },
            child: Text('Delete', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
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
        body: Center(
          child: Text('This collection is private', style: GoogleFonts.plusJakartaSans()),
        ),
      );
    }

    if (_collection == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Collection not found', style: GoogleFonts.plusJakartaSans())),
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

    return Scaffold(
      extendBody: true,
      backgroundColor: AppColors.backgroundSurface,
      body: StreamBuilder<List<CollectionItemEntity>>(
        stream: _itemsStream,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _items = snapshot.data!;
          }
          final itemsCount = snapshot.hasData ? snapshot.data!.length : collection.itemCount;

          return CustomScrollView(
            slivers: [
              // Hero header with cover image
              SliverAppBar(
                expandedHeight: hasCoverImage ? 280 : kToolbarHeight,
                pinned: true,
                stretch: true,
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
                  const SizedBox(width: 8),
                  _buildCircleButton(
                    icon: Icons.share,
                    onTap: _shareCollection,
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    offset: const Offset(0, 40),
                    child: Container(
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
                              return CachedNetworkImage(
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
                              );
                            },
                          ),
                          ],
                        ),
                      )
                    : null,
              ),

              // Collection info — matching mockup
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Updated time
                      Text(
                        'UPDATED ${_getTimeAgo(collection.lastActivityAt).toUpperCase()}',
                        style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 10),

                      // User Info
                      GestureDetector(
                        onTap: () => _navigateToUserProfile(collection.userId),
                        child: Row(
                          children: [
                            _buildUserAvatar(collection.userName, collection.userAvatarUrl, size: 28),
                            const SizedBox(width: 8),
                            Text(
                              '@${collection.userName}',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Large title — Changed from w800 to w900
                      Text(
                        collection.title,
                        style: GoogleFonts.plusJakartaSans(fontSize: 34, fontWeight: FontWeight.w900, color: AppColors.textPrimary, height: 1.1, letterSpacing: -0.8),
                      ),

                      // Description
                      if (collection.description != null && collection.description!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          collection.description!,
                          style: GoogleFonts.plusJakartaSans(fontSize: 15, color: AppColors.textSecondary, height: 1.5),
                        ),
                      ],

                      // Tags
                      if (collection.tags.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8, runSpacing: 8,
                          children: [
                            ...collection.tags.map((tag) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(8)),
                              child: Text('#${tag.toLowerCase()}', style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                            )),
                            if (collection.isOpenForContribution)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(8)),
                                child: Text('OPEN', style: GoogleFonts.plusJakartaSans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                          ],
                        ),
                      ],

                      // Stats
                      const SizedBox(height: 20),
                      Padding(
                        padding: const EdgeInsets.only(left: 4.0),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$itemsCount', style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                Text('ITEMS', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
                              ],
                            ),
                            Container(width: 1, height: 36, color: AppColors.divider, margin: const EdgeInsets.symmetric(horizontal: 20)),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${collection.likes}', style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                Text('LIKES', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textMuted, letterSpacing: 0.5)),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Action buttons — Save, Share, +, Heart
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          // Save
                          ElevatedButton.icon(
                            onPressed: _toggleSave,
                            icon: Icon(collection.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 16),
                            label: Text(collection.isSaved ? 'Saved' : 'Save', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 18),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusSmall)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Share
                          OutlinedButton.icon(
                            onPressed: _shareCollection,
                            icon: const Icon(Icons.share_outlined, size: 16),
                            label: Text('Share', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSecondary,
                              side: const BorderSide(color: AppColors.divider),
                              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusSmall)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Add item
                          if (_isOwner || collection.isOpenForContribution) ...[
                            GestureDetector(
                              onTap: () => _navigateToAddItem(),
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(AppColors.radiusSmall)),
                                child: const Icon(Icons.add_rounded, size: 20, color: AppColors.secondary),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          // Like (heart on the right)
                          GestureDetector(
                            onTap: _toggleLike,
                            child: Icon(
                              collection.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 24, color: collection.isLiked ? AppColors.heartSalmon : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),

              // Items / Discussion tab bar
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.only(top: 8),
                  child: TabBar(
                    controller: _tabController,
                    onTap: (_) => setState(() {}),
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 20),
                    labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                    unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
                    indicatorWeight: 3,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: AppColors.divider,
                    tabs: const [Tab(text: 'Items'), Tab(text: 'Discussion')],
                  ),
                ),
              ),

              // Search bar (if active)
              if (_showSearch && _tabController.index == 0)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    child: TextField(
                      autofocus: true,
                      style: GoogleFonts.plusJakartaSans(),
                      decoration: InputDecoration(
                        hintText: 'Search items...',
                        hintStyle: GoogleFonts.plusJakartaSans(),
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
                        fillColor: Colors.white,
                      ),
                      onChanged: (value) {
                        setState(() => _searchQuery = value);
                      },
                    ),
                  ),
                ),

              // Items list
              if (_tabController.index == 0)
                _buildItemsList(),

              // Discussion tab
              if (_tabController.index == 1) ...[
                SliverToBoxAdapter(child: _buildDiscussionTab()),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildItemsList() {
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
                style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            return _buildItemCard(item, index + 1);
          },
          childCount: items.length,
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildActionButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
    required bool isPrimary,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.primaryPurple : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 1),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscussionTab() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Comment input — wrapped in a white container with styling
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Current user avatar
                    SizedBox(
                      width: 36, height: 36,
                      child: ClipOval(
                        child: FutureBuilder<UserEntity?>(
                          future: _firestoreService.getUser(widget.currentUserId),
                          builder: (context, snap) {
                            final user = snap.data;
                            if (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty) {
                              return CachedNetworkImage(imageUrl: user.avatarUrl!, fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(color: AppColors.surfaceMuted, alignment: Alignment.center,
                                  child: Text(user.userName.isNotEmpty ? user.userName[0].toUpperCase() : '?', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.textSecondary))));
                            }
                            final initial = user?.userName.isNotEmpty == true ? user!.userName[0].toUpperCase() : '?';
                            return Container(color: AppColors.surfaceMuted, alignment: Alignment.center,
                              child: Text(initial, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.textSecondary)));
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _commentController,
                        style: GoogleFonts.plusJakartaSans(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: _replyingTo != null ? 'Write a reply...' : 'Add a comment...',
                          hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
                          border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                          filled: false, contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final text = _commentController.text.trim();
                        if (text.isEmpty) return;
                        _commentController.clear();
                        final auth = await _firestoreService.getUser(widget.currentUserId);
                        await _firestoreService.addComment(
                          collectionId: widget.collectionId, userId: widget.currentUserId,
                          userName: auth?.userName ?? '', userAvatarUrl: auth?.avatarUrl,
                          text: text, parentCommentId: _replyingTo,
                        );
                        if (mounted) setState(() => _replyingTo = null);
                      },
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Text('Post', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ],
                ),
                if (_replyingTo != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 46, bottom: 6),
                    child: GestureDetector(
                      onTap: () => setState(() => _replyingTo = null),
                      child: Text('Cancel reply', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Comments list
          StreamBuilder<List<CommentEntity>>(
            stream: _firestoreService.getCommentsStream(widget.collectionId),
            builder: (context, snapshot) {
              final comments = snapshot.data ?? [];
              final topLevel = comments.where((c) => c.parentCommentId == null).toList();
              final replies = <String, List<CommentEntity>>{};
              for (final c in comments.where((c) => c.parentCommentId != null)) {
                replies.putIfAbsent(c.parentCommentId!, () => []).add(c);
              }

              if (topLevel.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: Text('No comments yet. Start the discussion!', style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted))),
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Text('Community Discussion', style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(8)),
                        child: Text('${comments.length} comments', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  for (final comment in topLevel) ...[
                    _buildCommentTile(comment),
                    if (replies.containsKey(comment.id))
                      Padding(
                        padding: const EdgeInsets.only(left: 32),
                        child: Column(children: replies[comment.id]!.map((r) => _buildCommentTile(r)).toList()),
                      ),
                    const SizedBox(height: 12),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCommentTile(CommentEntity comment) {
    final isLiked = comment.likedBy.contains(widget.currentUserId);
    final isOwn = comment.userId == widget.currentUserId;
    final initial = comment.userName.isNotEmpty ? comment.userName[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          SizedBox(
            width: 40, height: 40,
            child: ClipOval(
              child: (comment.userAvatarUrl != null && comment.userAvatarUrl!.isNotEmpty)
                  ? CachedNetworkImage(imageUrl: comment.userAvatarUrl!, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => Container(color: AppColors.surfaceMuted, alignment: Alignment.center,
                        child: Text(initial, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.textSecondary))))
                  : Container(color: AppColors.surfaceMuted, alignment: Alignment.center,
                      child: Text(initial, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(comment.userName, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                    const Spacer(),
                    Text(_getTimeAgo(comment.createdAt), style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textMuted)),
                    if (isOwn) ...[
                      const SizedBox(width: 6),
                      GestureDetector(onTap: () => _firestoreService.deleteComment(comment.id),
                        child: const Icon(Icons.close, size: 14, color: AppColors.textMuted)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(comment.text, style: GoogleFonts.plusJakartaSans(fontSize: 15, color: AppColors.textPrimary, height: 1.5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _firestoreService.toggleCommentLike(comment.id, widget.currentUserId),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.thumb_up_alt_outlined, size: 15, color: isLiked ? AppColors.primary : AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('${comment.likes}', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: isLiked ? AppColors.primary : AppColors.textSecondary)),
                      ]),
                    ),
                    const SizedBox(width: 18),
                    GestureDetector(
                      onTap: () => setState(() => _replyingTo = comment.parentCommentId == null ? comment.id : comment.parentCommentId),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.subdirectory_arrow_right_rounded, size: 15, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('Reply', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textSecondary)),
                      ]),
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

  Widget _buildUserAvatar(String name, String? avatarUrl, {double size = 28}) {
    // ignore: unused_local_variable
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';

    Widget placeholder = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AppColors.surfaceMuted, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Icon(Icons.person, size: size * 0.6, color: AppColors.textMuted),
    );

    if (avatarUrl == null || avatarUrl.trim().isEmpty) return placeholder;

    final trimmed = avatarUrl.trim();

    if (trimmed.startsWith('gs://')) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.refFromURL(trimmed).getDownloadURL(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return _buildNetworkAvatar(snapshot.data!, size);
          }
          return placeholder;
        },
      );
    }

    return _buildNetworkAvatar(trimmed, size);
  }

  Widget _buildNetworkAvatar(String url, double size) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(width: size, height: size, color: AppColors.surfaceMuted),
        errorWidget: (_, __, ___) => Container(width: size, height: size, color: AppColors.surfaceMuted),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildStatChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildItemCard(CollectionItemEntity item, int rank) {
    final canEdit = _isOwner || item.userId == widget.currentUserId;
    final hasImages = item.imageUrls.isNotEmpty;
    final hasLocation = (item.googleMapsUrl ?? '').trim().isNotEmpty;
    final hasWebsite = (item.websiteUrl ?? '').trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppColors.radiusCard),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Rank + Title + Rating + Menu
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Rank container sized to match text line height (24px for 20px font at 1.2 height)
              Container(
                width: 20, height: 24,
                alignment: Alignment.center,
                child: Container(
                  width: 20, height: 20,
                  decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text('$rank', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 10, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(item.title,
                  style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.2)),
              ),
              if (item.rating > 0) ...[
                const SizedBox(width: 6),
                Container(
                  height: 24, // Align with text line height
                  alignment: Alignment.center,
                  child: _buildRatingBadge(item.rating),
                ),
              ],
              // Menu button sized to match text line height
              Container(
                width: 28, height: 24,
                alignment: Alignment.centerRight,
                child: PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                iconSize: 18,
                icon: const Icon(Icons.more_vert, size: 18, color: AppColors.textMuted),
                onSelected: (value) {
                  if (value == 'edit') _navigateToAddItem(item);
                  else if (value == 'delete') _deleteItem(item);
                  else if (value == 'add_to_collections') _showAddToCollectionsDialog(item);
                },
                itemBuilder: (context) => [
                  if (canEdit) PopupMenuItem(value: 'edit', child: Text('Edit', style: GoogleFonts.plusJakartaSans())),
                  if (_isOwner) PopupMenuItem(value: 'delete', child: Text('Delete', style: GoogleFonts.plusJakartaSans())),
                  PopupMenuItem(value: 'add_to_collections', child: Text('Add to collection', style: GoogleFonts.plusJakartaSans())),
                ],
              ),
              ),
            ],
          ),

          // Description
          if (item.description != null && item.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text(item.description!,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textPrimary, height: 1.5)),
            ),
          ],

          // Images below description
          if (hasImages) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 30, right: 4),
              child: SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: item.imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                    child: CachedNetworkImage(imageUrl: item.imageUrls[i], fit: BoxFit.cover, width: 200,
                      errorWidget: (_, __, ___) => Container(width: 200, color: AppColors.surfaceMuted)),
                  ),
                ),
              ),
            ),
          ],

          // Website + Location links
          if (hasWebsite || hasLocation) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Row(
                children: [
                  if (hasWebsite)
                    GestureDetector(
                      onTap: () {
                        var raw = (item.websiteUrl ?? '').trim();
                        if (!raw.startsWith('http')) raw = 'https://$raw';
                        final uri = Uri.tryParse(raw);
                        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Transform.translate(
                          offset: const Offset(-2, 0),
                          child: Icon(Icons.language_rounded, size: 16, color: AppColors.primary),
                        ),
                        const SizedBox(width: 1),
                        Text('Website', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ]),
                    ),
                  if (hasWebsite && hasLocation) ...[
                    const SizedBox(width: 24),
                  ],
                  if (hasLocation)
                    GestureDetector(
                      onTap: () {
                        final uri = Uri.tryParse((item.googleMapsUrl ?? '').trim());
                        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Transform.translate(
                          offset: const Offset(-2, 0),
                          child: Icon(Icons.location_on_outlined, size: 16, color: AppColors.primary),
                        ),
                        const SizedBox(width: 1),
                        Text('Location', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ]),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ignore: unused_element
  String _extractLocationName(String url) {
    // Try to extract query parameter
    if (url.contains('query=')) {
      try {
        final q = Uri.parse(url).queryParameters['query'];
        if (q != null && q.isNotEmpty) return Uri.decodeComponent(q).replaceAll('+', ' ');
      } catch (_) {}
    }
    // Try to extract place name from /place/ URLs
    final placeMatch = RegExp(r'/place/([^/]+)').firstMatch(url);
    if (placeMatch != null) {
      return Uri.decodeComponent(placeMatch.group(1)!).replaceAll('+', ' ');
    }
    // Fallback: show domain only
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return 'View on Maps';
    }
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

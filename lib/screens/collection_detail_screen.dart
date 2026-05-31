import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../widgets/avatar_fallback.dart';
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
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  String? _replyingToCommentId; // specific comment whose Reply was tapped
  final Set<String> _expandedThreadIds = {};
  static const int _maxCommentDepth = 2;
  final Map<String, ({bool isLiked, int likes})> _optimisticCommentLikes = {};

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

  Widget _buildRatingBadge(
    double rating, {
    double fontSize = 12,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    double borderRadius = 6,
    double iconGap = 4,
  }) {
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
      padding: padding,
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star, size: fontSize, color: badgeColor),
          SizedBox(width: iconGap),
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
    const ratingChipWidth = 62.0;
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
    _replyController.dispose();
    _replyFocusNode.dispose();
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

  bool _commentIsLiked(CommentEntity comment) {
    final override = _optimisticCommentLikes[comment.id];
    if (override != null) return override.isLiked;
    return comment.likedBy.contains(widget.currentUserId);
  }

  int _commentLikeCount(CommentEntity comment) {
    final override = _optimisticCommentLikes[comment.id];
    if (override != null) return override.likes;
    return comment.likes;
  }

  Future<void> _toggleCommentLike(CommentEntity comment) async {
    final wasLiked = _commentIsLiked(comment);
    final currentLikes = _commentLikeCount(comment);

    setState(() {
      _optimisticCommentLikes[comment.id] = (
        isLiked: !wasLiked,
        likes: wasLiked ? currentLikes - 1 : currentLikes + 1,
      );
    });

    try {
      await _firestoreService.toggleCommentLike(comment.id, widget.currentUserId);
      if (mounted) {
        setState(() => _optimisticCommentLikes.remove(comment.id));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _optimisticCommentLikes.remove(comment.id));
        SnackBarUtils.showErrorSnackBar(context, 'Could not update like');
      }
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

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
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
              SliverToBoxAdapter(
                child: _buildHeroHeader(
                  collection: collection,
                  itemsCount: itemsCount,
                  gradientColors: gradientColors,
                  hasCoverImage: hasCoverImage,
                ),
              ),

              // Items / Discussion tab bar
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    onTap: (_) => setState(() {}),
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelPadding: EdgeInsets.fromLTRB(
                      _heroHorizontalPadding + _heroContentShift,
                      6,
                      _heroHorizontalPadding,
                      4,
                    ),
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textMuted,
                    labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14),
                    unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14),
                    indicatorColor: AppColors.primary,
                    indicatorWeight: 1.5,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: AppColors.divider,
                    dividerHeight: 1,
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
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _DiscussionComposerHeaderDelegate(
                    child: _buildDiscussionComposer(),
                  ),
                ),
                SliverToBoxAdapter(child: _buildDiscussionComments()),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          );
        },
      ),
      ),
    );
  }

  static const double _heroHorizontalPadding = 20;
  static const double _heroContentShift = -3;
  static const double _heroNavContentGap = 20;
  static const double _heroStatsBandInset = 12;
  static const double _heroDividerInset = 2;
  static const Color _heroMutedButtonFill = Color(0xCC444444);
  static const Color _heroMutedButtonBorder = Color(0x40FFFFFF);

  static const TextStyle _heroTitleStyle = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w900,
    color: Colors.white,
    height: 1.15,
    letterSpacing: -0.2,
  );

  static const TextStyle _heroDescriptionStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: Colors.white,
    height: 1.5,
    letterSpacing: 0,
  );

  static const TextHeightBehavior _heroTextHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: true,
    applyHeightToLastDescent: false,
  );

  Widget _buildHeroScrim() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.30),
            Colors.black.withValues(alpha: 0.44),
            Colors.black.withValues(alpha: 0.58),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader({
    required CollectionEntity collection,
    required int itemsCount,
    required List<Color> gradientColors,
    required bool hasCoverImage,
  }) {
    final mediaQuery = MediaQuery.of(context);
    final topInset = mediaQuery.viewPadding.top > mediaQuery.padding.top
        ? mediaQuery.viewPadding.top
        : mediaQuery.padding.top;
    const navButtonSize = 38.0;
    const topPadding = 8.0;
    const bottomPadding = 20.0;

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: _buildCoverBackground(
              coverImageUrl: collection.coverImageUrl,
              gradientColors: gradientColors,
              hasCoverImage: hasCoverImage,
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(child: _buildHeroScrim()),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topInset),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _heroHorizontalPadding,
                topPadding,
                _heroHorizontalPadding,
                0,
              ),
              child: Row(
                children: [
                  Transform.translate(
                    offset: const Offset(_heroContentShift, 0),
                    child: _buildCircleButton(
                      icon: Icons.keyboard_arrow_left,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                  const Spacer(),
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
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    offset: const Offset(0, 44),
                    child: Container(
                      width: navButtonSize,
                      height: navButtonSize,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
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
                ],
              ),
            ),
            const SizedBox(height: _heroNavContentGap),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                _heroHorizontalPadding,
                0,
                _heroHorizontalPadding,
                bottomPadding,
              ),
              child: Transform.translate(
                offset: const Offset(_heroContentShift, 0),
                child: _buildHeroContent(
                  collection: collection,
                  itemsCount: itemsCount,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroContent({
    required CollectionEntity collection,
    required int itemsCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _navigateToUserProfile(collection.userId),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildUserAvatar(collection.userName, collection.userAvatarUrl, size: 28),
              const SizedBox(width: 8),
              Text(
                '@${collection.userName}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        DefaultTextStyle(
          style: GoogleFonts.plusJakartaSans(textStyle: _heroTitleStyle),
          textHeightBehavior: _heroTextHeightBehavior,
          child: Text(collection.title),
        ),
        if (collection.description != null && collection.description!.isNotEmpty) ...[
          const SizedBox(height: 10),
          DefaultTextStyle(
            style: GoogleFonts.plusJakartaSans(
              textStyle: _heroDescriptionStyle,
            ).copyWith(color: Colors.white.withValues(alpha: 0.95)),
            textHeightBehavior: _heroTextHeightBehavior,
            child: Text(collection.description!),
          ),
        ],
        if (collection.tags.isNotEmpty || collection.isOpenForContribution) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...collection.tags.map(_buildHeroTag),
              if (collection.isOpenForContribution)
                _buildHeroPill(
                  label: 'OPEN',
                  backgroundColor: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: _heroDividerInset),
              child: _buildHeroDivider(),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(_heroStatsBandInset, 16, 0, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeroStat('$itemsCount', 'ITEMS'),
                  const SizedBox(width: 36),
                  _buildHeroStat('${collection.likes}', 'LIKES'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: _heroDividerInset),
              child: _buildHeroDivider(),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _buildHeroPrimaryButton(
              icon: collection.isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              label: collection.isSaved ? 'Saved' : 'Save',
              onTap: _toggleSave,
            ),
            _buildHeroSecondaryButton(
              icon: Icons.share_outlined,
              label: 'Share',
              onTap: _shareCollection,
            ),
            _buildHeroIconButton(
              icon: collection.isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              onTap: _toggleLike,
              backgroundColor: collection.isLiked ? AppColors.heartSalmon : null,
            ),
            if (_isOwner || collection.isOpenForContribution)
              _buildHeroIconButton(
                icon: Icons.add_rounded,
                onTap: () => _navigateToAddItem(),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildCoverBackground({
    required String? coverImageUrl,
    required List<Color> gradientColors,
    required bool hasCoverImage,
  }) {
    if (!hasCoverImage) {
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

    return FutureBuilder<String?>(
      future: () async {
        final raw = coverImageUrl;
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
    );
  }

  Widget _buildHeroDivider() {
    return SizedBox(
      width: double.infinity,
      height: 1,
      child: ColoredBox(color: Colors.white.withValues(alpha: 0.18)),
    );
  }

  String _formatHeroTagLabel(String tag) {
    final trimmed = tag.trim().toLowerCase();
    if (trimmed.startsWith('#')) return trimmed;
    return '#$trimmed';
  }

  Widget _buildHeroPill({
    required String label,
    required Color backgroundColor,
    Color textColor = Colors.white,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: textColor,
            fontSize: 12,
            fontWeight: fontWeight,
            height: 1.0,
            letterSpacing: 0,
          ),
          textHeightBehavior: _heroTextHeightBehavior,
        ),
      ),
    );
  }

  Widget _buildHeroTag(String tag) {
    return _buildHeroPill(
      label: _formatHeroTagLabel(tag),
      backgroundColor: Colors.black.withValues(alpha: 0.42),
    );
  }

  Widget _buildHeroStat(String value, String label) {
    const statValueStyle = TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      color: Colors.white,
      height: 1,
      letterSpacing: 0,
    );
    const statLabelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Colors.white,
      height: 1,
      letterSpacing: 0.6,
    );

    return DefaultTextStyle(
      style: GoogleFonts.plusJakartaSans(),
      textHeightBehavior: _heroTextHeightBehavior,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(textStyle: statValueStyle),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              textStyle: statLabelStyle,
            ).copyWith(color: Colors.white.withValues(alpha: 0.65)),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroPrimaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSecondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: _heroMutedButtonFill,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _heroMutedButtonBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroIconButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? backgroundColor,
    Color iconColor = Colors.white,
  }) {
    final bg = backgroundColor ?? _heroMutedButtonFill;
    final showBorder = backgroundColor == null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: showBorder
                ? Border.all(color: _heroMutedButtonBorder)
                : null,
          ),
          child: Icon(icon, size: 20, color: iconColor),
        ),
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
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
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

  Widget _buildDiscussionComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: ClipOval(
              child: FutureBuilder<UserEntity?>(
                future: _firestoreService.getUser(widget.currentUserId),
                builder: (context, snap) {
                  final user = snap.data;
                  final userName = user?.userName ?? '';
                  if (user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty) {
                    return CachedNetworkImage(
                      imageUrl: user.avatarUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => AvatarFallback(name: userName, size: 36),
                    );
                  }
                  return AvatarFallback(name: userName, size: 36);
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
                hintText: 'Add a comment...',
                hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
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
                collectionId: widget.collectionId,
                userId: widget.currentUserId,
                userName: auth?.userName ?? '',
                userAvatarUrl: auth?.avatarUrl,
                text: text,
              );
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text(
              'Post',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiscussionComments() {
    return Container(
      color: AppColors.backgroundSurface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: StreamBuilder<List<CommentEntity>>(
        stream: _firestoreService.getCommentsStream(widget.collectionId),
        builder: (context, snapshot) {
          final comments = snapshot.data ?? [];
          final commentsById = {for (final c in comments) c.id: c};
          final topLevel = comments.where((c) => c.parentCommentId == null).toList();
          final repliesByParent = <String, List<CommentEntity>>{};
          for (final c in comments.where((c) => c.parentCommentId != null)) {
            repliesByParent.putIfAbsent(c.parentCommentId!, () => []).add(c);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Community Discussion',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${comments.length} comments',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (topLevel.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: Text(
                      'No comments yet. Start the discussion!',
                      style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
                    ),
                  ),
                )
              else
                for (var i = 0; i < topLevel.length; i++) ...[
                  _buildCommentThread(
                    topLevel[i],
                    repliesByParent,
                    commentsById: commentsById,
                    rootId: topLevel[i].id,
                  ),
                  if (i < topLevel.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: AppColors.divider.withValues(alpha: 0.6), height: 1),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }

  int _countThreadReplies(String commentId, Map<String, List<CommentEntity>> repliesByParent, int depth) {
    if (depth >= _maxCommentDepth) return 0;
    final children = repliesByParent[commentId] ?? const [];
    var count = children.length;
    for (final child in children) {
      count += _countThreadReplies(child.id, repliesByParent, depth + 1);
    }
    return count;
  }

  int _commentDepth(CommentEntity comment, Map<String, CommentEntity> commentsById) {
    var depth = 0;
    var parentId = comment.parentCommentId;
    while (parentId != null) {
      depth++;
      parentId = commentsById[parentId]?.parentCommentId;
    }
    return depth;
  }

  Widget _buildViewRepliesButton({required String rootId, required int count}) {
    return GestureDetector(
      onTap: () => setState(() => _expandedThreadIds.add(rootId)),
      child: Padding(
        padding: const EdgeInsets.only(left: 48, top: 2, bottom: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'View $count ${count == 1 ? 'reply' : 'replies'}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHideRepliesButton({required String rootId, required int count}) {
    return GestureDetector(
      onTap: () => setState(() => _expandedThreadIds.remove(rootId)),
      child: Padding(
        padding: const EdgeInsets.only(left: 48, top: 2, bottom: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.expand_less_rounded, size: 18, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(
              'Hide $count ${count == 1 ? 'reply' : 'replies'}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentThread(
    CommentEntity comment,
    Map<String, List<CommentEntity>> repliesByParent, {
    required Map<String, CommentEntity> commentsById,
    required String rootId,
    int depth = 0,
  }) {
    final children = repliesByParent[comment.id] ?? const [];
    final hasReplies = children.isNotEmpty && depth < _maxCommentDepth;
    final isThreadExpanded = _expandedThreadIds.contains(rootId);
    final replyCount = depth == 0 ? _countThreadReplies(comment.id, repliesByParent, 0) : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCommentTile(
          comment,
          depth: depth,
          rootId: rootId,
          commentsById: commentsById,
          canReply: depth < _maxCommentDepth,
        ),
        if (depth == 0 && hasReplies && !isThreadExpanded)
          _buildViewRepliesButton(rootId: rootId, count: replyCount),
        if (isThreadExpanded && hasReplies)
          for (final child in children)
            _buildCommentThread(
              child,
              repliesByParent,
              commentsById: commentsById,
              rootId: rootId,
              depth: depth + 1,
            ),
        if (depth == 0 && hasReplies && isThreadExpanded)
          _buildHideRepliesButton(rootId: rootId, count: replyCount),
      ],
    );
  }

  void _startReplyTo(CommentEntity comment, String rootId, Map<String, CommentEntity> commentsById) {
    if (_commentDepth(comment, commentsById) >= _maxCommentDepth) return;

    if (_replyingToCommentId == comment.id) {
      _replyFocusNode.requestFocus();
      return;
    }
    _replyController.clear();
    setState(() {
      _expandedThreadIds.add(rootId);
      _replyingToCommentId = comment.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _replyFocusNode.requestFocus();
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToCommentId = null;
      _replyController.clear();
    });
    _replyFocusNode.unfocus();
  }

  Future<void> _postReply(CommentEntity targetComment, Map<String, CommentEntity> commentsById) async {
    if (_commentDepth(targetComment, commentsById) >= _maxCommentDepth) return;

    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    _replyController.clear();
    final auth = await _firestoreService.getUser(widget.currentUserId);
    await _firestoreService.addComment(
      collectionId: widget.collectionId,
      userId: widget.currentUserId,
      userName: auth?.userName ?? '',
      userAvatarUrl: auth?.avatarUrl,
      text: text,
      parentCommentId: targetComment.id,
    );
    if (mounted) _cancelReply();
  }

  Widget _buildReplyComposer(CommentEntity targetComment, Map<String, CommentEntity> commentsById) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        TextField(
          controller: _replyController,
          focusNode: _replyFocusNode,
          style: GoogleFonts.plusJakartaSans(fontSize: 14),
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Reply to ${targetComment.userName}...',
            hintStyle: GoogleFonts.plusJakartaSans(color: AppColors.textMuted, fontSize: 14),
            filled: true,
            fillColor: AppColors.surfaceMuted,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            GestureDetector(
              onTap: _cancelReply,
              child: Text(
                'Cancel',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: () => _postReply(targetComment, commentsById),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: Text(
                'Reply',
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCommentActionButton({
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: child,
      ),
    );
  }

  Widget _buildCommentOwnerBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Owner',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _buildCommentTile(
    CommentEntity comment, {
    required int depth,
    required String rootId,
    required Map<String, CommentEntity> commentsById,
    required bool canReply,
  }) {
    final isLiked = _commentIsLiked(comment);
    final likeCount = _commentLikeCount(comment);
    final isOwn = comment.userId == widget.currentUserId;
    final isCollectionOwner = comment.userId == _collection?.userId;
    final isReplying = _replyingToCommentId == comment.id;
    final avatarSize = depth == 0 ? 36.0 : 30.0;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => _navigateToUserProfile(comment.userId),
          child: SizedBox(
            width: avatarSize,
            height: avatarSize,
            child: ClipOval(
              child: (comment.userAvatarUrl != null && comment.userAvatarUrl!.isNotEmpty)
                  ? CachedNetworkImage(
                      imageUrl: comment.userAvatarUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          AvatarFallback(name: comment.userName, size: avatarSize),
                    )
                  : AvatarFallback(name: comment.userName, size: avatarSize),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: () => _navigateToUserProfile(comment.userId),
                      child: Text(
                        comment.userName,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: depth == 0 ? 14 : 13,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  if (isCollectionOwner) ...[
                    const SizedBox(width: 6),
                    _buildCommentOwnerBadge(),
                  ],
                  const SizedBox(width: 8),
                  Text(
                    _getTimeAgo(comment.createdAt),
                    style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                comment.text,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: depth == 0 ? 15 : 14,
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildCommentActionButton(
                    onTap: () => _toggleCommentLike(comment),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        isLiked ? Icons.thumb_up_rounded : Icons.thumb_up_alt_outlined,
                        size: 15,
                        color: isLiked ? AppColors.primary : AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likeCount',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: isLiked ? AppColors.primary : AppColors.textSecondary,
                        ),
                      ),
                    ]),
                  ),
                  if (canReply) ...[
                    const SizedBox(width: 12),
                    _buildCommentActionButton(
                      onTap: () => _startReplyTo(comment, rootId, commentsById),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 14,
                          color: isReplying ? AppColors.primary : AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Reply',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: isReplying ? AppColors.primary : AppColors.textSecondary,
                            fontWeight: isReplying ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ]),
                    ),
                  ],
                ],
              ),
              if (isReplying) _buildReplyComposer(comment, commentsById),
            ],
          ),
        ),
        if (isOwn)
          GestureDetector(
            onTap: () => _firestoreService.deleteComment(comment.id),
            child: const Padding(
              padding: EdgeInsets.only(left: 8, top: 2),
              child: Icon(Icons.close, size: 14, color: AppColors.textMuted),
            ),
          ),
      ],
    );

    if (depth == 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: content,
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: 22.0 * depth, top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 2,
            height: 48,
            margin: const EdgeInsets.only(right: 12, top: 4),
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          Expanded(child: content),
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
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  Widget _buildUserAvatar(String name, String? avatarUrl, {double size = 28}) {
    Widget placeholder = AvatarFallback(name: name, size: size);

    if (avatarUrl == null || avatarUrl.trim().isEmpty) return placeholder;

    final trimmed = avatarUrl.trim();

    if (trimmed.startsWith('gs://')) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.refFromURL(trimmed).getDownloadURL(),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            return _buildNetworkAvatar(snapshot.data!, size, name: name);
          }
          return placeholder;
        },
      );
    }

    return _buildNetworkAvatar(trimmed, size, name: name);
  }

  Widget _buildNetworkAvatar(String url, double size, {required String name}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size),
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => AvatarFallback(name: name, size: size),
        errorWidget: (_, __, ___) => AvatarFallback(name: name, size: size),
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

  static const double _itemTitleFontSize = 17;
  static const double _itemTitleLineHeight = _itemTitleFontSize * 1.25;
  static const double _itemRankSize = 28;
  static const double _itemSingleLineTitleYOffset = -1.5;

  TextStyle get _itemTitleStyle => GoogleFonts.plusJakartaSans(
        fontSize: _itemTitleFontSize,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.25,
      );

  double _itemTitleTrailingWidth(CollectionItemEntity item) {
    var width = 24.0;
    if (item.rating > 0) {
      width += 14;
      final displayScore = item.rating;
      final label = (displayScore % 1 == 0)
          ? displayScore.toStringAsFixed(0)
          : displayScore.toStringAsFixed(1);
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      width += painter.width + 16 + 12;
    }
    return width;
  }

  bool _isSingleLineItemTitle(BuildContext context, String title, double maxWidth) {
    if (title.isEmpty || maxWidth <= 0) return true;
    final painter = TextPainter(
      text: TextSpan(text: title, style: _itemTitleStyle),
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);
    return painter.computeLineMetrics().length <= 1;
  }

  Widget _buildItemMenuButton({
    required CollectionItemEntity item,
    required bool canEdit,
  }) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      offset: const Offset(0, 24),
      child: const Icon(Icons.more_horiz, size: 18, color: AppColors.textMuted),
      onSelected: (value) {
        if (value == 'edit') _navigateToAddItem(item);
        else if (value == 'delete') _deleteItem(item);
        else if (value == 'add_to_collections') _showAddToCollectionsDialog(item);
      },
      itemBuilder: (context) => [
        if (canEdit) PopupMenuItem(value: 'edit', child: Text('Edit', style: GoogleFonts.plusJakartaSans())),
        if (canEdit) PopupMenuItem(value: 'delete', child: Text('Delete', style: GoogleFonts.plusJakartaSans())),
        PopupMenuItem(value: 'add_to_collections', child: Text('Add to collection', style: GoogleFonts.plusJakartaSans())),
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
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final trailingWidth = _itemTitleTrailingWidth(item);
              final titleMaxWidth =
                  constraints.maxWidth - _itemRankSize - 12 - trailingWidth;
              final isSingleLineTitle =
                  _isSingleLineItemTitle(context, item.title, titleMaxWidth);

              Widget buildTitleRow() {
                return Row(
                  crossAxisAlignment: isSingleLineTitle
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Transform.translate(
                        offset: isSingleLineTitle
                            ? const Offset(0, _itemSingleLineTitleYOffset)
                            : Offset.zero,
                        child: Text(
                          item.title,
                          style: _itemTitleStyle,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: isSingleLineTitle
                          ? _itemRankSize
                          : _itemTitleLineHeight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (item.rating > 0) ...[
                            const SizedBox(width: 6),
                            _buildRatingBadge(
                              item.rating,
                              fontSize: 12,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              borderRadius: 6,
                              iconGap: 4,
                            ),
                            const SizedBox(width: 8),
                          ],
                          _buildItemMenuButton(item: item, canEdit: canEdit),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: _itemRankSize,
                    height: _itemRankSize,
                    decoration: const BoxDecoration(
                      color: Color(0xFFEEF2FF),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$rank',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isSingleLineTitle)
                          SizedBox(
                            height: _itemRankSize,
                            child: buildTitleRow(),
                          )
                        else
                          buildTitleRow(),
                        if (item.description != null &&
                            item.description!.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            item.description!,
                            style: AppTextStyles.collectionDescription(
                              fontSize: 14,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),

          if (hasImages) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(left: 40, right: 4),
              child: SizedBox(
                height: 160,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: item.imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => ClipRRect(
                    borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                    child: CachedNetworkImage(
                      imageUrl: item.imageUrls[i],
                      fit: BoxFit.cover,
                      width: 200,
                      errorWidget: (_, __, ___) => Container(width: 200, color: AppColors.surfaceMuted),
                    ),
                  ),
                ),
              ),
            ),
          ],

          if (hasWebsite || hasLocation) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 40),
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
                        Icon(Icons.language_rounded, size: 16, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text('Website', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ]),
                    ),
                  if (hasWebsite && hasLocation) const SizedBox(width: 24),
                  if (hasLocation)
                    GestureDetector(
                      onTap: () {
                        final uri = Uri.tryParse((item.googleMapsUrl ?? '').trim());
                        if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.location_on_outlined, size: 16, color: AppColors.primary),
                        const SizedBox(width: 4),
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

class _DiscussionComposerHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _DiscussionComposerHeaderDelegate({required this.child});

  final Widget child;
  static const double _headerHeight = 84;

  @override
  double get minExtent => _headerHeight;

  @override
  double get maxExtent => _headerHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      color: AppColors.backgroundSurface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _DiscussionComposerHeaderDelegate oldDelegate) => true;
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

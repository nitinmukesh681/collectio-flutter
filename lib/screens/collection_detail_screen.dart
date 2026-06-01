import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/avatar_fallback.dart';
import '../widgets/user_avatar.dart';
import '../widgets/mention_text_field.dart';
import '../widgets/comment_mention_text.dart';
import 'add_item_screen.dart';
import 'create_collection_screen.dart';
import 'user_profile_screen.dart';
import 'profile_screen.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../widgets/manage_collaborators_dialog.dart';

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
  bool _isEditor = false;
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
  final FocusNode _commentFocusNode = FocusNode();
  final FocusNode _replyFocusNode = FocusNode();
  String? _replyingToCommentId; // specific comment whose Reply was tapped
  final Set<String> _expandedThreadIds = {};
  static const int _maxCommentDepth = 2;
  final Map<String, ({bool isLiked, int likes})> _optimisticCommentLikes = {};

  Color get _accentColor =>
      AppColors.categoryLabelColor(_collection?.category.name ?? 'other');

  Color get _accentSurfaceColor => _accentColor.withValues(alpha: 0.12);

  List<Color> _accentHeroGradient() {
    final hsl = HSLColor.fromColor(_accentColor);
    return [
      hsl.withLightness((hsl.lightness - 0.08).clamp(0.18, 0.88)).toColor(),
      hsl.withLightness((hsl.lightness + 0.14).clamp(0.22, 0.94)).toColor(),
    ];
  }

  StreamSubscription<CollectionEntity?>? _collectionSubscription;
  Stream<List<CollectionItemEntity>>? _itemsStream;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        if (_tabController.index != 1) {
          _dismissDiscussionComposer();
        }
        setState(() {});
      }
    });
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
          
          final userSavedIds =
              context.read<AuthProvider>().userEntity?.savedCollections ??
                  const <String>[];

          final isFollowing = await _firestoreService.isFollowing(
            widget.currentUserId, 
            collection.userId
          );

          if (!mounted) return;

          final isOwner = collection.userId == widget.currentUserId;
          final isEditor = collection.editors.contains(widget.currentUserId);
          final canView = _canViewCollection(collection, isOwner: isOwner, isFollowing: isFollowing);
          setState(() {
            _collection = collection.copyWith(
              isLiked: collection.likedBy.contains(widget.currentUserId),
              isSaved: _firestoreService.isCollectionSavedByUser(
                collection: collection,
                userId: widget.currentUserId,
                userSavedCollectionIds: userSavedIds,
              ),
            );
            _isOwner = isOwner;
            _isEditor = isEditor;
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
    _commentFocusNode.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  void _dismissDiscussionComposer() {
    _commentController.clear();
    _commentFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  bool get _isCommentComposerActive =>
      _commentFocusNode.hasFocus || _commentController.text.trim().isNotEmpty;

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

  bool _canAddItems(CollectionEntity collection) {
    return _isOwner || _isEditor || collection.isOpenForContribution;
  }

  bool _collectionHasMultipleContributors(CollectionEntity collection) {
    return collection.isOpenForContribution ||
        collection.editors.isNotEmpty ||
        collection.contributorCount > 0;
  }

  List<Map<String, dynamic>> _editorCollaborators(CollectionEntity collection) {
    return collection.collaborators
        .where((c) => collection.editors.contains(c['userId'] as String? ?? ''))
        .toList();
  }

  bool _isPublicCollection(CollectionEntity collection) {
    return collection.isPublic || collection.visibility == CollectionVisibility.public;
  }

  void _showManageCollaboratorsDialog() {
    if (_collection == null) return;
    showDialog(
      context: context,
      builder: (context) => ManageCollaboratorsDialog(
        collectionId: widget.collectionId,
        currentUserId: widget.currentUserId,
        currentUserName: _currentUserName,
        collectionTitle: _collection!.title,
        isPublicCollection: _isPublicCollection(_collection!),
      ),
    );
  }

  void _showCollaboratorsDialog(CollectionEntity collection) {
    final editors = _editorCollaborators(collection);
    if (editors.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Collaborators', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPeopleDialogRow(
                dialogContext: dialogContext,
                userId: collection.userId,
                username: collection.userName,
                avatarUrl: collection.userAvatarUrl,
                subtitle: 'Owner',
              ),
              ...editors.map((collab) {
                final userId = collab['userId'] as String? ?? '';
                final username = collab['username'] as String? ?? 'User';
                return _buildPeopleDialogRow(
                  dialogContext: dialogContext,
                  userId: userId,
                  username: username,
                );
              }),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Close', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildPeopleDialogRow({
    required BuildContext dialogContext,
    required String userId,
    required String username,
    String? avatarUrl,
    String? subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: userId.isEmpty
            ? null
            : () {
                Navigator.pop(dialogContext);
                _navigateToUserProfile(userId);
              },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              _buildUserAvatar(
                username,
                avatarUrl,
                size: 32,
                userId: userId,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@$username',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        color: _accentColor,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContributorsDialog(CollectionEntity collection) {
    final users = _contributorUsers;
    if (users.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Contributors', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPeopleDialogRow(
                dialogContext: dialogContext,
                userId: collection.userId,
                username: collection.userName,
                avatarUrl: collection.userAvatarUrl,
                subtitle: 'Owner',
              ),
              ...users.map(
                (user) => _buildPeopleDialogRow(
                  dialogContext: dialogContext,
                  userId: user.id,
                  username: user.userName,
                  avatarUrl: user.avatarUrl,
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Close', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showCollectionInfoDialog(CollectionEntity collection) {
    final dateFormat = DateFormat('MMM d, yyyy \'at\' h:mm a');
    final createdAt = dateFormat.format(
      DateTime.fromMillisecondsSinceEpoch(collection.createdAt),
    );
    final updatedAt = dateFormat.format(
      DateTime.fromMillisecondsSinceEpoch(collection.updatedAt),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Collection info', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Created', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(createdAt, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Text('Last updated', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(updatedAt, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showItemInfoDialog(CollectionItemEntity item) {
    final addedAt = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    final formattedDate = DateFormat('MMM d, yyyy \'at\' h:mm a').format(addedAt);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Item info', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Added by', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _navigateToUserProfile(item.userId);
              },
              child: Text(
                '@${item.userName}',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w800,
                  color: _accentColor,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text('Added on', style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(formattedDate, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
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
            style: ElevatedButton.styleFrom(backgroundColor: _accentColor),
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
    if (userId.isEmpty) return;

    if (userId == widget.currentUserId) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ProfileScreen()),
      );
      return;
    }

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
    final gradientColors = hasCoverImage
        ? (AppColors.categoryGradients[collection.category.name] ??
            AppColors.categoryGradients['other']!)
        : _accentHeroGradient();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        extendBody: true,
        resizeToAvoidBottomInset: true,
        backgroundColor: AppColors.backgroundSurface,
        body: StreamBuilder<List<CollectionItemEntity>>(
        stream: _itemsStream,
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            _items = snapshot.data!;
          }
          final itemsCount = snapshot.hasData ? snapshot.data!.length : collection.itemCount;

          final scrollView = CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
                child: _buildCollectionTabBar(),
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
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: _buildDiscussionComposer(),
                  ),
                ),
                SliverToBoxAdapter(child: _buildDiscussionComments()),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          );

          if (_tabController.index != 1) {
            return scrollView;
          }

          return GestureDetector(
            onTap: () {
              if (_replyingToCommentId != null) {
                _cancelReply();
              }
              if (_isCommentComposerActive) {
                _dismissDiscussionComposer();
              } else {
                FocusManager.instance.primaryFocus?.unfocus();
              }
            },
            behavior: HitTestBehavior.translucent,
            child: scrollView,
          );
        },
      ),
      ),
    );
  }

  Widget _buildCollectionTabBar() {
    final selectedIndex = _tabController.index;

    return ColoredBox(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              _buildCollectionTab(
                label: 'ITEMS',
                index: 0,
                selectedIndex: selectedIndex,
              ),
              _buildCollectionTab(
                label: 'DISCUSSION',
                index: 1,
                selectedIndex: selectedIndex,
              ),
            ],
          ),
          const Divider(height: 1, color: AppColors.divider),
        ],
      ),
    );
  }

  Widget _buildCollectionTab({
    required String label,
    required int index,
    required int selectedIndex,
  }) {
    final isSelected = index == selectedIndex;

    return Expanded(
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: () {
            if (_tabController.index != index) {
              _tabController.index = index;
            }
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.6,
                    color: isSelected ? _accentColor : AppColors.textMuted,
                  ),
                ),
              ),
              Container(
                height: 2,
                color: isSelected ? _accentColor : Colors.transparent,
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const double _heroHorizontalPadding = 16;
  static const double _heroNavContentGap = 20;
  static const double _heroInlineGap = 8;
  static const double _heroStatGap = 36;
  static const double _heroTagHorizontalPadding = 12;
  static const double _heroTagVerticalPadding = 6;
  static const double _heroOpenPillHorizontalPadding = 18;
  static const double _heroOpenPillVerticalPadding = 7;
  static const double _heroCategoryPillHorizontalPadding = 14;
  static const double _heroCategoryPillVerticalPadding = 8;
  static const double _heroCategoryPillRadius = 8;
  static const double _heroStatsOpticalInset = 4;
  static const double _heroCircleButtonSize = 36;
  static const Color _heroTagFill = Color(0x1FFFFFFF);
  static const Color _heroSecondaryButtonFill = Color(0x1FFFFFFF);

  static const double _heroTitleFontSize = 34;
  static const double _heroTitleStrokeWidth = 0.45;

  static TextStyle _heroTitleBaseStyle() {
    return GoogleFonts.plusJakartaSans(
      fontSize: _heroTitleFontSize,
      fontWeight: FontWeight.w800,
      height: 1.12,
      letterSpacing: -0.45,
    );
  }

  Widget _buildHeroTitle(String title) {
    final baseStyle = _heroTitleBaseStyle();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Text(
          title,
          textHeightBehavior: _heroTextHeightBehavior,
          style: baseStyle.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = _heroTitleStrokeWidth
              ..color = Colors.white,
          ),
        ),
        Text(
          title,
          textHeightBehavior: _heroTextHeightBehavior,
          style: baseStyle.copyWith(color: Colors.white),
        ),
      ],
    );
  }

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
            Colors.black.withValues(alpha: 0.38),
            Colors.black.withValues(alpha: 0.52),
            Colors.black.withValues(alpha: 0.70),
            Colors.black.withValues(alpha: 0.84),
          ],
          stops: const [0.0, 0.35, 0.65, 1.0],
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
                    _buildCircleButton(
                      icon: Icons.keyboard_arrow_left,
                      onTap: () => Navigator.pop(context),
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
                    const SizedBox(width: _heroInlineGap),
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
                        const PopupMenuItem(value: 'get_info', child: Text('Get info')),
                        if (_isOwner)
                          const PopupMenuItem(value: 'edit', child: Text('Edit collection')),
                        if (_isOwner && !(_collection?.isOpenForContribution ?? false))
                          const PopupMenuItem(value: 'collaborators', child: Text('Add collaborators')),
                        if (_isOwner)
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        if (!_isOwner)
                          const PopupMenuItem(value: 'add_to_new', child: Text('Add to new collection')),
                      ],
                      onSelected: (value) {
                        if (value == 'get_info') {
                          if (_collection != null) _showCollectionInfoDialog(_collection!);
                        } else if (value == 'edit') {
                          _navigateToEditCollection();
                        } else if (value == 'collaborators') {
                          _showManageCollaboratorsDialog();
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeroContent(collection: collection),
                    const SizedBox(height: 20),
                    _buildHeroBottomBar(
                      collection: collection,
                      itemsCount: itemsCount,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
    );
  }

  Widget _buildHeroContent({
    required CollectionEntity collection,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => _navigateToUserProfile(collection.userId),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildUserAvatar(
                    collection.userName,
                    collection.userAvatarUrl,
                    size: 28,
                    userId: collection.userId,
                  ),
                  const SizedBox(width: _heroInlineGap),
                  Flexible(
                    child: Text(
                      '@${collection.userName}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        height: 1.2,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (collection.editors.isNotEmpty) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showCollaboratorsDialog(collection),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '+${collection.editors.length}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ] else if (collection.isOpenForContribution && _contributorUsers.isNotEmpty) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showContributorsDialog(collection),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '+${_contributorUsers.length}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _buildHeroTitle(collection.title),
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
        const SizedBox(height: 16),
        Wrap(
          spacing: _heroInlineGap,
          runSpacing: _heroInlineGap,
          alignment: WrapAlignment.start,
          runAlignment: WrapAlignment.start,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...collection.tags.map(_buildHeroTag),
            if (collection.isOpenForContribution)
              _buildHeroPill(
                label: 'OPEN',
                backgroundColor: _accentColor,
                fontWeight: FontWeight.w800,
                horizontalPadding: _heroOpenPillHorizontalPadding,
                verticalPadding: _heroOpenPillVerticalPadding,
              ),
            _buildHeroCategoryPill(collection),
          ],
        ),
      ],
    );
  }

  Widget _buildHeroBottomBar({
    required CollectionEntity collection,
    required int itemsCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeroDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            _heroStatsOpticalInset,
            16,
            _heroStatsOpticalInset,
            16,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildHeroStat('$itemsCount', 'ITEMS'),
              const SizedBox(width: _heroStatGap),
              _buildHeroStat('${collection.likes}', 'LIKES'),
              const Spacer(),
              _buildHeroCircleButton(
                icon: collection.isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                onTap: _toggleSave,
                isPrimary: collection.isSaved,
              ),
              const SizedBox(width: _heroInlineGap),
              _buildHeroCircleButton(
                icon: Icons.share_outlined,
                onTap: _shareCollection,
              ),
              const SizedBox(width: _heroInlineGap),
              _buildHeroCircleButton(
                icon: collection.isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                onTap: _toggleLike,
                backgroundColor:
                    collection.isLiked ? AppColors.heartSalmon : null,
              ),
              if (_canAddItems(collection)) ...[
                const SizedBox(width: _heroInlineGap),
                _buildHeroCircleButton(
                  icon: Icons.add_rounded,
                  onTap: () => _navigateToAddItem(),
                ),
              ],
            ],
          ),
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
    double? horizontalPadding,
    double? verticalPadding,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding ?? _heroTagHorizontalPadding,
          vertical: verticalPadding ?? _heroTagVerticalPadding,
        ),
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
      backgroundColor: _heroTagFill,
    );
  }

  Widget _buildHeroCategoryPill(CollectionEntity collection) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _accentColor,
        borderRadius: BorderRadius.circular(_heroCategoryPillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _heroCategoryPillHorizontalPadding,
          vertical: _heroCategoryPillVerticalPadding,
        ),
        child: Text(
          collection.category.displayName.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            height: 1.0,
          ),
          textHeightBehavior: _heroTextHeightBehavior,
        ),
      ),
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

  Widget _buildHeroCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isPrimary = false,
    Color? backgroundColor,
    Color iconColor = Colors.white,
  }) {
    final bg = backgroundColor ??
        (isPrimary ? _accentColor : _heroSecondaryButtonFill);

    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: _heroCircleButtonSize,
          height: _heroCircleButtonSize,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: iconColor,
          ),
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
          color: isPrimary ? _accentColor : Colors.transparent,
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
    return MentionTextField(
      controller: _commentController,
      focusNode: _commentFocusNode,
      firestoreService: _firestoreService,
      accentColor: _accentColor,
      hintText: 'Add a comment... (@ to tag)',
      minLines: 1,
      maxLines: 6,
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      surroundBuilder: (textField) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: UserAvatar(
                  name: _currentUserName.isNotEmpty ? _currentUserName : 'You',
                  size: 36,
                  userId: widget.currentUserId,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: textField),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ElevatedButton(
                  onPressed: () async {
                    final text = _commentController.text.trim();
                    if (text.isEmpty) return;
                    _commentController.clear();
                    _commentFocusNode.unfocus();
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
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: Text(
                    'Post',
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiscussionComments() {
    return StreamBuilder<List<CommentEntity>>(
      stream: _firestoreService.getCommentsStream(widget.collectionId),
      builder: (context, snapshot) {
        final comments = snapshot.data ?? [];
        if (comments.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
            child: Center(
              child: Column(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, size: 56, color: AppColors.textMuted),
                  const SizedBox(height: 16),
                  Text(
                    'No comments yet',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Start the conversation',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final commentsById = {for (final c in comments) c.id: c};
        final topLevel = comments.where((c) => c.parentCommentId == null).toList()
          ..sort(_compareCommentsByNewest);
        final repliesByParent = <String, List<CommentEntity>>{};
        for (final c in comments.where((c) => c.parentCommentId != null)) {
          repliesByParent.putIfAbsent(c.parentCommentId!, () => []).add(c);
        }
        for (final replies in repliesByParent.values) {
          replies.sort(_compareCommentsByNewest);
        }

        return Container(
          color: AppColors.backgroundSurface,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final comment in topLevel)
                _buildCommentThread(
                  comment,
                  repliesByParent,
                  commentsById: commentsById,
                  rootId: comment.id,
                ),
            ],
          ),
        );
      },
    );
  }

  int _compareCommentsByNewest(CommentEntity a, CommentEntity b) {
    return b.createdAt.compareTo(a.createdAt);
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
            Icon(Icons.subdirectory_arrow_right_rounded, size: 16, color: _accentColor),
            const SizedBox(width: 6),
            Text(
              'View $count ${count == 1 ? 'reply' : 'replies'}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: _accentColor,
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

    final threadContent = Column(
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

    if (depth == 0) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppColors.radiusLarge),
          border: Border.all(color: AppColors.divider),
        ),
        child: threadContent,
      );
    }

    return threadContent;
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
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _postReply(CommentEntity targetComment, Map<String, CommentEntity> commentsById) async {
    if (_commentDepth(targetComment, commentsById) >= _maxCommentDepth) return;

    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    _replyController.clear();
    _replyFocusNode.unfocus();
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
        MentionTextField(
          controller: _replyController,
          focusNode: _replyFocusNode,
          firestoreService: _firestoreService,
          accentColor: _accentColor,
          hintText: 'Reply to ${targetComment.userName}... (@ to tag)',
          filled: true,
          minLines: 1,
          maxLines: 4,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(
              onPressed: _cancelReply,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
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
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
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
        color: _accentColor,
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
          child: UserAvatar(
            name: comment.userName,
            size: avatarSize,
            avatarUrl: comment.userAvatarUrl,
            userId: comment.userId,
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
              CommentMentionText(
                text: comment.text,
                mentions: comment.mentions,
                onMentionTap: _navigateToUserProfile,
                mentionColor: _accentColor,
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
                        color: isLiked ? _accentColor : AppColors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$likeCount',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: isLiked ? _accentColor : AppColors.textSecondary,
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
                          color: isReplying ? _accentColor : AppColors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Reply',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: isReplying ? _accentColor : AppColors.textSecondary,
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
      return content;
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

  Widget _buildUserAvatar(
    String name,
    String? avatarUrl, {
    double size = 28,
    String? userId,
  }) {
    return UserAvatar(
      name: name,
      size: size,
      avatarUrl: avatarUrl,
      userId: userId,
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
  static const double _itemMenuButtonReservedWidth = 24;

  TextStyle get _itemTitleStyle => GoogleFonts.plusJakartaSans(
        fontSize: _itemTitleFontSize,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.25,
      );

  double _itemTitleTrailingWidth(CollectionItemEntity item) {
    var width = _itemMenuButtonReservedWidth;
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
    required bool showGetInfo,
  }) {
    return PopupMenuButton<String>(
      padding: EdgeInsets.zero,
      offset: const Offset(0, 24),
      child: const Icon(Icons.more_horiz, size: 18, color: AppColors.textMuted),
      onSelected: (value) {
        if (value == 'edit') _navigateToAddItem(item);
        else if (value == 'delete') _deleteItem(item);
        else if (value == 'add_to_collections') _showAddToCollectionsDialog(item);
        else if (value == 'get_info') _showItemInfoDialog(item);
      },
      itemBuilder: (context) => [
        if (canEdit) PopupMenuItem(value: 'edit', child: Text('Edit', style: GoogleFonts.plusJakartaSans())),
        if (canEdit) PopupMenuItem(value: 'delete', child: Text('Delete', style: GoogleFonts.plusJakartaSans())),
        if (showGetInfo) PopupMenuItem(value: 'get_info', child: Text('Get info', style: GoogleFonts.plusJakartaSans())),
        PopupMenuItem(value: 'add_to_collections', child: Text('Add to collection', style: GoogleFonts.plusJakartaSans())),
      ],
    );
  }

  Widget _buildItemCard(CollectionItemEntity item, int rank) {
    final collection = _collection;
    final canEdit = _isOwner || item.userId == widget.currentUserId;
    final showGetInfo = collection != null && _collectionHasMultipleContributors(collection);
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
                          _buildItemMenuButton(item: item, canEdit: canEdit, showGetInfo: showGetInfo),
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
                    decoration: BoxDecoration(
                      color: _accentSurfaceColor,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$rank',
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: _accentColor,
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
                          Padding(
                            padding: const EdgeInsets.only(
                              right: _itemMenuButtonReservedWidth,
                            ),
                            child: Text(
                              item.description!,
                              style: AppTextStyles.collectionDescription(
                                fontSize: 14,
                                height: 1.45,
                              ),
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
                        Icon(Icons.language_rounded, size: 16, color: _accentColor),
                        const SizedBox(width: 4),
                        Text('Website', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: _accentColor)),
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
                        Icon(Icons.location_on_outlined, size: 16, color: _accentColor),
                        const SizedBox(width: 4),
                        Text('Location', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: _accentColor)),
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

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
import '../utils/avatar_display_utils.dart';
import '../widgets/avatar_fallback.dart';
import '../widgets/user_avatar.dart';
import '../utils/comment_mentions.dart';
import '../widgets/mention_text_field.dart';
import '../widgets/comment_mention_text.dart';
import 'add_item_screen.dart';
import 'create_collection_screen.dart';
import 'user_profile_screen.dart';
import 'profile_screen.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../widgets/manage_collaborators_dialog.dart';
import '../widgets/animated_segmented_tab_bar.dart';
import '../widgets/resolved_network_image.dart';
import '../utils/storage_image_url.dart';

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
  final TextEditingController _itemSearchController = TextEditingController();
  final FocusNode _itemSearchFocusNode = FocusNode();
  String _currentUserName = '';

  bool _isFollowing = false;
  bool _isAddToCollectionsLoading = false;
  bool _isUnauthorized = false;
  bool _isDeletingCollection = false;
  bool _isSubmittingComment = false;

  late TabController _tabController;
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _commentFocusNode = FocusNode();
  final FocusNode _replyFocusNode = FocusNode();
  List<CommentMention> _commentConfirmedMentions = const [];
  List<CommentMention> _replyConfirmedMentions = const [];
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

  void _onTabControllerChanged() {
    if (!mounted) return;
    if (_tabController.index != 0 && _showSearch) {
      _closeItemSearch();
    }
    setState(() {});
    if (_tabController.index != 1) {
      _dismissDiscussionComposer();
    }
  }

  void _onItemSearchFocusChanged() {
    if (mounted) setState(() {});
  }

  void _dismissItemSearchKeyboard() {
    _itemSearchFocusNode.unfocus();
  }

  void _openItemSearch() {
    if (_tabController.index != 0) {
      _tabController.index = 0;
    }
    setState(() => _showSearch = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _itemSearchFocusNode.requestFocus();
    });
  }

  void _closeItemSearch() {
    if (!_showSearch) return;
    _itemSearchController.clear();
    setState(() {
      _showSearch = false;
      _searchQuery = '';
    });
    _itemSearchFocusNode.unfocus();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabControllerChanged);
    _itemSearchFocusNode.addListener(_onItemSearchFocusChanged);
    _itemsStream = _firestoreService.getCollectionItems(widget.collectionId);
    _setupCollectionStream();
    _loadCurrentUserName();
  }

  void _setupCollectionStream() {
    _collectionSubscription = _firestoreService.getCollectionStream(widget.collectionId).listen(
      (collection) async {
        if (mounted) {
          if (collection == null) {
            if (_isDeletingCollection) {
              return;
            }
            debugPrint('Collection deleted, navigating back');
            await _collectionSubscription?.cancel();
            if (!mounted) return;
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
    _itemSearchController.dispose();
    _itemSearchFocusNode.removeListener(_onItemSearchFocusChanged);
    _itemSearchFocusNode.dispose();
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

    final ids = rawIds
        .where((id) => id.trim().isNotEmpty && id != collection.userId)
        .toSet()
        .toList();
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
    return _dedupeCollaboratorEntries(
      collection.collaborators
          .where((c) => collection.editors.contains(c['userId'] as String? ?? ''))
          .toList(),
    );
  }

  List<Map<String, dynamic>> _dedupeCollaboratorEntries(
    List<Map<String, dynamic>> entries,
  ) {
    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final entry in entries) {
      final userId = (entry['userId'] as String? ?? '').trim();
      if (userId.isEmpty || seen.contains(userId)) continue;
      seen.add(userId);
      unique.add(entry);
    }
    return unique;
  }

  List<UserEntity> _dedupeUsers(List<UserEntity> users) {
    final seen = <String>{};
    final unique = <UserEntity>[];
    for (final user in users) {
      if (seen.contains(user.id)) continue;
      seen.add(user.id);
      unique.add(user);
    }
    return unique;
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

  Future<void> _showCollaboratorsDialog(CollectionEntity collection) async {
    var collaborators = _editorCollaborators(collection);
    if (collaborators.isEmpty) {
      final editorIds = _editorUserIdsExcludingOwner(collection);
      if (editorIds.isEmpty) return;

      try {
        final users = await _firestoreService.getUsersByIds(editorIds);
        collaborators = _dedupeCollaboratorEntries(
          users.map((u) => {'userId': u.id, 'username': u.userName}).toList(),
        );
      } catch (e) {
        debugPrint('Error loading collaborators: $e');
        return;
      }
    }

    if (!mounted || collaborators.isEmpty) return;

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
              ...collaborators.map((collab) {
                final userId = collab['userId'] as String? ?? '';
                final username = collab['username'] as String? ?? 'User';
                final isEditor = collection.editors.contains(userId);
                return _buildPeopleDialogRow(
                  dialogContext: dialogContext,
                  userId: userId,
                  username: username,
                  subtitle: isEditor ? 'Editor' : 'Collaborator',
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
    final users = _dedupeUsers(_contributorUsers);
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

  void _showItemImagePreview(List<String> imageUrls, int initialIndex) {
    if (imageUrls.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogContext) => _ItemImagePreviewDialog(
        imageUrls: imageUrls,
        initialIndex: initialIndex.clamp(0, imageUrls.length - 1),
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

  Future<void> _deleteComment(CommentEntity comment) async {
    try {
      await _firestoreService.deleteComment(
        comment.id,
        requestingUserId: widget.currentUserId,
      );
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showErrorSnackBar(context, 'Could not delete comment');
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
              Navigator.pop(context);
              if (!mounted) return;

              final messenger = ScaffoldMessenger.of(context);
              setState(() => _isDeletingCollection = true);
              await _collectionSubscription?.cancel();
              _collectionSubscription = null;

              messenger.hideCurrentSnackBar();
              SnackBarUtils.showInfoSnackBar(context, 'Deleting collection...');

              try {
                await _firestoreService.deleteCollection(
                  widget.collectionId,
                  widget.currentUserId,
                );

                if (!mounted) return;
                messenger.hideCurrentSnackBar();
                await Navigator.of(context).maybePop(true);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Collection deleted'),
                    backgroundColor: Color(0xFF22C55E),
                    behavior: SnackBarBehavior.floating,
                    duration: Duration(seconds: 3),
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                setState(() => _isDeletingCollection = false);
                _setupCollectionStream();
                messenger.hideCurrentSnackBar();
                SnackBarUtils.showErrorSnackBar(
                  context,
                  'Could not delete collection. Please try again.',
                );
                debugPrint('Error deleting collection: $e');
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

          return ListenableBuilder(
            listenable: _tabController,
            builder: (context, _) {
              final isDiscussionTab = _tabController.index == 1;

              final scrollView = CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(
                child: RepaintBoundary(
                  child: _buildHeroHeader(
                    collection: collection,
                    itemsCount: itemsCount,
                    gradientColors: gradientColors,
                    hasCoverImage: hasCoverImage,
                  ),
                ),
              ),

              // Items / Discussion tab bar
              SliverToBoxAdapter(
                child: _buildCollectionTabBar(),
              ),

              // Items list
              if (_tabController.index == 0)
                _buildItemsList(),

              // Discussion tab
              if (_tabController.index == 1) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      _contentHorizontalPadding,
                      14,
                      _contentHorizontalPadding,
                      8,
                    ),
                    child: _buildDiscussionComposer(),
                  ),
                ),
                SliverToBoxAdapter(child: _buildDiscussionComments()),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          );

              return GestureDetector(
                onTap: () {
                  if (isDiscussionTab) {
                    if (_replyingToCommentId != null) {
                      _cancelReply();
                    }
                    if (_isCommentComposerActive) {
                      _dismissDiscussionComposer();
                    }
                    FocusManager.instance.primaryFocus?.unfocus();
                  } else if (_showSearch) {
                    _dismissItemSearchKeyboard();
                  } else {
                    FocusManager.instance.primaryFocus?.unfocus();
                  }
                },
                behavior: HitTestBehavior.translucent,
                child: scrollView,
              );
            },
          );
        },
      ),
      ),
    );
  }

  Widget _buildCollectionTabBar() {
    return AnimatedSegmentedTabBar(
      controller: _tabController,
      labels: const ['ITEMS', 'DISCUSSION'],
      padding: EdgeInsets.fromLTRB(
        _contentHorizontalPadding,
        _heroSectionGap,
        _contentHorizontalPadding,
        0,
      ),
    );
  }

  static const double _heroHorizontalPadding = 16;
  static const double _heroNavSize = 40;
  static const double _heroSearchHeight = 40;
  static const double _contentHorizontalPadding = 24;
  static const double _heroSectionGap = 22;
  static const double _heroCoverHeight = 210;
  static const double _heroCardOverlap = 85;
  static const double _heroInfoCardRadius = 20;
  static const double _heroInlineGap = 8;
  static const double _heroStatGap = 28;
  static const double _heroTagHorizontalPadding = 12;
  static const double _heroTagVerticalPadding = 6;
  static const double _heroOpenPillHorizontalPadding = 18;
  static const double _heroOpenPillVerticalPadding = 7;
  static const double _heroCategoryPillHorizontalPadding = 14;
  static const double _heroCategoryPillVerticalPadding = 8;
  static const double _heroCategoryPillRadius = 8;
  static const double _heroStatsOpticalInset = 0;
  static const double _heroActionButtonSize = 38;

  static const double _heroTitleFontSize = 24;

  static TextStyle _heroTitleBaseStyle() {
    return GoogleFonts.plusJakartaSans(
      fontSize: _heroTitleFontSize,
      fontWeight: FontWeight.w800,
      height: 1.2,
      letterSpacing: -0.35,
      color: AppColors.textPrimary,
    );
  }

  Widget _buildHeroTitle(String title) {
    return Text(
      title,
      textHeightBehavior: _heroTextHeightBehavior,
      style: _heroTitleBaseStyle(),
    );
  }

  List<String> _openCollectionAdditionalContributorIds(CollectionEntity collection) {
    final itemAuthorIds = _items
        .map((item) => item.userId)
        .where((id) => id.isNotEmpty)
        .toSet();

    // Only show when more than one person has added items.
    if (itemAuthorIds.length <= 1) return const [];

    return itemAuthorIds.where((id) => id != collection.userId).toSet().toList();
  }

  List<String> _editorUserIdsExcludingOwner(CollectionEntity collection) {
    return collection.editors
        .where((id) => id.isNotEmpty && id != collection.userId)
        .toSet()
        .toList();
  }

  ({int count, String label, VoidCallback onTap})? _heroPeopleExtras(
    CollectionEntity collection,
  ) {
    if (collection.isOpenForContribution) {
      final additionalIds = _openCollectionAdditionalContributorIds(collection);
      if (additionalIds.isEmpty) return null;

      final count = additionalIds.length;
      return (
        count: count,
        label: count == 1 ? 'contributor' : 'contributors',
        onTap: () => _showOpenContributorsDialog(collection, additionalIds),
      );
    }

    final editorIds = _editorUserIdsExcludingOwner(collection);
    if (editorIds.isEmpty) return null;

    final count = editorIds.length;
    return (
      count: count,
      label: count == 1 ? 'collaborator' : 'collaborators',
      onTap: () => _showCollaboratorsDialog(collection),
    );
  }

  Future<void> _showOpenContributorsDialog(
    CollectionEntity collection,
    List<String> contributorIds,
  ) async {
    final uniqueContributorIds = contributorIds.toSet().toList();
    if (uniqueContributorIds.isEmpty) return;

    var users =
        _contributorUsers.where((u) => uniqueContributorIds.contains(u.id)).toList();
    if (users.length < uniqueContributorIds.length) {
      try {
        users = await _firestoreService.getUsersByIds(uniqueContributorIds);
      } catch (e) {
        debugPrint('Error loading open contributors: $e');
      }
    }
    users = _dedupeUsers(users);

    if (!mounted || users.isEmpty) return;

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
                (user) {
                  final isEditor = collection.editors.contains(user.id);
                  return _buildPeopleDialogRow(
                    dialogContext: dialogContext,
                    userId: user.id,
                    username: user.userName,
                    avatarUrl: user.avatarUrl,
                    subtitle: isEditor ? 'Editor' : null,
                  );
                },
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

  Widget _buildHeroPeopleRow(CollectionEntity collection) {
    final extras = _heroPeopleExtras(collection);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _navigateToUserProfile(collection.userId),
            behavior: HitTestBehavior.opaque,
            child: UserAvatar(
              userId: collection.userId,
              avatarUrl: _avatarUrlForUser(collection.userId, collection.userAvatarUrl),
              trustProvidedAvatar: collection.userId == widget.currentUserId,
              name: collection.userName,
              size: 28,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                GestureDetector(
                  onTap: () => _navigateToUserProfile(collection.userId),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    collection.userName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      height: 1.2,
                    ),
                  ),
                ),
                if (extras != null)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: extras.onTap,
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Text(
                          '+ ${extras.count} ${extras.label}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _accentColor,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const TextStyle _heroDescriptionStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppColors.collectionDescription,
    height: 1.45,
    letterSpacing: 0,
  );

  static const TextHeightBehavior _heroTextHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: true,
    applyHeightToLastDescent: false,
  );

  Widget _buildHeroInfoCard({
    required CollectionEntity collection,
    required int itemsCount,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_heroInfoCardRadius),
        boxShadow: AppColors.elevatedShadow,
      ),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeroContent(collection: collection),
          _buildHeroBottomBar(
            collection: collection,
            itemsCount: itemsCount,
          ),
        ],
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
    const topPadding = 8.0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _heroCoverHeight,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _StableCollectionCover(
                coverImageUrl: collection.coverImageUrl,
                fallbackGradient: gradientColors,
                hasCoverImage: hasCoverImage,
              ),
              Column(
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
                        const SizedBox(width: _heroInlineGap),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SizeTransition(
                                  sizeFactor: animation,
                                  axisAlignment: -1,
                                  child: child,
                                ),
                              );
                            },
                            child: _showSearch && _tabController.index == 0
                                ? _buildHeroSearchField(key: const ValueKey('hero-search-field'))
                                : Align(
                                    key: const ValueKey('hero-search-button'),
                                    alignment: Alignment.centerRight,
                                    child: _buildCircleButton(
                                      icon: Icons.search_rounded,
                                      onTap: _openItemSearch,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: _heroInlineGap),
                        _AnchoredTrailingMenu(
                          itemBuilder: (context) => [
                            if (_isOwner)
                              _popupMenuEntry(value: 'edit', label: 'Edit collection'),
                            if (_isOwner && !(_collection?.isOpenForContribution ?? false))
                              _popupMenuEntry(value: 'collaborators', label: 'Add collaborators'),
                            if (!_isOwner)
                              _popupMenuEntry(value: 'add_to_new', label: 'Add to new collection'),
                            _popupMenuEntry(value: 'get_info', label: 'Get info'),
                            if (_isOwner) ...[
                              const PopupMenuDivider(height: 1),
                              _popupMenuEntry(
                                value: 'delete',
                                label: 'Delete',
                                color: AppColors.heartSalmon,
                              ),
                            ],
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
                          child: Container(
                            width: _heroNavSize,
                            height: _heroNavSize,
                            decoration: _navCircleDecoration,
                            child: const Icon(Icons.more_horiz, color: AppColors.textPrimary, size: 22),
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
          padding: EdgeInsets.only(
            top: _heroCoverHeight - _heroCardOverlap,
            left: _heroHorizontalPadding,
            right: _heroHorizontalPadding,
          ),
          child: _buildHeroInfoCard(
            collection: collection,
            itemsCount: itemsCount,
          ),
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
        _buildHeroPeopleRow(collection),
        _buildHeroTitle(collection.title),
        if (collection.description != null && collection.description!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            collection.description!,
            textHeightBehavior: _heroTextHeightBehavior,
            style: GoogleFonts.plusJakartaSans(textStyle: _heroDescriptionStyle),
          ),
        ],
        if (_collectionHasWebsite(collection) || _collectionHasLocation(collection)) ...[
          const SizedBox(height: 14),
          _buildLinkLocationRow(
            websiteUrl: collection.websiteUrl,
            googleMapsUrl: collection.googleMapsUrl,
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: _heroInlineGap,
          runSpacing: _heroInlineGap,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...collection.tags.map(_buildHeroTag),
            if (collection.isOpenForContribution)
              _buildHeroPill(
                label: 'OPEN',
                backgroundColor: _accentColor,
                textColor: Colors.white,
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
        const SizedBox(height: 14),
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
              _buildHeroActionButton(
                icon: collection.isSaved
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
                onTap: _toggleSave,
                filled: collection.isSaved,
                fillColor: collection.isSaved ? _accentColor : null,
              ),
              const SizedBox(width: _heroInlineGap),
              _buildHeroActionButton(
                icon: Icons.share_outlined,
                onTap: _shareCollection,
              ),
              const SizedBox(width: _heroInlineGap),
              _buildHeroActionButton(
                icon: collection.isLiked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                onTap: _toggleLike,
                filled: collection.isLiked,
                fillColor: collection.isLiked ? AppColors.heartSalmon : null,
              ),
              if (_canAddItems(collection)) ...[
                const SizedBox(width: _heroInlineGap),
                _buildHeroActionButton(
                  icon: Icons.add_rounded,
                  onTap: () => _navigateToAddItem(),
                  filled: true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroDivider() {
    return SizedBox(
      width: double.infinity,
      height: 1,
      child: ColoredBox(color: AppColors.divider),
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
    Color? borderColor,
    Color textColor = Colors.white,
    FontWeight fontWeight = FontWeight.w600,
    double? horizontalPadding,
    double? verticalPadding,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
        border: borderColor != null
            ? Border.all(color: borderColor, width: 1)
            : null,
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
      backgroundColor: AppColors.chipBg,
      textColor: AppColors.textSecondary,
      fontWeight: FontWeight.w600,
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
            height: 1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textMuted,
            letterSpacing: 0.6,
            height: 1,
          ),
        ),
      ],
    );
  }

  Widget _buildHeroActionButton({
    required IconData icon,
    required VoidCallback onTap,
    bool filled = false,
    Color? fillColor,
    Color? iconColor,
  }) {
    final bg = filled ? (fillColor ?? _accentColor) : Colors.white;
    final resolvedIconColor = filled
        ? Colors.white
        : (iconColor ?? AppColors.textPrimary);

    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: _heroActionButtonSize,
          height: _heroActionButtonSize,
          decoration: BoxDecoration(
            color: bg,
            shape: BoxShape.circle,
            border: filled
                ? null
                : Border.all(color: AppColors.divider, width: 1.2),
          ),
          child: Icon(icon, size: 20, color: resolvedIconColor),
        ),
      ),
    );
  }

  Widget _buildItemsList() {
    final items = _filteredItems;

    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(0, _heroSectionGap - 8, 0, 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final item = items[index];
            return _buildItemCard(item);
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

  static const double _discussionComposerInputMinHeight = 40;
  static const double _discussionComposerAvatarSize = 38;
  static const double _discussionComposerInputRadius = 10;

  Widget _buildDiscussionComposer() {
    return AnimatedBuilder(
      animation: _commentController,
      builder: (context, _) {
        final hasExplicitLineBreak = _commentController.text.contains('\n');

        return MentionTextField(
          controller: _commentController,
          focusNode: _commentFocusNode,
          firestoreService: _firestoreService,
          accentColor: _accentColor,
          onConfirmedMentionsChanged: (mentions) {
            _commentConfirmedMentions = mentions;
          },
          hintText: 'Add a comment...',
          minLines: 1,
          maxLines: 6,
          dense: true,
          collapseDecoration: !hasExplicitLineBreak,
          textAlignVertical: TextAlignVertical.top,
          textStyle: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            height: 1.25,
            color: AppColors.textPrimary,
          ),
          contentPadding: EdgeInsets.zero,
          surroundBuilder: (textField) {
            return Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
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
                    padding: const EdgeInsets.only(top: 1),
                    child: UserAvatar(
                      name: _currentUserName.isNotEmpty ? _currentUserName : 'You',
                      size: _discussionComposerAvatarSize,
                      userId: widget.currentUserId,
                      avatarUrl: _avatarUrlForUser(
                        widget.currentUserId,
                        context.watch<AuthProvider>().userEntity?.avatarUrl,
                      ),
                      trustProvidedAvatar: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: _discussionComposerInputMinHeight,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius:
                            BorderRadius.circular(_discussionComposerInputRadius),
                      ),
                      alignment: Alignment.topLeft,
                      child: textField,
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: _isSubmittingComment
                        ? null
                        : () async {
                      final text = _commentController.text.trim();
                      if (text.isEmpty) return;
                      final mentions = List<CommentMention>.from(_commentConfirmedMentions);
                      _commentController.clear();
                      _commentConfirmedMentions = const [];
                      _commentFocusNode.unfocus();
                      setState(() => _isSubmittingComment = true);
                      try {
                        final auth = await _firestoreService.getUser(widget.currentUserId);
                        await _firestoreService.addComment(
                          collectionId: widget.collectionId,
                          userId: widget.currentUserId,
                          userName: auth?.userName ?? '',
                          userAvatarUrl: auth?.avatarUrl,
                          text: text,
                          confirmedMentions: mentions,
                        );
                      } finally {
                        if (mounted) setState(() => _isSubmittingComment = false);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      minimumSize: const Size(0, 36),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
          },
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
          return const SizedBox.shrink();
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
          padding: EdgeInsets.fromLTRB(_contentHorizontalPadding, 12, _contentHorizontalPadding, 0),
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
      _replyConfirmedMentions = const [];
    });
    _replyFocusNode.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
  }

  Future<void> _postReply(CommentEntity targetComment, Map<String, CommentEntity> commentsById) async {
    if (_isSubmittingComment) return;
    if (_commentDepth(targetComment, commentsById) >= _maxCommentDepth) return;

    final text = _replyController.text.trim();
    if (text.isEmpty) return;
    final mentions = List<CommentMention>.from(_replyConfirmedMentions);
    _replyController.clear();
    _replyConfirmedMentions = const [];
    _replyFocusNode.unfocus();
    setState(() => _isSubmittingComment = true);
    try {
      final auth = await _firestoreService.getUser(widget.currentUserId);
      await _firestoreService.addComment(
        collectionId: widget.collectionId,
        userId: widget.currentUserId,
        userName: auth?.userName ?? '',
        userAvatarUrl: auth?.avatarUrl,
        text: text,
        parentCommentId: targetComment.id,
        confirmedMentions: mentions,
      );
      if (mounted) _cancelReply();
    } finally {
      if (mounted) setState(() => _isSubmittingComment = false);
    }
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
          onConfirmedMentionsChanged: (mentions) {
            _replyConfirmedMentions = mentions;
          },
          hintText: 'Reply to ${targetComment.userName}...',
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
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: child,
      ),
    );
  }

  Widget _buildCommentOwnerBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _accentColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'OWNER',
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.45,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }

  Widget _buildCommentLikeAction({
    required bool isLiked,
    required int likeCount,
    required VoidCallback onTap,
  }) {
    final likeColor = isLiked ? AppColors.heartSalmon : AppColors.textSecondary;

    return _buildCommentActionButton(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 17,
            color: likeColor,
          ),
          const SizedBox(width: 5),
          Text(
            '$likeCount',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: isLiked ? FontWeight.w700 : FontWeight.w600,
              color: likeColor,
            ),
          ),
        ],
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
    final canDeleteComment = isOwn || _isOwner;
    final isCommentByCollectionOwner = comment.userId == _collection?.userId;
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
            avatarUrl: _avatarUrlForUser(comment.userId, comment.userAvatarUrl),
            trustProvidedAvatar: comment.userId == widget.currentUserId,
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
                  if (isCommentByCollectionOwner) ...[
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
                  fontSize: 14,
                  color: AppColors.textPrimary,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildCommentLikeAction(
                    isLiked: isLiked,
                    likeCount: likeCount,
                    onTap: () => _toggleCommentLike(comment),
                  ),
                  if (canReply) ...[
                    const SizedBox(width: 18),
                    _buildCommentActionButton(
                        onTap: () => _startReplyTo(comment, rootId, commentsById),
                        child: Text(
                          'Reply',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: isReplying ? _accentColor : AppColors.textSecondary,
                            fontWeight: isReplying ? FontWeight.w800 : FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              if (isReplying) _buildReplyComposer(comment, commentsById),
            ],
          ),
        ),
        if (canDeleteComment)
          GestureDetector(
            onTap: () => _deleteComment(comment),
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

  static const double _popupMenuItemHeight = 40;

  PopupMenuItem<String> _popupMenuEntry({
    required String value,
    required String label,
    Color? color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: _popupMenuItemHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: color ?? AppColors.textPrimary,
        ),
      ),
    );
  }

  static const BoxDecoration _navCircleDecoration = BoxDecoration(
    color: Colors.white,
    shape: BoxShape.circle,
    boxShadow: [
      BoxShadow(
        color: Color(0x1A000000),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ],
  );

  Widget _buildCircleButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: _heroNavSize,
        height: _heroNavSize,
        decoration: _navCircleDecoration,
        child: Icon(icon, color: AppColors.textPrimary, size: 22),
      ),
    );
  }

  Widget _buildHeroSearchField({Key? key}) {
    const radius = _heroSearchHeight / 2;

    return Container(
      key: key,
      height: _heroSearchHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: _navCircleDecoration.boxShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: TextField(
          controller: _itemSearchController,
          focusNode: _itemSearchFocusNode,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
            height: 1.2,
          ),
          cursorColor: AppColors.textPrimary,
          decoration: InputDecoration(
            hintText: 'Search items...',
            hintStyle: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w400,
              color: AppColors.textMuted,
            ),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.search_rounded,
                size: 20,
                color: AppColors.textMuted.withValues(alpha: 0.85),
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: _heroSearchHeight),
            suffixIcon: IconButton(
              onPressed: _closeItemSearch,
              icon: Icon(
                Icons.close_rounded,
                size: 18,
                color: AppColors.textMuted.withValues(alpha: 0.85),
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              splashRadius: 18,
            ),
            suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: _heroSearchHeight),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (value) {
            setState(() => _searchQuery = value);
          },
          textInputAction: TextInputAction.search,
        ),
      ),
    );
  }

  String? _avatarUrlForUser(String userId, String? storedUrl) {
    final auth = context.watch<AuthProvider>();
    return displayAvatarUrl(
      storedAvatarUrl: storedUrl,
      subjectUserId: userId,
      currentUserId: widget.currentUserId,
      currentUserAvatarUrl: auth.userEntity?.avatarUrl,
    );
  }

  Widget _buildUserAvatar(
    String name,
    String? avatarUrl, {
    double size = 28,
    String? userId,
  }) {
    final resolvedUrl = userId == null
        ? avatarUrl
        : _avatarUrlForUser(userId, avatarUrl);
    final isCurrentUser = userId == widget.currentUserId;
    return UserAvatar(
      name: name,
      size: size,
      avatarUrl: resolvedUrl,
      userId: userId,
      trustProvidedAvatar: isCurrentUser,
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
  static const double _itemRatingBadgeHeight = 26;
  static const double _itemMenuButtonReservedWidth = 24;
  static const double _itemMetaRowTopGap = 4;
  static const double _itemImageThumbSize = 100;
  static const double _itemImagesTopGap = 12;
  static const double _itemImagesAfterLinksGap = 22;
  static const TextHeightBehavior _itemTitleTextHeightBehavior = TextHeightBehavior(
    applyHeightToFirstAscent: true,
    applyHeightToLastDescent: false,
  );

  TextStyle get _itemTitleStyle => GoogleFonts.plusJakartaSans(
        fontSize: _itemTitleFontSize,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        height: 1.25,
      );

  TextStyle get _itemMetaLabelStyle => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: _accentColor,
      );

  bool _collectionHasWebsite(CollectionEntity collection) =>
      (collection.websiteUrl ?? '').trim().isNotEmpty;

  bool _collectionHasLocation(CollectionEntity collection) =>
      (collection.googleMapsUrl ?? '').trim().isNotEmpty;

  Widget _buildLinkLocationRow({
    required String? websiteUrl,
    required String? googleMapsUrl,
  }) {
    final hasWebsite = (websiteUrl ?? '').trim().isNotEmpty;
    final hasLocation = (googleMapsUrl ?? '').trim().isNotEmpty;
    if (!hasWebsite && !hasLocation) return const SizedBox.shrink();

    return Row(
      children: [
        if (hasWebsite)
          GestureDetector(
            onTap: () {
              var raw = websiteUrl!.trim();
              if (!raw.startsWith('http')) raw = 'https://$raw';
              final uri = Uri.tryParse(raw);
              if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: const Offset(-2, 0),
                  child: Icon(Icons.link, size: 18, color: _accentColor),
                ),
                const SizedBox(width: 2),
                Text('Link', style: _itemMetaLabelStyle),
              ],
            ),
          ),
        if (hasWebsite && hasLocation) const SizedBox(width: 24),
        if (hasLocation)
          GestureDetector(
            onTap: () {
              final uri = Uri.tryParse(googleMapsUrl!.trim());
              if (uri != null) launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: const Offset(-2, 0),
                  child: Icon(Icons.location_on, size: 18, color: _accentColor),
                ),
                const SizedBox(width: 2),
                Text('Location', style: _itemMetaLabelStyle),
              ],
            ),
          ),
      ],
    );
  }

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
    return _AnchoredTrailingMenu(
      child: const SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: Icon(Icons.more_horiz, size: 18, color: AppColors.textMuted),
        ),
      ),
      onSelected: (value) {
        if (value == 'edit') _navigateToAddItem(item);
        else if (value == 'delete') _deleteItem(item);
        else if (value == 'add_to_collections') _showAddToCollectionsDialog(item);
        else if (value == 'get_info') _showItemInfoDialog(item);
      },
      itemBuilder: (context) => [
        if (canEdit)
          _popupMenuEntry(value: 'edit', label: 'Edit'),
        _popupMenuEntry(value: 'add_to_collections', label: 'Add to collection'),
        if (showGetInfo)
          _popupMenuEntry(value: 'get_info', label: 'Get info'),
        if (canEdit) ...[
          const PopupMenuDivider(height: 1),
          _popupMenuEntry(
            value: 'delete',
            label: 'Delete',
            color: AppColors.heartSalmon,
          ),
        ],
      ],
    );
  }

  Widget _buildItemCard(CollectionItemEntity item) {
    final collection = _collection;
    final canEdit = _isOwner || item.userId == widget.currentUserId;
    final showGetInfo = collection != null && _collectionHasMultipleContributors(collection);
    final hasImages = item.imageUrls.isNotEmpty;
    final hasDescription =
        item.description != null && item.description!.trim().isNotEmpty;
    final hasLocation = (item.googleMapsUrl ?? '').trim().isNotEmpty;
    final hasWebsite = (item.websiteUrl ?? '').trim().isNotEmpty;

    return Container(
      margin: EdgeInsets.fromLTRB(
        _contentHorizontalPadding,
        8,
        _contentHorizontalPadding,
        8,
      ),
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
              final titleMaxWidth = constraints.maxWidth - trailingWidth;
              final isSingleLineTitle =
                  _isSingleLineItemTitle(context, item.title, titleMaxWidth);

              final titleRowHeight =
                  item.rating > 0 ? _itemRatingBadgeHeight : _itemTitleLineHeight;

              Widget buildTitleRow() {
                return Row(
                  crossAxisAlignment: isSingleLineTitle
                      ? CrossAxisAlignment.center
                      : CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        style: _itemTitleStyle,
                        textHeightBehavior: _itemTitleTextHeightBehavior,
                      ),
                    ),
                    SizedBox(
                      height: isSingleLineTitle ? titleRowHeight : _itemTitleLineHeight,
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
                                vertical: 4,
                              ),
                              borderRadius: 6,
                              iconGap: 4,
                            ),
                            const SizedBox(width: 4),
                          ],
                          _buildItemMenuButton(item: item, canEdit: canEdit, showGetInfo: showGetInfo),
                        ],
                      ),
                    ),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isSingleLineTitle)
                    SizedBox(
                      height: titleRowHeight,
                      child: buildTitleRow(),
                    )
                  else
                    buildTitleRow(),
                  if (hasDescription) ...[
                    const SizedBox(height: _itemMetaRowTopGap),
                    Padding(
                      padding: EdgeInsets.only(
                        right: _itemTitleTrailingWidth(item),
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
              );
            },
          ),

          if (hasWebsite || hasLocation) ...[
            const SizedBox(height: _itemMetaRowTopGap),
            _buildLinkLocationRow(
              websiteUrl: item.websiteUrl,
              googleMapsUrl: item.googleMapsUrl,
            ),
          ],

          if (hasImages) ...[
            SizedBox(
              height: (hasWebsite || hasLocation)
                  ? _itemImagesAfterLinksGap
                  : _itemImagesTopGap,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox(
                height: _itemImageThumbSize,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: item.imageUrls.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, i) => GestureDetector(
                    onTap: () => _showItemImagePreview(item.imageUrls, i),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                      child: ResolvedNetworkImage(
                        imageUrl: item.imageUrls[i],
                        fit: BoxFit.cover,
                        width: _itemImageThumbSize,
                        height: _itemImageThumbSize,
                        errorWidget: (_, __, ___) => Container(
                          width: _itemImageThumbSize,
                          height: _itemImageThumbSize,
                          color: AppColors.surfaceMuted,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
                        ),
                      ),
                    ),
                  ),
                ),
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

/// Keeps the resolved cover URL in its own state so tab switches don't
/// re-run FutureBuilder or briefly show the category gradient fallback.
class _StableCollectionCover extends StatefulWidget {
  const _StableCollectionCover({
    required this.coverImageUrl,
    required this.fallbackGradient,
    required this.hasCoverImage,
  });

  final String? coverImageUrl;
  final List<Color> fallbackGradient;
  final bool hasCoverImage;

  @override
  State<_StableCollectionCover> createState() => _StableCollectionCoverState();
}

class _StableCollectionCoverState extends State<_StableCollectionCover> {
  static const _loadingColor = AppColors.surfaceMuted;

  String? _resolvedUrl;
  String? _cacheKey;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _StableCollectionCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    final raw = widget.coverImageUrl?.trim() ?? '';
    if (raw != _cacheKey) {
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final raw = widget.coverImageUrl?.trim() ?? '';
    _cacheKey = raw;

    if (raw.isEmpty) {
      if (mounted) setState(() => _resolvedUrl = null);
      return;
    }

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      if (mounted) setState(() => _resolvedUrl = raw);
      return;
    }

    if (raw.startsWith('gs://')) {
      try {
        final url = await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
        if (mounted && _cacheKey == raw) {
          setState(() => _resolvedUrl = url);
        }
      } catch (_) {
        if (mounted && _cacheKey == raw) {
          setState(() => _resolvedUrl = null);
        }
      }
    }
  }

  Widget _gradientFallback() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: widget.fallbackGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasCoverImage) {
      return _gradientFallback();
    }

    final url = _resolvedUrl;
    if (url != null && url.isNotEmpty) {
      return RepaintBoundary(
        child: CachedNetworkImage(
          key: ValueKey(url),
          imageUrl: url,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          fadeOutDuration: Duration.zero,
          placeholder: (_, __) => const ColoredBox(color: _loadingColor),
          errorWidget: (_, __, ___) => _gradientFallback(),
        ),
      );
    }

    return const ColoredBox(color: _loadingColor);
  }
}

class _ItemImagePreviewDialog extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _ItemImagePreviewDialog({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_ItemImagePreviewDialog> createState() => _ItemImagePreviewDialogState();
}

class _ItemImagePreviewDialogState extends State<_ItemImagePreviewDialog> {
  late final PageController _pageController;
  late int _currentIndex;
  Size? _imageSize;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;
  final Map<int, String?> _resolvedUrls = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _resolveImageSize(widget.initialIndex);
  }

  @override
  void dispose() {
    _removeImageListener();
    _pageController.dispose();
    super.dispose();
  }

  void _removeImageListener() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  Future<void> _resolveImageSize(int index) async {
    _removeImageListener();
    if (!mounted) return;
    setState(() => _imageSize = null);

    final raw = widget.imageUrls[index];
    var resolved = _resolvedUrls[index];
    resolved ??= await resolveStorageImageUrl(raw);
    _resolvedUrls[index] = resolved;
    if (!mounted) return;

    if (resolved == null || resolved.isEmpty) return;

    final provider = CachedNetworkImageProvider(resolved);
    final stream = provider.resolve(ImageConfiguration.empty);
    _imageStream = stream;
    _imageListener = ImageStreamListener((info, _) {
      if (!mounted) return;
      setState(() {
        _imageSize = Size(
          info.image.width.toDouble(),
          info.image.height.toDouble(),
        );
      });
    });
    stream.addListener(_imageListener!);
  }

  Rect _imageDisplayRect(Size containerSize) {
    final imageSize = _imageSize;
    if (imageSize == null || imageSize.width <= 0 || imageSize.height <= 0) {
      return Rect.zero;
    }

    final imageAspect = imageSize.width / imageSize.height;
    final containerAspect = containerSize.width / containerSize.height;

    late final double displayWidth;
    late final double displayHeight;
    if (imageAspect > containerAspect) {
      displayWidth = containerSize.width;
      displayHeight = containerSize.width / imageAspect;
    } else {
      displayHeight = containerSize.height;
      displayWidth = containerSize.height * imageAspect;
    }

    return Rect.fromLTWH(
      (containerSize.width - displayWidth) / 2,
      (containerSize.height - displayHeight) / 2,
      displayWidth,
      displayHeight,
    );
  }

  Widget _buildImagePage(int index) {
    final imageUrl = widget.imageUrls[index];
    return LayoutBuilder(
      builder: (context, constraints) {
        final containerSize = Size(constraints.maxWidth, constraints.maxHeight);
        final displayRect = _imageDisplayRect(containerSize);
        final hasDisplayRect = displayRect.width > 0 && displayRect.height > 0;

        return Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: const SizedBox.expand(),
            ),
            if (hasDisplayRect)
              Positioned.fromRect(
                rect: displayRect,
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 4,
                  child: ResolvedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const Center(
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    errorWidget: (_, __, ___) => const Center(
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 48,
                      ),
                    ),
                  ),
                ),
              )
            else
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.imageUrls.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
                _resolveImageSize(index);
              },
              itemBuilder: (context, index) => _buildImagePage(index),
            ),
          ),
          Positioned(
            top: topPadding + 8,
            right: 12,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
            ),
          ),
          if (widget.imageUrls.length > 1)
            Positioned(
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Text(
                  '${_currentIndex + 1} / ${widget.imageUrls.length}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
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

/// Opens a popup menu anchored to the bottom-right of [anchorKey], so it
/// drops directly below trailing ⋯ buttons.
Future<String?> _showTrailingPopupMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<PopupMenuEntry<String>> items,
  double gapBelow = 4,
}) {
  final anchorContext = anchorKey.currentContext;
  if (anchorContext == null) {
    return Future<String?>.value(null);
  }

  final renderObject = anchorContext.findRenderObject();
  if (renderObject is! RenderBox || !renderObject.hasSize) {
    return Future<String?>.value(null);
  }

  final anchor = renderObject;
  final overlayBox = Overlay.of(context).context.findRenderObject() as RenderBox;
  final bottomRight = anchor.localToGlobal(
    anchor.size.bottomRight(Offset.zero),
    ancestor: overlayBox,
  );
  final menuTop = bottomRight.dy + gapBelow;

  return showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(
      bottomRight.dx,
      menuTop,
      overlayBox.size.width - bottomRight.dx,
      overlayBox.size.height - menuTop,
    ),
    items: items,
    popUpAnimationStyle: const AnimationStyle(
      curve: Curves.easeOutCubic,
      duration: Duration(milliseconds: 200),
    ),
  );
}

class _AnchoredTrailingMenu extends StatefulWidget {
  const _AnchoredTrailingMenu({
    required this.child,
    required this.itemBuilder,
    required this.onSelected,
    this.gapBelow = 4,
  });

  final Widget child;
  final List<PopupMenuEntry<String>> Function(BuildContext context) itemBuilder;
  final ValueChanged<String> onSelected;
  final double gapBelow;

  @override
  State<_AnchoredTrailingMenu> createState() => _AnchoredTrailingMenuState();
}

class _AnchoredTrailingMenuState extends State<_AnchoredTrailingMenu> {
  final GlobalKey _anchorKey = GlobalKey();

  Future<void> _openMenu() async {
    final items = widget.itemBuilder(context);
    if (items.isEmpty) return;

    final selected = await _showTrailingPopupMenu(
      context: context,
      anchorKey: _anchorKey,
      items: items,
      gapBelow: widget.gapBelow,
    );
    if (selected != null) {
      widget.onSelected(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _openMenu,
      behavior: HitTestBehavior.opaque,
      child: KeyedSubtree(
        key: _anchorKey,
        child: widget.child,
      ),
    );
  }
}

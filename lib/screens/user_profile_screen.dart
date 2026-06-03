import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../models/collection_entity.dart';
import '../models/user_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_grid_card.dart';
import 'collection_detail_screen.dart';
import '../widgets/profile_header_layout.dart';
import 'edit_profile_screen.dart';
import 'followers_following_screen.dart';
import 'settings_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;
  final String currentUserId;

  const UserProfileScreen({
    super.key,
    required this.userId,
    required this.currentUserId,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  static const double _bottomNavClearance = 24;

  final FirestoreService _firestoreService = FirestoreService();

  StreamSubscription<UserEntity?>? _userSubscription;
  StreamSubscription<List<CollectionEntity>>? _collectionsSubscription;

  UserEntity? _user;
  List<CollectionEntity> _allCollections = [];
  List<CollectionEntity> _collections = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowLoading = false;

  bool _canViewCollectionOnProfile(CollectionEntity collection) {
    if (collection.isPublic || collection.visibility == CollectionVisibility.public) {
      return true;
    }

    if (collection.visibility == CollectionVisibility.followers && _isFollowing) {
      return true;
    }

    final uid = widget.currentUserId;
    if (collection.editors.contains(uid) || collection.viewers.contains(uid)) {
      return true;
    }

    for (final collab in collection.collaborators) {
      final id = collab['userId'];
      if (id is String && id == uid) {
        return true;
      }
    }

    return false;
  }

  void _applyVisibleCollections() {
    final isOwnProfile = widget.userId == widget.currentUserId;
    _collections = isOwnProfile
        ? _allCollections
        : _allCollections.where(_canViewCollectionOnProfile).toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _setupRealtimeStreams();
  }

  void _setupRealtimeStreams() {
    setState(() => _isLoading = true);

    _userSubscription = _firestoreService.getUserStream(widget.userId).listen(
      (user) async {
        if (user != null && mounted) {
          final isFollowing = widget.userId == widget.currentUserId
              ? false
              : await _firestoreService.isFollowing(
                  widget.currentUserId,
                  widget.userId,
                );
          if (!mounted) return;
          setState(() {
            _user = user;
            _isFollowing = isFollowing;
            _isLoading = false;
            _applyVisibleCollections();
          });
        }
      },
      onError: (error) {
        debugPrint('Error in user stream: $error');
        if (mounted) setState(() => _isLoading = false);
      },
    );

    _collectionsSubscription = _firestoreService.getUserCollectionsStream(widget.userId).listen(
      (collections) {
        if (mounted) {
          setState(() {
            _allCollections = collections;
            _applyVisibleCollections();
          });
        }
      },
      onError: (error) {
        debugPrint('Error in collections stream: $error');
      },
    );
  }

  @override
  void dispose() {
    _userSubscription?.cancel();
    _collectionsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _toggleFollow() async {
    if (_user == null) return;

    final wasFollowing = _isFollowing;

    setState(() {
      _isFollowLoading = true;
      _isFollowing = !wasFollowing;

      if (_user != null) {
        if (wasFollowing) {
          _user = _user!.copyWith(
            followers: _user!.followers.where((id) => id != widget.currentUserId).toList(),
            followerCount: _user!.followerCount - 1,
          );
        } else {
          _user = _user!.copyWith(
            followers: [..._user!.followers, widget.currentUserId],
            followerCount: _user!.followerCount + 1,
          );
        }
      }

      _applyVisibleCollections();
    });

    try {
      if (wasFollowing) {
        await _firestoreService.unfollowUser(widget.currentUserId, widget.userId);
      } else {
        final currentUser = await _firestoreService.getUser(widget.currentUserId);
        final currentUsername = currentUser?.userName ?? 'Someone';
        await _firestoreService.followUser(widget.currentUserId, widget.userId, currentUsername);
      }
    } catch (e) {
      if (mounted && _user != null) {
        setState(() {
          _isFollowing = wasFollowing;
          if (wasFollowing) {
            _user = _user!.copyWith(
              followers: [..._user!.followers, widget.currentUserId],
              followerCount: _user!.followerCount + 1,
            );
          } else {
            _user = _user!.copyWith(
              followers: _user!.followers.where((id) => id != widget.currentUserId).toList(),
              followerCount: _user!.followerCount - 1,
            );
          }
          _applyVisibleCollections();
        });
      }
      debugPrint('Error toggling follow: $e');
    } finally {
      if (mounted) {
        setState(() => _isFollowLoading = false);
      }
    }
  }

  void _navigateToFollowers({required bool showFollowers}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowersFollowingScreen(
          userId: widget.userId,
          currentUserId: widget.currentUserId,
          showFollowers: showFollowers,
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000000) {
      final value = count / 1000000;
      return '${value >= 10 ? value.toStringAsFixed(0) : value.toStringAsFixed(1)}M';
    }
    if (count >= 10000) {
      return '${(count / 1000).round()}k';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}k';
    }
    return '$count';
  }

  Future<void> _navigateToEditProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditProfileScreen()),
    );
    if (result == true && mounted) {
      _setupRealtimeStreams();
    }
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  Widget _buildProfileTopBar({required bool isOwnProfile}) {
    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(20),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Center(
                  child: Icon(
                    Icons.arrow_back,
                    size: 22,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const Spacer(),
          _buildTopBarActions(isOwnProfile: isOwnProfile),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildTopBarActions({required bool isOwnProfile}) {
    if (isOwnProfile) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const Icon(
              Icons.edit_outlined,
              size: 22,
              color: AppColors.collectionDescription,
            ),
            tooltip: 'Edit profile',
            onPressed: _navigateToEditProfile,
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            icon: const Icon(
              Icons.settings_outlined,
              size: 22,
              color: AppColors.collectionDescription,
            ),
            tooltip: 'Settings',
            onPressed: _navigateToSettings,
          ),
        ],
      );
    }

    return ProfileHeaderLayout.buildProfileFollowButton(
      label: _isFollowing ? 'FOLLOWING' : 'FOLLOW',
      onPressed: _toggleFollow,
      isLoading: _isFollowLoading,
      filled: !_isFollowing,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundSurface,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: AppColors.backgroundSurface,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text('User not found', style: GoogleFonts.plusJakartaSans()),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final user = _user!;
    final isOwnProfile = widget.userId == widget.currentUserId;

    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      body: CustomScrollView(
        slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(36),
                    bottomRight: Radius.circular(36),
                  ),
                  boxShadow: AppColors.profileHeaderShadow,
                ),
                child: SafeArea(
                  bottom: false,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: _buildProfileTopBar(isOwnProfile: isOwnProfile),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
                          child: ProfileHeaderLayout(
                            user: user,
                            emphasizeStats: true,
                            statsRow: ProfileHeaderLayout.buildStatsRow(
                              collectionsCount: _formatCount(_collections.length),
                              followersCount: _formatCount(user.followers.length),
                              followingCount: _formatCount(user.following.length),
                              onFollowersTap: () => _navigateToFollowers(showFollowers: true),
                              onFollowingTap: () => _navigateToFollowers(showFollowers: false),
                              countFontSize: 24,
                              labelFontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ..._buildCollectionsSlivers(),
            const SliverToBoxAdapter(child: SizedBox(height: _bottomNavClearance)),
          ],
        ),
    );
  }

  List<Widget> _buildCollectionsSlivers() {
    if (_collections.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.collections_outlined, size: 64, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text(
                  'No collections yet',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final collection = _collections[index];
              return CollectionGridCard(
                collection: collection,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => CollectionDetailScreen(
                        collectionId: collection.id,
                        currentUserId: widget.currentUserId,
                      ),
                    ),
                  );
                },
              );
            },
            childCount: _collections.length,
          ),
        ),
      ),
    ];
  }
}

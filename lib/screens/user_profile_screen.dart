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
import 'followers_following_screen.dart';

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
  List<CollectionEntity> _collections = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowLoading = false;

  @override
  void initState() {
    super.initState();
    _setupRealtimeStreams();
  }

  void _setupRealtimeStreams() {
    setState(() => _isLoading = true);

    _userSubscription = _firestoreService.getUserStream(widget.userId).listen(
      (user) {
        if (user != null && mounted) {
          setState(() {
            _user = user;
            _isFollowing = user.followers.contains(widget.currentUserId);
            _isLoading = false;
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
          final isOwnProfile = widget.userId == widget.currentUserId;
          final visibleCollections = isOwnProfile
              ? collections
              : collections.where((c) => c.isPublic).toList(growable: false);
          setState(() {
            _collections = visibleCollections;
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

  Widget? _buildFollowButton(bool isOwnProfile) {
    if (isOwnProfile) return null;

    return ProfileHeaderLayout.buildOutlinedActionButton(
      label: _isFollowing ? 'Following' : 'Follow',
      onPressed: _toggleFollow,
      isLoading: _isFollowLoading,
      filled: !_isFollowing,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        body: Center(child: Text('User not found', style: GoogleFonts.plusJakartaSans())),
      );
    }

    final user = _user!;
    final isOwnProfile = widget.userId == widget.currentUserId;
    final followButton = _buildFollowButton(isOwnProfile);

    return Scaffold(
      backgroundColor: Colors.white,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: ProfileHeaderLayout(
                  user: user,
                  actionButton: followButton,
                  statsRow: ProfileHeaderLayout.buildStatsRow(
                    collectionsCount: _formatCount(_collections.length),
                    followersCount: _formatCount(user.followers.length),
                    followingCount: _formatCount(user.following.length),
                    onFollowersTap: () => _navigateToFollowers(showFollowers: true),
                    onFollowingTap: () => _navigateToFollowers(showFollowers: false),
                  ),
                ),
              ),
            ),
          ];
        },
        body: ColoredBox(
          color: AppColors.backgroundSurface,
          child: _buildCollectionsList(),
        ),
      ),
    );
  }

  Widget _buildCollectionsList() {
    if (_collections.isEmpty) {
      return Center(
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
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, _bottomNavClearance),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.72,
      ),
      itemCount: _collections.length,
      itemBuilder: (context, index) {
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
    );
  }
}

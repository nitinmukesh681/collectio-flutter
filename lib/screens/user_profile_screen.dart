import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:async';
import '../models/collection_entity.dart';
import '../models/user_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_list_card.dart';
import '../widgets/avatar_fallback.dart';
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
        appBar: AppBar(),
        body: Center(child: Text('User not found', style: GoogleFonts.plusJakartaSans())),
      );
    }

    final user = _user!;
    final isOwnProfile = widget.userId == widget.currentUserId;

    return Scaffold(
      backgroundColor: Colors.white,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 248,
              pinned: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 40),
                        _buildProfileHeader(user, isOwnProfile: isOwnProfile),
                        const SizedBox(height: 20),
                        _buildStatsRow(user),
                      ],
                    ),
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

  Widget _buildProfileHeader(UserEntity user, {required bool isOwnProfile}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipOval(
          child: SizedBox(
            width: 80,
            height: 80,
            child: _buildAvatar(user),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName.isNotEmpty ? user.displayName : user.userName,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.1,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '@${user.userName}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              if (!isOwnProfile) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _isFollowLoading ? null : _toggleFollow,
                    style: TextButton.styleFrom(
                      backgroundColor: _isFollowing ? Colors.white : const Color(0xFFEEF2FF),
                      foregroundColor: AppColors.primary,
                      side: _isFollowing
                          ? BorderSide(color: AppColors.primary.withOpacity(0.25))
                          : null,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                      ),
                      elevation: 0,
                    ),
                    child: _isFollowLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _isFollowing ? 'Following' : 'Follow',
                            style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(UserEntity user) {
    Widget fallback() => AvatarFallback(name: user.userName, size: 80);

    if (user.avatarUrl == null || user.avatarUrl!.isEmpty) {
      return fallback();
    }

    if (user.avatarUrl!.trim().startsWith('gs://')) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.refFromURL(user.avatarUrl!.trim()).getDownloadURL(),
        builder: (context, snap) {
          final url = snap.data;
          if (url == null || url.isEmpty) return fallback();
          return CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => fallback(),
          );
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: user.avatarUrl!.trim(),
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => fallback(),
    );
  }

  Widget _buildStatsRow(UserEntity user) {
    return Row(
      children: [
        Expanded(
          child: _buildStat(_formatCount(_collections.length), 'COLLECTIONS'),
        ),
        Container(width: 1, height: 36, color: AppColors.divider),
        Expanded(
          child: _buildStat(
            _formatCount(user.followers.length),
            'FOLLOWERS',
            onTap: () => _navigateToFollowers(showFollowers: true),
          ),
        ),
        Container(width: 1, height: 36, color: AppColors.divider),
        Expanded(
          child: _buildStat(
            _formatCount(user.following.length),
            'FOLLOWING',
            onTap: () => _navigateToFollowers(showFollowers: false),
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String count, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Text(
            count,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
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

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
      itemCount: _collections.length,
      itemBuilder: (context, index) {
        return CollectionListCard(
          collection: _collections[index],
          currentUserId: widget.currentUserId,
          profileStyle: true,
        );
      },
    );
  }
}

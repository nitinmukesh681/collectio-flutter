import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:async';
import '../models/collection_entity.dart';
import '../models/user_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_grid_card.dart';
import 'collection_detail_screen.dart';

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
    
    // Setup user stream for real-time updates
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
      }
    );

    // Setup collections stream for real-time updates
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
      }
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
    
    // Optimistic update - update UI immediately
    setState(() {
      _isFollowLoading = true;
      _isFollowing = !wasFollowing;
      
      // Update user entity optimistically
      if (_user != null) {
        if (wasFollowing) {
          // Unfollow - remove from followers list
          _user = _user!.copyWith(
            followers: _user!.followers.where((id) => id != widget.currentUserId).toList(),
            followerCount: _user!.followerCount - 1,
          );
        } else {
          // Follow - add to followers list
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
        // We need current username for the notification
        final currentUser = await _firestoreService.getUser(widget.currentUserId);
        final currentUsername = currentUser?.userName ?? 'Someone';
        
        await _firestoreService.followUser(widget.currentUserId, widget.userId, currentUsername);
      }
      // Success - real-time stream will keep data in sync
    } catch (e) {
      // Revert on error
      if (mounted && _user != null) {
        setState(() {
          _isFollowing = wasFollowing;
          if (wasFollowing) {
            // Revert unfollow - add back to followers
            _user = _user!.copyWith(
              followers: [..._user!.followers, widget.currentUserId],
              followerCount: _user!.followerCount + 1,
            );
          } else {
            // Revert follow - remove from followers
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('User not found')),
      );
    }

    final user = _user!;
    final isOwnProfile = widget.userId == widget.currentUserId;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 352,
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
            title: LayoutBuilder(
              builder: (context, constraints) {
                final collapsed = constraints.biggest.height <= (kToolbarHeight + 10);
                return AnimatedOpacity(
                  opacity: collapsed ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Text(
                    '@${user.userName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                );
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                  child: Column(
                    children: [
                      const SizedBox(height: 44),
                      SizedBox(
                        width: 78,
                        height: 78,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                          ),
                          child: ClipOval(
                            child: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                                ? (user.avatarUrl!.trim().startsWith('gs://')
                                    ? FutureBuilder<String>(
                                        future: FirebaseStorage.instance
                                            .refFromURL(user.avatarUrl!.trim())
                                            .getDownloadURL(),
                                        builder: (context, snap) {
                                          final url = snap.data;
                                          if (url == null || url.isEmpty) {
                                            return Container(
                                              color: AppColors.primaryPurple.withOpacity(0.10),
                                              alignment: Alignment.center,
                                              child: Text(
                                                user.userName.isNotEmpty ? user.userName[0].toUpperCase() : '?',
                                                style: const TextStyle(
                                                  fontSize: 34,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primaryPurpleDark,
                                                ),
                                              ),
                                            );
                                          }
                                          return CachedNetworkImage(
                                            imageUrl: url,
                                            fit: BoxFit.cover,
                                            errorWidget: (context, _, __) {
                                              return Container(
                                                color: AppColors.primaryPurple.withOpacity(0.10),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  user.userName.isNotEmpty ? user.userName[0].toUpperCase() : '?',
                                                  style: const TextStyle(
                                                    fontSize: 34,
                                                    fontWeight: FontWeight.w800,
                                                    color: AppColors.primaryPurpleDark,
                                                  ),
                                                ),
                                              );
                                            },
                                          );
                                        },
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: user.avatarUrl!.trim(),
                                        fit: BoxFit.cover,
                                        errorWidget: (context, url, error) {
                                          return Container(
                                            color: AppColors.primaryPurple.withOpacity(0.10),
                                            alignment: Alignment.center,
                                            child: Text(
                                              user.userName.isNotEmpty ? user.userName[0].toUpperCase() : '?',
                                              style: const TextStyle(
                                                fontSize: 34,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.primaryPurpleDark,
                                              ),
                                            ),
                                          );
                                        },
                                      ))
                                : Container(
                                    color: AppColors.primaryPurple.withOpacity(0.10),
                                    alignment: Alignment.center,
                                    child: Text(
                                      user.userName.isNotEmpty ? user.userName[0].toUpperCase() : '?',
                                      style: const TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w800,
                                        color: AppColors.primaryPurpleDark,
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user.userName,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                          height: 1.1,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '@${user.userName}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      if (!isOwnProfile) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isFollowLoading ? null : _toggleFollow,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: AppColors.primaryPurple,
                              side: BorderSide(color: AppColors.primaryPurple.withOpacity(0.25)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
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
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Expanded(child: _buildStat(_collections.length, 'Collections', dark: true)),
                            Container(width: 1, height: 32, color: const Color(0xFFE5E7EB)),
                            Expanded(child: _buildStat(user.followers.length, 'Followers', dark: true)),
                            Container(width: 1, height: 32, color: const Color(0xFFE5E7EB)),
                            Expanded(child: _buildStat(user.following.length, 'Following', dark: true)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Collections list
          if (_collections.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.collections_outlined, size: 64, color: AppColors.textMuted),
                    const SizedBox(height: 16),
                    const Text(
                      'No collections yet',
                      style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.86,
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
                      onUserTap: () {
                        // No-op: tapping username line isn't shown on grid cards.
                      },
                    );
                  },
                  childCount: _collections.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStat(int count, String label, {bool dark = false}) {
    return GestureDetector(
      onTap: () {
        // Navigate to followers/following screen
      },
      child: Column(
        children: [
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

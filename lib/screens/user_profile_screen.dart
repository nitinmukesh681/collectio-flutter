import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/collection_entity.dart';
import '../models/user_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_card.dart';
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
  
  UserEntity? _user;
  List<CollectionEntity> _collections = [];
  bool _isLoading = true;
  bool _isFollowing = false;
  bool _isFollowLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      final user = await _firestoreService.getUser(widget.userId);
      final collections = await _firestoreService.getUserCollections(widget.userId);
      
      if (user != null) {
        setState(() {
          _user = user;
          _collections = collections;
          _isFollowing = user.followers.contains(widget.currentUserId);
        });
      }
    } catch (e) {
      debugPrint('Error loading user: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _toggleFollow() async {
    if (_user == null) return;
    
    setState(() => _isFollowLoading = true);
    try {
      if (_isFollowing) {
        await _firestoreService.unfollowUser(widget.currentUserId, widget.userId);
        setState(() {
          _isFollowing = false;
          _user = _user!.copyWith(
            followersCount: _user!.followersCount - 1,
          );
        });
      } else {
        // We need current username for the notification
        // Ideally this should be passed to the screen or stored in a UserProvider
        // For now, fetching it or using a placeholder if we want to be fast, but fetching is safer
        final currentUser = await _firestoreService.getUser(widget.currentUserId);
        final currentUsername = currentUser?.userName ?? 'Someone';
        
        await _firestoreService.followUser(widget.currentUserId, widget.userId, currentUsername);
        setState(() {
          _isFollowing = true;
          _user = _user!.copyWith(
            followersCount: _user!.followersCount + 1,
          );
        });
      }
    } catch (e) {
      debugPrint('Error toggling follow: $e');
    }
    setState(() => _isFollowLoading = false);
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
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primaryPurple,
                      AppColors.primaryPurple.withOpacity(0.8),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Avatar
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: Colors.white,
                          backgroundImage: user.avatarUrl != null
                              ? CachedNetworkImageProvider(user.avatarUrl!)
                              : null,
                          child: user.avatarUrl == null
                              ? Text(
                                  user.userName[0].toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryPurple,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(height: 16),
                        // Username
                        Text(
                          '@${user.userName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (user.bio != null && user.bio!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            user.bio!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        ],
                        const SizedBox(height: 16),
                        // Follow button
                        if (!isOwnProfile)
                          SizedBox(
                            width: 140,
                            child: ElevatedButton(
                              onPressed: _isFollowLoading ? null : _toggleFollow,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isFollowing ? Colors.white : AppColors.primaryPurple,
                                foregroundColor: _isFollowing ? AppColors.primaryPurple : Colors.white,
                                side: BorderSide(
                                  color: _isFollowing ? AppColors.primaryPurple : Colors.transparent,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: _isFollowLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : Text(_isFollowing ? 'Following' : 'Follow'),
                            ),
                          ),
                        const SizedBox(height: 16),
                        // Stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildStat(user.collectionsCount, 'Collections'),
                            Container(
                              width: 1,
                              height: 30,
                              color: Colors.white24,
                              margin: const EdgeInsets.symmetric(horizontal: 20),
                            ),
                            _buildStat(user.followersCount, 'Followers'),
                            Container(
                              width: 1,
                              height: 30,
                              color: Colors.white24,
                              margin: const EdgeInsets.symmetric(horizontal: 20),
                            ),
                            _buildStat(user.followingCount, 'Following'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Collections header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Collections (${_collections.length})',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
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
                    Icon(Icons.collections_outlined, size: 64, color: Colors.grey),
                    SizedBox(height: 16),
                    Text('No collections yet', style: TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final collection = _collections[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: CollectionCard(
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
                      ),
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

  Widget _buildStat(int count, String label) {
    return GestureDetector(
      onTap: () {
        // Navigate to followers/following screen
      },
      child: Column(
        children: [
          Text(
            '$count',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

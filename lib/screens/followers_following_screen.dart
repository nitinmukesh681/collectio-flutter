import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'user_profile_screen.dart';

class FollowersFollowingScreen extends StatefulWidget {
  final String userId;
  final String currentUserId;
  final bool showFollowers; // true = followers, false = following

  const FollowersFollowingScreen({
    super.key,
    required this.userId,
    required this.currentUserId,
    this.showFollowers = true,
  });

  @override
  State<FollowersFollowingScreen> createState() => _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();

  List<UserEntity> _followers = [];
  List<UserEntity> _following = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.showFollowers ? 0 : 1,
    );
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _firestoreService.getUser(widget.userId);
      if (user != null) {
        // Load followers
        final followers = <UserEntity>[];
        for (final followerId in user.followers) {
          final follower = await _firestoreService.getUser(followerId);
          if (follower != null) {
            followers.add(follower);
          }
        }

        // Load following
        final following = <UserEntity>[];
        for (final followingId in user.following) {
          final followingUser = await _firestoreService.getUser(followingId);
          if (followingUser != null) {
            following.add(followingUser);
          }
        }

        setState(() {
          _followers = followers;
          _following = following;
        });
      }
    } catch (e) {
      debugPrint('Error loading followers/following: $e');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connections'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primaryPurple,
          unselectedLabelColor: Colors.grey,
          indicatorColor: AppColors.primaryPurple,
          tabs: [
            Tab(text: 'Followers (${_followers.length})'),
            Tab(text: 'Following (${_following.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUserList(_followers, 'No followers yet'),
                _buildUserList(_following, 'Not following anyone yet'),
              ],
            ),
    );
  }

  Widget _buildUserList(List<UserEntity> users, String emptyMessage) {
    if (users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(emptyMessage, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return _buildUserTile(user);
      },
    );
  }

  Widget _buildUserTile(UserEntity user) {
    final isCurrentUser = user.id == widget.currentUserId;
    final isFollowing = _following.any((u) => u.id == user.id);

    return ListTile(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(
              userId: user.id,
              currentUserId: widget.currentUserId,
            ),
          ),
        );
      },
      leading: CircleAvatar(
        backgroundColor: AppColors.primaryPurple.withOpacity(0.2),
        backgroundImage: user.avatarUrl != null
            ? CachedNetworkImageProvider(user.avatarUrl!)
            : null,
        child: user.avatarUrl == null
            ? Text(
                user.userName[0].toUpperCase(),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryPurple,
                ),
              )
            : null,
      ),
      title: Text(
        '@${user.userName}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: user.bio != null && user.bio!.isNotEmpty
          ? Text(
              user.bio!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : Text('${user.collectionsCount} collections'),
      trailing: isCurrentUser
          ? null
          : ElevatedButton(
              onPressed: () => _toggleFollow(user, isFollowing),
              style: ElevatedButton.styleFrom(
                backgroundColor: isFollowing ? Colors.grey[200] : AppColors.primaryPurple,
                foregroundColor: isFollowing ? Colors.black : Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(isFollowing ? 'Following' : 'Follow'),
            ),
    );
  }

  Future<void> _toggleFollow(UserEntity user, bool isFollowing) async {
    try {
      if (isFollowing) {
        await _firestoreService.unfollowUser(widget.currentUserId, user.id);
        setState(() {
          _following.removeWhere((u) => u.id == user.id);
        });
      } else {
        // Fetch current user for the notification username
        final currentUser = await _firestoreService.getUser(widget.currentUserId);
        final currentUsername = currentUser?.userName ?? 'Someone';
        
        await _firestoreService.followUser(widget.currentUserId, user.id, currentUsername);
        setState(() {
          _following.add(user);
        });
      }
    } catch (e) {
      debugPrint('Error toggling follow: $e');
    }
  }
}

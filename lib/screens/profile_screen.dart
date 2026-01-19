import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/collection_entity.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_card.dart';
import 'collection_detail_screen.dart';
import 'create_collection_screen.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';
import 'followers_following_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();
  
  List<CollectionEntity> _myCollections = [];
  List<CollectionEntity> _savedCollections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    if (auth.userEntity == null) return;

    setState(() => _isLoading = true);
    try {
      final myCollections = await _firestoreService.getUserCollections(auth.userId);
      final savedCollections = await _firestoreService.getSavedCollections(auth.userId);
      setState(() {
        _myCollections = myCollections;
        _savedCollections = savedCollections;
      });
    } catch (e) {
      debugPrint('Error loading profile data: $e');
    }
    setState(() => _isLoading = false);
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  void _navigateToEditProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditProfileScreen()),
    );
    if (result == true) {
      // Refresh data if profile was updated
      _loadData();
    }
  }

  void _navigateToFollowers(String userId, {bool showFollowers = true}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowersFollowingScreen(
          userId: userId,
          currentUserId: userId,
          showFollowers: showFollowers,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        final user = auth.userEntity;

        if (user == null) {
          return const Center(child: CircularProgressIndicator());
        }

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  expandedHeight: 280,
                  pinned: true,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.settings_outlined),
                      onPressed: _navigateToSettings,
                    ),
                    PopupMenuButton(
                      itemBuilder: (context) => [
                        const PopupMenuItem(value: 'edit', child: Text('Edit Profile')),
                        const PopupMenuItem(value: 'signout', child: Text('Sign Out')),
                      ],
                      onSelected: (value) {
                        if (value == 'edit') {
                          _navigateToEditProfile();
                        } else if (value == 'signout') {
                          auth.signOut();
                        }
                      },
                    ),
                  ],
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
                              GestureDetector(
                                onTap: _navigateToEditProfile,
                                child: Stack(
                                  children: [
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
                                    Positioned(
                                      bottom: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: AppColors.primaryPurple, width: 2),
                                        ),
                                        child: const Icon(Icons.edit, size: 16, color: AppColors.primaryPurple),
                                      ),
                                    ),
                                  ],
                                ),
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
                              // Stats
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _buildStat(user.collectionsCount, 'Collections', onTap: null),
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: Colors.white24,
                                    margin: const EdgeInsets.symmetric(horizontal: 20),
                                  ),
                                  _buildStat(
                                    user.followersCount,
                                    'Followers',
                                    onTap: () => _navigateToFollowers(auth.userId, showFollowers: true),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 30,
                                    color: Colors.white24,
                                    margin: const EdgeInsets.symmetric(horizontal: 20),
                                  ),
                                  _buildStat(
                                    user.followingCount,
                                    'Following',
                                    onTap: () => _navigateToFollowers(auth.userId, showFollowers: false),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabBarDelegate(
                    TabBar(
                      controller: _tabController,
                      labelColor: AppColors.primaryPurple,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: AppColors.primaryPurple,
                      tabs: const [
                        Tab(text: 'My Collections'),
                        Tab(text: 'Saved'),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: TabBarView(
              controller: _tabController,
              children: [
                // My Collections
                _buildCollectionsList(_myCollections, auth.userId, isEmpty: 'You haven\'t created any collections yet'),
                // Saved Collections
                _buildCollectionsList(_savedCollections, auth.userId, isEmpty: 'No saved collections'),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => CreateCollectionScreen(
                    userId: auth.userId,
                    userName: user.userName,
                    userAvatarUrl: user.avatarUrl,
                  ),
                ),
              );
              if (result == true) {
                _loadData();
              }
            },
            backgroundColor: AppColors.primaryPurple,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        );
      },
    );
  }

  Widget _buildStat(int count, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
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

  Widget _buildCollectionsList(List<CollectionEntity> collections, String userId, {required String isEmpty}) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (collections.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.collections_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(isEmpty, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: collections.length,
      itemBuilder: (context, index) {
        final collection = collections[index];
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
                    currentUserId: userId,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}

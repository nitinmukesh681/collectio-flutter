import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/collection_entity.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_card.dart';
import '../widgets/collection_grid_card.dart';
import 'collection_detail_screen.dart';
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
  List<CollectionEntity> _collaborationCollections = [];
  bool _isLoading = true;

  String _collectionsFilter = 'my';

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
      final collaborationCollections = await _firestoreService.getUserCollaborations(auth.userId);
      setState(() {
        _myCollections = myCollections;
        _savedCollections = savedCollections;
        _collaborationCollections = collaborationCollections;
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
          backgroundColor: const Color(0xFFF6F7FB),
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  expandedHeight: 352,
                  pinned: true,
                  backgroundColor: const Color(0xFFF6F7FB),
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  title: AnimatedOpacity(
                    opacity: innerBoxIsScrolled ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Text(
                      'Profile',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, color: Colors.black),
                      onPressed: _navigateToSettings,
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                        child: Column(
                          children: [
                            const SizedBox(height: 44),
                            GestureDetector(
                              onTap: _navigateToEditProfile,
                              child: SizedBox(
                                width: 78,
                                height: 78,
                                child: ClipOval(
                                  child: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                                      ? CachedNetworkImage(
                                          imageUrl: user.avatarUrl!,
                                          fit: BoxFit.cover,
                                          errorWidget: (context, url, error) {
                                            return Container(
                                              color: Colors.white,
                                              alignment: Alignment.center,
                                              child: Text(
                                                user.userName.isNotEmpty
                                                    ? user.userName[0].toUpperCase()
                                                    : '?',
                                                style: const TextStyle(
                                                  fontSize: 34,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primaryPurple,
                                                ),
                                              ),
                                            );
                                          },
                                        )
                                      : Container(
                                          color: Colors.white,
                                          alignment: Alignment.center,
                                          child: Text(
                                            user.userName.isNotEmpty
                                                ? user.userName[0].toUpperCase()
                                                : '?',
                                            style: const TextStyle(
                                              fontSize: 34,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.primaryPurple,
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
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _navigateToEditProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryPurple,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  elevation: 0,
                                ),
                                child: const Text(
                                  'Edit Profile',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
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
                                  Expanded(
                                    child: _buildStat(
                                      _myCollections.length,
                                      'Collections',
                                      onTap: null,
                                      dark: true,
                                    ),
                                  ),
                                  Container(width: 1, height: 32, color: const Color(0xFFE5E7EB)),
                                  Expanded(
                                    child: _buildStat(
                                      user.followers.length,
                                      'Followers',
                                      onTap: () => _navigateToFollowers(auth.userId, showFollowers: true),
                                      dark: true,
                                    ),
                                  ),
                                  Container(width: 1, height: 32, color: const Color(0xFFE5E7EB)),
                                  Expanded(
                                    child: _buildStat(
                                      user.following.length,
                                      'Following',
                                      onTap: () => _navigateToFollowers(auth.userId, showFollowers: false),
                                      dark: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
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
                      indicatorWeight: 3,
                      tabs: const [
                        Tab(text: 'Collections'),
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
                _buildCollectionsTab(auth.userId),
                // Saved Collections
                _buildCollectionsList(_savedCollections, auth.userId, isEmpty: 'No saved collections'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollectionsTab(String userId) {
    final list = _collectionsFilter == 'collab' ? _collaborationCollections : _myCollections;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 176,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _collectionsFilter,
                    isExpanded: true,
                    isDense: true,
                    iconSize: 18,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    items: const [
                      DropdownMenuItem(value: 'my', child: Text('My collections')),
                      DropdownMenuItem(value: 'collab', child: Text('Collaborations')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _collectionsFilter = value);
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _buildCollectionsList(
            list,
            userId,
            isEmpty: _collectionsFilter == 'collab' ? 'No collaborations' : 'You haven\'t created any collections yet',
          ),
        ),
      ],
    );
  }

  Widget _buildStat(int count, String label, {VoidCallback? onTap, bool dark = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Text(
            '$count',
            style: TextStyle(
              color: dark ? AppColors.textPrimary : Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: dark ? AppColors.textSecondary : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
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

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: collections.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.86,
      ),
      itemBuilder: (context, index) {
        final collection = collections[index];
        return CollectionGridCard(
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
          onUserTap: () {
            // Self profile: username tap stays on same screen
          },
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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/collection_entity.dart';
import '../theme/app_theme.dart';
import '../widgets/feed_collection_card.dart';
import '../widgets/collaboration_card.dart';
import 'collection_detail_screen.dart';
import 'explore_screen.dart';
import 'create_collection_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'open_collaborations_screen.dart';

/// Home screen with feed of collections
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  int _selectedIndex = 0;
  
  // Data lists
  List<CollectionEntity> _collabCollections = [];
  List<CollectionEntity> _feedCollections = [];
  
  bool _isLoadingCollabs = true;
  bool _isLoadingFeed = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    _loadCollabs();
    _loadFeed();
  }

  Future<void> _loadCollabs() async {
    setState(() => _isLoadingCollabs = true);
    try {
      final collabs = await _firestoreService.getOpenCollaborationCollections();
      if (mounted) {
        setState(() {
          _collabCollections = collabs;
          _isLoadingCollabs = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading collabs: $e');
      if (mounted) setState(() => _isLoadingCollabs = false);
    }
  }

  Future<void> _loadFeed() async {
    setState(() => _isLoadingFeed = true);
    try {
      final auth = context.read<AuthProvider>();
      
      // 1. Fetch Following Feed
      final followingStored = await _firestoreService.getFollowingCollections(auth.userId);
      
      // 2. Fetch Public Feed (Explore/Recommended)
      final publicStored = await _firestoreService.getPublicCollectionsList(limit: 20);
      
      // 3. Merge & Deduplicate
      final Map<String, CollectionEntity> mergedMap = {};
      
      for (var c in followingStored) {
        mergedMap[c.id] = c;
      }
      for (var c in publicStored) {
        if (!mergedMap.containsKey(c.id)) {
          mergedMap[c.id] = c;
        }
      }
      
      final combinedList = mergedMap.values.toList();
      
      // 4. Sort by CreatedAt Descending
      combinedList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      if (mounted) {
        setState(() {
          _feedCollections = combinedList;
          _isLoadingFeed = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading feed: $e');
      if (mounted) setState(() => _isLoadingFeed = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get current user details from provider
    final auth = context.watch<AuthProvider>();
    final user = auth.userEntity;
    final userName = user?.userName.split(' ').first ?? 'Curator';

    return Scaffold(
      backgroundColor: Colors.white, // Ensure clean white background
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            // Tab 0: Home Feed
            RefreshIndicator(
              onRefresh: () async {
                _loadData();
              },
              child: CustomScrollView(
                slivers: [
                  // 1. Header with Greeting
                  SliverPadding(
                    padding: const EdgeInsets.all(20.0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 10),
                        Text(
                          'Welcome Back, $userName',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            height: 1.2,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const Text(
                          'Ready to curate?',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryPurple,
                            height: 1.2,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ]),
                    ),
                  ),

                  // 2. Open Collaborations Section
                  if (!_isLoadingCollabs && _collabCollections.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Open Collaborations',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const OpenCollaborationsScreen(),
                                  ),
                                );
                              },
                              child: const Row(
                                children: [
                                  Text(
                                    'See All',
                                    style: TextStyle(color: AppColors.primaryPurple),
                                  ),
                                  Icon(Icons.arrow_forward, size: 16, color: AppColors.primaryPurple),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 350, // Height for the cards
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          scrollDirection: Axis.horizontal,
                          itemCount: _collabCollections.length,
                          itemBuilder: (context, index) {
                            final collection = _collabCollections[index];
                            return CollaborationCard(
                              collection: collection,
                              onTap: () => _navigateToCollection(collection.id, auth.userId),
                            );
                          },
                        ),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],

                  // 3. Main Feed Section Title
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      child: Text(
                        'Your Feed',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),

                  // 4. Feed Items
                  if (_isLoadingFeed)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_feedCollections.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.feed_outlined, size: 64, color: Colors.grey[300]),
                            const SizedBox(height: 16),
                            Text('Your feed is empty', style: TextStyle(color: Colors.grey[500])),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final collection = _feedCollections[index];
                            return FeedCollectionCard(
                              collection: collection,
                              onTap: () => _navigateToCollection(collection.id, auth.userId),
                              onLike: () async {
                                // Optimistic update
                                // Note: Real logic should update state
                                await _firestoreService.likeCollection(collection.id, auth.userId);
                                _loadFeed(); // Refresh for now
                              },
                              onSave: () async {
                                // Optimistic update
                                if (collection.isSaved) {
                                  await _firestoreService.unsaveCollection(collection.id, auth.userId);
                                } else {
                                  await _firestoreService.saveCollection(collection.id, auth.userId);
                                }
                                _loadFeed(); // Refresh for now
                              },
                            );
                          },
                          childCount: _feedCollections.length,
                        ),
                      ),
                    ),
                  
                  // Bottom padding
                  const SliverToBoxAdapter(child: SizedBox(height: 80)),
                ],
              ),
            ),
            
            // Other Tabs
            ExploreScreen(currentUserId: auth.userId),
            _buildCreateTab(auth),
            NotificationsScreen(userId: auth.userId),
            const ProfileScreen(),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        elevation: 0,
        indicatorColor: AppColors.primaryPurple.withOpacity(0.1),
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index == 2) {
            _navigateToCreate(auth);
          } else {
            setState(() {
              _selectedIndex = index;
            });
          }
        },
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home, color: AppColors.primaryPurple),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore, color: AppColors.primaryPurple),
            label: 'Search',
          ),
          // Custom middle button visual
           NavigationDestination(
             icon: Container(
               width: 48,
               height: 48,
               decoration: const BoxDecoration(
                 color: AppColors.primaryPurple,
                 shape: BoxShape.circle,
                 boxShadow: [
                    BoxShadow(
                      color: Color(0x666B4EFF),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                 ]
               ),
               child: const Icon(Icons.add, color: Colors.white),
             ),
             label: 'Create',
           ),
          NavigationDestination(
            icon: StreamBuilder<int>(
              stream: _firestoreService.getUnreadNotificationCount(auth.userId),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 9 ? '9+' : '$count'),
                  child: const Icon(Icons.favorite_outline),
                );
              },
            ),
            selectedIcon: const Icon(Icons.favorite, color: AppColors.primaryPurple),
            label: 'Activity',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person, color: AppColors.primaryPurple),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  void _navigateToCreate(AuthProvider auth) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCollectionScreen(
          userId: auth.userId,
          userName: auth.userEntity?.userName ?? 'User',
          userAvatarUrl: auth.userEntity?.avatarUrl,
        ),
      ),
    );
  }

  void _navigateToCollection(String collectionId, String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CollectionDetailScreen(
          collectionId: collectionId,
          currentUserId: userId,
        ),
      ),
    );
  }

  void _navigateToSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  Widget _buildCreateTab(AuthProvider auth) {
    // This is just a placeholder if accessing via index, currently handled by nav bar override
     return Container(); 
  }
}

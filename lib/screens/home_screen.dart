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
import 'user_profile_screen.dart';

/// Home screen with feed of collections
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _profileKey = ProfileScreenKey();
  int _selectedIndex = 0;

  final Set<String> _savedCollectionIds = {};
  
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

  void _navigateToUserProfile(String userId, String currentUserId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: userId,
          currentUserId: currentUserId,
        ),
      ),
    );
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

    if (_savedCollectionIds.isEmpty && (user?.savedCollections.isNotEmpty ?? false)) {
      _savedCollectionIds.addAll(user!.savedCollections);
    }

    return Scaffold(
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
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryPurple,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: AppColors.primaryPurple,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'finds',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Welcome Back, $userName',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                            height: 1.2,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          'Ready to curate?',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
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
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Open Collaborations',
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
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
                              child: Row(
                                children: [
                                  Text(
                                    'See All',
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.primaryPurple),
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
                        height: 320, // Height for the cards
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            'Your Feed',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 6,
                            height: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Color(0xFFEF4444),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
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
                            const Icon(Icons.feed_outlined, size: 64, color: AppColors.textMuted),
                            const SizedBox(height: 16),
                            Text(
                              'Your feed is empty',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                            ),
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
                            final raw = _feedCollections[index];
                            final isLiked = raw.likedBy.contains(auth.userId);
                            final isSaved = _savedCollectionIds.contains(raw.id);
                            final collection = raw.copyWith(
                              isLiked: isLiked,
                              isSaved: isSaved,
                            );
                            return FeedCollectionCard(
                              collection: collection,
                              onTap: () => _navigateToCollection(collection.id, auth.userId),
                              onUserTap: () => _navigateToUserProfile(collection.userId, auth.userId),
                              onLike: () async {
                                final wasLiked = collection.isLiked;

                                // Optimistic UI
                                setState(() {
                                  final current = _feedCollections[index];
                                  final updatedLikedBy = List<String>.from(current.likedBy);
                                  if (wasLiked) {
                                    updatedLikedBy.remove(auth.userId);
                                  } else {
                                    updatedLikedBy.add(auth.userId);
                                  }
                                  _feedCollections[index] = current.copyWith(
                                    likes: (current.likes + (wasLiked ? -1 : 1)).clamp(0, 1 << 31),
                                    likedBy: updatedLikedBy,
                                  );
                                });

                                try {
                                  await _firestoreService.toggleCollectionLike(collection.id, auth.userId);
                                } catch (e) {
                                  // Revert UI
                                  if (mounted) {
                                    setState(() {
                                      final current = _feedCollections[index];
                                      final updatedLikedBy = List<String>.from(current.likedBy);
                                      if (wasLiked) {
                                        updatedLikedBy.add(auth.userId);
                                      } else {
                                        updatedLikedBy.remove(auth.userId);
                                      }
                                      _feedCollections[index] = current.copyWith(
                                        likes: (current.likes + (wasLiked ? 1 : -1)).clamp(0, 1 << 31),
                                        likedBy: updatedLikedBy,
                                      );
                                    });
                                  }

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Could not update like: $e')),
                                    );
                                  }
                                }
                              },
                              onSave: () async {
                                final wasSaved = collection.isSaved;

                                // Optimistic UI
                                setState(() {
                                  if (wasSaved) {
                                    _savedCollectionIds.remove(collection.id);
                                  } else {
                                    _savedCollectionIds.add(collection.id);
                                  }
                                });

                                try {
                                  await _firestoreService.toggleCollectionSave(collection.id, auth.userId);
                                  // Keep AuthProvider in sync so next load of home screen shows correct state
                                  if (mounted) await auth.refreshUser();
                                } catch (e) {
                                  // Revert UI
                                  if (mounted) {
                                    setState(() {
                                      if (wasSaved) {
                                        _savedCollectionIds.add(collection.id);
                                      } else {
                                        _savedCollectionIds.remove(collection.id);
                                      }
                                    });
                                  }

                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Could not save collection: $e')),
                                    );
                                  }
                                }
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
            ProfileScreen(key: _profileKey),
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
            // Refresh profile data when switching to profile tab
            if (index == 4) {
              _profileKey.reload();
            }
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
            label: 'Explore',
          ),
          const NavigationDestination(
            icon: Icon(Icons.add_circle_outline),
            selectedIcon: Icon(Icons.add_circle, color: AppColors.primaryPurple),
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

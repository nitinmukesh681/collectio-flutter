import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
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
  int _selectedIndex = 0;

  final Set<String> _savedCollectionIds = {};
  
  // Stream subscriptions
  StreamSubscription<List<CollectionEntity>>? _followingSubscription;
  StreamSubscription<List<CollectionEntity>>? _publicSubscription;
  StreamSubscription<List<CollectionEntity>>? _collabSubscription;
  
  // Data lists
  List<CollectionEntity> _collabCollections = [];
  List<CollectionEntity> _feedCollections = [];
  List<CollectionEntity> _followingCollections = [];
  List<CollectionEntity> _publicCollections = [];
  
  bool _isLoadingCollabs = true;
  bool _isLoadingFeed = true;

  @override
  void initState() {
    super.initState();
    _setupRealtimeStreams();
  }

  void _setupRealtimeStreams() {
    final auth = context.read<AuthProvider>();
    
    // Setup following collections stream
    _followingSubscription = _firestoreService.getFollowingCollectionsStream(auth.userId).listen(
      (collections) {
        if (mounted) {
          setState(() {
            _followingCollections = collections;
            _mergeFeedCollections();
          });
        }
      },
      onError: (error) {
        debugPrint('Error in following collections stream: $error');
      }
    );

    // Setup public collections stream
    _publicSubscription = _firestoreService.getPublicCollectionsStream(limit: 20).listen(
      (collections) {
        if (mounted) {
          setState(() {
            _publicCollections = collections;
            _mergeFeedCollections();
          });
        }
      },
      onError: (error) {
        debugPrint('Error in public collections stream: $error');
      }
    );

    // Setup collaborations stream
    _collabSubscription = _firestoreService.getOpenCollaborationCollectionsStream().listen(
      (collections) {
        if (mounted) {
          setState(() {
            _collabCollections = collections;
            _isLoadingCollabs = false;
          });
        }
      },
      onError: (error) {
        debugPrint('Error in collaborations stream: $error');
        if (mounted) setState(() => _isLoadingCollabs = false);
      }
    );
  }

  void _mergeFeedCollections() {
    // Merge & Deduplicate following and public collections
    final Map<String, CollectionEntity> mergedMap = {};
    
    for (var c in _followingCollections) {
      mergedMap[c.id] = c;
    }
    for (var c in _publicCollections) {
      if (!mergedMap.containsKey(c.id)) {
        mergedMap[c.id] = c;
      }
    }
    
    final combinedList = mergedMap.values.toList();
    
    // Sort by CreatedAt Descending
    combinedList.sort((a, b) => b.createdAt.compareTo(a.createdAt));

    setState(() {
      _feedCollections = combinedList;
      _isLoadingFeed = false;
    });
  }

  @override
  void dispose() {
    _followingSubscription?.cancel();
    _publicSubscription?.cancel();
    _collabSubscription?.cancel();
    super.dispose();
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
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _selectedIndex,
          children: [
            // Tab 0: Home Feed
            RefreshIndicator(
              onRefresh: () async {
                // Refresh all streams by canceling and recreating them
                await _followingSubscription?.cancel();
                await _publicSubscription?.cancel();
                await _collabSubscription?.cancel();
                _setupRealtimeStreams();
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
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: AppColors.primaryPurple,
                                      fontWeight: FontWeight.w700,
                                    ),
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
                  
                  // Bottom padding for floating nav bar
                  const SliverToBoxAdapter(child: SizedBox(height: 120)),
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
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFFF1F5F9)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_outlined, Icons.home, 'Home'),
              _buildNavItem(1, Icons.explore_outlined, Icons.explore, 'Explore'),
              _buildNavItem(2, Icons.add_circle_outline, Icons.add_circle, 'Create', isSpecial: true, onSpecialTap: () => _navigateToCreate(auth)),
              _buildActivityNavItem(3, auth),
              _buildNavItem(4, Icons.person_outline, Icons.person, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData selectedIcon, String label, {bool isSpecial = false, VoidCallback? onSpecialTap}) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (isSpecial && onSpecialTap != null) {
            onSpecialTap();
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? AppColors.primaryPurple : Colors.black,
              size: 26,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primaryPurple : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityNavItem(int index, AuthProvider auth) {
    final isSelected = _selectedIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedIndex = index),
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<int>(
              stream: _firestoreService.getUnreadNotificationCount(auth.userId),
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                return Badge(
                  isLabelVisible: count > 0,
                  label: Text(count > 9 ? '9+' : '$count'),
                  backgroundColor: Color(0xFFEF4444),
                  child: Icon(
                    isSelected ? Icons.favorite : Icons.favorite_outline,
                    color: isSelected ? AppColors.primaryPurple : Colors.black,
                    size: 26,
                  ),
                );
              },
            ),
            const SizedBox(height: 2),
            Text(
              'Activity',
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? AppColors.primaryPurple : Colors.black,
              ),
            ),
          ],
        ),
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

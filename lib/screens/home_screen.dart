import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/collection_entity.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/feed_collection_card.dart';
import '../widgets/collaboration_card.dart';
import 'collection_detail_screen.dart';
import 'explore_screen.dart';
import 'create_collection_screen.dart';
import 'profile_screen.dart';
import 'notifications_screen.dart';
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
                  // App bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Text('finds', 
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18, 
                              fontWeight: FontWeight.w800, 
                              color: AppColors.primary, 
                              letterSpacing: -0.5
                            )
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ),

                  // Open Collaborations Section
                  if (!_isLoadingCollabs && _collabCollections.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Open Collaborations', 
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 26, 
                                fontWeight: FontWeight.w800, 
                                color: AppColors.textPrimary, 
                                letterSpacing: -0.5
                              )
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.push(context, MaterialPageRoute(builder: (context) => const OpenCollaborationsScreen()));
                              },
                              child: Text('View All', 
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.primary, 
                                  fontWeight: FontWeight.w700
                                )
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: 265, // Reduced from 275 to further tighten the carousel and reduce bottom whitespace
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
                    const SliverToBoxAdapter(child: SizedBox(height: 12)),
                  ],

                  // 3. Main Feed Section Title
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text('Your Feed', 
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 26, 
                          fontWeight: FontWeight.w800, 
                          color: AppColors.textPrimary, 
                          letterSpacing: -0.5
                        )
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
                              style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
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
                            final isSaved = raw.savedBy.contains(auth.userId);
                            final collection = raw.copyWith(
                              isLiked: isLiked,
                              isSaved: isSaved,
                            );
                            return FeedCollectionCard(
                              collection: collection,
                              onTap: () => _navigateToCollection(collection.id, auth.userId),
                              onUserTap: () => _navigateToUserProfile(collection.userId, auth.userId),
                              onLike: () async {
                                final current = _feedCollections[index];
                                final wasLiked = current.likedBy.contains(auth.userId);

                                // Optimistic UI
                                setState(() {
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
                                    SnackBarUtils.showErrorSnackBar(context, 'Could not update like: $e');
                                  }
                                }
                              },
                              onSave: () async {
                                final current = _feedCollections[index];
                                final wasSaved = current.savedBy.contains(auth.userId);

                                // Optimistic UI
                                setState(() {
                                  final updatedSavedBy = List<String>.from(current.savedBy);
                                  if (wasSaved) {
                                    updatedSavedBy.remove(auth.userId);
                                  } else {
                                    updatedSavedBy.add(auth.userId);
                                  }
                                  _feedCollections[index] = current.copyWith(
                                    saveCount: (current.saveCount + (wasSaved ? -1 : 1)).clamp(0, 1 << 31),
                                    savedBy: updatedSavedBy,
                                  );
                                });

                                try {
                                  await _firestoreService.toggleCollectionSave(collection.id, auth.userId);
                                } catch (e) {
                                  // Revert UI
                                  if (mounted) {
                                    setState(() {
                                      final current = _feedCollections[index];
                                      final updatedSavedBy = List<String>.from(current.savedBy);
                                      if (wasSaved) {
                                        updatedSavedBy.add(auth.userId);
                                      } else {
                                        updatedSavedBy.remove(auth.userId);
                                      }
                                      _feedCollections[index] = current.copyWith(
                                        saveCount: (current.saveCount + (wasSaved ? 1 : -1)).clamp(0, 1 << 31),
                                        savedBy: updatedSavedBy,
                                      );
                                    });
                                  }

                                  if (context.mounted) {
                                    SnackBarUtils.showErrorSnackBar(context, 'Could not save collection: $e');
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
      bottomNavigationBar: Material(
        color: Colors.transparent,
        elevation: 0,
        child: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(40),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_outlined, Icons.home_rounded),
              _buildNavItem(1, Icons.explore_outlined, Icons.explore_rounded),
              _buildNavItem(2, Icons.add_circle_outline_rounded, Icons.add_circle_rounded, isSpecial: true, onSpecialTap: () => _navigateToCreate(auth)),
              _buildActivityNavItem(3, auth),
              _buildNavItem(4, Icons.person_outline_rounded, Icons.person_rounded),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, IconData selectedIcon, {bool isSpecial = false, VoidCallback? onSpecialTap}) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        if (isSpecial && onSpecialTap != null) { onSpecialTap(); }
        else { setState(() => _selectedIndex = index); }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48, height: 48,
        child: Center(
          child: isSelected
              ? Container(
                  width: 44, height: 44,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(selectedIcon, color: Colors.white, size: 22),
                )
              : Icon(icon, color: AppColors.textSecondary, size: 26),
        ),
      ),
    );
  }

  Widget _buildActivityNavItem(int index, AuthProvider auth) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedIndex = index);
        _firestoreService.markAllNotificationsAsRead(auth.userId);
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48, height: 48,
        child: Center(
          child: StreamBuilder<int>(
            stream: _firestoreService.getUnreadNotificationCount(auth.userId),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              final icon = isSelected
                  ? Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_rounded, color: Colors.white, size: 22),
                    )
                  : const Icon(Icons.notifications_none_rounded, color: AppColors.textSecondary, size: 26);
              return Badge(
                isLabelVisible: count > 0,
                label: Text(count > 9 ? '9+' : '$count', style: GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w700)),
                backgroundColor: AppColors.heartSalmon,
                child: icon,
              );
            },
          ),
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
          userName: auth.resolvedUserName,
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

  Widget _buildCreateTab(AuthProvider auth) {
    // This is just a placeholder if accessing via index, currently handled by nav bar override
     return Container(); 
  }
}

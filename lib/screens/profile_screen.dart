import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/collection_entity.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_list_card.dart';
import '../widgets/profile_header_layout.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';
import 'followers_following_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  static const double _headerExpandedHeight = 420;
  static const double _bottomNavClearance = 120;

  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();

  StreamSubscription<List<CollectionEntity>>? _myCollectionsSubscription;
  StreamSubscription<List<CollectionEntity>>? _savedCollectionsSubscription;
  StreamSubscription<List<CollectionEntity>>? _collaborationsSubscription;

  List<CollectionEntity> _myCollections = [];
  List<CollectionEntity> _savedCollections = [];
  // ignore: unused_field
  List<CollectionEntity> _collaborationCollections = [];
  bool _isLoading = true;

  String? _activeUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final userId = auth.userId;
    if (userId.isNotEmpty && userId != _activeUserId) {
      _activeUserId = userId;
      _setupRealtimeStreams(isInitial: true);
    }
  }

  void _setupRealtimeStreams({bool isInitial = false}) {
    if (!mounted) return;
    _cancelSubscriptions();

    final auth = context.read<AuthProvider>();
    if (auth.userId.isEmpty) {
      debugPrint('ProfileScreen: Cannot setup streams - user not authenticated');
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    if (isInitial && mounted) {
      setState(() => _isLoading = true);
    }

    _myCollectionsSubscription = _firestoreService.getUserCollectionsStream(auth.userId).listen(
      (collections) {
        if (mounted) {
          setState(() {
            _myCollections = collections;
            _isLoading = false;
          });
        }
      },
      onError: (error) {
        debugPrint('Error in my collections stream: $error');
        if (mounted) setState(() => _isLoading = false);
      },
    );

    _savedCollectionsSubscription = _firestoreService.getSavedCollectionsStream(auth.userId).listen(
      (collections) {
        if (mounted) {
          setState(() {
            _savedCollections = collections;
          });
        }
      },
      onError: (error) {
        debugPrint('Error in saved collections stream: $error');
      },
    );

    _collaborationsSubscription = _firestoreService.getUserCollaborationsStream(auth.userId).listen(
      (collections) {
        if (mounted) {
          setState(() {
            _collaborationCollections = collections;
          });
        }
      },
      onError: (error) {
        debugPrint('Error in collaborations stream: $error');
      },
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cancelSubscriptions();
    super.dispose();
  }

  void _cancelSubscriptions() {
    _myCollectionsSubscription?.cancel();
    _savedCollectionsSubscription?.cancel();
    _collaborationsSubscription?.cancel();
    _myCollectionsSubscription = null;
    _savedCollectionsSubscription = null;
    _collaborationsSubscription = null;
  }

  Future<void> _refreshStreams() async {
    _setupRealtimeStreams();
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
    if (result == true && mounted) {
      _refreshStreams();
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

  Widget _buildEditProfileButton() {
    return ProfileHeaderLayout.buildOutlinedActionButton(
      label: 'Edit Profile',
      onPressed: _navigateToEditProfile,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        final user = auth.userEntity;

        if (user == null) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          backgroundColor: Colors.white,
          body: NestedScrollView(
            headerSliverBuilder: (context, innerBoxIsScrolled) {
              return [
                SliverAppBar(
                  expandedHeight: _headerExpandedHeight,
                  pinned: true,
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, color: AppColors.collectionDescription),
                      onPressed: _navigateToSettings,
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(height: 20),
                            ProfileHeaderLayout(
                              user: user,
                              showAvatarEditBadge: true,
                              onAvatarTap: _navigateToEditProfile,
                              actionButton: _buildEditProfileButton(),
                              statsRow: ProfileHeaderLayout.buildStatsRow(
                                collectionsCount: _formatCount(_myCollections.length),
                                followersCount: _formatCount(user.followers.length),
                                followingCount: _formatCount(user.following.length),
                                onFollowersTap: () => _navigateToFollowers(auth.userId, showFollowers: true),
                                onFollowingTap: () => _navigateToFollowers(auth.userId, showFollowers: false),
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
                      labelColor: AppColors.primary,
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.primary,
                      indicatorWeight: 3,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelStyle: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.6,
                      ),
                      unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        letterSpacing: 0.6,
                      ),
                      tabs: const [
                        Tab(text: 'COLLECTIONS'),
                        Tab(text: 'SAVED'),
                      ],
                    ),
                  ),
                ),
              ];
            },
            body: ColoredBox(
              color: AppColors.backgroundSurface,
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildCollectionsList(
                    _myCollections,
                    auth.userId,
                    isEmpty: 'You haven\'t created any collections yet',
                  ),
                  _buildCollectionsList(
                    _savedCollections,
                    auth.userId,
                    isEmpty: 'No saved collections',
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
            const Icon(Icons.collections_outlined, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              isEmpty,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshStreams,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, _bottomNavClearance),
        itemCount: collections.length,
        itemBuilder: (context, index) {
          return CollectionListCard(
            collection: collections[index],
            currentUserId: userId,
            profileStyle: true,
          );
        },
      ),
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
    return ColoredBox(
      color: Colors.white,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}

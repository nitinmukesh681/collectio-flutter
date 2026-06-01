import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/collection_entity.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_grid_card.dart';
import '../screens/collection_detail_screen.dart';
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
  static const double _bottomNavClearance = 120;

  late TabController _tabController;
  final FirestoreService _firestoreService = FirestoreService();

  StreamSubscription<List<CollectionEntity>>? _myCollectionsSubscription;
  StreamSubscription<List<CollectionEntity>>? _savedCollectionsSubscription;
  StreamSubscription<List<CollectionEntity>>? _collaborationsSubscription;

  List<CollectionEntity> _myCollections = [];
  List<CollectionEntity> _savedCollections = [];
  List<CollectionEntity> _collaborationCollections = [];
  bool _isLoading = true;

  String? _activeUserId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
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

  List<CollectionEntity> _mergedMyCollections(String userId) {
    final ownedIds = _myCollections.map((c) => c.id).toSet();
    final collaborated = _collaborationCollections
        .where((c) =>
            !c.isOpenForContribution &&
            !ownedIds.contains(c.id) &&
            c.editors.contains(userId))
        .toList();
    final merged = [..._myCollections, ...collaborated];
    merged.sort(
      (a, b) => b.lastContentActivityAt.compareTo(a.lastContentActivityAt),
    );
    return merged;
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

        final mergedCollections = _mergedMyCollections(auth.userId);

        final activeCollections = _tabController.index == 0
            ? mergedCollections
            : _savedCollections;
        final emptyMessage = _tabController.index == 0
            ? 'You haven\'t created any collections yet'
            : 'No saved collections';

        return Scaffold(
          backgroundColor: AppColors.backgroundSurface,
          body: RefreshIndicator(
            onRefresh: _refreshStreams,
            color: AppColors.primary,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: Colors.white,
                    child: SafeArea(
                      bottom: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              icon: const Icon(
                                Icons.settings_outlined,
                                color: AppColors.collectionDescription,
                              ),
                              onPressed: _navigateToSettings,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            child: ProfileHeaderLayout(
                              user: user,
                              actionButton: _buildEditProfileButton(),
                              statsRow: ProfileHeaderLayout.buildStatsRow(
                                collectionsCount: _formatCount(mergedCollections.length),
                                followersCount: _formatCount(user.followers.length),
                                followingCount: _formatCount(user.following.length),
                                onFollowersTap: () =>
                                    _navigateToFollowers(auth.userId, showFollowers: true),
                                onFollowingTap: () =>
                                    _navigateToFollowers(auth.userId, showFollowers: false),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: Colors.white,
                    child: TabBar(
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
                ..._buildCollectionsSlivers(
                  activeCollections,
                  auth.userId,
                  isEmpty: emptyMessage,
                ),
                const SliverToBoxAdapter(child: SizedBox(height: _bottomNavClearance)),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildCollectionsSlivers(
    List<CollectionEntity> collections,
    String userId, {
    required String isEmpty,
  }) {
    if (_isLoading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }

    if (collections.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
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
          ),
        ),
      ];
    }

    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.72,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, index) {
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
              );
            },
            childCount: collections.length,
          ),
        ),
      ),
    ];
  }
}

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/collection_entity.dart';
import '../models/user_entity.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_list_card.dart';
import 'edit_profile_screen.dart';
import 'settings_screen.dart';
import 'followers_following_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with SingleTickerProviderStateMixin {
  static const Color _listBackground = Color(0xFFF7F6FC);
  static const Color _editButtonBg = Color(0xFFEEF2FF);

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
    if (result == true) {
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
                  expandedHeight: 248,
                  pinned: true,
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.settings_outlined, color: AppColors.textPrimary),
                      onPressed: _navigateToSettings,
                    ),
                  ],
                  flexibleSpace: FlexibleSpaceBar(
                    background: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 40),
                            _buildProfileHeader(user),
                            const SizedBox(height: 20),
                            _buildStatsRow(user, auth.userId),
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
                      dividerColor: AppColors.divider,
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
              color: _listBackground,
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

  Widget _buildProfileHeader(UserEntity user) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: _navigateToEditProfile,
          child: SizedBox(
            width: 88,
            height: 88,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  child: ClipOval(
                    child: SizedBox(
                      width: 80,
                      height: 80,
                      child: _buildAvatar(user),
                    ),
                  ),
                ),
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.add, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user.displayName.isNotEmpty ? user.displayName : user.userName,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  height: 1.1,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '@${user.userName}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _navigateToEditProfile,
                  style: TextButton.styleFrom(
                    backgroundColor: _editButtonBg,
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppColors.radiusSmall),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Edit Profile',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(UserEntity user) {
    Widget fallback() {
      return Container(
        color: AppColors.primary.withOpacity(0.10),
        alignment: Alignment.center,
        child: Text(
          user.userName.isNotEmpty ? user.userName[0].toUpperCase() : '?',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppColors.primaryDark,
          ),
        ),
      );
    }

    if (user.avatarUrl == null || user.avatarUrl!.isEmpty) {
      return fallback();
    }

    if (user.avatarUrl!.trim().startsWith('gs://')) {
      return FutureBuilder<String>(
        future: FirebaseStorage.instance.refFromURL(user.avatarUrl!.trim()).getDownloadURL(),
        builder: (context, snap) {
          final url = snap.data;
          if (url == null || url.isEmpty) return fallback();
          return CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            errorWidget: (_, __, ___) => fallback(),
          );
        },
      );
    }

    return CachedNetworkImage(
      imageUrl: user.avatarUrl!.trim(),
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => fallback(),
    );
  }

  Widget _buildStatsRow(UserEntity user, String userId) {
    return Row(
      children: [
        Expanded(
          child: _buildStat(_formatCount(_myCollections.length), 'COLLECTIONS'),
        ),
        Container(width: 1, height: 36, color: AppColors.divider),
        Expanded(
          child: _buildStat(
            _formatCount(user.followers.length),
            'FOLLOWERS',
            onTap: () => _navigateToFollowers(userId, showFollowers: true),
          ),
        ),
        Container(width: 1, height: 36, color: AppColors.divider),
        Expanded(
          child: _buildStat(
            _formatCount(user.following.length),
            'FOLLOWING',
            onTap: () => _navigateToFollowers(userId, showFollowers: false),
          ),
        ),
      ],
    );
  }

  Widget _buildStat(String count, String label, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          Text(
            count,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.primary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        itemCount: collections.length,
        itemBuilder: (context, index) {
          return CollectionListCard(
            collection: collections[index],
            currentUserId: userId,
            compact: true,
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
    return Container(
      color: Colors.white,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => false;
}

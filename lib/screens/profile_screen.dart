import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/collection_entity.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
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
  final ScrollController _scrollController = ScrollController();
  
  StreamSubscription<List<CollectionEntity>>? _myCollectionsSubscription;
  StreamSubscription<List<CollectionEntity>>? _savedCollectionsSubscription;
  StreamSubscription<List<CollectionEntity>>? _collaborationsSubscription;
  
  List<CollectionEntity> _myCollections = [];
  List<CollectionEntity> _savedCollections = [];
  List<CollectionEntity> _collaborationCollections = [];
  bool _isLoading = true;

  String _collectionsFilter = 'my';
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
    // Always cancel any existing subscriptions before wiring new ones
    _cancelSubscriptions();

    final auth = context.read<AuthProvider>();
    if (auth.userId.isEmpty) {
      debugPrint('ProfileScreen: Cannot setup streams - user not authenticated');
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // Only show loading indicator on initial setup, not on refresh
    if (isInitial && mounted) {
      setState(() => _isLoading = true);
    }
    
    // Setup real-time streams for immediate updates
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
      }
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
      }
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
      }
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
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
    // Setup new streams (existing ones will be cancelled in _setupRealtimeStreams)
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
      // Refresh streams if profile was updated
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
                  expandedHeight: 380,
                  pinned: true,
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.transparent,
                  elevation: 0,
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
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(color: AppColors.divider, width: 1),
                                  ),
                                  child: ClipOval(
                                    child: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                                        ? (user.avatarUrl!.trim().startsWith('gs://')
                                            ? FutureBuilder<String>(
                                                future: FirebaseStorage.instance
                                                    .refFromURL(user.avatarUrl!.trim())
                                                    .getDownloadURL(),
                                                builder: (context, snap) {
                                                  final url = snap.data;
                                                  if (url == null || url.isEmpty) {
                                                    return Container(
                                                      color: AppColors.primaryPurple.withOpacity(0.10),
                                                      alignment: Alignment.center,
                                                      child: Text(
                                                        user.userName.isNotEmpty
                                                            ? user.userName[0].toUpperCase()
                                                            : '?',
                                                        style: GoogleFonts.plusJakartaSans(
                                                          fontSize: 34,
                                                          fontWeight: FontWeight.w800,
                                                          color: AppColors.primaryPurpleDark,
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  return CachedNetworkImage(
                                                    imageUrl: url,
                                                    fit: BoxFit.cover,
                                                    errorWidget: (context, _, __) {
                                                      return Container(
                                                        color: AppColors.primaryPurple.withOpacity(0.10),
                                                        alignment: Alignment.center,
                                                        child: Text(
                                                          user.userName.isNotEmpty
                                                              ? user.userName[0].toUpperCase()
                                                              : '?',
                                                          style: GoogleFonts.plusJakartaSans(
                                                            fontSize: 34,
                                                            fontWeight: FontWeight.w800,
                                                            color: AppColors.primaryPurpleDark,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                  );
                                                },
                                              )
                                            : CachedNetworkImage(
                                                imageUrl: user.avatarUrl!.trim(),
                                                fit: BoxFit.cover,
                                                errorWidget: (context, url, error) {
                                                  return Container(
                                                    color: AppColors.primaryPurple.withOpacity(0.10),
                                                    alignment: Alignment.center,
                                                    child: Text(
                                                      user.userName.isNotEmpty
                                                          ? user.userName[0].toUpperCase()
                                                          : '?',
                                                      style: GoogleFonts.plusJakartaSans(
                                                        fontSize: 34,
                                                        fontWeight: FontWeight.w800,
                                                        color: AppColors.primaryPurpleDark,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ))
                                        : Container(
                                            color: AppColors.primaryPurple.withOpacity(0.10),
                                            alignment: Alignment.center,
                                            child: Text(
                                              user.userName.isNotEmpty
                                                  ? user.userName[0].toUpperCase()
                                                  : '?',
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 34,
                                                fontWeight: FontWeight.w800,
                                                color: AppColors.primaryPurpleDark,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              user.userName,
                              style: GoogleFonts.plusJakartaSans(
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
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            if (user.bio != null && user.bio!.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                user.bio!,
                                textAlign: TextAlign.center,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  color: AppColors.textSecondary,
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _navigateToEditProfile,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radiusSmall)),
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  elevation: 0,
                                ),
                                child: Text('Edit Profile', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
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
                                  Container(width: 1, height: 32, color: AppColors.divider),
                                  Expanded(
                                    child: _buildStat(
                                      user.followers.length,
                                      'Followers',
                                      onTap: () => _navigateToFollowers(auth.userId, showFollowers: true),
                                      dark: true,
                                    ),
                                  ),
                                  Container(width: 1, height: 32, color: AppColors.divider),
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
                      unselectedLabelColor: AppColors.textSecondary,
                      indicatorColor: AppColors.primaryPurple,
                      indicatorWeight: 3,
                      labelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14),
                      unselectedLabelStyle: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 14),
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
    final filterLabel = _collectionsFilter == 'collab' ? 'Collaborations' : 'My collections';

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
                  border: Border.all(color: AppColors.divider),
                ),
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  onSelected: (value) => setState(() => _collectionsFilter = value),
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'my',
                      child: Row(
                        children: [
                          const Icon(Icons.collections_outlined, size: 18, color: Colors.black87),
                          const SizedBox(width: 10),
                          Text('My collections', style: GoogleFonts.plusJakartaSans()),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'collab',
                      child: Row(
                        children: [
                          const Icon(Icons.groups_outlined, size: 18, color: Colors.black87),
                          const SizedBox(width: 10),
                          Text('Collaborations', style: GoogleFonts.plusJakartaSans()),
                        ],
                      ),
                    ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            filterLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down, size: 18, color: Colors.black87),
                      ],
                    ),
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
            style: GoogleFonts.plusJakartaSans(color: AppColors.primary, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5),
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
              style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshStreams,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
        itemCount: collections.length,
        itemBuilder: (context, index) {
          final collection = collections[index];
          return _buildCollectionListCard(collection, userId);
        },
      ),
    );
  }

  Widget _buildCollectionListCard(CollectionEntity collection, String userId) {
    final gradientColors = AppColors.categoryGradients[collection.category.name] ?? AppColors.categoryGradients['other']!;

    Future<String?> resolveCover() async {
      final candidate = (collection.coverImageUrl != null && collection.coverImageUrl!.isNotEmpty)
          ? collection.coverImageUrl!.trim()
          : (collection.previewImageUrls.isNotEmpty ? collection.previewImageUrls.first.trim() : '');
      if (candidate.isEmpty) return null;
      if (candidate.startsWith('gs://')) {
        try { return await FirebaseStorage.instance.refFromURL(candidate).getDownloadURL(); } catch (_) { return null; }
      }
      if (candidate.startsWith('http')) return candidate;
      return null;
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(
          builder: (context) => CollectionDetailScreen(collectionId: collection.id, currentUserId: userId),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          boxShadow: AppColors.cardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with padding inside card
            ClipRRect(
              borderRadius: BorderRadius.circular(AppColors.radiusSmall),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: FutureBuilder<String?>(
                  future: resolveCover(),
                  builder: (context, snap) {
                    final url = snap.data;
                    if (url != null && url.isNotEmpty) {
                      return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          decoration: BoxDecoration(gradient: LinearGradient(colors: gradientColors)),
                        ));
                    }
                    return Container(
                      decoration: BoxDecoration(gradient: LinearGradient(colors: gradientColors)),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Category
            Text(
              collection.category.displayName.toUpperCase(),
              style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 1),
            ),
            const SizedBox(height: 6),
            // Title
            Text(
              collection.title,
              style: GoogleFonts.plusJakartaSans(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.2),
            ),
            if (collection.description != null && collection.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                collection.description!,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                maxLines: 2, overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
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

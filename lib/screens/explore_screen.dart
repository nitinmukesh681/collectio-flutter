import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../models/category_type.dart';
import '../models/collection_entity.dart';
import '../models/user_entity.dart';
import '../providers/auth_provider.dart';
import '../widgets/collection_card.dart';
import '../widgets/collection_list_card.dart';
import '../widgets/user_avatar.dart';
import '../utils/category_icons.dart';
import '../utils/collection_cover_placeholder.dart';
import 'collection_detail_screen.dart';
import 'user_profile_screen.dart';
import 'dart:async';
import 'dart:math' as math;

enum _SearchTab { collections, people }

enum _TopLikedRange { week, month, allTime }

class ExploreScreen extends StatefulWidget {
  final String currentUserId;

  const ExploreScreen({super.key, required this.currentUserId});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  String _searchQuery = '';
  // ignore: unused_field
  bool _isSearching = false; // Kept for future use if needed or remove ignore
  
  _SearchTab _selectedTab = _SearchTab.collections;
  
  List<CollectionEntity> _searchResults = [];
  List<UserEntity> _userResults = [];
  List<CollectionEntity> _allPublicCollections = [];
  
  List<CollectionEntity> _trendingCollections = [];
  List<CollectionEntity> _topLikedCollections = [];
  bool _isLoading = true;

  Map<CategoryType, int> _categoryCounts = {};
  bool _isSearchLoading = false;

  _TopLikedRange _topLikedRange = _TopLikedRange.week;

  static const double _trendingGravity = 1.8;
  static const Duration _trendingWindow = Duration(days: 2);
  static const int _topLikedMaxItems = 5;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _navigateToUserProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: userId,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final since = _sinceForTopLikedRange(_topLikedRange);

      final allPublic = await _firestoreService.getPublicCollectionsList(limit: 200);

      final trending = _computeTrending(allPublic, limit: 5);

      List<CollectionEntity> topLiked = [];
      if (since != null) {
        // Prefer the already-loaded public list so mixed createdAt types are not missed.
        topLiked = _filterBySince(allPublic, since)
          ..sort((a, b) => b.likes.compareTo(a.likes));
        if (topLiked.length > _topLikedMaxItems) {
          topLiked = topLiked.take(_topLikedMaxItems).toList();
        }
      }

      if (topLiked.isEmpty) {
        try {
          topLiked = await _firestoreService.getTopLikedCollections(
            since: since,
            limit: _topLikedMaxItems,
          );
        } catch (e) {
          debugPrint('Top liked query failed: $e');
        }
      }

      if (topLiked.isEmpty && since != null) {
        topLiked = _filterBySince(allPublic, since)
          ..sort((a, b) => b.likes.compareTo(a.likes));
        if (topLiked.length > _topLikedMaxItems) {
          topLiked = topLiked.take(_topLikedMaxItems).toList();
        }
      }
      
      if (mounted) {
        setState(() {
          _allPublicCollections = allPublic;
          _categoryCounts = _computeCategoryCounts(allPublic);
          _trendingCollections = trending;
          _topLikedCollections = topLiked;
        });
      }
    } catch (e) {
      debugPrint('Error loading explore data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
    setState(() => _isLoading = false);
  }

  Map<CategoryType, int> _computeCategoryCounts(List<CollectionEntity> collections) {
    final counts = <CategoryType, int>{};
    for (final c in collections) {
      counts[c.category] = (counts[c.category] ?? 0) + 1;
    }
    return counts;
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    setState(() => _searchQuery = query);
    
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _userResults = [];
        _isSearchLoading = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearchLoading = true);
    
    try {
      if (_selectedTab == _SearchTab.collections) {
        final results = await _firestoreService.searchCollections(
          query,
          supplementalCollections: _allPublicCollections,
        );
        setState(() => _searchResults = results);
      } else {
        final results = await _firestoreService.searchUsers(query);
        setState(() => _userResults = results);
      }
    } catch (e) {
      debugPrint('Error searching: $e');
    }
    
    setState(() => _isSearchLoading = false);
  }

  void _changeTab(_SearchTab tab) {
    setState(() {
      _selectedTab = tab;
    });
    if (_searchQuery.isNotEmpty) {
      _performSearch(_searchQuery);
    }
  }

  void _navigateToBrowseCategories() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _BrowseCategoriesScreen(
          currentUserId: widget.currentUserId,
          onCategoryTap: _navigateToCategory,
          categoryCounts: _categoryCounts,
        ),
      ),
    );
  }

  void _navigateToTrendingViewAll() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _CollectionsListScreen(
          title: 'Trending now',
          icon: trendingCoverIcon,
          loader: () async {
            final all = await _firestoreService.getPublicCollectionsList(limit: 50);
            return _computeTrending(all, limit: 50);
          },
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }

  DateTime? _sinceForTopLikedRange(_TopLikedRange range) {
    final now = DateTime.now();
    switch (range) {
      case _TopLikedRange.week:
        return now.subtract(const Duration(days: 7));
      case _TopLikedRange.month:
        return now.subtract(const Duration(days: 30));
      case _TopLikedRange.allTime:
        return null;
    }
  }

  String _topLikedRangeLabel(_TopLikedRange range) {
    switch (range) {
      case _TopLikedRange.week:
        return 'This week';
      case _TopLikedRange.month:
        return 'This month';
      case _TopLikedRange.allTime:
        return 'All time';
    }
  }

  List<CollectionEntity> _filterBySince(List<CollectionEntity> collections, DateTime? since) {
    if (since == null) return [...collections];
    final sinceMs = since.millisecondsSinceEpoch;
    return collections.where((c) => c.createdAt >= sinceMs).toList();
  }

  double _trendingScore(CollectionEntity c) {
    final score = c.likes.toDouble();
    final hoursOld = (DateTime.now().millisecondsSinceEpoch - c.createdAt) / (1000.0 * 60.0 * 60.0);
    final timeFactor = (hoursOld < 0.1 ? 0.1 : hoursOld) + 2.0;
    return (score - 1.0) / math.pow(timeFactor, _trendingGravity);
  }

  List<CollectionEntity> _computeTrending(List<CollectionEntity> collections, {required int limit}) {
    final cutoffMs = DateTime.now().subtract(_trendingWindow).millisecondsSinceEpoch;
    final recent = collections.where((c) => c.createdAt >= cutoffMs).toList();
    final pool = recent.isNotEmpty ? recent : collections;
    final scored = pool.map((c) => MapEntry(c, _trendingScore(c))).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }

  void _navigateToCollection(String collectionId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CollectionDetailScreen(
          collectionId: collectionId,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }

  void _navigateToCategory(CategoryType category) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _CollectionsListScreen(
          title: category.displayName,
          icon: categoryIcon(category),
          accentColor: AppColors.categoryLabelColor(category.name),
          currentUserId: widget.currentUserId,
          emptyMessage: 'No collections in ${category.displayName} yet',
          loader: () => _firestoreService.getCollectionsByCategory(
            category.name,
            limit: 50,
          ),
        ),
      ),
    );
  }

  static const double _bottomNavClearance = 120;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
            // Search bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0F000000),
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                      BoxShadow(
                        color: Color(0x06000000),
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search curated collections, items,',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        color: AppColors.textMuted,
                        fontSize: 15,
                        fontWeight: FontWeight.w400,
                      ),
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.search_rounded,
                          color: AppColors.textMuted.withValues(alpha: 0.85),
                          size: 22,
                        ),
                      ),
                      prefixIconConstraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: AppColors.textMuted.withValues(alpha: 0.85),
                              ),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchQuery = '';
                                  _searchResults = [];
                                });
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
                      isDense: true,
                    ),
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (value) => _performSearch(value),
                  ),
                ),
              ),
            ),

            // Search Tabs (visible only when searching)
            if (_searchQuery.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 16, 8),
                  child: Row(
                    children: [
                      _buildSearchTab('Collections', _SearchTab.collections),
                      const SizedBox(width: 12),
                      _buildSearchTab('People', _SearchTab.people),
                    ],
                  ),
                ),
              ),

            // Search results or main content
            if (_searchQuery.isNotEmpty) ...[
              _buildSearchResults(),
            ] else ...[
              // Browse by Category
              _buildSectionHeader('Browse', onViewAll: _navigateToBrowseCategories, topPadding: 10),
              _buildCategoryGrid(),

              // Trending Now
              _buildSectionHeader('Trending now', onViewAll: _navigateToTrendingViewAll),
              _buildTrendingCarousel(),

              // Top Liked
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 10, 12),
                  child: Row(
                    children: [
                      Text('Top liked', 
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 26, 
                          fontWeight: FontWeight.w800, 
                          color: AppColors.textPrimary, 
                          letterSpacing: -0.5
                        )
                      ),
                      const Spacer(),
                      PopupMenuButton<_TopLikedRange>(
                        onSelected: (value) async {
                          setState(() {
                            _topLikedRange = value;
                          });
                          await _loadData();
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: _TopLikedRange.week,
                            child: Text(_topLikedRangeLabel(_TopLikedRange.week)),
                          ),
                          PopupMenuItem(
                            value: _TopLikedRange.month,
                            child: Text(_topLikedRangeLabel(_TopLikedRange.month)),
                          ),
                          PopupMenuItem(
                            value: _TopLikedRange.allTime,
                            child: Text(_topLikedRangeLabel(_TopLikedRange.allTime)),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _topLikedRangeLabel(_topLikedRange),
                                style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(Icons.keyboard_arrow_down, size: 18, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              _buildTopLikedList(),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: _bottomNavClearance)),
          ],
        ),
    );
  }

  Widget _buildSectionHeader(
    String title, {
    IconData? icon,
    required VoidCallback onViewAll,
    double topPadding = 16,
  }) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, topPadding, 10, 12),
        child: Row(
          children: [
            Text(title, 
              style: GoogleFonts.plusJakartaSans(
                fontSize: 26, 
                fontWeight: FontWeight.w800, 
                color: AppColors.textPrimary, 
                letterSpacing: -0.5
              )
            ),
            const Spacer(),
            TextButton(
              onPressed: onViewAll,
              child: Text('View all', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, color: AppColors.primary, fontSize: 14)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    final categories = <CategoryType>[
      CategoryType.food,
      CategoryType.travel,
      CategoryType.tech,
      CategoryType.shopping,
    ];

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.6,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= categories.length) return null;
            final category = categories[index];
            return _buildCategoryTile(category);
          },
          childCount: categories.length,
        ),
      ),
    );
  }

  // Design-system palette only: primary, secondary, tertiary, light indigo
  static Color _categoryColor(CategoryType category) =>
      AppColors.categoryLabelColor(category.name);

  Widget _buildCategoryTile(CategoryType category) {
    final color = _categoryColor(category);
    return GestureDetector(
      onTap: () => _navigateToCategory(category),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: CategoryPhosphorIcon(
                category: category,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            Text(category.displayName, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendingCarousel() {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: SizedBox(
        height: 280,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _trendingCollections.length,
          itemBuilder: (context, index) {
            final collection = _trendingCollections[index];
            return Padding(
              padding: const EdgeInsets.only(right: 14),
              child: _buildTrendingCard(collection),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrendingCard(CollectionEntity collection) {
    final gradientColors = AppColors.categoryGradients[collection.category.name] ?? 
        AppColors.categoryGradients['other']!;

    Future<String?> resolveCoverUrl() async {
      final candidate = (collection.coverImageUrl != null && collection.coverImageUrl!.isNotEmpty)
          ? collection.coverImageUrl!.trim()
          : (collection.previewImageUrls.isNotEmpty ? collection.previewImageUrls.first.trim() : '');
      if (candidate.isEmpty) return null;
      if (!(candidate.startsWith('http://') || candidate.startsWith('https://') || candidate.startsWith('gs://'))) {
        return null;
      }
      if (candidate.startsWith('gs://')) {
        try {
          return await FirebaseStorage.instance.refFromURL(candidate).getDownloadURL();
        } catch (e) {
          debugPrint('Failed to resolve gs:// trending cover url: $candidate, error: $e');
          return null;
        }
      }
      return candidate;
    }

    return GestureDetector(
      onTap: () => _navigateToCollection(collection.id),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image top
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AppColors.radiusCard)),
              child: SizedBox(
                height: 160,
                width: double.infinity,
                child: FutureBuilder<String?>(
                  future: resolveCoverUrl(),
                  builder: (context, snap) {
                    final url = snap.data;
                    if (url != null && url.isNotEmpty) {
                      return CachedNetworkImage(imageUrl: url, fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => CollectionCoverPlaceholder(
                          category: collection.category,
                          seed: collectionCoverSeed(
                            collectionId: collection.id,
                            title: collection.title,
                          ),
                          gradientColors: gradientColors,
                          iconSize: 40,
                          iconOpacity: 0.7,
                        ));
                    }
                    return CollectionCoverPlaceholder(
                      category: collection.category,
                      seed: collectionCoverSeed(
                        collectionId: collection.id,
                        title: collection.title,
                      ),
                      gradientColors: gradientColors,
                      iconSize: 40,
                      iconOpacity: 0.7,
                    );
                  },
                ),
              ),
            ),
            // Text below
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(collection.title,
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary, height: 1.2),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                  if (collection.description != null && collection.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      collection.description!.trim(),
                      style: AppTextStyles.collectionDescription(fontSize: 13, height: 1.3),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.trending_up_rounded, size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('High Momentum', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(bool active) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? Colors.white : Colors.white.withOpacity(0.45),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildTopLikedList() {
    if (_isLoading) {
      return const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())));
    }

    final count = _topLikedCollections.length > _topLikedMaxItems
        ? _topLikedMaxItems
        : _topLikedCollections.length;
    if (count == 0) return const SliverToBoxAdapter(child: SizedBox.shrink());

    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppColors.radiusCard),
        ),
        child: Column(
          children: List.generate(count, (i) =>
            _buildTopLikedRow(i + 1, _topLikedCollections[i], isLast: i == count - 1)),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ExploreScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentUserId != widget.currentUserId) {
      _loadData();
    }
  }

  Color _topLikedRankColor(int rank) {
    if (rank == 1) return AppColors.primaryPurple;
    if (rank == 2) return const Color(0xFF22C55E);
    if (rank == 3) return const Color(0xFFF59E0B);
    return AppColors.divider;
  }

  Widget _buildTopLikedLikes(int likes) {
    return Transform.translate(
      offset: const Offset(0, 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.favorite, size: 15, color: AppColors.heartSalmon),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              _formatCount(likes),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.collectionDescription,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopLikedRow(int rank, CollectionEntity collection, {required bool isLast}) {
    return GestureDetector(
      onTap: () => _navigateToCollection(collection.id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
        decoration: BoxDecoration(
          border: isLast ? null : const Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 40,
              child: Text(
                rank.toString().padLeft(2, '0'),
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w500, fontSize: 24, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          collection.title,
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppColors.textPrimary,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 10),
                      _buildTopLikedLikes(collection.likes),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'by ${collection.userName}',
                    style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) {
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}k';
    return '$count';
  }

  Widget _buildSearchResults() {
    if (_isSearchLoading) {
      return const SliverFillRemaining(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    
    if (_selectedTab == _SearchTab.collections) {
      return _buildCollectionResults();
    } else {
      return _buildPeopleResults();
    }
  }

  Widget _buildSearchTab(String label, _SearchTab tab) {
    final isSelected = _selectedTab == tab;
    return GestureDetector(
      onTap: () => _changeTab(tab),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryPurple : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: isSelected
              ? null
              : Border.all(color: AppColors.divider),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            color: isSelected ? Colors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildPeopleResults() {
    if (_userResults.isEmpty) {
      return _buildNoResults();
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final user = _userResults[index];

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(
                      userId: user.id,
                      currentUserId: widget.currentUserId,
                    ),
                  ),
                );
              },
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppColors.radiusLarge),
                  boxShadow: AppColors.cardShadow,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    UserAvatar(
                      userId: user.id,
                      avatarUrl: user.avatarUrl,
                      name: user.userName,
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '@${user.userName}',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                          height: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: _userResults.length,
        ),
      ),
    );
  }

  Widget _buildCollectionResults() {
    if (_searchResults.isEmpty) {
      return _buildNoResults();
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final collection = _searchResults[index];
            return CollectionListCard(
              collection: collection,
              currentUserId: widget.currentUserId,
              collaborationStyle: true,
            );
          },
          childCount: _searchResults.length,
        ),
      ),
    );
  }

  Widget _buildNoResults() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textSecondary,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionsListScreen extends StatefulWidget {
  final String title;
  final IconData icon;
  final Color accentColor;
  final String? trailing;
  final Future<List<CollectionEntity>> Function() loader;
  final String currentUserId;
  final String? emptyMessage;

  const _CollectionsListScreen({
    required this.title,
    required this.icon,
    required this.loader,
    required this.currentUserId,
    this.accentColor = AppColors.primary,
    this.trailing,
    this.emptyMessage,
  });

  @override
  State<_CollectionsListScreen> createState() => _CollectionsListScreenState();
}

class _CollectionsListScreenState extends State<_CollectionsListScreen> {
  bool _loading = true;
  List<CollectionEntity> _collections = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await widget.loader();
      if (!mounted) return;
      setState(() => _collections = result);
    } catch (e) {
      debugPrint('CollectionsListScreen load failed: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(widget.icon, size: 18, color: widget.accentColor),
            const SizedBox(width: 8),
            Text(
              widget.title,
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            if (widget.trailing != null) ...[
              const Spacer(),
              Text(
                widget.trailing!,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ]
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _collections.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(widget.icon, size: 64, color: widget.accentColor.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text(
                        widget.emptyMessage ?? 'No collections found',
                        style: GoogleFonts.plusJakartaSans(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                  itemCount: _collections.length,
                  itemBuilder: (context, index) {
                    final c = _collections[index];
                    return CollectionListCard(
                      collection: c,
                      currentUserId: widget.currentUserId,
                      collaborationStyle: true,
                    );
                  },
                ),
    );
  }
}

class _BrowseCategoriesScreen extends StatelessWidget {
  final String currentUserId;
  final void Function(CategoryType) onCategoryTap;
  final Map<CategoryType, int> categoryCounts;

  const _BrowseCategoriesScreen({
    required this.currentUserId,
    required this.onCategoryTap,
    required this.categoryCounts,
  });

  @override
  Widget build(BuildContext context) {
    final categories = CategoryType.values.toList();

    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Browse categories',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            color: Colors.black,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: GridView.builder(
          itemCount: categories.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.4,
          ),
          itemBuilder: (context, index) {
            final category = categories[index];
            final count = categoryCounts[category] ?? 0;
            final color = AppColors.categoryLabelColor(category.name);

            return GestureDetector(
              onTap: () {
                onCategoryTap(category);
              },
              child: Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppColors.radiusCard),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 48, height: 48,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      child: CategoryPhosphorIcon(
                        category: category,
                        size: 22,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(category.displayName, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text('$count items', style: GoogleFonts.plusJakartaSans(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

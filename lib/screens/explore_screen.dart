import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:provider/provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../models/category_type.dart';
import '../models/collection_entity.dart';
import '../models/user_entity.dart';
import '../providers/auth_provider.dart';
import '../widgets/collection_card.dart';
import '../widgets/collection_grid_card.dart';
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

      final allCollections = await _firestoreService.getPublicCollectionsList(limit: 200);

      final allPublic = await _firestoreService.getPublicCollectionsList(limit: 50);

      final trending = _computeTrending(allPublic, limit: 5);

      List<CollectionEntity> topLiked = [];
      try {
        topLiked = await _firestoreService.getTopLikedCollections(since: since, limit: 10);
      } catch (e) {
        debugPrint('Top liked query failed: $e');
      }

      if (topLiked.isEmpty) {
        topLiked = _filterBySince(allPublic, since)
          ..sort((a, b) => b.likes.compareTo(a.likes));
        if (topLiked.length > 10) topLiked = topLiked.take(10).toList();
      }
      
      if (mounted) {
        setState(() {
          _allPublicCollections = allCollections;
          _categoryCounts = _computeCategoryCounts(allCollections);
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
        final results = await _firestoreService.searchCollections(query);
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
          icon: Icons.local_fire_department,
          useCategoryCollectionCard: true,
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

  IconData _categoryIcon(CategoryType category) {
    switch (category) {
      case CategoryType.food:
        return Icons.restaurant;
      case CategoryType.finance:
        return Icons.attach_money;
      case CategoryType.wellness:
        return Icons.spa;
      case CategoryType.career:
        return Icons.work_outline;
      case CategoryType.home:
        return Icons.home_outlined;
      case CategoryType.travel:
        return Icons.flight_takeoff;
      case CategoryType.tech:
        return Icons.computer;
      case CategoryType.gaming:
        return Icons.sports_esports;
      case CategoryType.entertainment:
        return Icons.movie_outlined;
      case CategoryType.shopping:
        return Icons.shopping_bag_outlined;
      case CategoryType.style:
        return Icons.checkroom;
      case CategoryType.books:
        return Icons.menu_book;
      case CategoryType.growth:
        return Icons.trending_up;
      case CategoryType.projects:
        return Icons.build;
      case CategoryType.creativity:
        return Icons.brush;
      case CategoryType.sports:
        return Icons.sports_soccer;
      case CategoryType.other:
        return Icons.category_outlined;
    }
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

  void _navigateToCategory(CategoryType category) async {
    final collections = await _firestoreService.getCollectionsByCategory(
      category.name,
      limit: 50,
    );
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => _CategoryCollectionsScreen(
            category: category,
            collections: collections,
            currentUserId: widget.currentUserId,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Title
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                child: const Text(
                  'Explore',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                    height: 1.1,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
            // Search bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: 'Find topics, people, or trends...',
                    hintStyle: TextStyle(color: Colors.grey[400]),
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
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
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: const BorderSide(color: AppColors.primaryPurple, width: 2),
                    ),
                  ),
                   onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) => _performSearch(value),
                ),
              ),
            ),

            // Search Tabs (visible only when searching)
            if (_searchQuery.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
              _buildSectionHeader('Browse', onViewAll: _navigateToBrowseCategories),
              _buildCategoryGrid(),

              // Trending Now
              _buildSectionHeader('Trending now', icon: Icons.local_fire_department, onViewAll: _navigateToTrendingViewAll),
              _buildTrendingCarousel(),

              // Top Liked
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                  child: Row(
                    children: [
                      Icon(Icons.favorite, size: 20, color: AppColors.primaryPurple),
                      const SizedBox(width: 8),
                      const Text(
                        'Top liked',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
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
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _topLikedRangeLabel(_topLikedRange),
                                style: const TextStyle(
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

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, {IconData? icon, required VoidCallback onViewAll}) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: AppColors.primaryPurple),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onViewAll,
              child: const Text(
                'View All',
                style: TextStyle(
                  color: AppColors.primaryPurple,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.85,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= categories.length) return null;
            final category = categories[index];
            final count = _categoryCounts[category] ?? 0;
            return _buildCategoryPill(category, count);
          },
          childCount: categories.length,
        ),
      ),
    );
  }

  Widget _buildCategoryPill(CategoryType category, int count) {
    final gradientColors = AppColors.categoryGradients[category.name] ?? 
        AppColors.categoryGradients['other']!;

    return GestureDetector(
      onTap: () => _navigateToCategory(category),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.25),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    _categoryIcon(category),
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      category.displayName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count items',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
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
        height: 240,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _trendingCollections.length,
          itemBuilder: (context, index) {
            final collection = _trendingCollections[index];
            return Padding(
              padding: const EdgeInsets.only(right: 16),
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
        width: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background
              FutureBuilder<String?>(
                future: resolveCoverUrl(),
                builder: (context, snap) {
                  final url = snap.data;
                  if (url == null || url.isEmpty) {
                    return Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          _categoryIcon(collection.category),
                          size: 48,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    );
                  }
                  return CachedNetworkImage(
                    imageUrl: url,
                    fit: BoxFit.cover,
                    placeholder: (context, _) => Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    errorWidget: (context, u, error) {
                      debugPrint('Trending cover image failed: $u, error: $error');
                      return Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: gradientColors,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          _categoryIcon(collection.category),
                          size: 48,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      );
                    },
                  );
                },
              ),
              
              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.82),
                    ],
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        collection.category.displayName.toUpperCase(),
                        style: TextStyle(
                          color: gradientColors[0],
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      collection.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        shadows: [
                          Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2)),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (collection.description != null && collection.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        collection.description!.trim(),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2)),
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.favorite, size: 14, color: AppColors.heartSalmon),
                              const SizedBox(width: 6),
                              Text(
                                '${collection.likes} likes',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
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
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final count = _topLikedCollections.length > 5 ? 5 : _topLikedCollections.length;
    if (count == 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: List.generate(count, (index) {
              final collection = _topLikedCollections[index];
              return _buildTopLikedRow(index + 1, collection, isLast: index == count - 1);
            }),
          ),
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
    return const Color(0xFFE5E7EB);
  }

  Widget _buildTopLikedRow(int rank, CollectionEntity collection, {required bool isLast}) {
    final rankColor = _topLikedRankColor(rank);
    final subtitleParts = <String>[
      collection.category.displayName,
      '${collection.itemCount} items',
    ];
    if (collection.isOpenForContribution) {
      subtitleParts.add('OPEN');
    }
    final subtitle = subtitleParts.join(' • ');

    return GestureDetector(
      onTap: () => _navigateToCollection(collection.id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: isLast
              ? null
              : const Border(
                  bottom: BorderSide(color: Color(0xFFF1F5F9)),
                ),
        ),
        child: Row(
          children: [
            // Rank
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: rankColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  '#$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: rank <= 3 ? Colors.white : Colors.black87,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Likes pill
            Container(
              width: 46,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    '${collection.likes}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'LIKES',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey[600],
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryPurple : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryPurple : Colors.grey[300]!,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: FontWeight.w600,
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
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final user = _userResults[index];
            return ListTile(
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
              leading: SizedBox(
                width: 48,
                height: 48,
                child: ClipOval(
                  child: (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: user.avatarUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) {
                            return Container(
                              color: AppColors.primaryPurple.withOpacity(0.1),
                              alignment: Alignment.center,
                              child: Text(
                                user.userName.isNotEmpty
                                    ? user.userName[0].toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryPurple,
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          color: AppColors.primaryPurple.withOpacity(0.1),
                          alignment: Alignment.center,
                          child: Text(
                            user.userName.isNotEmpty
                                ? user.userName[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryPurple,
                            ),
                          ),
                        ),
                ),
              ),
              title: Text(
                '@${user.userName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: user.bio != null && user.bio!.isNotEmpty
                  ? Text(
                      user.bio!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : null,
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
      padding: const EdgeInsets.all(16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.86,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final collection = _searchResults[index];
            return CollectionGridCard(
              collection: collection,
              onTap: () => _navigateToCollection(collection.id),
              onUserTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => UserProfileScreen(
                      userId: collection.userId,
                      currentUserId: widget.currentUserId,
                    ),
                  ),
                );
              },
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
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  static IconData _iconForCategory(CategoryType category) {
    switch (category) {
      case CategoryType.food:
        return Icons.restaurant;
      case CategoryType.finance:
        return Icons.attach_money;
      case CategoryType.wellness:
        return Icons.spa;
      case CategoryType.career:
        return Icons.work_outline;
      case CategoryType.home:
        return Icons.home_outlined;
      case CategoryType.travel:
        return Icons.flight_takeoff;
      case CategoryType.tech:
        return Icons.computer;
      case CategoryType.gaming:
        return Icons.sports_esports;
      case CategoryType.entertainment:
        return Icons.movie_outlined;
      case CategoryType.shopping:
        return Icons.shopping_bag_outlined;
      case CategoryType.style:
        return Icons.checkroom;
      case CategoryType.books:
        return Icons.menu_book;
      case CategoryType.growth:
        return Icons.trending_up;
      case CategoryType.projects:
        return Icons.build;
      case CategoryType.creativity:
        return Icons.brush;
      case CategoryType.sports:
        return Icons.sports_soccer;
      case CategoryType.other:
        return Icons.category_outlined;
    }
  }
}

class _CollectionsListScreen extends StatefulWidget {
  final String title;
  final IconData icon;
  final String? trailing;
  final Future<List<CollectionEntity>> Function() loader;
  final String currentUserId;
  final bool useCategoryCollectionCard;

  const _CollectionsListScreen({
    required this.title,
    required this.icon,
    required this.loader,
    required this.currentUserId,
    this.trailing,
    this.useCategoryCollectionCard = false,
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

  void _navigateToCollection(BuildContext context, String collectionId) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Icon(widget.icon, size: 18, color: AppColors.primaryPurple),
            const SizedBox(width: 8),
            Text(
              widget.title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
            if (widget.trailing != null) ...[
              const Spacer(),
              Text(
                widget.trailing!,
                style: const TextStyle(
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
          : RefreshIndicator(
              onRefresh: _load,
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemCount: _collections.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.86,
                ),
                itemBuilder: (context, index) {
                  final c = _collections[index];
                  if (widget.useCategoryCollectionCard) {
                    return CollectionGridCard(
                      collection: c,
                      onTap: () => _navigateToCollection(context, c.id),
                      onUserTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(
                              userId: c.userId,
                              currentUserId: widget.currentUserId,
                            ),
                          ),
                        );
                      },
                    );
                  }
                  return CollectionCard(
                    collection: c,
                    onTap: () => _navigateToCollection(context, c.id),
                  );
                },
              ),
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

  static IconData _iconForCategory(CategoryType category) {
    switch (category) {
      case CategoryType.food:
        return Icons.restaurant;
      case CategoryType.finance:
        return Icons.attach_money;
      case CategoryType.wellness:
        return Icons.spa;
      case CategoryType.career:
        return Icons.work_outline;
      case CategoryType.home:
        return Icons.home_outlined;
      case CategoryType.travel:
        return Icons.flight_takeoff;
      case CategoryType.tech:
        return Icons.computer;
      case CategoryType.gaming:
        return Icons.sports_esports;
      case CategoryType.entertainment:
        return Icons.movie_outlined;
      case CategoryType.shopping:
        return Icons.shopping_bag_outlined;
      case CategoryType.style:
        return Icons.checkroom;
      case CategoryType.books:
        return Icons.menu_book;
      case CategoryType.growth:
        return Icons.trending_up;
      case CategoryType.projects:
        return Icons.build;
      case CategoryType.creativity:
        return Icons.brush;
      case CategoryType.sports:
        return Icons.sports_soccer;
      case CategoryType.other:
        return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = CategoryType.values.where((c) => c != CategoryType.other).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Browse categories',
          style: TextStyle(
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
            childAspectRatio: 2.85,
          ),
          itemBuilder: (context, index) {
            final category = categories[index];
            final count = categoryCounts[category] ?? 0;
            final gradient = AppColors.categoryGradients[category.name] ??
                AppColors.categoryGradients['other']!;

            return GestureDetector(
              onTap: () {
                Navigator.pop(context);
                onCategoryTap(category);
              },
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(
                            _iconForCategory(category),
                            size: 18,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              category.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                                height: 1.1,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$count items',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Category collections screen
class _CategoryCollectionsScreen extends StatelessWidget {
  final CategoryType category;
  final List<CollectionEntity> collections;
  final String currentUserId;

  const _CategoryCollectionsScreen({
    required this.category,
    required this.collections,
    required this.currentUserId,
  });

  static IconData _iconForCategory(CategoryType category) {
    switch (category) {
      case CategoryType.food:
        return Icons.restaurant;
      case CategoryType.finance:
        return Icons.attach_money;
      case CategoryType.wellness:
        return Icons.spa;
      case CategoryType.career:
        return Icons.work_outline;
      case CategoryType.home:
        return Icons.home_outlined;
      case CategoryType.travel:
        return Icons.flight_takeoff;
      case CategoryType.tech:
        return Icons.computer;
      case CategoryType.gaming:
        return Icons.sports_esports;
      case CategoryType.entertainment:
        return Icons.movie_outlined;
      case CategoryType.shopping:
        return Icons.shopping_bag_outlined;
      case CategoryType.style:
        return Icons.checkroom;
      case CategoryType.books:
        return Icons.menu_book;
      case CategoryType.growth:
        return Icons.trending_up;
      case CategoryType.projects:
        return Icons.build;
      case CategoryType.creativity:
        return Icons.brush;
      case CategoryType.sports:
        return Icons.sports_soccer;
      case CategoryType.other:
        return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(category.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
      ),
      backgroundColor: const Color(0xFFF6F7FB),
      body: collections.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_iconForCategory(category), size: 64, color: AppColors.primaryPurple),
                  const SizedBox(height: 16),
                  Text(
                    'No collections in ${category.displayName} yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                  onUserTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => UserProfileScreen(
                          userId: collection.userId,
                          currentUserId: currentUserId,
                        ),
                      ),
                    );
                  },
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CollectionDetailScreen(
                          collectionId: collection.id,
                          currentUserId: currentUserId,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _CategoryCollectionCard extends StatelessWidget {
  final CollectionEntity collection;
  final VoidCallback onTap;
  final VoidCallback? onUserTap;

  const _CategoryCollectionCard({required this.collection, required this.onTap, this.onUserTap});

  Future<String?> _resolveCoverUrl() async {
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
      } catch (_) {
        return null;
      }
    }
    return candidate;
  }

  IconData _categoryIcon(CategoryType category) {
    switch (category) {
      case CategoryType.food:
        return Icons.restaurant;
      case CategoryType.finance:
        return Icons.attach_money;
      case CategoryType.wellness:
        return Icons.spa;
      case CategoryType.career:
        return Icons.work_outline;
      case CategoryType.home:
        return Icons.home_outlined;
      case CategoryType.travel:
        return Icons.flight_takeoff;
      case CategoryType.tech:
        return Icons.computer;
      case CategoryType.gaming:
        return Icons.sports_esports;
      case CategoryType.entertainment:
        return Icons.movie_outlined;
      case CategoryType.shopping:
        return Icons.shopping_bag_outlined;
      case CategoryType.style:
        return Icons.checkroom;
      case CategoryType.books:
        return Icons.menu_book;
      case CategoryType.growth:
        return Icons.trending_up;
      case CategoryType.projects:
        return Icons.build;
      case CategoryType.creativity:
        return Icons.brush;
      case CategoryType.sports:
        return Icons.sports_soccer;
      case CategoryType.other:
        return Icons.category_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = AppColors.categoryGradients[collection.category.name] ??
        AppColors.categoryGradients['other']!;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FutureBuilder<String?>(
                future: _resolveCoverUrl(),
                builder: (context, snap) {
                  final url = snap.data;
                  if (url == null || url.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 8,
                        child: CachedNetworkImage(
                          imageUrl: url,
                          fit: BoxFit.cover,
                          placeholder: (context, _) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: gradientColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                          ),
                          errorWidget: (context, _, __) => Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: gradientColors,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              _categoryIcon(collection.category),
                              size: 44,
                              color: Colors.white.withOpacity(0.9),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            collection.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                              height: 1.15,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (collection.coverImageUrl == null || collection.coverImageUrl!.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4D7E7),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.favorite, size: 14, color: Color(0xFFE11D48)),
                                const SizedBox(width: 6),
                                Text(
                                  '${collection.likes}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: onUserTap,
                      child: Text(
                        'by @${collection.userName}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    if (collection.description != null && collection.description!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        collection.description!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: gradientColors[0].withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            collection.category.displayName.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: gradientColors[0],
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${collection.itemCount} items',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

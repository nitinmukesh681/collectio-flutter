import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/collection_entity.dart';
import '../models/category_type.dart';
import '../models/user_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_card.dart';
import 'collection_detail_screen.dart';
import 'user_profile_screen.dart';
import 'dart:async';

enum _SearchTab { collections, people }

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
  
  List<CollectionEntity> _trendingCollections = [];
  List<CollectionEntity> _topLikedCollections = [];
  bool _isLoading = true;
  bool _isSearchLoading = false;

  @override
  void initState() {
    super.initState();
    _loadData();
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
      // Try to get trending collections (requires composite index)
      List<CollectionEntity> trending = [];
      List<CollectionEntity> topLiked = [];
      
      try {
        trending = await _firestoreService.getTrendingCollections(limit: 5);
        topLiked = await _firestoreService.getTrendingCollections(limit: 10);
      } catch (e) {
        // Fallback: Get public collections if index is missing
        debugPrint('Trending query failed (likely missing index): $e');
        final fallback = await _firestoreService.getPublicCollectionsList(limit: 10);
        trending = fallback.take(5).toList();
        topLiked = fallback;
      }
      
      setState(() {
        _trendingCollections = trending;
        _topLikedCollections = topLiked;
      });
    } catch (e) {
      debugPrint('Error loading explore data: $e');
    }
    setState(() => _isLoading = false);
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
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Search bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  decoration: InputDecoration(
                    hintText: 'Search collections or @users',
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
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
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
              _buildSectionHeader('Browse', onViewAll: () {}),
              _buildCategoryGrid(),

              // Trending Now
              _buildSectionHeader('Trending now', icon: Icons.local_fire_department, onViewAll: () {}),
              _buildTrendingCarousel(),

              // Top Liked
              _buildSectionHeader('Top liked', icon: Icons.favorite, onViewAll: () {}),
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
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20, color: AppColors.primaryPurple),
              const SizedBox(width: 8),
            ],
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: onViewAll,
              child: const Text('View all'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryGrid() {
    final categories = CategoryType.values.where((c) => c != CategoryType.other).toList();
    
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 2.5,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= categories.length) return null;
            final category = categories[index];
            return _buildCategoryPill(category);
          },
          childCount: categories.length > 8 ? 8 : categories.length,
        ),
      ),
    );
  }

  Widget _buildCategoryPill(CategoryType category) {
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
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            Positioned(
              right: 8,
              bottom: 8,
              child: Text(
                category.emoji,
                style: const TextStyle(fontSize: 32),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    category.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
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

  Widget _buildTrendingCarousel() {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: SizedBox(
          height: 210,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return SliverToBoxAdapter(
      child: SizedBox(
        height: 210,
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

    return GestureDetector(
      onTap: () => _navigateToCollection(collection.id),
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Background
              collection.coverImageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: collection.coverImageUrl!,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: gradientColors,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          collection.category.emoji,
                          style: const TextStyle(fontSize: 48),
                        ),
                      ),
                    ),
              
              // Gradient overlay
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.7),
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
                    // Category chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${collection.category.emoji} ${collection.category.displayName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Title
                    Text(
                      collection.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    // Stats
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.white.withOpacity(0.3),
                          child: Text(
                            collection.userName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          collection.userName,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.favorite, color: AppColors.heartSalmon, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${collection.likes}',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
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

  Widget _buildTopLikedList() {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            if (index >= _topLikedCollections.length) return null;
            final collection = _topLikedCollections[index];
            return _buildTopLikedRow(index + 1, collection);
          },
          childCount: _topLikedCollections.length > 5 ? 5 : _topLikedCollections.length,
        ),
      ),
    );
  }

  Widget _buildTopLikedRow(int rank, CollectionEntity collection) {
    return GestureDetector(
      onTap: () => _navigateToCollection(collection.id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Rank
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: rank <= 3 
                    ? AppColors.primaryPurple.withOpacity(0.1) 
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: rank <= 3 ? AppColors.primaryPurple : Colors.grey[600],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 56,
                height: 56,
                child: collection.coverImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: collection.coverImageUrl!,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: AppColors.categoryGradients[collection.category.name] ?? 
                                AppColors.categoryGradients['other']!,
                          ),
                        ),
                        child: Center(
                          child: Text(collection.category.emoji, style: const TextStyle(fontSize: 24)),
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
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${collection.userName}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            // Likes
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.heartSalmon.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite, size: 14, color: AppColors.heartSalmon),
                  const SizedBox(width: 4),
                  Text(
                    '${collection.likes}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.heartSalmon,
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
            return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
                color: Colors.white,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(12),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.primaryPurple.withOpacity(0.1),
                    backgroundImage: user.avatarUrl != null 
                        ? CachedNetworkImageProvider(user.avatarUrl!) 
                        : null,
                    child: user.avatarUrl == null
                        ? Text(
                            user.userName[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.primaryPurple,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  title: Text(
                    user.userName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text('@${user.userName}'),
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
      padding: const EdgeInsets.all(16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final collection = _searchResults[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: CollectionCard(
                collection: collection,
                onTap: () => _navigateToCollection(collection.id),
              ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${category.emoji} ${category.displayName}'),
      ),
      body: collections.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(category.emoji, style: const TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  Text(
                    'No collections in ${category.displayName} yet',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: collections.length,
              itemBuilder: (context, index) {
                final collection = collections[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: CollectionCard(
                    collection: collection,
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
                  ),
                );
              },
            ),
    );
  }
}

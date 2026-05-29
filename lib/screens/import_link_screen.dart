import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import '../models/collection_entity.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/link_import_defaults.dart';
import '../utils/link_title_utils.dart';
import '../utils/snackbar_utils.dart';
import 'collection_detail_screen.dart';
import 'create_collection_screen.dart';

/// Screen for handling shared URLs/links and adding them to collections.
class ImportLinkScreen extends StatefulWidget {
  final String sharedUrl;
  final String? sharedTitle;
  final String userId;
  final String userName;

  const ImportLinkScreen({
    super.key,
    required this.sharedUrl,
    this.sharedTitle,
    required this.userId,
    required this.userName,
  });

  @override
  State<ImportLinkScreen> createState() => _ImportLinkScreenState();
}

class _ImportLinkScreenState extends State<ImportLinkScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  List<CollectionEntity> _userCollections = [];
  Set<String> _selectedCollectionIds = {};
  String _searchQuery = '';
  bool _collectionsLoading = true;
  bool _isCreatingItem = false;
  StreamSubscription<List<CollectionEntity>>? _collectionsSubscription;

  @override
  void initState() {
    super.initState();
    _checkIfCollectionUrl();
    _loadUserCollections();
    _titleController.text = LinkTitleUtils.resolveItemTitle(
      sharedTitle: widget.sharedTitle,
      url: widget.sharedUrl,
    );
    _descriptionController.text = LinkImportDefaults.randomDescription();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim().toLowerCase());
    });
    _titleController.addListener(() => setState(() {}));
  }

  void _checkIfCollectionUrl() {
    final collectionId = _extractCollectionId(widget.sharedUrl);
    if (collectionId == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => CollectionDetailScreen(
            collectionId: collectionId,
            currentUserId: widget.userId,
          ),
        ),
      );
    });
  }

  String? _extractCollectionId(String url) {
    try {
      final uri = Uri.parse(url);
      if (uri.host.contains('collectio-b6b15.web.app') ||
          uri.host.contains('collectio') ||
          uri.host == 'localhost') {
        final pathSegments = uri.pathSegments;
        if (pathSegments.length >= 2 && pathSegments[0] == 'collection') {
          return pathSegments[1];
        }
      }
    } catch (e) {
      debugPrint('Error parsing collection URL: $e');
    }
    return null;
  }

  List<CollectionEntity> get _filteredCollections {
    if (_searchQuery.isEmpty) return _userCollections;
    return _userCollections
        .where((c) => c.title.toLowerCase().contains(_searchQuery))
        .toList();
  }

  String _resolvedUserName(BuildContext context) {
    final fromAuth = context.read<AuthProvider>().resolvedUserName.trim();
    if (fromAuth.isNotEmpty) return fromAuth;
    final fromWidget = widget.userName.trim();
    if (fromWidget.isNotEmpty) return fromWidget;
    return 'User';
  }

  String? _resolvedUserAvatarUrl(BuildContext context) {
    return context.read<AuthProvider>().userEntity?.avatarUrl;
  }

  @override
  void dispose() {
    _collectionsSubscription?.cancel();
    _titleController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUserCollections() async {
    try {
      final collections =
          await _firestoreService.getUserCollectionsList(widget.userId);
      if (mounted) {
        setState(() {
          _userCollections = collections;
          _collectionsLoading = false;
        });
      }
    } catch (error) {
      debugPrint('[ImportLink] Error loading collections: $error');
      if (mounted) setState(() => _collectionsLoading = false);
    }

    _listenToUserCollections();
  }

  void _listenToUserCollections() {
    _collectionsSubscription?.cancel();
    _collectionsSubscription =
        _firestoreService.getUserCollectionsStream(widget.userId).listen(
      (collections) {
        if (mounted) {
          setState(() {
            _userCollections = collections;
            _collectionsLoading = false;
          });
        }
      },
      onError: (error) {
        debugPrint('[ImportLink] Error loading collections: $error');
        if (mounted) setState(() => _collectionsLoading = false);
      },
    );
  }

  Future<void> _refreshUserCollections() async {
    final showLoading = _userCollections.isEmpty;
    if (showLoading) setState(() => _collectionsLoading = true);
    try {
      final collections =
          await _firestoreService.getUserCollectionsList(widget.userId);
      if (mounted) {
        setState(() {
          _userCollections = collections;
          _collectionsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('[ImportLink] Error refreshing collections: $e');
      if (mounted) setState(() => _collectionsLoading = false);
    }
  }

  Future<void> _createNewCollection() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCollectionScreen(
          userId: widget.userId,
          userName: _resolvedUserName(context),
          userAvatarUrl: _resolvedUserAvatarUrl(context),
        ),
      ),
    );

    if (created == true && mounted) {
      await _refreshUserCollections();
      setState(_selectedCollectionIds.clear);
    }
  }

  void _toggleCollectionSelected(String collectionId) {
    setState(() {
      if (_selectedCollectionIds.contains(collectionId)) {
        _selectedCollectionIds.remove(collectionId);
      } else {
        _selectedCollectionIds.add(collectionId);
      }
    });
  }

  Future<void> _createLinkItems() async {
    if (_selectedCollectionIds.isEmpty) return;

    final title = _titleController.text.trim();
    if (title.isEmpty) {
      SnackBarUtils.showErrorSnackBar(context, 'Could not determine a link title');
      return;
    }

    setState(() => _isCreatingItem = true);
    var addedCount = 0;
    final userName = _resolvedUserName(context);

    try {
      await Future.wait(
        _selectedCollectionIds.map(
          (collectionId) => _firestoreService.addLinkItem(
            collectionId: collectionId,
            userId: widget.userId,
            userName: userName,
            title: title,
            websiteUrl: widget.sharedUrl,
            description: _descriptionController.text.trim(),
          ),
        ),
      );
      addedCount = _selectedCollectionIds.length;

      if (mounted) {
        SnackBarUtils.showSuccessSnackBar(
          context,
          'Added to $addedCount collection${addedCount > 1 ? 's' : ''}',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtils.showErrorSnackBar(context, 'Error: $e');
      }
    }

    if (mounted) setState(() => _isCreatingItem = false);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _selectedCollectionIds.length;
    final hasTitle = _titleController.text.trim().isNotEmpty;
    final canContinue = selectedCount > 0 && hasTitle && !_isCreatingItem;

    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Save Link',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            fontSize: 18,
          ),
        ),
        centerTitle: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _buildSharedLinkCard(),
                const SizedBox(height: 16),
                      _buildTitleField(),
                      const SizedBox(height: 16),
                      _buildDescriptionField(),
                      const SizedBox(height: 16),
                      _buildSearchField(),
                const SizedBox(height: 20),
                _buildSectionHeader(),
                const SizedBox(height: 12),
                ..._buildCollectionRows(),
              ],
            ),
          ),
          _buildContinueButton(canContinue, selectedCount),
        ],
      ),
    );
  }

  Widget _buildSharedLinkCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.cardShadow,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.link_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SHARED LINK',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.sharedUrl,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabeledField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    int maxLines = 1,
    TextCapitalization textCapitalization = TextCapitalization.sentences,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          textCapitalization: textCapitalization,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: GoogleFonts.plusJakartaSans(
              color: AppColors.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w500,
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTitleField() {
    return _buildLabeledField(
      label: 'ITEM TITLE',
      controller: _titleController,
      hintText: 'Enter a title for this link',
    );
  }

  Widget _buildDescriptionField() {
    return _buildLabeledField(
      label: 'DESCRIPTION',
      controller: _descriptionController,
      hintText: 'Add a note about this link',
      maxLines: 2,
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 15,
        color: AppColors.textPrimary,
      ),
      decoration: InputDecoration(
        hintText: 'Search your collections...',
        hintStyle: GoogleFonts.plusJakartaSans(
          color: AppColors.textMuted,
          fontSize: 15,
        ),
        prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 22),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'YOUR COLLECTIONS',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        TextButton(
          onPressed: _isCreatingItem ? null : _createNewCollection,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            '+ Create New',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildCollectionRows() {
    if (_collectionsLoading && _userCollections.isEmpty) {
      return List.generate(4, (_) => const _ImportCollectionRowSkeleton());
    }

    final collections = _filteredCollections;

    if (!_collectionsLoading && _userCollections.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Column(
            children: [
              const Icon(Icons.folder_off_outlined,
                  size: 48, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text(
                'No collections yet',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _createNewCollection,
                child: const Text('Create your first collection'),
              ),
            ],
          ),
        ),
      ];
    }

    if (collections.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No collections match your search',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(color: AppColors.textMuted),
          ),
        ),
      ];
    }

    return collections
        .map(
          (collection) => _ImportCollectionRow(
            collection: collection,
            isSelected: _selectedCollectionIds.contains(collection.id),
            onTap: () => _toggleCollectionSelected(collection.id),
          ),
        )
        .toList();
  }

  Widget _buildContinueButton(bool canContinue, int selectedCount) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: canContinue ? _createLinkItems : null,
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  canContinue ? AppColors.primary : AppColors.surfaceMuted,
              foregroundColor:
                  canContinue ? Colors.white : AppColors.textMuted,
              disabledBackgroundColor: AppColors.surfaceMuted,
              disabledForegroundColor: AppColors.textMuted,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(26),
              ),
            ),
            child: _isCreatingItem
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'Continue ($selectedCount selected)',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _ImportCollectionRow extends StatelessWidget {
  final CollectionEntity collection;
  final bool isSelected;
  final VoidCallback onTap;

  const _ImportCollectionRow({
    required this.collection,
    required this.isSelected,
    required this.onTap,
  });

  Widget _buildThumb(List<Color> gradientColors) {
    final candidate = (collection.coverImageUrl != null &&
            collection.coverImageUrl!.isNotEmpty)
        ? collection.coverImageUrl!.trim()
        : (collection.previewImageUrls.isNotEmpty
            ? collection.previewImageUrls.first.trim()
            : '');

    if (candidate.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: candidate,
        fit: BoxFit.cover,
        memCacheWidth: 156,
        placeholder: (_, __) => _gradientThumb(gradientColors),
        errorWidget: (_, __, ___) => _gradientThumb(gradientColors),
      );
    }

    return _gradientThumb(gradientColors);
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = AppColors.categoryGradients[collection.category.name] ??
        AppColors.categoryGradients['other']!;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? AppColors.primary : AppColors.divider,
                width: isSelected ? 1.5 : 1,
              ),
              boxShadow: AppColors.cardShadow,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onTap(),
                    activeColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.textMuted, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        collection.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${collection.itemCount} item${collection.itemCount == 1 ? '' : 's'}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 52,
                    height: 52,
                    child: _buildThumb(gradientColors),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gradientThumb(List<Color> colors) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
    );
  }
}

class _ImportCollectionRowSkeleton extends StatelessWidget {
  const _ImportCollectionRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.divider),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 14,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 72,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

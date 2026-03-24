import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_utils.dart';
import '../services/firestore_service.dart';
import '../models/collection_entity.dart';
import 'create_collection_screen.dart';
import 'collection_detail_screen.dart';

/// Screen for handling shared URLs/links and adding them to collections
class ImportLinkScreen extends StatefulWidget {
  final String sharedUrl;
  final String userId;
  final String userName;

  const ImportLinkScreen({
    super.key,
    required this.sharedUrl,
    required this.userId,
    required this.userName,
  });

  @override
  State<ImportLinkScreen> createState() => _ImportLinkScreenState();
}

enum _ImportStep { choose, selectCollection, enterTitle }

class _ImportLinkScreenState extends State<ImportLinkScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _titleController = TextEditingController();
  
  _ImportStep _currentStep = _ImportStep.choose;
  List<CollectionEntity> _userCollections = [];
  Set<String> _selectedCollectionIds = {};
  bool _isLoading = false;
  bool _isCreatingItem = false;

  @override
  void initState() {
    super.initState();
    debugPrint('[ImportLink:init] initState — sharedUrl=${widget.sharedUrl} userId=${widget.userId} userName=${widget.userName}');
    _checkIfCollectionUrl();
    _loadUserCollections();
    _titleController.text = _extractTitleFromUrl(widget.sharedUrl);
    debugPrint('[ImportLink:init] pre-filled title: ${_titleController.text}');
  }

  void _checkIfCollectionUrl() {
    debugPrint('[ImportLink:check] _checkIfCollectionUrl — url=${widget.sharedUrl}');
    final collectionId = _extractCollectionId(widget.sharedUrl);
    debugPrint('[ImportLink:check] extractedCollectionId=$collectionId');
    if (collectionId != null) {
      debugPrint('[ImportLink:check] detected internal collection URL — will redirect to CollectionDetailScreen');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          debugPrint('[ImportLink:check] redirecting to CollectionDetailScreen collectionId=$collectionId');
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => CollectionDetailScreen(
                collectionId: collectionId,
                currentUserId: widget.userId,
              ),
            ),
          );
        } else {
          debugPrint('[ImportLink:check] unmounted before redirect could happen');
        }
      });
    } else {
      debugPrint('[ImportLink:check] external URL — staying on ImportLinkScreen');
    }
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

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  String _extractTitleFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host.replaceFirst('www.', '');
    } catch (_) {
      return 'Shared Link';
    }
  }

  Future<void> _loadUserCollections() async {
    debugPrint('[ImportLink:load] _loadUserCollections — userId=${widget.userId}');
    setState(() => _isLoading = true);
    try {
      final collections = await _firestoreService.getUserCollectionsList(widget.userId);
      debugPrint('[ImportLink:load] loaded ${collections.length} collections: ${collections.map((c) => c.title).toList()}');
      setState(() => _userCollections = collections);
    } catch (e) {
      debugPrint('[ImportLink:load] ERROR loading collections: $e');
    }
    setState(() => _isLoading = false);
    debugPrint('[ImportLink:load] done — _userCollections.length=${_userCollections.length}');
  }

  Future<void> _createNewCollection() async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => CreateCollectionScreen(
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );

    if (created == true && mounted) {
      await _loadUserCollections();
      setState(() {
        _currentStep = _ImportStep.selectCollection;
        _selectedCollectionIds.clear();
      });
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
    debugPrint('[ImportLink:save] _createLinkItems — selectedIds=$_selectedCollectionIds title=${_titleController.text.trim()} url=${widget.sharedUrl}');
    if (_selectedCollectionIds.isEmpty) {
      debugPrint('[ImportLink:save] no collections selected');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one collection')),
      );
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      debugPrint('[ImportLink:save] title is empty');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    setState(() => _isCreatingItem = true);
    int addedCount = 0;

    try {
      for (final collectionId in _selectedCollectionIds) {
        debugPrint('[ImportLink:save] adding to collectionId=$collectionId');
        await _firestoreService.addLinkItem(
          collectionId: collectionId,
          userId: widget.userId,
          userName: widget.userName,
          title: _titleController.text.trim(),
          websiteUrl: widget.sharedUrl,
        );
        addedCount++;
        debugPrint('[ImportLink:save] added to collectionId=$collectionId (total=$addedCount)');
      }
      debugPrint('[ImportLink:save] all done — added to $addedCount collection(s)');

      if (mounted) {
        SnackBarUtils.showSuccessSnackBar(
          context,
          'Added to $addedCount collection${addedCount > 1 ? 's' : ''}',
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('[ImportLink:save] ERROR: $e');
      if (mounted) {
        SnackBarUtils.showErrorSnackBar(context, 'Error: $e');
      }
    }

    setState(() => _isCreatingItem = false);
  }

  void _handleBack() {
    switch (_currentStep) {
      case _ImportStep.choose:
        Navigator.pop(context);
        break;
      case _ImportStep.selectCollection:
        setState(() {
          _currentStep = _ImportStep.choose;
          _selectedCollectionIds.clear();
        });
        break;
      case _ImportStep.enterTitle:
        setState(() => _currentStep = _ImportStep.selectCollection);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
        ),
        title: const Text('Add to Collection'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shared URL card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Shared Link',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),                  const SizedBox(height: 6),
                  Text(
                    widget.sharedUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Step content
            Expanded(child: _buildStepContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case _ImportStep.choose:
        return _buildChooseStep();
      case _ImportStep.selectCollection:
        return _buildSelectCollectionStep();
      case _ImportStep.enterTitle:
        return _buildEnterTitleStep();
    }
  }

  Widget _buildChooseStep() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: () {
            // Navigate to create new collection, then come back
            // For simplicity, we'll go straight to existing collections
            setState(() => _currentStep = _ImportStep.selectCollection);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Add to existing collection', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _createNewCollection,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Add to new collection'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: () {
            // For simplicity, just select first collection if any
            if (_userCollections.isNotEmpty) {
              _toggleCollectionSelected(_userCollections.first.id);
              setState(() => _currentStep = _ImportStep.enterTitle);
            }
          },
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Quick add to latest collection'),
        ),
      ],
    );
  }

  Widget _buildSelectCollectionStep() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_userCollections.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_off, size: 64, color: AppColors.textMuted),
            const SizedBox(height: 16),
            const Text('No collections yet'),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Create one first'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Select collections', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: _selectedCollectionIds.isNotEmpty
              ? () => setState(() => _currentStep = _ImportStep.enterTitle)
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(46),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: Text('Continue (${_selectedCollectionIds.length} selected)'),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: _userCollections.length,
            itemBuilder: (context, index) {
              final collection = _userCollections[index];
              final isSelected = _selectedCollectionIds.contains(collection.id);
              
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Checkbox(
                    value: isSelected,
                    onChanged: (_) => _toggleCollectionSelected(collection.id),
                    activeColor: AppColors.primaryPurple,
                  ),
                  title: Text(collection.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${collection.itemCount} items'),
                  onTap: () => _toggleCollectionSelected(collection.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEnterTitleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Item Title', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            hintText: 'Enter a title for this link',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _isCreatingItem ? null : _createLinkItems,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryPurple,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _isCreatingItem
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(
                  _selectedCollectionIds.length <= 1 
                      ? 'Add' 
                      : 'Add to ${_selectedCollectionIds.length} collections',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _isCreatingItem ? null : _handleBack,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: const Text('Back'),
        ),
      ],
    );
  }
}

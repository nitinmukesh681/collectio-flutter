import 'package:flutter/material.dart';
import '../models/collection_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import 'create_collection_screen.dart';

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
    _loadUserCollections();
    // Pre-fill title from URL domain
    _titleController.text = _extractTitleFromUrl(widget.sharedUrl);
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
    setState(() => _isLoading = true);
    try {
      final collections = await _firestoreService.getUserCollectionsList(widget.userId);
      setState(() => _userCollections = collections);
    } catch (e) {
      debugPrint('Error loading collections: $e');
    }
    setState(() => _isLoading = false);
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
    if (_selectedCollectionIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one collection')),
      );
      return;
    }

    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }

    setState(() => _isCreatingItem = true);
    int addedCount = 0;

    try {
      for (final collectionId in _selectedCollectionIds) {
        await _firestoreService.addLinkItem(
          collectionId: collectionId,
          userId: widget.userId,
          userName: widget.userName,
          title: _titleController.text.trim(),
          websiteUrl: widget.sharedUrl,
        );
        addedCount++;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added to $addedCount collection(s)')),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error creating link items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
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

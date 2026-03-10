import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../models/collection_entity.dart';
import '../models/category_type.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../widgets/unsplash_search_dialog.dart';


class CreateCollectionScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final CollectionEntity? existingCollection; // For editing

  const CreateCollectionScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    this.existingCollection,
  });

  @override
  State<CreateCollectionScreen> createState() => _CreateCollectionScreenState();
}

class _CreateCollectionScreenState extends State<CreateCollectionScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  
  CategoryType _selectedCategory = CategoryType.other;
  List<String> _tags = [];
  bool _isPublic = true;
  bool _isOpenForContribution = false;
  File? _coverImage;
  String? _selectedUnsplashUrl; // New state variable for Unsplash image
  bool _isLoading = false;

  bool get _isEditing => widget.existingCollection != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final collection = widget.existingCollection!;
      _titleController.text = collection.title;
      _descriptionController.text = collection.description ?? '';
      _selectedCategory = collection.category;
      _tags = List.from(collection.tags);
      _isPublic = collection.isPublic;
      _isOpenForContribution = collection.isOpenForContribution;
      // If editing, and there's an existing cover image, check if it's an Unsplash URL
      if (collection.coverImageUrl != null) {
        final raw = collection.coverImageUrl!.trim();
        if (raw.startsWith('gs://')) {
          FirebaseStorage.instance.refFromURL(raw).getDownloadURL().then((url) {
            if (!mounted) return;
            setState(() => _selectedUnsplashUrl = url);
          }).catchError((_) {
            // ignore
          });
        } else if (raw.isNotEmpty) {
          _selectedUnsplashUrl = raw;
        }
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _coverImage = File(pickedFile.path);
        _selectedUnsplashUrl = null; // Clear Unsplash selection if local image is picked
      });
    }
  }

  void _addTag() {
    final tag = _tagController.text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      String? finalCoverImageUrl;

      if (_coverImage != null) {
        // Upload local image
        finalCoverImageUrl = await _firestoreService.uploadImage(
          _coverImage!,
          'collections/${widget.userId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
      } else if (_selectedUnsplashUrl != null) {
        // Use Unsplash URL directly
        finalCoverImageUrl = _selectedUnsplashUrl;
      } else if (_isEditing && widget.existingCollection?.coverImageUrl != null) {
        // If editing and no new image selected, retain existing image URL
        finalCoverImageUrl = widget.existingCollection!.coverImageUrl;
      }

      if (_isEditing) {
        // Update existing collection
        final updated = widget.existingCollection!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          category: _selectedCategory,
          tags: _tags,
          isPublic: _isPublic,
          isOpenForContribution: _isOpenForContribution,
          coverImageUrl: finalCoverImageUrl,
        );
        await _firestoreService.updateCollection(updated);
      } else {
        // Create new collection
        final collection = CollectionEntity(
          id: '',
          userId: widget.userId,
          userName: widget.userName,
          userAvatarUrl: widget.userAvatarUrl,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          category: _selectedCategory,
          tags: _tags,
          coverImageUrl: finalCoverImageUrl,
          isPublic: _isPublic,
          isOpenForContribution: _isOpenForContribution,
        );
        await _firestoreService.createCollection(collection);
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving collection: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Collection' : 'New Collection',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _save,
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _isEditing ? 'Save' : 'Create',
                    style: const TextStyle(
                      color: AppColors.primaryPurple,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Cover Image (Optional)',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Upload'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => UnsplashSearchDialog(
                          onImageSelected: (imageUrl, attribution) {
                            setState(() {
                              _coverImage = null;
                              _selectedUnsplashUrl = imageUrl;
                            });
                          },
                        ),
                      );
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: const Text('Unsplash'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                image: _coverImage != null
                    ? DecorationImage(
                        image: FileImage(_coverImage!),
                        fit: BoxFit.cover,
                      )
                    : _selectedUnsplashUrl != null
                        ? DecorationImage(
                            image: NetworkImage(_selectedUnsplashUrl!),
                            fit: BoxFit.cover,
                          )
                        : widget.existingCollection?.coverImageUrl != null
                            ? DecorationImage(
                                image: NetworkImage(widget.existingCollection!.coverImageUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
              ),
              child: _coverImage == null &&
                      _selectedUnsplashUrl == null &&
                      widget.existingCollection?.coverImageUrl == null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.image_outlined, size: 42, color: Colors.grey[400]),
                        const SizedBox(height: 8),
                        Text(
                          'No cover selected',
                          style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.w600),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            // Title
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Collection Name *',
                hintText: 'e.g., Summer Reading List',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a title';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description (Optional)',
                hintText: 'What is this collection about?',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Category
            const Text(
              'Category *',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: CategoryType.values.map((category) {
                final isSelected = _selectedCategory == category;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = category),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryPurple : Colors.grey[100],
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isSelected ? AppColors.primaryPurple : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          category.displayName,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // Tags
            const Text(
              'Tags',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: InputDecoration(
                      hintText: 'Add a tag',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primaryPurple,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: IconButton(
                    onPressed: _addTag,
                    icon: const Icon(Icons.add, color: Colors.white),
                  ),
                ),
              ],
            ),
            if (_tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _tags.map((tag) {
                  return Chip(
                    label: Text('#$tag'),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () => _removeTag(tag),
                    backgroundColor: AppColors.primaryPurple.withOpacity(0.1),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 24),

            // Visibility
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(_isPublic ? 'Public' : 'Private'),
                    subtitle: Text(
                      _isPublic
                          ? 'Anyone can see this collection'
                          : 'Only you can see this collection',
                    ),
                    value: _isPublic,
                    onChanged: (value) => setState(() => _isPublic = value),
                    activeColor: AppColors.primaryPurple,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const Divider(),
                  SwitchListTile(
                    title: const Text('Open for contribution'),
                    subtitle: const Text('Anyone can add items'),
                    value: _isOpenForContribution,
                    onChanged: _isPublic
                        ? (value) => setState(() => _isOpenForContribution = value)
                        : null,
                    activeColor: AppColors.primaryPurple,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class RoundedCornerShape extends RoundedRectangleBorder {
  RoundedCornerShape(double radius) : super(borderRadius: BorderRadius.circular(radius));
}

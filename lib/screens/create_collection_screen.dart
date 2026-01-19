import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
      if (collection.coverImageUrl != null && !collection.coverImageUrl!.startsWith('gs://')) {
        _selectedUnsplashUrl = collection.coverImageUrl;
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
        title: Text(_isEditing ? 'Edit Collection' : 'Create Collection'),
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
                      fontWeight: FontWeight.bold,
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
            // Cover image picker
            GestureDetector(
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  builder: (context) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.photo_library),
                        title: const Text('Gallery'),
                        onTap: () {
                          Navigator.pop(context);
                          _pickImage();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.search),
                        title: const Text('Unsplash'),
                        onTap: () {
                          Navigator.pop(context);
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
                      ),
                    ],
                  ),
                );
              },
              child: Container(
                height: 180,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey[300]!),
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
                child: _coverImage == null && _selectedUnsplashUrl == null && widget.existingCollection?.coverImageUrl == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined, size: 48, color: Colors.grey[400]),
                          const SizedBox(height: 8),
                          Text(
                            'Add cover image',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      )
                    : Align(
                        alignment: Alignment.bottomRight,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.edit, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 24),

            // Title
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: 'Give your collection a name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                labelText: 'Description',
                hintText: 'What is this collection about?',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Category
            const Text(
              'Category',
              style: TextStyle(fontWeight: FontWeight.w600),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryPurple : Colors.grey[100],
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected ? AppColors.primaryPurple : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(category.emoji),
                        const SizedBox(width: 6),
                        Text(
                          category.displayName,
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
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
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _tagController,
                    decoration: InputDecoration(
                      hintText: 'Add a tag',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onSubmitted: (_) => _addTag(),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _addTag,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryPurple,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedCornerShape(12),
                  ),
                  child: const Text('Add', style: TextStyle(color: Colors.white)),
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
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Public'),
                    subtitle: const Text('Anyone can see this collection'),
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

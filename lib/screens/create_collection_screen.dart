import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import '../models/collection_entity.dart';
import '../models/category_type.dart';
import '../models/place_prediction.dart';
import '../services/firestore_service.dart';
import '../services/places_service.dart';
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
  final PlacesService _placesService = PlacesService();
  final _formKey = GlobalKey<FormState>();
  
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _websiteUrlController = TextEditingController();
  final TextEditingController _googleMapsUrlController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  
  CategoryType _selectedCategory = CategoryType.other;
  List<String> _tags = [];
  bool _isPublic = true;
  bool _isOpenForContribution = false;
  File? _coverImage;
  String? _selectedUnsplashUrl; // New state variable for Unsplash image
  bool _isLoading = false;
  String? _selectedGoogleMapsUrl;

  bool get _isEditing => widget.existingCollection != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final collection = widget.existingCollection!;
      _titleController.text = collection.title;
      _descriptionController.text = collection.description ?? '';
      _websiteUrlController.text = collection.websiteUrl ?? '';
      if (collection.googleMapsUrl != null && collection.googleMapsUrl!.trim().isNotEmpty) {
        _selectedGoogleMapsUrl = collection.googleMapsUrl;
        final url = collection.googleMapsUrl!.trim();
        if (url.contains('query=')) {
          try {
            final query = Uri.parse(url).queryParameters['query'];
            _googleMapsUrlController.text = query ?? url;
          } catch (_) {
            _googleMapsUrlController.text = url;
          }
        } else {
          _googleMapsUrlController.text = url;
        }
      } else {
        _googleMapsUrlController.text = '';
      }
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
    _websiteUrlController.dispose();
    _googleMapsUrlController.dispose();
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

      String? finalizeMapsUrl() {
        final raw = _googleMapsUrlController.text.trim();
        if (raw.isEmpty) return null;
        if (raw.startsWith('http://') || raw.startsWith('https://')) return raw;
        if (_selectedGoogleMapsUrl != null && _selectedGoogleMapsUrl!.trim().isNotEmpty) {
          return _selectedGoogleMapsUrl!.trim();
        }
        final query = Uri.encodeComponent(raw);
        return 'https://www.google.com/maps/search/?api=1&query=$query';
      }

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
          websiteUrl: _websiteUrlController.text.trim().isEmpty
              ? null
              : _websiteUrlController.text.trim(),
          googleMapsUrl: finalizeMapsUrl(),
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
          websiteUrl: _websiteUrlController.text.trim().isEmpty
              ? null
              : _websiteUrlController.text.trim(),
          googleMapsUrl: finalizeMapsUrl(),
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
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPurple.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator.adaptive(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryPurple),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
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
                color: const Color(0xFFF8FAFC),
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
                        const Icon(Icons.image_outlined, size: 42, color: AppColors.textMuted),
                        const SizedBox(height: 8),
                        Text(
                          'No cover selected',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 24),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Collection name *',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
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
                  const Text(
                    'Description (Optional)',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      hintText: 'What is this collection about?',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Link (Optional)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _websiteUrlController,
                    decoration: const InputDecoration(
                      hintText: 'https://...',
                      prefixIcon: Icon(Icons.link),
                    ),
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Location (Optional)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  RawAutocomplete<PlacePrediction>(
                    textEditingController: _googleMapsUrlController,
                    focusNode: FocusNode(),
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      final q = textEditingValue.text.trim();
                      if (q.length < 2) return const Iterable<PlacePrediction>.empty();
                      if (q.startsWith('http://') || q.startsWith('https://')) {
                        return const Iterable<PlacePrediction>.empty();
                      }
                      return await _placesService.getAutocompletePredictions(q);
                    },
                    displayStringForOption: (PlacePrediction option) => option.description,
                    onSelected: (PlacePrediction selection) async {
                      _googleMapsUrlController.text = selection.description;
                      final url = await _placesService.getPlaceUrl(selection.placeId);
                      if (!mounted) return;
                      setState(() {
                        _selectedGoogleMapsUrl = url;
                      });
                    },
                    fieldViewBuilder: (
                      BuildContext context,
                      TextEditingController textEditingController,
                      FocusNode focusNode,
                      VoidCallback onFieldSubmitted,
                    ) {
                      return TextFormField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          hintText: 'Search for a place or paste URL',
                          prefixIcon: Icon(Icons.place_outlined),
                        ),
                        textInputAction: TextInputAction.next,
                        onChanged: (_) {
                          if (_selectedGoogleMapsUrl != null) {
                            setState(() => _selectedGoogleMapsUrl = null);
                          }
                        },
                      );
                    },
                    optionsViewBuilder: (
                      BuildContext context,
                      AutocompleteOnSelected<PlacePrediction> onSelected,
                      Iterable<PlacePrediction> options,
                    ) {
                      return Align(
                        alignment: Alignment.topLeft,
                        child: Material(
                          elevation: 10,
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 240, maxWidth: 360),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (context, index) {
                                final option = options.elementAt(index);
                                return ListTile(
                                  leading: const Icon(Icons.place, size: 20, color: AppColors.textMuted),
                                  title: Text(
                                    option.mainText,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: option.secondaryText.isNotEmpty
                                      ? Text(option.secondaryText)
                                      : null,
                                  onTap: () => onSelected(option),
                                );
                              },
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 22),
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
                            color: isSelected ? AppColors.primaryPurple : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: isSelected ? AppColors.primaryPurple : const Color(0xFFE5E7EB),
                            ),
                          ),
                          child: Text(
                            category.displayName,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black,
                              fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 22),
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
                          decoration: const InputDecoration(
                            hintText: 'Add a tag',
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  const SizedBox(height: 22),
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primaryPurple.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: AppColors.primaryPurple.withOpacity(0.14),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                _isPublic ? Icons.public : Icons.lock_outline,
                                size: 18,
                                color: AppColors.primaryPurple,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isPublic ? 'Public' : 'Private',
                                    style: const TextStyle(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isPublic
                                        ? 'Anyone can see this collection'
                                        : 'Only you can see this collection',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: _isPublic,
                              onChanged: (value) => setState(() => _isPublic = value),
                              activeColor: AppColors.primaryPurple,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Opacity(
                        opacity: _isPublic ? 1 : 0.45,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.group_add_outlined,
                                  size: 18,
                                  color: Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Open for contribution',
                                      style: TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Anyone can add items',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Switch.adaptive(
                                value: _isOpenForContribution,
                                onChanged: _isPublic
                                    ? (value) => setState(() => _isOpenForContribution = value)
                                    : null,
                                activeColor: AppColors.primaryPurple,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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

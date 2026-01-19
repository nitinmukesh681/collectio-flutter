import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'dart:io';
import '../widgets/unsplash_search_dialog.dart';
import 'package:http/http.dart' as http; // Determine if network image implies http

import '../models/collection_item_entity.dart';
import '../models/place_prediction.dart';
import '../services/firestore_service.dart';
import '../services/places_service.dart';
import '../theme/app_theme.dart';

class AddItemScreen extends StatefulWidget {
  final String collectionId;
  final String userId;
  final String userName;
  final CollectionItemEntity? existingItem; // For editing

  const AddItemScreen({
    super.key,
    required this.collectionId,
    required this.userId,
    required this.userName,
    this.existingItem,
  });

  @override
  State<AddItemScreen> createState() => _AddItemScreenState();
}

class _AddItemScreenState extends State<AddItemScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final PlacesService _placesService = PlacesService(); // Initialize service
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _mapsUrlController = TextEditingController(); // Acts as Location Name input
  final TextEditingController _websiteUrlController = TextEditingController();

  double _rating = 0;
  List<File> _images = [];
  List<String> _existingImageUrls = [];
  bool _isLoading = false;
  String? _selectedGoogleMapsUrl; // Store the actual URL

  bool get _isEditing => widget.existingItem != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final item = widget.existingItem!;
      _titleController.text = item.title;
      _descriptionController.text = item.description ?? '';
      _notesController.text = item.notes ?? '';
      
      // Handle Google Maps URL prefill
      if (item.googleMapsUrl != null) {
        _selectedGoogleMapsUrl = item.googleMapsUrl;
        // Try to extract readable name from URL for display
        final url = item.googleMapsUrl!;
        if (url.contains("query=")) {
          try {
             final query = Uri.parse(url).queryParameters['query'];
             if (query != null) {
               // If it's a coordinate, show it, otherwise show name
               _mapsUrlController.text = query;
             } else {
               _mapsUrlController.text = url;
             }
          } catch (_) {
            _mapsUrlController.text = url;
          }
        } else {
           _mapsUrlController.text = url;
        }
      } else {
        _mapsUrlController.text = '';
      }

      _websiteUrlController.text = item.websiteUrl ?? '';
      _rating = item.rating;
      _existingImageUrls = List.from(item.imageUrls);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    _mapsUrlController.dispose();
    _websiteUrlController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _images.addAll(pickedFiles.map((f) => File(f.path)));
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      if (index < _existingImageUrls.length) {
        _existingImageUrls.removeAt(index);
      } else {
        _images.removeAt(index - _existingImageUrls.length);
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Upload new images
      List<String> imageUrls = List.from(_existingImageUrls);
      for (final image in _images) {
        final url = await _firestoreService.uploadImage(
          image,
          'items/${widget.collectionId}/${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
        if (url != null) {
          imageUrls.add(url);
        }
      }

      if (_isEditing) {
        // Determine final Google Maps URL
        // If user text starts with http, use it. If valid selection exists, use it.
        String? finalMapsUrl = _selectedGoogleMapsUrl;
        if (_mapsUrlController.text.startsWith('http')) {
           finalMapsUrl = _mapsUrlController.text.trim();
        } else if (_mapsUrlController.text.isEmpty) {
           finalMapsUrl = null;
        } 
        // If user typed a text that is NOT a URL and NOT selected from dropdown, 
        // we might just ignore it for the map URL but keep it in description? 
        // For now, if no URL selected/typed, set null.

        // Update existing item
        final updated = widget.existingItem!.copyWith(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim(),
          notes: _notesController.text.trim(),
          googleMapsUrl: finalMapsUrl,
          websiteUrl: _websiteUrlController.text.trim().isNotEmpty ? _websiteUrlController.text.trim() : null,
          rating: _rating,
          imageUrls: imageUrls,
        );
        await _firestoreService.updateCollectionItem(
          widget.collectionId,
          updated,
        );
      } else {
        // Determine final Google Maps URL
        String? finalMapsUrl = _selectedGoogleMapsUrl;
        if (_mapsUrlController.text.startsWith('http')) {
           finalMapsUrl = _mapsUrlController.text.trim();
        } else if (_mapsUrlController.text.isEmpty) {
           finalMapsUrl = null;
        }

        // Create new item
        final item = CollectionItemEntity(
          id: '',
          collectionId: widget.collectionId,
          userId: widget.userId,
          userName: widget.userName,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          notes: _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null,
          googleMapsUrl: finalMapsUrl,
          websiteUrl: _websiteUrlController.text.trim().isNotEmpty ? _websiteUrlController.text.trim() : null,
          rating: _rating,
          imageUrls: imageUrls,
        );
        await _firestoreService.addCollectionItem(
          widget.collectionId,
          item,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('Error saving item: $e');
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
    final allImages = [
      ..._existingImageUrls.map((url) => _ImageItem.network(url)),
      ..._images.map((file) => _ImageItem.file(file)),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Item' : 'Add Item'),
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
                    _isEditing ? 'Save' : 'Add',
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
            // Images
            const Text(
              'Images',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  // Add image button
                  GestureDetector(
                    onTap: _pickImages,
                    child: Container(
                      width: 100,
                      height: 100,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: 32, color: Colors.grey[400]),
                          const SizedBox(height: 4),
                          Text(
                            'Add',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Unsplash button
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (context) => UnsplashSearchDialog(
                          onImageSelected: (imageUrl, attribution) {
                            setState(() {
                              _existingImageUrls.add(imageUrl);
                            });
                          },
                        ),
                      );
                    },
                    child: Container(
                      width: 100,
                      height: 100,
                      margin: const EdgeInsets.only(right: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search, size: 32, color: Colors.grey[400]),
                          const SizedBox(height: 4),
                          Text(
                            'Unsplash',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Existing images
                  ...allImages.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    return Stack(
                      children: [
                        Container(
                          width: 100,
                          height: 100,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            image: DecorationImage(
                              image: item.isNetwork
                                  ? NetworkImage(item.url!)
                                  : FileImage(item.file!) as ImageProvider,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 16,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Title
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(
                labelText: 'Title',
                hintText: 'Name of the item',
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

            // Rating
            const Text(
              'Rating',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                RatingBar.builder(
                  initialRating: _rating,
                  minRating: 0,
                  direction: Axis.horizontal,
                  allowHalfRating: true,
                  itemCount: 5,
                  itemSize: 36,
                  itemPadding: const EdgeInsets.symmetric(horizontal: 2),
                  itemBuilder: (context, _) => const Icon(
                    Icons.star,
                    color: Colors.amber,
                  ),
                  onRatingUpdate: (rating) {
                    setState(() => _rating = rating);
                  },
                ),
                const SizedBox(width: 12),
                Text(
                  _rating > 0 ? _rating.toStringAsFixed(1) : 'Not rated',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Description
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description',
                hintText: 'Brief description of the item',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Notes',
                hintText: 'Personal notes (tips, experiences, etc.)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Links section
            const Text(
              'Links',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),

            // Location (Google Maps)
            RawAutocomplete<PlacePrediction>(
              textEditingController: _mapsUrlController,
              focusNode: FocusNode(),
              optionsBuilder: (TextEditingValue textEditingValue) async {
                if (textEditingValue.text.length < 2) {
                  return const Iterable<PlacePrediction>.empty();
                }
                // If it looks like a URL, don't search
                if (textEditingValue.text.startsWith('http')) {
                  return const Iterable<PlacePrediction>.empty();
                }
                return await _placesService.getAutocompletePredictions(textEditingValue.text);
              },
              displayStringForOption: (PlacePrediction option) => option.description,
              onSelected: (PlacePrediction selection) async {
                // Determine URL
                _mapsUrlController.text = selection.description; // Show name
                
                final url = await _placesService.getPlaceUrl(selection.placeId);
                if (url != null) {
                  // Store URL in a separate variable or tag? 
                  // Since the controller now holds the Name, we need a way to store the URL.
                  // But the save logic reads _mapsUrlController.text.
                  // If we change the controller to hold the name, the save logic creates a nice "Location Name" 
                  // but we want the Google Maps URL stored in the DB field `googleMapsUrl`.
                  
                  // Wait, CollectionItemEntity has `googleMapsUrl`. It doesn't have `locationName`.
                  // If I store "Paris, France" in `googleMapsUrl` field, it's not a URL.
                  // Android logic stores the URL.
                  
                  // So I need a separate variable for the URL, and _mapsUrlController is just for the UI.
                  _selectedGoogleMapsUrl = url;
                }
              },
              fieldViewBuilder: (BuildContext context, TextEditingController textEditingController, FocusNode focusNode, VoidCallback onFieldSubmitted) {
                // Sync the internal controller with our _mapsUrlController if needed, 
                // but RawAutocomplete takes a controller. I passed _mapsUrlController. 
                // So textEditingController is _mapsUrlController.
                return TextFormField(
                  controller: textEditingController,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    labelText: 'Location', // Changed from Google Maps URL to Location to match UI
                    hintText: 'Search for a place or paste URL',
                    prefixIcon: const Icon(Icons.place_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: textEditingController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              textEditingController.clear();
                              _selectedGoogleMapsUrl = null;
                            },
                          )
                        : null,
                  ),
                  onFieldSubmitted: (String value) {
                    onFieldSubmitted();
                  },
                  validator: (value) {
                     // No validation needed generally
                     return null;
                  },
                );
              },
              optionsViewBuilder: (BuildContext context, AutocompleteOnSelected<PlacePrediction> onSelected, Iterable<PlacePrediction> options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4.0,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
                    ),
                    child: Container(
                      width: MediaQuery.of(context).size.width - 32, // Match padding
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final PlacePrediction option = options.elementAt(index);
                          return ListTile(
                            leading: const Icon(Icons.place, size: 20, color: Colors.grey),
                            title: Text(option.mainText, style: const TextStyle(fontWeight: FontWeight.w500)),
                            subtitle: option.secondaryText.isNotEmpty ? Text(option.secondaryText) : null,
                            onTap: () {
                              onSelected(option);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // Website
            TextFormField(
              controller: _websiteUrlController,
              decoration: InputDecoration(
                labelText: 'Website URL',
                hintText: 'https://...',
                prefixIcon: const Icon(Icons.link),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _ImageItem {
  final String? url;
  final File? file;

  _ImageItem.network(this.url) : file = null;
  _ImageItem.file(this.file) : url = null;

  bool get isNetwork => url != null;
}

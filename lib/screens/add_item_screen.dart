import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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
  final TextEditingController _mapsUrlController = TextEditingController(); // Acts as Location Name input
  final TextEditingController _websiteUrlController = TextEditingController();

  double _rating = 0;
  final TextEditingController _ratingController = TextEditingController();
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
      _ratingController.text = _rating > 0 ? _rating.toStringAsFixed(1) : '';
      _existingImageUrls = List.from(item.imageUrls);
    }
  }

  void _setRatingFromText(String value) {
    final raw = value.trim();
    if (raw.isEmpty) {
      setState(() => _rating = 0);
      return;
    }
    final parsed = double.tryParse(raw);
    if (parsed == null) return;
    // Input is 0-10, store as 0-10 (no conversion needed)
    final clamped10 = parsed.clamp(0, 10).toDouble();
    final rounded10 = (clamped10 * 10).round() / 10.0;
    setState(() => _rating = rounded10);
  }

  Widget _buildRatingBadge(double rating) {
    if (rating <= 0) return const SizedBox.shrink();
    // Check if rating is old scale (0-5) or new scale (0-10)
    final displayScore = rating <= 5 ? rating * 2 : rating;
    final label = (displayScore % 1 == 0) ? displayScore.toStringAsFixed(0) : displayScore.toStringAsFixed(1);

    Color badgeColor;
    if (displayScore < 4) {
      badgeColor = Colors.red[700] ?? Colors.red;
    } else if (displayScore < 7) {
      badgeColor = Colors.amber[800] ?? Colors.amber;
    } else {
      badgeColor = Colors.green[700] ?? Colors.green;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 14, color: badgeColor),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: badgeColor,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _mapsUrlController.dispose();
    _websiteUrlController.dispose();
    _ratingController.dispose();
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
        title: Text(
          _isEditing ? 'Edit Item' : 'Add Item',
          style: const TextStyle(fontWeight: FontWeight.w800),
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
                    _isEditing ? 'Save' : 'Add',
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
                        color: AppColors.primaryPurple.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate,
                            size: 32,
                            color: AppColors.primaryPurple.withOpacity(0.75),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
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
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.search,
                            size: 32,
                            color: Colors.black.withOpacity(0.45),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Unsplash',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
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
                            color: const Color(0xFFF1F5F9),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: item.isNetwork
                                ? CachedNetworkImage(
                                    imageUrl: item.url ?? '',
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(
                                      color: const Color(0xFFF1F5F9),
                                      child: const Center(
                                        child: SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                    ),
                                    errorWidget: (context, url, error) => Container(
                                      color: const Color(0xFFF1F5F9),
                                      alignment: Alignment.center,
                                      child: const Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
                                    ),
                                  )
                                : Image.file(
                                    item.file!,
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
                    'Title',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      hintText: 'Name of the item',
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
                    'Rating',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _ratingController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            hintText: '0-10',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^[0-9]*\.?[0-9]*$')),
                          ],
                          onChanged: _setRatingFromText,
                          onEditingComplete: () {
                            _setRatingFromText(_ratingController.text);
                            _ratingController.text = _rating > 0
                                ? ((_rating % 1 == 0)
                                    ? _rating.toStringAsFixed(0)
                                    : _rating.toStringAsFixed(1))
                                : '';
                            FocusScope.of(context).unfocus();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      _buildRatingBadge(_rating),
                    ],
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
                      hintText: 'Brief description of the item',
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Links',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 12),

                  const Text(
                    'Location (Optional)',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  RawAutocomplete<PlacePrediction>(
                    textEditingController: _mapsUrlController,
                    focusNode: FocusNode(),
                    optionsBuilder: (TextEditingValue textEditingValue) async {
                      if (textEditingValue.text.length < 2) {
                        return const Iterable<PlacePrediction>.empty();
                      }
                      if (textEditingValue.text.startsWith('http')) {
                        return const Iterable<PlacePrediction>.empty();
                      }
                      return await _placesService.getAutocompletePredictions(textEditingValue.text);
                    },
                    displayStringForOption: (PlacePrediction option) => option.description,
                    onSelected: (PlacePrediction selection) async {
                      _mapsUrlController.text = selection.description;
                      final url = await _placesService.getPlaceUrl(selection.placeId);
                      if (url != null) {
                        _selectedGoogleMapsUrl = url;
                      }
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
                        decoration: InputDecoration(
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
                          return null;
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
                            constraints: const BoxConstraints(maxHeight: 220),
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              shrinkWrap: true,
                              itemCount: options.length,
                              itemBuilder: (BuildContext context, int index) {
                                final PlacePrediction option = options.elementAt(index);
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
                  const SizedBox(height: 16),
                  const Text(
                    'Website (Optional)',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _websiteUrlController,
                    decoration: const InputDecoration(
                      hintText: 'https://...',
                      prefixIcon: Icon(Icons.link),
                    ),
                    keyboardType: TextInputType.url,
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

class _StarFillClipper extends CustomClipper<Rect> {
  final double fill;

  _StarFillClipper(this.fill);

  @override
  Rect getClip(Size size) {
    final width = size.width * fill.clamp(0, 1);
    return Rect.fromLTWH(0, 0, width, size.height);
  }

  @override
  bool shouldReclip(covariant _StarFillClipper oldClipper) => oldClipper.fill != fill;
}

class _ImageItem {
  final String? url;
  final File? file;

  _ImageItem.network(this.url) : file = null;
  _ImageItem.file(this.file) : url = null;

  bool get isNetwork => url != null;
}

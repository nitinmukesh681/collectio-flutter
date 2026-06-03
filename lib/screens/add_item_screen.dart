import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../widgets/unsplash_search_dialog.dart';
import 'package:http/http.dart' as http; // Determine if network image implies http
import '../utils/snackbar_utils.dart';
import '../models/collection_item_entity.dart';
import '../models/place_prediction.dart';
import '../services/firestore_service.dart';
import '../services/places_service.dart';
import '../theme/app_theme.dart';
import 'package:google_fonts/google_fonts.dart';

const double _kImageThumbSize = 88;
const int _maxItemImages = 10;

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
  final List<_ImageItem> _imageItems = [];
  bool _isLoading = false;
  String? _selectedGoogleMapsUrl; // Store the actual URL

  bool get _isEditing => widget.existingItem != null;
  bool get _canAddMoreImages => _imageItems.length < _maxItemImages;
  int get _remainingImageSlots => _maxItemImages - _imageItems.length;

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
      _imageItems.addAll(
        item.imageUrls.map((url) => _ImageItem.network(url)),
      );
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
    final displayScore = rating;
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

  TextStyle get _labelStyle => GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        color: AppColors.textPrimary,
      );

  TextStyle get _sectionTitleStyle => GoogleFonts.plusJakartaSans(
        fontWeight: FontWeight.w800,
        fontSize: 16,
        color: AppColors.textPrimary,
      );

  Widget _fieldLabel(String text, {bool optional = false}) {
    return Text(
      optional ? '$text (Optional)' : text,
      style: _labelStyle,
    );
  }

  Widget _formCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildPhotosSection(List<_ImageItem> allImages) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Photos', style: _sectionTitleStyle),
        const SizedBox(height: 4),
        Text(
          'Upload from your library or search Unsplash (up to $_maxItemImages)',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _canAddMoreImages ? _pickImages : null,
                icon: const Icon(Icons.photo_library_outlined, size: 20),
                label: const Text('Upload'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.divider),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _canAddMoreImages
                    ? () {
                        showDialog(
                          context: context,
                          builder: (context) => UnsplashSearchDialog(
                            onImageSelected: (imageUrl, attribution) {
                              if (!_canAddMoreImages) {
                                SnackBarUtils.showErrorSnackBar(
                                  context,
                                  'You can add up to $_maxItemImages photos per item',
                                );
                                return;
                              }
                              setState(() {
                                _imageItems.add(_ImageItem.network(imageUrl));
                              });
                            },
                          ),
                        );
                      }
                    : null,
                icon: const Icon(Icons.image_search_outlined, size: 20),
                label: const Text('Unsplash'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.divider),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  textStyle: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (allImages.isNotEmpty) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: _kImageThumbSize,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: allImages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _buildImagePreviewTile(
                item: allImages[index],
                onRemove: () => _removeImage(index),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildImagePreviewTile({
    required _ImageItem item,
    required VoidCallback onRemove,
  }) {
    return SizedBox(
      width: _kImageThumbSize,
      height: _kImageThumbSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
              boxShadow: AppColors.cardShadow,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: SizedBox(
                width: _kImageThumbSize,
                height: _kImageThumbSize,
                child: item.isNetwork
                    ? CachedNetworkImage(
                        imageUrl: item.url ?? '',
                        width: _kImageThumbSize,
                        height: _kImageThumbSize,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => ColoredBox(
                          color: AppColors.surfaceMuted,
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary.withValues(alpha: 0.7),
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => ColoredBox(
                          color: AppColors.surfaceMuted,
                          child: const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textMuted,
                          ),
                        ),
                      )
                    : Image.file(
                        item.file!,
                        width: _kImageThumbSize,
                        height: _kImageThumbSize,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, color: Colors.white, size: 14),
                ),
              ),
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
    if (!_canAddMoreImages) {
      SnackBarUtils.showErrorSnackBar(
        context,
        'You can add up to $_maxItemImages photos per item',
      );
      return;
    }

    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage();
    if (pickedFiles.isEmpty || !mounted) return;

    final remaining = _remainingImageSlots;
    final filesToAdd = pickedFiles.take(remaining);

    setState(() {
      _imageItems.addAll(
        filesToAdd.map((f) => _ImageItem.file(File(f.path))),
      );
    });

    if (pickedFiles.length > remaining) {
      SnackBarUtils.showErrorSnackBar(
        context,
        'Only $remaining more photo${remaining == 1 ? '' : 's'} could be added (max $_maxItemImages).',
      );
    }
  }

  void _removeImage(int index) {
    setState(() => _imageItems.removeAt(index));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Preserve add order; upload new local files in parallel.
      final orderedUrls = List<String?>.filled(_imageItems.length, null);
      final uploadBaseMs = DateTime.now().millisecondsSinceEpoch;
      var uploadIndex = 0;
      final uploadFutures = <Future<void>>[];

      for (var i = 0; i < _imageItems.length; i++) {
        final image = _imageItems[i];
        if (image.isNetwork) {
          final url = image.url?.trim();
          if (url != null && url.isNotEmpty) {
            orderedUrls[i] = url;
          }
        } else if (image.file != null) {
          final slot = i;
          final path =
              'items/${widget.collectionId}/${uploadBaseMs}_$uploadIndex.jpg';
          uploadIndex++;
          uploadFutures.add(() async {
            final url = await _firestoreService.uploadImage(image.file!, path);
            if (url != null) {
              orderedUrls[slot] = url;
            }
          }());
        }
      }

      if (uploadFutures.isNotEmpty) {
        await Future.wait(uploadFutures);
      }

      final imageUrls = orderedUrls
          .whereType<String>()
          .where((url) => url.isNotEmpty)
          .toList(growable: false);

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

        // Update existing item — use direct map update to allow nulling fields
        final updatedItem = CollectionItemEntity(
          id: widget.existingItem!.id,
          collectionId: widget.collectionId,
          userId: widget.existingItem!.userId,
          userName: widget.existingItem!.userName,
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
          googleMapsUrl: finalMapsUrl,
          websiteUrl: _websiteUrlController.text.trim().isNotEmpty ? _websiteUrlController.text.trim() : null,
          rating: _rating,
          imageUrls: imageUrls,
          order: widget.existingItem!.order,
          likes: widget.existingItem!.likes,
          likedBy: widget.existingItem!.likedBy,
        );
        await _firestoreService.updateCollectionItem(
          widget.collectionId,
          updatedItem,
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
        SnackBarUtils.showErrorSnackBar(context, 'Error: ${e.toString()}');
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundSurface,
        scrolledUnderElevation: 0,
        title: Text(
          _isEditing ? 'Edit Item' : 'Add Item',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _isLoading ? null : _save,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator.adaptive(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                        strokeCap: StrokeCap.round,
                      ),
                    )
                  : Text(
                      _isEditing ? 'Save' : 'Add',
                      style: GoogleFonts.plusJakartaSans(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _buildPhotosSection(_imageItems),
            const SizedBox(height: 20),
            _formCard(
              children: [
                Text('Details', style: _sectionTitleStyle),
                const SizedBox(height: 18),
                _fieldLabel('Title'),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
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
                const SizedBox(height: 18),
                _fieldLabel('Rating'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _ratingController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          hintText: '0–10',
                          prefixIcon: Icon(Icons.star_outline_rounded, size: 22),
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
                const SizedBox(height: 18),
                _fieldLabel('Description', optional: true),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    hintText: 'Brief description of the item',
                    alignLabelWithHint: true,
                  ),
                  maxLines: 4,
                  minLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _formCard(
              children: [
                Text('Links', style: _sectionTitleStyle),
                const SizedBox(height: 18),
                _fieldLabel('Location', optional: true),
                const SizedBox(height: 8),
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
                          suffixIcon: textEditingController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded),
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
                const SizedBox(height: 18),
                _fieldLabel('Website', optional: true),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _websiteUrlController,
                  decoration: const InputDecoration(
                    hintText: 'https://...',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
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

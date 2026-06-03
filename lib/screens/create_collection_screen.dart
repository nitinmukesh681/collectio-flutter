import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import '../theme/app_theme.dart';
import '../utils/snackbar_utils.dart';
import '../utils/category_icons.dart';
import '../models/category_type.dart';
import '../models/place_prediction.dart';
import '../services/firestore_service.dart';
import '../services/places_service.dart';
import '../services/unsplash_service.dart';
import '../models/collection_entity.dart';
import '../widgets/unsplash_search_dialog.dart';
import '../widgets/resolved_network_image.dart';


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
  final UnsplashService _unsplashService = UnsplashService();
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
  String? _coverImageSourcePath;
  String? _selectedUnsplashUrl; // New state variable for Unsplash image
  bool _isLoading = false;
  bool _isCoverPreparing = false;
  bool _isAutoSearchingCover = false;
  bool _coverManuallySet = false;
  bool _coverClearedForTitle = false;
  bool _coverExplicitlyCleared = false;
  String? _coverAutoSearchTitle;
  String? _selectedGoogleMapsUrl;
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _locationFocusNode = FocusNode();

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
    } else {
      _titleFocusNode.addListener(_onTitleFocusChanged);
    }
  }

  void _onTitleFocusChanged() {
    if (_isEditing || _titleFocusNode.hasFocus) return;
    _maybeAutoFetchCover();
  }

  void _onTitleSubmitted(String _) {
    _titleFocusNode.unfocus();
    _maybeAutoFetchCover();
  }

  Future<void> _maybeAutoFetchCover() async {
    if (_isEditing || _coverManuallySet || !mounted) return;

    final title = _titleController.text.trim();
    if (title.length < 3) return;

    if (_coverClearedForTitle && _coverAutoSearchTitle != title) {
      _coverClearedForTitle = false;
      _coverExplicitlyCleared = false;
    }

    if (_coverClearedForTitle && _coverAutoSearchTitle == title) return;
    if (_selectedUnsplashUrl != null &&
        _coverAutoSearchTitle == title &&
        !_coverClearedForTitle) {
      return;
    }

    setState(() => _isAutoSearchingCover = true);
    try {
      final photos = await _unsplashService.searchPhotos(title, perPage: 1);
      if (!mounted || _coverManuallySet) return;
      if (photos.isNotEmpty) {
        setState(() {
          _selectedUnsplashUrl = photos.first.urls.regular;
          _coverImage = null;
          _coverImageSourcePath = null;
          _coverAutoSearchTitle = title;
          _coverClearedForTitle = false;
          _coverExplicitlyCleared = false;
        });
      }
    } catch (e) {
      debugPrint('Auto Unsplash cover failed: $e');
    } finally {
      if (mounted) setState(() => _isAutoSearchingCover = false);
    }
  }

  void _clearCover() {
    setState(() {
      _coverImage = null;
      _coverImageSourcePath = null;
      _selectedUnsplashUrl = null;
      _coverManuallySet = false;
      _coverClearedForTitle = true;
      _coverExplicitlyCleared = true;
      _coverAutoSearchTitle = _titleController.text.trim();
    });
  }

  bool get _hasCover {
    if (_coverExplicitlyCleared) return false;
    return _coverImage != null ||
        (_selectedUnsplashUrl != null && _selectedUnsplashUrl!.isNotEmpty) ||
        (_isEditing &&
            widget.existingCollection?.coverImageUrl != null &&
            widget.existingCollection!.coverImageUrl!.isNotEmpty);
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

  TextStyle get _hintStyle => GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.35,
      );

  Widget _fieldLabel(String text, {bool optional = false, bool required = false}) {
    final suffix = required ? ' *' : (optional ? ' (Optional)' : '');
    return Text('$text$suffix', style: _labelStyle);
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

  ButtonStyle get _outlineActionStyle => OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(vertical: 13),
        textStyle: GoogleFonts.plusJakartaSans(
          fontWeight: FontWeight.w700,
          fontSize: 14,
        ),
      );

  String? get _displayCoverUrl {
    if (_coverExplicitlyCleared) return null;
    if (_selectedUnsplashUrl != null && _selectedUnsplashUrl!.isNotEmpty) {
      return _selectedUnsplashUrl;
    }
    if (_isEditing &&
        widget.existingCollection?.coverImageUrl != null &&
        widget.existingCollection!.coverImageUrl!.isNotEmpty) {
      return widget.existingCollection!.coverImageUrl;
    }
    return null;
  }

  Widget _buildCoverSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cover', style: _sectionTitleStyle),
        const SizedBox(height: 4),
        Text(
          _isEditing
              ? 'Upload a photo or search Unsplash'
              : 'Optional — we can suggest one from your collection name',
          style: _hintStyle,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isCoverPreparing ? null : _pickImage,
                icon: const Icon(Icons.photo_library_outlined, size: 20),
                label: const Text('Upload'),
                style: _outlineActionStyle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isCoverPreparing
                    ? null
                    : () {
                        showDialog(
                          context: context,
                          builder: (context) => UnsplashSearchDialog(
                            onImageSelected: (imageUrl, attribution) {
                              _applyRemoteCover(imageUrl);
                            },
                          ),
                        );
                      },
                icon: const Icon(Icons.image_search_outlined, size: 20),
                label: const Text('Unsplash'),
                style: _outlineActionStyle,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildCoverPreview(),
      ],
    );
  }

  Widget _buildCoverPreview() {
    const height = 200.0;
    final remoteUrl = _displayCoverUrl;

    Widget coverChild;
    if (_coverImage != null) {
      coverChild = Image.file(_coverImage!, width: double.infinity, height: height, fit: BoxFit.cover);
    } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
      coverChild = ResolvedNetworkImage(
        imageUrl: remoteUrl,
        width: double.infinity,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, __) => _coverPlaceholder(height, loading: true),
        errorWidget: (_, __, ___) => _coverPlaceholder(height),
      );
    } else {
      coverChild = _coverPlaceholder(height);
    }

    return GestureDetector(
      onTap: _isCoverPreparing
          ? null
          : () {
              if (!_hasCover) _pickImage();
            },
      child: Stack(
        alignment: Alignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: double.infinity,
              height: height,
              child: coverChild,
            ),
          ),
          if (_hasCover) ...[
            if (_canCropCover)
              Positioned(
                bottom: 10,
                left: 10,
                child: Material(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: _cropCoverImage,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.crop_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text(
                            'Crop',
                            style: GoogleFonts.plusJakartaSans(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 10,
              right: 10,
              child: Material(
                color: Colors.black.withValues(alpha: 0.55),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: _clearCover,
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ),
            ),
          ],
          if (_isCoverPreparing || _isAutoSearchingCover)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _coverPlaceholder(double height, {bool loading = false}) {
    return Container(
      width: double.infinity,
      height: height,
      color: AppColors.surfaceMuted,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            loading ? Icons.hourglass_top_rounded : Icons.image_outlined,
            size: 40,
            color: AppColors.textMuted,
          ),
          const SizedBox(height: 8),
          Text(
            loading ? 'Finding a cover...' : 'Tap to add a cover',
            style: GoogleFonts.plusJakartaSans(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(CategoryType category) {
    final isSelected = _selectedCategory == category;
    final color = AppColors.categoryLabelColor(category.name);

    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? color : AppColors.divider,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CategoryPhosphorIcon(
              category: category,
              size: 16,
              color: isSelected ? Colors.white : color,
            ),
            const SizedBox(width: 6),
            Text(
              category.displayName,
              style: GoogleFonts.plusJakartaSans(
                color: isSelected ? Colors.white : AppColors.textPrimary,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisibilityTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
    Color? accentColor,
  }) {
    final accent = accentColor ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: onChanged != null ? accent.withValues(alpha: 0.06) : AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: _hintStyle),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _titleFocusNode.removeListener(_onTitleFocusChanged);
    _titleFocusNode.dispose();
    _locationFocusNode.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    _websiteUrlController.dispose();
    _googleMapsUrlController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  bool get _canCropCover =>
      !_isCoverPreparing &&
      (_coverImageSourcePath != null ||
          _coverImage != null ||
          (_selectedUnsplashUrl != null && _selectedUnsplashUrl!.isNotEmpty) ||
          (_isEditing &&
              widget.existingCollection?.coverImageUrl != null &&
              widget.existingCollection!.coverImageUrl!.isNotEmpty));

  String? get _remoteCoverUrl {
    if (_selectedUnsplashUrl != null && _selectedUnsplashUrl!.isNotEmpty) {
      return _selectedUnsplashUrl;
    }
    if (_coverImage == null &&
        _isEditing &&
        widget.existingCollection?.coverImageUrl != null &&
        widget.existingCollection!.coverImageUrl!.isNotEmpty) {
      return widget.existingCollection!.coverImageUrl;
    }
    return null;
  }

  Future<String> _downloadCoverToTemp(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Invalid image URL');
    }

    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.local') ||
        host.startsWith('127.') ||
        host.startsWith('10.') ||
        host.startsWith('192.168.') ||
        host.startsWith('172.')) {
      throw const FormatException('Invalid image URL');
    }

    final response = await http.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Failed to download image');
    }

    final extension = uri.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
    final file = File(
      '${Directory.systemTemp.path}/cover_${DateTime.now().millisecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(response.bodyBytes);
    return file.path;
  }

  Future<void> _applyRemoteCover(String imageUrl, {bool manual = true}) async {
    if (manual) {
      _coverManuallySet = true;
      _coverExplicitlyCleared = false;
    }
    setState(() => _isCoverPreparing = true);
    try {
      final path = await _downloadCoverToTemp(imageUrl);
      if (!mounted) return;
      setState(() {
        _coverImageSourcePath = path;
        _coverImage = File(path);
        _selectedUnsplashUrl = imageUrl;
      });
    } catch (e) {
      debugPrint('Failed to prepare Unsplash cover: $e');
      if (mounted) {
        SnackBarUtils.showErrorSnackBar(
          context,
          'Could not load Unsplash image for cropping.',
        );
      }
    } finally {
      if (mounted) setState(() => _isCoverPreparing = false);
    }
  }

  Future<String?> _resolveCropSourcePath() async {
    if (_coverImageSourcePath != null && File(_coverImageSourcePath!).existsSync()) {
      return _coverImageSourcePath;
    }
    if (_coverImage != null && _coverImage!.existsSync()) {
      return _coverImage!.path;
    }

    final remoteUrl = _remoteCoverUrl;
    if (remoteUrl == null) return null;

    final path = await _downloadCoverToTemp(remoteUrl);
    if (mounted) {
      setState(() {
        _coverImageSourcePath = path;
        _coverImage = File(path);
      });
    }
    return path;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() {
      _coverImageSourcePath = pickedFile.path;
      _coverImage = File(pickedFile.path);
      _selectedUnsplashUrl = null;
      _coverManuallySet = true;
      _coverExplicitlyCleared = false;
    });
  }

  Future<void> _cropCoverImage() async {
    setState(() => _isCoverPreparing = true);

    try {
      final sourcePath = await _resolveCropSourcePath();
      if (sourcePath == null) {
        if (mounted) {
          SnackBarUtils.showErrorSnackBar(context, 'No image available to crop.');
        }
        return;
      }

      final croppedFile = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop Cover Image',
            toolbarColor: AppColors.primaryPurple,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: AppColors.primaryPurple,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.square,
            ],
          ),
          IOSUiSettings(
            title: 'Crop Cover Image',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
            embedInNavigationController: true,
            aspectRatioPresets: [
              CropAspectRatioPreset.original,
              CropAspectRatioPreset.ratio16x9,
              CropAspectRatioPreset.ratio4x3,
              CropAspectRatioPreset.ratio3x2,
              CropAspectRatioPreset.square,
            ],
          ),
        ],
      );

      if (!mounted) return;

      if (croppedFile != null) {
        setState(() {
          _coverImageSourcePath = croppedFile.path;
          _coverImage = File(croppedFile.path);
          _selectedUnsplashUrl = null;
          _coverManuallySet = true;
          _coverExplicitlyCleared = false;
        });
      }
    } catch (e) {
      debugPrint('Cover image crop failed: $e');
      if (mounted) {
        SnackBarUtils.showErrorSnackBar(
          context,
          'Could not open image cropper. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isCoverPreparing = false);
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
        finalCoverImageUrl = _selectedUnsplashUrl;
      } else if (_isEditing &&
          !_coverExplicitlyCleared &&
          widget.existingCollection?.coverImageUrl != null) {
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
          visibility: _isPublic ? CollectionVisibility.public : CollectionVisibility.private,
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
          visibility: _isPublic ? CollectionVisibility.public : CollectionVisibility.private,
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
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditing ? 'Edit Collection' : 'New Collection',
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
                      _isEditing ? 'Save' : 'Create',
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
            _buildCoverSection(),
            const SizedBox(height: 20),
            _formCard(
              children: [
                Text('Details', style: _sectionTitleStyle),
                const SizedBox(height: 18),
                _fieldLabel('Collection name', required: true),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _titleController,
                  focusNode: _titleFocusNode,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: _onTitleSubmitted,
                  decoration: const InputDecoration(
                    hintText: 'e.g., Summer Reading List',
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                _fieldLabel('Description', optional: true),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    hintText: 'What is this collection about?',
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
                _fieldLabel('Website', optional: true),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _websiteUrlController,
                  decoration: const InputDecoration(
                    hintText: 'https://...',
                    prefixIcon: Icon(Icons.link_rounded),
                  ),
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 18),
                _fieldLabel('Location', optional: true),
                const SizedBox(height: 8),
                RawAutocomplete<PlacePrediction>(
                  textEditingController: _googleMapsUrlController,
                  focusNode: _locationFocusNode,
                  optionsBuilder: (TextEditingValue textEditingValue) async {
                    final q = textEditingValue.text.trim();
                    if (q.length < 2) return const Iterable<PlacePrediction>.empty();
                    if (q.startsWith('http://') || q.startsWith('https://')) {
                      return const Iterable<PlacePrediction>.empty();
                    }
                    return _placesService.getAutocompletePredictions(q);
                  },
                  displayStringForOption: (PlacePrediction option) => option.description,
                  onSelected: (PlacePrediction selection) async {
                    _googleMapsUrlController.text = selection.description;
                    final url = await _placesService.getPlaceUrl(selection.placeId);
                    if (!mounted) return;
                    setState(() => _selectedGoogleMapsUrl = url);
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
                                  setState(() => _selectedGoogleMapsUrl = null);
                                },
                              )
                            : null,
                      ),
                      textInputAction: TextInputAction.done,
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
                          constraints: const BoxConstraints(maxHeight: 220),
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
              ],
            ),
            const SizedBox(height: 16),
            _formCard(
              children: [
                Text('Category & tags', style: _sectionTitleStyle),
                const SizedBox(height: 6),
                Text('Pick a category and add hashtags to help others discover it', style: _hintStyle),
                const SizedBox(height: 16),
                _fieldLabel('Category', required: true),
                const SizedBox(height: 10),
                SizedBox(
                  height: 120,
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: CategoryType.values.map(_buildCategoryChip).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                _fieldLabel('Tags', optional: true),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagController,
                        decoration: const InputDecoration(
                          hintText: 'Add a tag',
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Material(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: _addTag,
                        borderRadius: BorderRadius.circular(14),
                        child: const SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(Icons.add_rounded, color: Colors.white),
                        ),
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
                      return InputChip(
                        label: Text('#$tag'),
                        deleteIcon: const Icon(Icons.close_rounded, size: 16),
                        onDeleted: () => _removeTag(tag),
                        backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                        labelStyle: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                        side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            _formCard(
              children: [
                Text('Visibility', style: _sectionTitleStyle),
                const SizedBox(height: 16),
                _buildVisibilityTile(
                  icon: _isPublic ? Icons.public_rounded : Icons.lock_outline_rounded,
                  title: _isPublic ? 'Public' : 'Private',
                  subtitle: _isPublic
                      ? 'Anyone can see this collection'
                      : 'Only you can see this collection',
                  value: _isPublic,
                  onChanged: (value) => setState(() => _isPublic = value),
                ),
                const SizedBox(height: 12),
                Opacity(
                  opacity: _isPublic ? 1 : 0.45,
                  child: _buildVisibilityTile(
                    icon: Icons.group_add_outlined,
                    title: 'Open for contribution',
                    subtitle: 'Let others add items to this collection',
                    value: _isOpenForContribution,
                    onChanged: _isPublic
                        ? (value) => setState(() => _isOpenForContribution = value)
                        : null,
                    accentColor: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

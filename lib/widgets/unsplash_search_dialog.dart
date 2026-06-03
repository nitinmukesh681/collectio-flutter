import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/unsplash_service.dart';
import '../theme/app_theme.dart';

/// Dialog for searching and selecting Unsplash photos
class UnsplashSearchDialog extends StatefulWidget {
  final Function(String imageUrl, String? attribution) onImageSelected;
  /// When true, the dialog stays open so the user can pick several photos.
  final bool allowMultiple;
  /// Max photos the user may add in this session (only used when [allowMultiple]).
  final int? maxSelections;

  const UnsplashSearchDialog({
    super.key,
    required this.onImageSelected,
    this.allowMultiple = false,
    this.maxSelections,
  });

  @override
  State<UnsplashSearchDialog> createState() => _UnsplashSearchDialogState();
}

class _UnsplashSearchDialogState extends State<UnsplashSearchDialog> {
  final UnsplashService _unsplashService = UnsplashService();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedPhotoIds = {};

  List<UnsplashPhoto> _photos = [];
  bool _isLoading = false;
  String? _error;

  int get _maxSelections => widget.maxSelections ?? 1;
  bool get _canSelectMore =>
      !widget.allowMultiple || _selectedPhotoIds.length < _maxSelections;

  Future<void> _search(String query) async {
    if (query.length < 2) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final results = await _unsplashService.searchPhotos(query);
      setState(() => _photos = results);
    } catch (e) {
      setState(() => _error = e.toString());
    }

    setState(() => _isLoading = false);
  }

  void _selectPhoto(UnsplashPhoto photo) {
    if (widget.allowMultiple) {
      if (_selectedPhotoIds.contains(photo.id)) return;
      if (!_canSelectMore) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _maxSelections == 1
                  ? 'You can only add one more photo'
                  : 'You can add up to $_maxSelections photos',
            ),
          ),
        );
        return;
      }
    }

    final attribution = 'Photo by ${photo.user.name} on Unsplash';
    widget.onImageSelected(photo.urls.regular, attribution);

    if (widget.allowMultiple) {
      setState(() => _selectedPhotoIds.add(photo.id));
      return;
    }

    Navigator.pop(context);
  }

  void _finishMultiSelect() {
    Navigator.pop(context);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Text(
                    'Unsplash',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  if (widget.allowMultiple) ...[
                    const SizedBox(width: 8),
                    Text(
                      '${_selectedPhotoIds.length}/$_maxSelections',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (widget.allowMultiple)
                    TextButton(
                      onPressed: _finishMultiSelect,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: Text(
                        _selectedPhotoIds.isEmpty ? 'Cancel' : 'Done',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                ],
              ),
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search photos...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : null,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: _search,
                onChanged: (value) {
                  if (value.length >= 3) {
                    Future.delayed(const Duration(milliseconds: 500), () {
                      if (_searchController.text == value) {
                        _search(value);
                      }
                    });
                  }
                },
              ),
            ),

            // Error message
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),

            // Results grid
            Expanded(
              child: _photos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.image_search, size: 64, color: AppColors.textMuted),
                          const SizedBox(height: 16),
                          Text(
                            'Search for free photos',
                            style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1,
                      ),
                      itemCount: _photos.length,
                      itemBuilder: (context, index) {
                        final photo = _photos[index];
                        final isSelected =
                            widget.allowMultiple && _selectedPhotoIds.contains(photo.id);
                        return GestureDetector(
                          onTap: _canSelectMore || isSelected
                              ? () => _selectPhoto(photo)
                              : null,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: CachedNetworkImage(
                                  imageUrl: photo.urls.small,
                                  fit: BoxFit.cover,
                                  color: isSelected
                                      ? Colors.black.withValues(alpha: 0.35)
                                      : null,
                                  colorBlendMode:
                                      isSelected ? BlendMode.darken : null,
                                  placeholder: (context, url) => Container(
                                    color: AppColors.surfaceMuted,
                                    child: const Center(child: CircularProgressIndicator()),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: AppColors.surfaceMuted,
                                    child: const Icon(Icons.error),
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              // Attribution overlay
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.bottomCenter,
                                      end: Alignment.topCenter,
                                      colors: [
                                        Colors.black.withOpacity(0.7),
                                        Colors.transparent,
                                      ],
                                    ),
                                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                                  ),
                                  child: Text(
                                    photo.user.name,
                                    style: const TextStyle(color: Colors.white, fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surfaceMuted,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Column(
                children: [
                  if (widget.allowMultiple)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        _selectedPhotoIds.isEmpty
                            ? 'Tap photos to add them, then press Done'
                            : '${_selectedPhotoIds.length} photo${_selectedPhotoIds.length == 1 ? '' : 's'} selected',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Photos by ',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                      const Text(
                        'Unsplash',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

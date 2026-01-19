import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../models/collection_item_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

/// Dialog for adding multiple items to a collection at once
class AddMultipleItemsDialog extends StatefulWidget {
  final String collectionId;
  final String userId;
  final String userName;

  const AddMultipleItemsDialog({
    super.key,
    required this.collectionId,
    required this.userId,
    required this.userName,
  });

  @override
  State<AddMultipleItemsDialog> createState() => _AddMultipleItemsDialogState();
}

class _AddMultipleItemsDialogState extends State<AddMultipleItemsDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  final List<_ItemEntry> _items = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _addNewItem(); // Start with one empty item
  }

  void _addNewItem() {
    setState(() {
      _items.add(_ItemEntry(
        titleController: TextEditingController(),
        descriptionController: TextEditingController(),
      ));
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items[index].titleController.dispose();
      _items[index].descriptionController.dispose();
      _items.removeAt(index);
    });
  }

  Future<void> _pickImageForItem(int index) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file != null) {
      setState(() {
        _items[index].image = File(file.path);
      });
    }
  }

  Future<void> _saveAll() async {
    // Validate
    final validItems = _items.where((i) => i.titleController.text.trim().isNotEmpty).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one item with a title')),
      );
      return;
    }

    setState(() => _isLoading = true);
    int successCount = 0;

    try {
      for (int i = 0; i < validItems.length; i++) {
        final itemEntry = validItems[i];
        
        // Upload image if exists
        String? imageUrl;
        if (itemEntry.image != null) {
          imageUrl = await _firestoreService.uploadImage(
            itemEntry.image!,
            'items/${widget.collectionId}/${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
          );
        }

        final item = CollectionItemEntity(
          id: '',
          collectionId: widget.collectionId,
          userId: widget.userId,
          userName: widget.userName,
          title: itemEntry.titleController.text.trim(),
          description: itemEntry.descriptionController.text.trim().isNotEmpty
              ? itemEntry.descriptionController.text.trim()
              : null,
          imageUrls: imageUrl != null ? [imageUrl] : [],
          order: i,
        );

        await _firestoreService.addCollectionItem(widget.collectionId, item);
        successCount++;
      }

      if (mounted) {
        Navigator.pop(context, successCount);
      }
    } catch (e) {
      debugPrint('Error adding items: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added $successCount items. Error: $e')),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.titleController.dispose();
      item.descriptionController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryPurple,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Add Multiple Items',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Items list
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                itemCount: _items.length,
                itemBuilder: (context, index) => _buildItemEntry(index),
              ),
            ),

            // Add more button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton.icon(
                onPressed: _addNewItem,
                icon: const Icon(Icons.add),
                label: const Text('Add Another Item'),
              ),
            ),

            // Bottom bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('${_items.length} item(s)', style: TextStyle(color: Colors.grey[600])),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _saveAll,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryPurple,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: _isLoading
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Add Items'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemEntry(int index) {
    final item = _items[index];
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.primaryPurple,
                  child: Text('${index + 1}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                ),
                const Spacer(),
                if (_items.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _removeItem(index),
                    iconSize: 20,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: item.titleController,
              decoration: const InputDecoration(
                labelText: 'Title *',
                hintText: 'Item name',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: item.descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'Optional description',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _pickImageForItem(index),
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                  image: item.image != null
                      ? DecorationImage(image: FileImage(item.image!), fit: BoxFit.cover)
                      : null,
                ),
                child: item.image == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_photo_alternate, color: Colors.grey[400]),
                            Text('Add Image', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                          ],
                        ),
                      )
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemEntry {
  final TextEditingController titleController;
  final TextEditingController descriptionController;
  File? image;

  _ItemEntry({
    required this.titleController,
    required this.descriptionController,
    this.image,
  });
}

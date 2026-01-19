import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/collection_entity.dart';
import '../widgets/feed_collection_card.dart';
import 'collection_detail_screen.dart';

class OpenCollaborationsScreen extends StatefulWidget {
  const OpenCollaborationsScreen({super.key});

  @override
  State<OpenCollaborationsScreen> createState() => _OpenCollaborationsScreenState();
}

class _OpenCollaborationsScreenState extends State<OpenCollaborationsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<CollectionEntity> _collections = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  Future<void> _loadCollections() async {
    setState(() => _isLoading = true);
    try {
      // Fetch more items for the "See All" screen
      final collections = await _firestoreService.getOpenCollaborationCollections(limit: 50);
      if (mounted) {
        setState(() {
          _collections = collections;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading open collaborations: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _navigateToCollection(String collectionId) async {
    final auth = context.read<AuthProvider>();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CollectionDetailScreen(
          collectionId: collectionId,
          currentUserId: auth.userId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Open Collaborations',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _collections.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group_off_outlined, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No open collaborations found',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _collections.length,
                  itemBuilder: (context, index) {
                    final collection = _collections[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: FeedCollectionCard(
                        collection: collection,
                        onTap: () => _navigateToCollection(collection.id),
                        onLike: () async {
                          // Optimistic update
                          await _firestoreService.likeCollection(
                              collection.id, auth.userId);
                          // In a real app, update local state instead of reloading
                          _loadCollections(); 
                        },
                        onSave: () async {
                          if (collection.isSaved) {
                            await _firestoreService.unsaveCollection(
                                collection.id, auth.userId);
                          } else {
                            await _firestoreService.saveCollection(
                                collection.id, auth.userId);
                          }
                          _loadCollections();
                        },
                      ),
                    );
                  },
                ),
    );
  }
}

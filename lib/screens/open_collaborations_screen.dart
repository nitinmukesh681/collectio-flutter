import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/collection_entity.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_grid_card.dart';
import 'collection_detail_screen.dart';
import 'user_profile_screen.dart';

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

  void _navigateToUserProfile(String userId, String currentUserId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: userId,
          currentUserId: currentUserId,
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
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _collections.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.group_off_outlined, size: 64, color: AppColors.textMuted),
                      const SizedBox(height: 16),
                      Text(
                        'No open collaborations found',
                        style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: _collections.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.86,
                  ),
                  itemBuilder: (context, index) {
                    final c = _collections[index];
                    return CollectionGridCard(
                      collection: c,
                      onTap: () => _navigateToCollection(c.id),
                      onUserTap: () => _navigateToUserProfile(c.userId, auth.userId),
                    );
                  },
                ),
    );
  }
}

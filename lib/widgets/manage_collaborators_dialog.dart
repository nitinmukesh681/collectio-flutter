import 'package:flutter/material.dart';
import '../models/user_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';

/// Dialog for managing collection collaborators
class ManageCollaboratorsDialog extends StatefulWidget {
  final String collectionId;
  final String currentUserId;
  final String currentUserName;
  final String collectionTitle;
  final bool isOpenForContribution;
  final VoidCallback onOpenForContributionChanged;

  const ManageCollaboratorsDialog({
    super.key,
    required this.collectionId,
    required this.currentUserId,
    required this.currentUserName,
    required this.collectionTitle,
    required this.isOpenForContribution,
    required this.onOpenForContributionChanged,
  });

  @override
  State<ManageCollaboratorsDialog> createState() => _ManageCollaboratorsDialogState();
}

class _ManageCollaboratorsDialogState extends State<ManageCollaboratorsDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  final TextEditingController _searchController = TextEditingController();
  
  List<UserEntity> _searchResults = [];
  List<Map<String, dynamic>> _collaborators = [];
  String _selectedRole = 'editor';
  bool _isLoading = false;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadCollaborators();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCollaborators() async {
    setState(() => _isLoading = true);
    try {
      final collection = await _firestoreService.getCollection(widget.collectionId);
      if (collection != null && mounted) {
        setState(() {
          _collaborators = collection.collaborators
              .map((c) => {'userId': c['userId'], 'username': c['username'], 'role': c['role']})
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading collaborators: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _searchUsers(String query) async {
    if (query.length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    
    setState(() => _isSearching = true);
    try {
      final results = await _firestoreService.searchUsers(query);
      // Filter out current user and existing collaborators
      final filtered = results.where((user) {
        if (user.id == widget.currentUserId) return false;
        if (_collaborators.any((c) => c['userId'] == user.id)) return false;
        return true;
      }).toList();
      
      setState(() => _searchResults = filtered);
    } catch (e) {
      debugPrint('Error searching users: $e');
    }
    setState(() => _isSearching = false);
  }

  Future<void> _addCollaborator(UserEntity user) async {
    setState(() => _isLoading = true);
    try {
      await _firestoreService.addCollaborator(
        collectionId: widget.collectionId,
        userId: user.id,
        username: user.userName,
        role: _selectedRole,
        currentUserId: widget.currentUserId,
        currentUsername: widget.currentUserName,
        collectionTitle: widget.collectionTitle,
      );
      
      setState(() {
        _collaborators.add({
          'userId': user.id,
          'username': user.userName,
          'role': _selectedRole,
        });
        _searchController.clear();
        _searchResults = [];
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added ${user.userName} as $_selectedRole')),
        );
      }
    } catch (e) {
      debugPrint('Error adding collaborator: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _removeCollaborator(String userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Collaborator?'),
        content: Text('Remove @$username from this collection?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      await _firestoreService.removeCollaborator(
        collectionId: widget.collectionId,
        userId: userId,
      );
      
      setState(() {
        _collaborators.removeWhere((c) => c['userId'] == userId);
      });
    } catch (e) {
      debugPrint('Error removing collaborator: $e');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Collaborators',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Open for contribution toggle
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Open collaboration', style: TextStyle(fontWeight: FontWeight.w600)),
                      Text('Allow anyone to add items', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ),
                Switch(
                  value: widget.isOpenForContribution,
                  onChanged: (_) => widget.onOpenForContributionChanged(),
                  activeColor: AppColors.primaryPurple,
                ),
              ],
            ),
            const Divider(height: 24),

            // Add collaborator section
            const Text('Add collaborator', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search username...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: _searchUsers,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedRole,
                      items: const [
                        DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                        DropdownMenuItem(value: 'editor', child: Text('Editor')),
                      ],
                      onChanged: (value) => setState(() => _selectedRole = value!),
                    ),
                  ),
                ),
              ],
            ),

            // Search results
            if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final user = _searchResults[index];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundImage: user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                        child: user.avatarUrl == null ? Text(user.userName[0].toUpperCase()) : null,
                      ),
                      title: Text('@${user.userName}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle, color: AppColors.primaryPurple),
                        onPressed: () => _addCollaborator(user),
                      ),
                    );
                  },
                ),
              ),

            const SizedBox(height: 16),
            const Divider(),

            // Collaborators list
            Row(
              children: [
                Text('Collaborators (${_collaborators.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
                if (_isLoading) ...[
                  const SizedBox(width: 10),
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
            ),
            const SizedBox(height: 10),
            
            Flexible(
              child: _collaborators.isEmpty
                  ? Center(child: Text('No collaborators yet', style: TextStyle(color: Colors.grey[500])))
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _collaborators.length,
                      itemBuilder: (context, index) {
                        final collab = _collaborators[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            child: Text((collab['username'] ?? 'U')[0].toUpperCase()),
                          ),
                          title: Text('@${collab['username']}'),
                          subtitle: Text(
                            (collab['role'] as String).toUpperCase(),
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                            onPressed: () => _removeCollaborator(collab['userId'], collab['username']),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

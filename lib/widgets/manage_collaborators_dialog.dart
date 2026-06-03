import 'package:flutter/material.dart';
import '../models/user_entity.dart';
import '../services/firestore_service.dart';
import '../theme/app_theme.dart';
import '../utils/snackbar_utils.dart';
import '../screens/user_profile_screen.dart';

/// Dialog for managing collection collaborators
class ManageCollaboratorsDialog extends StatefulWidget {
  final String collectionId;
  final String currentUserId;
  final String currentUserName;
  final String collectionTitle;
  final bool isPublicCollection;
  final bool showOpenCollaborationToggle;
  final bool isOpenForContribution;
  final VoidCallback? onOpenForContributionChanged;

  const ManageCollaboratorsDialog({
    super.key,
    required this.collectionId,
    required this.currentUserId,
    required this.currentUserName,
    required this.collectionTitle,
    required this.isPublicCollection,
    this.showOpenCollaborationToggle = false,
    this.isOpenForContribution = false,
    this.onOpenForContributionChanged,
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
  bool _isLoadingCollaborators = false;
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
    setState(() => _isLoadingCollaborators = true);
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
    if (mounted) setState(() => _isLoadingCollaborators = false);
  }

  Future<void> _searchUsers(String query) async {
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await _firestoreService.searchUsers(query);
      if (!mounted) return;
      final filtered = results.where((user) {
        if (user.id == widget.currentUserId) return false;
        if (_collaborators.any((c) => c['userId'] == user.id)) return false;
        return true;
      }).toList();

      setState(() => _searchResults = filtered);
    } catch (e) {
      debugPrint('Error searching users: $e');
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _addCollaborator(UserEntity user) async {
    final role = widget.isPublicCollection ? 'editor' : _selectedRole;
    setState(() => _isLoadingCollaborators = true);
    try {
      await _firestoreService.addCollaborator(
        collectionId: widget.collectionId,
        userId: user.id,
        username: user.userName,
        role: role,
        currentUserId: widget.currentUserId,
        currentUsername: widget.currentUserName,
        collectionTitle: widget.collectionTitle,
      );
      
      setState(() {
        _collaborators.add({
          'userId': user.id,
          'username': user.userName,
          'role': role.toUpperCase(),
        });
        _searchController.clear();
        _searchResults = [];
      });
      
      if (mounted) {
        final label = role == 'editor' ? 'edit' : 'view';
        SnackBarUtils.showSuccessSnackBar(context, 'Added ${user.userName} with $label access');
      }
    } catch (e) {
      debugPrint('Error adding collaborator: $e');
      if (mounted) {
        SnackBarUtils.showErrorSnackBar(context, 'Error: $e');
      }
    }
    if (mounted) setState(() => _isLoadingCollaborators = false);
  }

  Future<void> _removeCollaborator(String userId, String username) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Collaborator?'),
        content: Text('Remove @$username from this collection?'),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700]),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoadingCollaborators = true);
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
    if (mounted) setState(() => _isLoadingCollaborators = false);
  }

  String _roleLabel(String role) {
    switch (role.toUpperCase()) {
      case 'EDITOR':
        return 'Edit access';
      case 'VIEWER':
        return 'View access';
      default:
        return role.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
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

            if (widget.showOpenCollaborationToggle) ...[
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Open collaboration', style: TextStyle(fontWeight: FontWeight.w600)),
                        Text(
                          'Allow anyone to add items',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: widget.isOpenForContribution,
                    onChanged: widget.onOpenForContributionChanged == null
                        ? null
                        : (_) => widget.onOpenForContributionChanged!(),
                    activeColor: AppColors.primaryPurple,
                  ),
                ],
              ),
              const Divider(height: 24),
            ],

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
                      suffixIcon: _isSearching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    onChanged: _searchUsers,
                  ),
                ),
                if (!widget.isPublicCollection) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.divider),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedRole,
                        items: const [
                          DropdownMenuItem(value: 'viewer', child: Text('View')),
                          DropdownMenuItem(value: 'editor', child: Text('Edit')),
                        ],
                        onChanged: (value) => setState(() => _selectedRole = value!),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.isPublicCollection
                  ? 'Public collections already allow view access. Collaborators get edit access.'
                  : _selectedRole == 'editor'
                      ? 'Edit access lets them add items to this collection.'
                      : 'View access lets them see this private collection.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),

            // Search results
            if (_searchResults.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 8),
                constraints: const BoxConstraints(maxHeight: 120),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final user = _searchResults[index];
                    return ListTile(
                      dense: true,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(
                              userId: user.id,
                              currentUserId: widget.currentUserId,
                            ),
                          ),
                        );
                      },
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
                if (_isLoadingCollaborators) ...[
                  const SizedBox(width: 10),
                  const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ],
            ),
            const SizedBox(height: 10),

            if (_collaborators.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'No collaborators yet',
                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.35,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _collaborators.length,
                  itemBuilder: (context, index) {
                    final collab = _collaborators[index];
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(
                              userId: collab['userId'],
                              currentUserId: widget.currentUserId,
                            ),
                          ),
                        );
                      },
                      leading: CircleAvatar(
                        radius: 16,
                        child: Text((collab['username'] ?? 'U')[0].toUpperCase()),
                      ),
                      title: Text('@${collab['username']}'),
                      subtitle: Text(
                        _roleLabel(collab['role'] as String? ?? ''),
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
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

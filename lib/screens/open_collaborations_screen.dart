import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../models/collection_entity.dart';
import '../theme/app_theme.dart';
import '../widgets/collection_list_card.dart';

class OpenCollaborationsScreen extends StatefulWidget {
  final List<CollectionEntity> initialCollections;

  const OpenCollaborationsScreen({
    super.key,
    this.initialCollections = const [],
  });

  @override
  State<OpenCollaborationsScreen> createState() => _OpenCollaborationsScreenState();
}

class _OpenCollaborationsScreenState extends State<OpenCollaborationsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late List<CollectionEntity> _collections;
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _collections = List<CollectionEntity>.from(widget.initialCollections);
    _isLoading = _collections.isEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadCollections();
    });
  }

  Future<void> _loadCollections() async {
    if (!mounted) return;

    final showFullScreenLoader = _collections.isEmpty;
    if (showFullScreenLoader) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }

    try {
      final collections =
          await _firestoreService.getOpenCollaborationCollections(limit: 50);
      if (!mounted) return;
      setState(() {
        _collections = collections;
        _loadError = null;
      });
    } catch (e) {
      debugPrint('Error loading open collaborations: $e');
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load collaborations';
        if (_collections.isEmpty) {
          _collections = [];
        }
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();

    return Scaffold(
      backgroundColor: AppColors.backgroundSurface,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Open Collaborations',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            color: Colors.black,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null && _collections.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 56, color: AppColors.textMuted),
                        const SizedBox(height: 16),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: _loadCollections,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _collections.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.group_off_outlined, size: 64, color: AppColors.textMuted),
                          const SizedBox(height: 16),
                          Text(
                            'No open collaborations found',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadCollections,
                      color: AppColors.primary,
                      child: ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                        itemCount: _collections.length,
                        itemBuilder: (context, index) {
                          final c = _collections[index];
                          return CollectionListCard(
                            collection: c,
                            currentUserId: auth.userId,
                          );
                        },
                      ),
                    ),
    );
  }
}

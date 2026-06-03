import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category_type.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/user_avatar.dart';
import 'collection_detail_screen.dart';
import 'user_profile_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final String userId;

  const NotificationsScreen({super.key, required this.userId});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestoreService _firestoreService = FirestoreService();

  String _currentUsername = '';
  final Map<String, bool> _isFollowingCache = <String, bool>{};
  final Map<String, String> _collectionCategoryCache = <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadCurrentUsername();
  }

  Widget _buildFollowBackRow(String? fromUserId) {
    if (fromUserId == null || fromUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    final cached = _isFollowingCache[fromUserId];
    if (cached != null) {
      if (cached) return const SizedBox.shrink();
      return _followBackButton(fromUserId);
    }

    return FutureBuilder<bool>(
      future: _firestoreService.isFollowing(widget.userId, fromUserId),
      builder: (context, snap) {
        final isFollowing = snap.data ?? false;
        if (snap.connectionState == ConnectionState.done) {
          _isFollowingCache[fromUserId] = isFollowing;
        }
        if (isFollowing) return const SizedBox.shrink();
        return _followBackButton(fromUserId);
      },
    );
  }

  Widget _followBackButton(String fromUserId) {
    return OutlinedButton(
      onPressed: () async {
        try {
          await _firestoreService.followUser(
            widget.userId,
            fromUserId,
            _currentUsername,
          );

          if (mounted) {
            setState(() => _isFollowingCache[fromUserId] = true);
            SnackBarUtils.showSuccessSnackBar(context, 'Followed back');
          }
        } catch (e) {
          if (mounted) {
            SnackBarUtils.showErrorSnackBar(context, 'Could not follow back: $e');
          }
        }
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryPurple,
        side: const BorderSide(color: AppColors.primaryPurple, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: Text(
        'Follow Back',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  Future<String> _resolveCollectionCategoryName(
    String? collectionId,
    Map<String, dynamic> data,
  ) async {
    final stored = data['collectionCategory'] as String?;
    if (stored != null && stored.trim().isNotEmpty) {
      return CategoryType.fromString(stored).name;
    }

    if (collectionId == null || collectionId.isEmpty) {
      return CategoryType.other.name;
    }

    final cached = _collectionCategoryCache[collectionId];
    if (cached != null) return cached;

    final categoryName = await _firestoreService.getCollectionCategoryName(collectionId);
    _collectionCategoryCache[collectionId] = categoryName;
    return categoryName;
  }

  Widget _buildCollectionTitleLabel({
    required String title,
    required String? collectionId,
    required Map<String, dynamic> data,
    required VoidCallback? onTap,
  }) {
    return FutureBuilder<String>(
      future: _resolveCollectionCategoryName(collectionId, data),
      builder: (context, snapshot) {
        final categoryName = snapshot.data ?? CategoryType.other.name;
        final color = AppColors.categoryLabelColor(categoryName);

        return GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              height: 1.45,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadCurrentUsername() async {
    try {
      final user = await _firestoreService.getUser(widget.userId);
      if (mounted) {
        setState(() => _currentUsername = user?.userName ?? '');
      }
    } catch (_) {
      // ignore
    }
  }

  static const double _bottomNavClearance = 120;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Activity', 
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 24, 
                            fontWeight: FontWeight.w800, 
                            color: AppColors.textPrimary,
                            letterSpacing: -0.4,
                            height: 1.15,
                          )
                        ),
                        const SizedBox(height: 4),
                        Text('Updates from your curated community', 
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.done_all_rounded, color: AppColors.primary),
                    onPressed: _markAllAsRead,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Notifications list
            Expanded(child: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('notifications')
            .where('toUserId', isEqualTo: widget.userId)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}', style: GoogleFonts.plusJakartaSans()));
          }

          final notifications = snapshot.data?.docs ?? [];

          if (notifications.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.notifications_off_outlined, size: 80, color: AppColors.textMuted),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We\'ll notify you when something happens',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }

          // Group by today / earlier
          final today = <QueryDocumentSnapshot>[];
          final earlier = <QueryDocumentSnapshot>[];
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);

          for (final doc in notifications) {
            final data = doc.data() as Map<String, dynamic>;
            final createdAt = data['createdAt'];
            DateTime date = now;
            if (createdAt is Timestamp) date = createdAt.toDate();
            else if (createdAt is int) date = DateTime.fromMillisecondsSinceEpoch(createdAt);

            if (date.isAfter(todayStart)) { today.add(doc); } else { earlier.add(doc); }
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, _bottomNavClearance),
            children: [
              if (today.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10, top: 8),
                  child: Text('TODAY', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 1)),
                ),
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppColors.radiusCard)),
                  child: Column(
                    children: [
                      for (int i = 0; i < today.length; i++)
                        _buildNotificationTile(today[i].id, today[i].data() as Map<String, dynamic>),
                    ],
                  ),
                ),
              ],
              if (earlier.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.only(bottom: 10, top: today.isNotEmpty ? 24 : 18),
                  child: Text('EARLIER', style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: 1)),
                ),
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppColors.radiusCard)),
                  child: Column(
                    children: [
                      for (int i = 0; i < earlier.length; i++)
                        _buildNotificationTile(earlier[i].id, earlier[i].data() as Map<String, dynamic>),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      )),
          ],
      ),
    );
  }

  Widget _buildNotificationTile(String id, Map<String, dynamic> data) {
    final type = (data['type'] as String? ?? 'unknown').toLowerCase();
    // ignore: unused_local_variable
    final isRead = data['isRead'] as bool? ?? false;
    final createdAt = data['createdAt'];
    
    // Parse timestamp
    String timeAgo = '';
    if (createdAt != null) {
      DateTime date;
      if (createdAt is Timestamp) {
        date = createdAt.toDate();
      } else if (createdAt is int) {
        date = DateTime.fromMillisecondsSinceEpoch(createdAt);
      } else {
        date = DateTime.now();
      }
      timeAgo = _formatTimeAgo(date);
    }

    // Get notification details based on type
    IconData icon;
    Color iconColor;
    String actionText;
    String? subtitle;
    bool showFollowBack = false;
    bool showCollabInviteActions = false;
    bool showCollabRequestActions = false;

    final fromUsername = data['fromUsername'] as String? ?? 'Someone';
    final collectionTitle = data['collectionTitle'] as String?;
    final fromUserId = data['fromUserId'] as String?;
    final collectionId = data['collectionId'] as String?;

    switch (type) {
      case 'follow':
      case 'new_follower':
      case 'follow_request':
        icon = Icons.person_add_rounded;
        iconColor = AppColors.primaryPurple;
        actionText = ' started following you';
        showFollowBack = true;
        break;
      case 'like':
      case 'like_collection':
      case 'like_item':
        icon = Icons.favorite_rounded;
        iconColor = AppColors.heartSalmon;
        actionText = ' liked your collection';
        subtitle = collectionTitle;
        break;
      case 'save':
      case 'save_collection':
        icon = Icons.bookmark_rounded;
        iconColor = Colors.orangeAccent;
        actionText = ' saved your collection';
        subtitle = collectionTitle;
        break;
      case 'new_item':
      case 'new_collection':
        icon = Icons.add_circle_rounded;
        iconColor = Colors.teal;
        actionText = ' created a new collection';
        subtitle = collectionTitle;
        break;
      case 'collaborate':
      case 'collaboration_invite':
      case 'collaborator_added':
        icon = Icons.group_add_rounded;
        iconColor = Colors.blueAccent;
        actionText = ' invited you to collaborate';
        subtitle = collectionTitle;
        showCollabInviteActions = type == 'collaboration_invite';
        break;
      case 'collaboration_request':
        icon = Icons.group_add_rounded;
        iconColor = Colors.blueAccent;
        actionText = ' requested to collaborate';
        subtitle = collectionTitle;
        showCollabRequestActions = true;
        break;
      case 'collaboration_accepted':
        icon = Icons.check_circle_rounded;
        iconColor = Colors.teal;
        actionText = ' added you as a collaborator';
        subtitle = collectionTitle;
        break;
      case 'comment':
        icon = Icons.chat_bubble_rounded;
        iconColor = AppColors.primary;
        actionText = ' commented on your collection';
        subtitle = collectionTitle;
        break;
      case 'comment_reply':
        icon = Icons.reply_rounded;
        iconColor = AppColors.primary;
        actionText = ' replied to your comment';
        subtitle = collectionTitle;
        break;
      case 'comment_like':
        icon = Icons.thumb_up_rounded;
        iconColor = AppColors.primary;
        actionText = ' liked your comment';
        subtitle = collectionTitle;
        break;
      case 'comment_mention':
        icon = Icons.alternate_email_rounded;
        iconColor = AppColors.primary;
        actionText = ' mentioned you in a comment';
        subtitle = collectionTitle;
        break;
      default:
        icon = Icons.notifications_rounded;
        iconColor = AppColors.textMuted;
        actionText = '';
    }

    return InkWell(
      onTap: () => _handleNotificationTap(id, data),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar with small badge — tap opens user profile
            GestureDetector(
              onTap: fromUserId != null && fromUserId.isNotEmpty
                  ? () {
                      _markAsRead(id);
                      _navigateToUser(fromUserId);
                    }
                  : null,
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: 48,
                height: 48,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    UserAvatar(
                      name: fromUsername,
                      size: 48,
                      userId: fromUserId,
                    ),
                    Positioned(
                      bottom: -2,
                      left: -2,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: iconColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(icon, color: Colors.white, size: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        height: 1.45,
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: GestureDetector(
                            onTap: fromUserId != null && fromUserId.isNotEmpty
                                ? () {
                                    _markAsRead(id);
                                    _navigateToUser(fromUserId);
                                  }
                                : null,
                            child: Text(
                              fromUsername,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                height: 1.45,
                                color: AppColors.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        TextSpan(text: actionText),
                        if (subtitle != null) ...[
                          const TextSpan(text: '\n'),
                          WidgetSpan(
                            alignment: PlaceholderAlignment.baseline,
                            baseline: TextBaseline.alphabetic,
                            child: _buildCollectionTitleLabel(
                              title: subtitle,
                              collectionId: collectionId,
                              data: data,
                              onTap: collectionId != null && collectionId.isNotEmpty
                                  ? () {
                                      _markAsRead(id);
                                      _navigateToCollection(collectionId);
                                    }
                                  : null,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(timeAgo, style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  if (showFollowBack) ...[
                    const SizedBox(height: 8),
                    _buildFollowBackRow(fromUserId),
                  ],
                  if (showCollabInviteActions &&
                      collectionId != null &&
                      collectionId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildCollaborationInviteActions(
                      notificationId: id,
                      collectionId: collectionId,
                    ),
                  ],
                  if (showCollabRequestActions &&
                      collectionId != null &&
                      collectionId.isNotEmpty &&
                      fromUserId != null &&
                      fromUserId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildCollaborationRequestActions(
                      notificationId: id,
                      collectionId: collectionId,
                      requesterId: fromUserId,
                      requesterUsername: fromUsername,
                      role: (data['role'] as String?) ?? 'EDITOR',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollaborationInviteActions({
    required String notificationId,
    required String collectionId,
  }) {
    return Row(
      children: [
        OutlinedButton(
          onPressed: () async {
            try {
              final user = await _firestoreService.getUser(widget.userId);
              await _firestoreService.acceptCollaboratorInvite(
                collectionId: collectionId,
                userId: widget.userId,
                username: user?.userName ?? 'user',
              );
              _markAsRead(notificationId);
              if (mounted) {
                SnackBarUtils.showSuccessSnackBar(context, 'Collaboration accepted');
                setState(() {});
              }
            } catch (e) {
              if (mounted) {
                SnackBarUtils.showErrorSnackBar(context, 'Could not accept: $e');
              }
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryPurple,
            side: const BorderSide(color: AppColors.primaryPurple),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Accept', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () async {
            try {
              await _firestoreService.declineCollaboratorInvite(
                collectionId: collectionId,
                userId: widget.userId,
              );
              _markAsRead(notificationId);
              if (mounted) {
                SnackBarUtils.showInfoSnackBar(context, 'Invite declined');
                setState(() {});
              }
            } catch (e) {
              if (mounted) {
                SnackBarUtils.showErrorSnackBar(context, 'Could not decline: $e');
              }
            }
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Decline', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildCollaborationRequestActions({
    required String notificationId,
    required String collectionId,
    required String requesterId,
    required String requesterUsername,
    required String role,
  }) {
    return Row(
      children: [
        OutlinedButton(
          onPressed: () async {
            try {
              await _firestoreService.acceptCollaboratorRequest(
                collectionId: collectionId,
                requesterId: requesterId,
                requesterUsername: requesterUsername,
                role: role.toLowerCase() == 'viewer' ? 'viewer' : 'editor',
                ownerId: widget.userId,
                ownerUsername: _currentUsername.isNotEmpty ? _currentUsername : 'owner',
              );
              _markAsRead(notificationId);
              if (mounted) {
                SnackBarUtils.showSuccessSnackBar(context, 'Collaborator added');
                setState(() {});
              }
            } catch (e) {
              if (mounted) {
                SnackBarUtils.showErrorSnackBar(context, 'Could not accept: $e');
              }
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryPurple,
            side: const BorderSide(color: AppColors.primaryPurple),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Accept', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 12)),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () async {
            try {
              await _firestoreService.declineCollaboratorRequest(
                collectionId: collectionId,
                requesterId: requesterId,
              );
              _markAsRead(notificationId);
              if (mounted) {
                SnackBarUtils.showInfoSnackBar(context, 'Request declined');
                setState(() {});
              }
            } catch (e) {
              if (mounted) {
                SnackBarUtils.showErrorSnackBar(context, 'Could not decline: $e');
              }
            }
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('Decline', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, fontSize: 12)),
        ),
      ],
    );
  }

  void _navigateToUser(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(
          userId: userId,
          currentUserId: widget.userId,
        ),
      ),
    );
  }

  void _navigateToCollection(String collectionId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CollectionDetailScreen(
          collectionId: collectionId,
          currentUserId: widget.userId,
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays > 7) {
      return '${date.day}/${date.month}/${date.year}';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  void _handleNotificationTap(String id, Map<String, dynamic> data) {
    // Mark as read
    _markAsRead(id);

    final type = (data['type'] as String? ?? '').toLowerCase();

    // Navigate based on type
    switch (type) {
      case 'follow':
      case 'new_follower':
      case 'follow_request':
        if (data['fromUserId'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserProfileScreen(
                userId: data['fromUserId'],
                currentUserId: widget.userId,
              ),
            ),
          );
        }
        break;
      case 'like':
      case 'like_collection':
      case 'like_item':
      case 'save':
      case 'save_collection':
      case 'new_item':
      case 'new_collection':
      case 'comment':
      case 'comment_reply':
      case 'comment_like':
      case 'comment_mention':
      case 'collaborate':
      case 'collaboration_invite':
      case 'collaborator_added':
      case 'collaboration_accepted':
      case 'collaboration_request':
        if (data['collectionId'] != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CollectionDetailScreen(
                collectionId: data['collectionId'],
                currentUserId: widget.userId,
              ),
            ),
          );
        }
        break;
    }
  }

  void _markAsRead(String id) {
    _firestore
        .collection('notifications')
        .doc(id)
        .update({'isRead': true});
  }

  // ignore: unused_element
  void _toggleRead(String id, bool currentlyRead) {
    _firestore
        .collection('notifications')
        .doc(id)
        .update({'isRead': !currentlyRead});
  }

  // ignore: unused_element
  void _deleteNotification(String id) {
    _firestore
        .collection('notifications')
        .doc(id)
        .delete();
  }

  void _markAllAsRead() async {
    final notifications = await _firestore
        .collection('notifications')
        .where('toUserId', isEqualTo: widget.userId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _firestore.batch();
    for (final doc in notifications.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();

    if (mounted) {
      SnackBarUtils.showSuccessSnackBar(context, 'All notifications marked as read');
    }
  }
}

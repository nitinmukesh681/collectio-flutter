import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
import '../services/firestore_service.dart';
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Followed back')),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not follow back: $e')),
            );
          }
        }
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primaryPurple,
        side: const BorderSide(color: AppColors.primaryPurple, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: const Text(
        'Follow Back',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
      ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all),
            tooltip: 'Mark all as read',
            onPressed: _markAllAsRead,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
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
            return Center(child: Text('Error: ${snapshot.error}'));
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
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We\'ll notify you when something happens',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = notifications[index];
              final data = doc.data() as Map<String, dynamic>;
              return _buildNotificationTile(doc.id, data);
            },
          );
        },
      ),
    );
  }

  Widget _buildNotificationTile(String id, Map<String, dynamic> data) {
    final type = (data['type'] as String? ?? 'unknown').toLowerCase();
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
        break;
      default:
        icon = Icons.notifications_rounded;
        iconColor = AppColors.textMuted;
        actionText = '';
    }

    final unreadBg = AppColors.primaryPurple.withOpacity(0.05);
    final cardColor = isRead ? Colors.white : unreadBg;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _handleNotificationTap(id, data),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isRead ? const Color(0xFFF1F5F9) : AppColors.primaryPurple.withOpacity(0.1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: (data['fromUserAvatarUrl'] != null && (data['fromUserAvatarUrl'] as String).isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: data['fromUserAvatarUrl'],
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) {
                                return Icon(icon, color: iconColor, size: 24);
                              },
                            )
                          : Icon(icon, color: iconColor, size: 24),
                    ),
                  ),
                  if (!isRead)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.primaryPurple,
                          shape: BoxShape.circle,
                          border: Border.all(color: cardColor, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.textPrimary,
                          fontFamily: 'Inter',
                          height: 1.3,
                        ),
                        children: [
                          TextSpan(
                            text: fromUsername,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          TextSpan(
                            text: actionText.isNotEmpty
                                ? actionText
                                : (data['message'] as String? ?? ' sent you a notification'),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      timeAgo,
                      style: TextStyle(
                        fontSize: 12,
                        color: isRead ? AppColors.textMuted : AppColors.primaryPurple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (showFollowBack) ...[
                      const SizedBox(height: 12),
                      _buildFollowBackRow(fromUserId),
                    ],
                  ],
                ),
              ),
              PopupMenuButton(
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.more_vert_rounded, size: 20, color: Colors.black45),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'read',
                    child: Text(isRead ? 'Mark as unread' : 'Mark as read'),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Delete', style: TextStyle(color: Colors.red)),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'read') {
                    _toggleRead(id, isRead);
                  } else if (value == 'delete') {
                    _deleteNotification(id);
                  }
                },
              ),
            ],
          ),
        ),
      ),
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
      case 'collaborate':
      case 'collaboration_invite':
      case 'collaborator_added':
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

  void _toggleRead(String id, bool currentlyRead) {
    _firestore
        .collection('notifications')
        .doc(id)
        .update({'isRead': !currentlyRead});
  }

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All notifications marked as read')),
      );
    }
  }
}

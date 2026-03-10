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
        side: const BorderSide(color: AppColors.primaryPurple),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      child: const Text(
        'Follow Back',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
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
      appBar: AppBar(
        title: const Text('Notifications'),
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
                  Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No notifications yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'We\'ll notify you when something happens',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: notifications.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
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
    final type = data['type'] as String? ?? 'unknown';
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
      case 'FOLLOW':
      case 'NEW_FOLLOWER':
        icon = Icons.person_add;
        iconColor = AppColors.primaryPurple;
        actionText = ' started following you';
        showFollowBack = true;
        break;
      case 'like':
      case 'LIKE_COLLECTION':
      case 'LIKE_ITEM':
        icon = Icons.favorite;
        iconColor = AppColors.heartSalmon;
        actionText = ' liked your collection';
        subtitle = collectionTitle;
        break;
      case 'save':
      case 'SAVE_COLLECTION': // Assuming hypothetical android type
        icon = Icons.bookmark;
        iconColor = Colors.amber;
        actionText = ' saved your collection';
        subtitle = collectionTitle;
        break;
      case 'new_item':
      case 'NEW_COLLECTION': // Mapping NEW_COLLECTION to this for now or separate
        icon = Icons.add_circle;
        iconColor = Colors.green;
        actionText = ' created a new collection';
        subtitle = collectionTitle;
        break;
      case 'collaborate':
      case 'COLLABORATION_INVITE':
      case 'COLLABORATOR_ADDED':
        icon = Icons.group_add;
        iconColor = Colors.blue;
        actionText = ' invited you to collaborate';
        subtitle = collectionTitle;
        break;
      default:
        icon = Icons.notifications;
        iconColor = Colors.grey;
        actionText = '';
    }

    final bgColor = isRead ? Colors.white : AppColors.primaryPurple.withOpacity(0.04);

    return Material(
      color: bgColor,
      child: InkWell(
        onTap: () => _handleNotificationTap(id, data),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.18),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: (data['fromUserAvatarUrl'] != null && (data['fromUserAvatarUrl'] as String).isNotEmpty)
                          ? CachedNetworkImage(
                              imageUrl: data['fromUserAvatarUrl'],
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) {
                                return Icon(icon, color: iconColor, size: 22);
                              },
                            )
                          : Icon(icon, color: iconColor, size: 22),
                    ),
                  ),
                  if (!isRead)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.primaryPurple,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (fromUserId != null && fromUserId.isNotEmpty) {
                              _navigateToUser(fromUserId);
                            }
                          },
                          child: Text(
                            fromUsername,
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              height: 1.25,
                            ),
                          ),
                        ),
                        Text(
                          actionText.isNotEmpty
                              ? actionText
                              : (data['message'] as String? ?? ' sent you a notification'),
                          style: const TextStyle(
                            fontSize: 15,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w400,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () {
                          if (collectionId != null && collectionId.isNotEmpty) {
                            _navigateToCollection(collectionId);
                          }
                        },
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      timeAgo,
                      style: TextStyle(fontSize: 12.5, color: Colors.grey[500]),
                    ),
                    if (showFollowBack) ...[
                      const SizedBox(height: 10),
                      _buildFollowBackRow(fromUserId),
                    ],
                  ],
                ),
              ),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert, size: 20, color: Colors.black54),
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

    final type = data['type'] as String? ?? '';

    // Navigate based on type
    switch (type) {
      case 'follow':
      case 'NEW_FOLLOWER':
      case 'FOLLOW_REQUEST':
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
      case 'LIKE_COLLECTION':
      case 'LIKE_ITEM':
      case 'save':
      case 'new_item':
      case 'collaborate':
      case 'COLLABORATION_INVITE':
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

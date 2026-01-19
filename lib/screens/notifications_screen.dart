import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';
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
    String title;
    String? subtitle;

    switch (type) {
      case 'follow':
        icon = Icons.person_add;
        iconColor = AppColors.primaryPurple;
        title = '${data['fromUserName'] ?? 'Someone'} started following you';
        break;
      case 'like':
        icon = Icons.favorite;
        iconColor = AppColors.heartSalmon;
        title = '${data['fromUserName'] ?? 'Someone'} liked your collection';
        subtitle = data['collectionTitle'];
        break;
      case 'save':
        icon = Icons.bookmark;
        iconColor = Colors.amber;
        title = '${data['fromUserName'] ?? 'Someone'} saved your collection';
        subtitle = data['collectionTitle'];
        break;
      case 'new_item':
        icon = Icons.add_circle;
        iconColor = Colors.green;
        title = '${data['fromUserName'] ?? 'Someone'} added an item to your collection';
        subtitle = data['collectionTitle'];
        break;
      case 'collaborate':
        icon = Icons.group_add;
        iconColor = Colors.blue;
        title = '${data['fromUserName'] ?? 'Someone'} invited you to collaborate';
        subtitle = data['collectionTitle'];
        break;
      default:
        icon = Icons.notifications;
        iconColor = Colors.grey;
        title = data['message'] ?? 'New notification';
    }

    return ListTile(
      onTap: () => _handleNotificationTap(id, data),
      tileColor: isRead ? null : AppColors.primaryPurple.withOpacity(0.05),
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: iconColor.withOpacity(0.2),
            backgroundImage: data['fromUserAvatar'] != null
                ? CachedNetworkImageProvider(data['fromUserAvatar'])
                : null,
            child: data['fromUserAvatar'] == null
                ? Icon(icon, color: iconColor, size: 24)
                : null,
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
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isRead ? FontWeight.normal : FontWeight.w600,
          fontSize: 14,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null)
            Text(
              subtitle,
              style: const TextStyle(fontSize: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          Text(
            timeAgo,
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
      trailing: PopupMenuButton(
        icon: const Icon(Icons.more_vert, size: 20),
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
      case 'save':
      case 'new_item':
      case 'collaborate':
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

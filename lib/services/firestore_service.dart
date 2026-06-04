import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:async/async.dart';
import 'dart:io';
import '../models/category_type.dart';
import '../models/collection_entity.dart';
import '../models/collection_item_entity.dart';
import '../models/user_entity.dart';
import '../models/comment_entity.dart';
import '../utils/comment_mentions.dart';
import '../utils/search_tokenizer.dart';
import '../utils/username_utils.dart';


/// Firestore service for database operations
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Collection references
  CollectionReference get _usersRef => _firestore.collection('users');
  CollectionReference get _collectionsRef => _firestore.collection('collections');
  CollectionReference get _collectionItemsRef => _firestore.collection('collectionItems');

  String _collectionCategoryFromMap(Map<String, dynamic> data) =>
      CategoryType.fromString(data['category'] as String?).name;

  /// Resolves a collection's category name for activity notifications.
  Future<String> getCollectionCategoryName(String collectionId) async {
    final doc = await _collectionsRef.doc(collectionId).get();
    if (!doc.exists) return CategoryType.other.name;
    return _collectionCategoryFromMap(doc.data() as Map<String, dynamic>);
  }

  /// Sorts collections by most recent content change (items, title, description, etc.).
  void _sortCollectionsByContentActivity(List<CollectionEntity> collections) {
    collections.sort((a, b) => b.lastContentActivityAt.compareTo(a.lastContentActivityAt));
  }

  /// Bumps collection `updatedAt` when items or other collection content changes.
  Future<void> _touchCollectionContentUpdatedAt(String collectionId) async {
    try {
      await _collectionsRef.doc(collectionId).update({
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Could not update collection updatedAt: $e');
    }
  }
  CollectionReference get _commentsRef => _firestore.collection('comments');
  CollectionReference get _reportsRef => _firestore.collection('reports');

  // ==================== COMMENTS ====================

  Stream<List<CommentEntity>> getCommentsStream(String collectionId) {
    return _commentsRef
        .where('collectionId', isEqualTo: collectionId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => CommentEntity.fromMap(d.data() as Map<String, dynamic>, d.id))
              .toList();
          list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return list;
        });
  }

  Future<String> addComment({
    required String collectionId,
    required String userId,
    required String userName,
    String? userAvatarUrl,
    required String text,
    String? parentCommentId,
    List<CommentMention> confirmedMentions = const [],
  }) async {
    final normalizedParentId = _normalizeCommentParentId(parentCommentId);
    final mentions = confirmedMentions
        .where((mention) => mention.userId.isNotEmpty && mention.username.isNotEmpty)
        .where((mention) => text.contains('@${mention.username}'))
        .toList();

    final commentData = <String, dynamic>{
      'collectionId': collectionId,
      'userId': userId,
      'userName': UsernameUtils.normalize(userName),
      'userAvatarUrl': userAvatarUrl,
      'text': text,
      'likes': 0,
      'likedBy': [],
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (normalizedParentId != null) {
      commentData['parentCommentId'] = normalizedParentId;
    }
    if (mentions.isNotEmpty) {
      commentData['mentions'] = mentions.map((m) => m.toMap()).toList();
    }

    final docRef = await _commentsRef.add(commentData);

    try {
      final collectionSnap = await _collectionsRef.doc(collectionId).get();
      if (collectionSnap.exists) {
        final data = collectionSnap.data() as Map<String, dynamic>;
        final ownerId = data['userId'] as String? ?? '';
        final title = data['title'] as String? ?? '';
        final collectionCategory = _collectionCategoryFromMap(data);
        final notifiedUserIds = await _sendCommentNotifications(
          commentId: docRef.id,
          collectionId: collectionId,
          collectionTitle: title,
          collectionCategory: collectionCategory,
          ownerId: ownerId,
          userId: userId,
          userName: userName,
          userAvatarUrl: userAvatarUrl,
          text: text,
          parentCommentId: normalizedParentId,
        );
        await _sendMentionNotifications(
          commentId: docRef.id,
          collectionId: collectionId,
          collectionTitle: title,
          collectionCategory: collectionCategory,
          userId: userId,
          userName: userName,
          userAvatarUrl: userAvatarUrl,
          text: text,
          mentions: mentions,
          excludeUserIds: notifiedUserIds,
        );
      }
    } catch (e) {
      debugPrint('Comment notification error: $e');
    }

    return docRef.id;
  }

  String? _normalizeCommentParentId(String? parentCommentId) {
    final trimmed = parentCommentId?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  Future<Set<String>> _sendCommentNotifications({
    required String commentId,
    required String collectionId,
    required String collectionTitle,
    required String collectionCategory,
    required String ownerId,
    required String userId,
    required String userName,
    String? userAvatarUrl,
    required String text,
    String? parentCommentId,
  }) async {
    var resolvedAvatarUrl = userAvatarUrl;
    if (resolvedAvatarUrl == null || resolvedAvatarUrl.trim().isEmpty) {
      resolvedAvatarUrl = await _getUserAvatarUrl(userId);
    }

    final notifiedUserIds = <String>{};

    Future<void> createNotification({
      required String toUserId,
      required String type,
    }) async {
      if (toUserId.isEmpty || toUserId == userId) return;

      final payload = <String, dynamic>{
        'toUserId': toUserId,
        'type': type,
        'fromUserId': userId,
        'fromUsername': UsernameUtils.normalize(userName),
        'fromUserAvatarUrl': resolvedAvatarUrl,
        'collectionId': collectionId,
        'collectionTitle': collectionTitle,
        'collectionCategory': collectionCategory,
        'commentId': commentId,
        'message': text,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (parentCommentId != null) {
        payload['parentCommentId'] = parentCommentId;
      }
      await _firestore.collection('notifications').add(payload);
      notifiedUserIds.add(toUserId);
    }

    if (parentCommentId == null) {
      await createNotification(toUserId: ownerId, type: 'COMMENT');
      return notifiedUserIds;
    }

    final parentSnap = await _commentsRef.doc(parentCommentId).get();
    final parentAuthorId = parentSnap.exists
        ? (parentSnap.data() as Map<String, dynamic>)['userId'] as String? ?? ''
        : '';

    if (parentAuthorId.isNotEmpty) {
      await createNotification(toUserId: parentAuthorId, type: 'COMMENT_REPLY');
    }

    if (ownerId.isNotEmpty && ownerId != parentAuthorId) {
      await createNotification(toUserId: ownerId, type: 'COMMENT');
    }

    return notifiedUserIds;
  }

  Future<List<CommentMention>> _resolveCommentMentions(String text) async {
    final usernames = CommentMentions.extractUsernames(text);
    if (usernames.isEmpty) return const [];

    final users = await getUsersByUsernames(usernames);
    final usersByLowerUsername = {
      for (final user in users) user.username.toLowerCase(): user,
    };

    final mentions = <CommentMention>[];
    final seenUserIds = <String>{};
    for (final username in usernames) {
      final user = usersByLowerUsername[username.toLowerCase()];
      if (user == null || user.id.isEmpty || seenUserIds.contains(user.id)) continue;
      seenUserIds.add(user.id);
      mentions.add(CommentMention(userId: user.id, username: user.username));
    }
    return mentions;
  }

  Future<void> _sendMentionNotifications({
    required String commentId,
    required String collectionId,
    required String collectionTitle,
    required String collectionCategory,
    required String userId,
    required String userName,
    String? userAvatarUrl,
    required String text,
    required List<CommentMention> mentions,
    Set<String> excludeUserIds = const {},
  }) async {
    var resolvedAvatarUrl = userAvatarUrl;
    if (resolvedAvatarUrl == null || resolvedAvatarUrl.trim().isEmpty) {
      resolvedAvatarUrl = await _getUserAvatarUrl(userId);
    }

    final sentUserIds = <String>{...excludeUserIds};
    for (final mention in mentions) {
      if (mention.userId.isEmpty || mention.userId == userId) continue;
      if (sentUserIds.contains(mention.userId)) continue;
      sentUserIds.add(mention.userId);

      await _firestore.collection('notifications').add({
        'toUserId': mention.userId,
        'type': 'COMMENT_MENTION',
        'fromUserId': userId,
        'fromUsername': UsernameUtils.normalize(userName),
        'fromUserAvatarUrl': resolvedAvatarUrl,
        'collectionId': collectionId,
        'collectionTitle': collectionTitle,
        'collectionCategory': collectionCategory,
        'commentId': commentId,
        'message': text,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> toggleCommentLike(String commentId, String userId) async {
    try {
      final ref = _commentsRef.doc(commentId);
      final snap = await ref.get();
      if (!snap.exists) {
        throw StateError('Comment not found');
      }
      final data = snap.data() as Map<String, dynamic>;
      final likedBy = List<String>.from(data['likedBy'] ?? []);

      if (likedBy.contains(userId)) {
        await ref.update({
          'likedBy': FieldValue.arrayRemove([userId]),
          'likes': FieldValue.increment(-1),
        });
      } else {
        await ref.update({
          'likedBy': FieldValue.arrayUnion([userId]),
          'likes': FieldValue.increment(1),
        });

        // Notify comment author
        try {
          final commentUserId = data['userId'] as String? ?? '';
          final collectionId = data['collectionId'] as String? ?? '';
          if (commentUserId.isNotEmpty && commentUserId != userId) {
            final fromUsername = await _getUsername(userId);
            final fromUserAvatarUrl = await _getUserAvatarUrl(userId);
            String collectionTitle = '';
            var collectionCategory = CategoryType.other.name;
            if (collectionId.isNotEmpty) {
              final collectionSnap = await _collectionsRef.doc(collectionId).get();
              if (collectionSnap.exists) {
                final collectionData =
                    collectionSnap.data() as Map<String, dynamic>;
                collectionTitle = collectionData['title'] as String? ?? '';
                collectionCategory = _collectionCategoryFromMap(collectionData);
              }
            }
            await _firestore.collection('notifications').add({
              'toUserId': commentUserId,
              'type': 'COMMENT_LIKE',
              'fromUserId': userId,
              'fromUsername': UsernameUtils.normalize(fromUsername),
              if (fromUserAvatarUrl != null) 'fromUserAvatarUrl': fromUserAvatarUrl,
              'collectionId': collectionId,
              'collectionTitle': collectionTitle,
              'collectionCategory': collectionCategory,
              'commentId': commentId,
              'message': data['text'] ?? '',
              'isRead': false,
              'createdAt': FieldValue.serverTimestamp(),
            });
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('FirestoreService: toggleCommentLike ERROR: $e');
      rethrow;
    }
  }

  /// Deletes a comment when [requestingUserId] is the author or collection owner.
  Future<void> deleteComment(
    String commentId, {
    required String requestingUserId,
  }) async {
    final snap = await _commentsRef.doc(commentId).get();
    if (!snap.exists) return;

    final data = snap.data() as Map<String, dynamic>;
    final commentUserId = data['userId'] as String? ?? '';
    if (commentUserId == requestingUserId) {
      await _commentsRef.doc(commentId).delete();
      return;
    }

    final collectionId = data['collectionId'] as String? ?? '';
    if (collectionId.isNotEmpty) {
      final collection = await getCollection(collectionId);
      if (collection?.userId == requestingUserId) {
        await _commentsRef.doc(commentId).delete();
        return;
      }
    }

    throw Exception('Not authorized to delete this comment');
  }

  Future<String> _getUsername(String userId) async {
    final userDoc = await _usersRef.doc(userId).get();
    if (!userDoc.exists) return 'Someone';
    final data = userDoc.data() as Map<String, dynamic>;
    final name = (data['username'] as String?) ??
        (data['userName'] as String?) ??
        (data['displayName'] as String?) ??
        '';
    final trimmed = name.trim();
    return trimmed.isNotEmpty ? UsernameUtils.normalize(trimmed) : 'Someone';
  }

  Future<String?> _getUserAvatarUrl(String userId) async {
    if (userId.isEmpty) return null;
    try {
      final user = await getUser(userId);
      final avatar = user?.avatarUrl?.trim();
      if (avatar != null && avatar.isNotEmpty) return avatar;
    } catch (_) {}
    return null;
  }

  Future<void> _createLikeNotification({
    required String toUserId,
    required String fromUserId,
    required String fromUsername,
    required String collectionId,
    required String collectionTitle,
    String itemId = '',
    String itemTitle = '',
    required String type,
  }) async {
    if (toUserId == fromUserId) return;

    final collectionDoc = await _collectionsRef.doc(collectionId).get();
    if (!collectionDoc.exists) return;
    final c = collectionDoc.data() as Map<String, dynamic>;
    final isPublic = c['isPublic'] as bool? ?? true;
    final visibility = c['visibility'] as String?;
    final isPrivate = !isPublic || visibility == 'PRIVATE';
    if (isPrivate) return;

    final payload = <String, dynamic>{
      'toUserId': toUserId,
      'type': type,
      'fromUserId': fromUserId,
      'fromUsername': UsernameUtils.normalize(fromUsername),
      'collectionId': collectionId,
      'collectionTitle': collectionTitle,
      'collectionCategory': _collectionCategoryFromMap(c),
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
    final fromUserAvatarUrl = await _getUserAvatarUrl(fromUserId);
    if (fromUserAvatarUrl != null) {
      payload['fromUserAvatarUrl'] = fromUserAvatarUrl;
    }
    if (itemId.isNotEmpty) payload['itemId'] = itemId;
    if (itemTitle.isNotEmpty) payload['itemTitle'] = itemTitle;

    await _firestore.collection('notifications').add(payload);
  }


  // ==================== USER OPERATIONS ====================

  /// Get user by ID
  Future<UserEntity?> getUser(String userId) async {
    final doc = await _usersRef.doc(userId).get();
    if (!doc.exists) return null;
    return UserEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }

  /// Get user by ID as a real-time stream
  Stream<UserEntity?> getUserStream(String userId) {
    return _usersRef.doc(userId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return UserEntity.fromMap(snapshot.data() as Map<String, dynamic>, snapshot.id);
    });
  }

  Future<List<UserEntity>> getUsersByIds(List<String> userIds) async {
    final ids = userIds.where((e) => e.trim().isNotEmpty).toSet().toList();
    if (ids.isEmpty) return [];

    final users = <UserEntity>[];
    for (final chunk in _chunk(ids, 10)) {
      final snapshot = await _usersRef
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        users.add(UserEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id));
      }
    }
    return users;
  }

  List<List<T>> _chunk<T>(List<T> items, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < items.length; i += size) {
      chunks.add(items.sublist(i, (i + size).clamp(0, items.length)));
    }
    return chunks;
  }

  /// Removes the user's profile photo from Storage and Firestore.
  Future<void> clearUserAvatar(String userId) async {
    try {
      await _storage.ref().child('avatars/$userId.jpg').delete();
    } catch (e) {
      debugPrint('Could not delete avatar from storage: $e');
    }
    await _usersRef.doc(userId).update({'avatarUrl': FieldValue.delete()});
    await syncUserAvatarDenormalized(userId: userId, avatarUrl: null);
  }

  /// Updates denormalized avatar URLs on the user's collections and comments.
  Future<void> syncUserAvatarDenormalized({
    required String userId,
    required String? avatarUrl,
  }) async {
    final updateData = (avatarUrl == null || avatarUrl.trim().isEmpty)
        ? {'userAvatarUrl': FieldValue.delete()}
        : {'userAvatarUrl': avatarUrl.trim()};

    final notificationUpdate = (avatarUrl == null || avatarUrl.trim().isEmpty)
        ? {'fromUserAvatarUrl': FieldValue.delete()}
        : {'fromUserAvatarUrl': avatarUrl.trim()};

    try {
      await _updateQueryDocumentsInBatches(
        _collectionsRef.where('userId', isEqualTo: userId),
        updateData,
      );
      await _updateQueryDocumentsInBatches(
        _commentsRef.where('userId', isEqualTo: userId),
        updateData,
      );
      await _updateQueryDocumentsInBatches(
        _firestore.collection('notifications').where('fromUserId', isEqualTo: userId),
        notificationUpdate,
      );
    } catch (e) {
      debugPrint('Could not sync avatar across content: $e');
    }
  }

  Future<void> _deleteQueryDocumentsInBatches(Query query) async {
    const pageSize = 200;
    QueryDocumentSnapshot? lastDoc;

    while (true) {
      var paged = query.limit(pageSize);
      if (lastDoc != null) {
        paged = paged.startAfterDocument(lastDoc);
      }

      final snapshot = await paged.get();
      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < pageSize) break;
      lastDoc = snapshot.docs.last;
    }
  }

  Future<void> _updateQueryDocumentsInBatches(
    Query query,
    Map<String, dynamic> updateData,
  ) async {
    const pageSize = 200;
    QueryDocumentSnapshot? lastDoc;

    while (true) {
      var paged = query.limit(pageSize);
      if (lastDoc != null) {
        paged = paged.startAfterDocument(lastDoc);
      }

      final snapshot = await paged.get();
      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, updateData);
      }
      await batch.commit();

      if (snapshot.docs.length < pageSize) break;
      lastDoc = snapshot.docs.last;
    }
  }

  /// Create or update user
  Future<void> saveUser(UserEntity user) async {
    final normalized = UsernameUtils.normalize(user.username);
    final data = <String, dynamic>{
      ...user.copyWith(username: normalized).toMap(),
      'usernameLower': normalized,
    };
    final avatar = user.avatarUrl?.trim();
    if (avatar == null || avatar.isEmpty) {
      data['avatarUrl'] = FieldValue.delete();
    } else {
      data['avatarUrl'] = avatar;
    }
    await _usersRef.doc(user.id).set(data, SetOptions(merge: true));
  }

  /// Update username
  Future<void> updateUsername(String userId, String username) async {
    final normalized = UsernameUtils.normalize(username);
    await _usersRef.doc(userId).update({
      'username': normalized,
      'usernameLower': normalized,
    });
  }

  /// Finds a user document id whose username matches [lower] (already normalized).
  Future<String?> findUserIdByNormalizedUsername(String lower) async {
    if (lower.isEmpty) return null;

    try {
      final byLower = await _usersRef
          .where('usernameLower', isEqualTo: lower)
          .limit(1)
          .get();
      if (byLower.docs.isNotEmpty) return byLower.docs.first.id;
    } catch (e) {
      debugPrint('findUserIdByNormalizedUsername usernameLower failed: $e');
    }

    for (final field in ['username', 'userName']) {
      try {
        final snapshot = await _usersRef.where(field, isEqualTo: lower).limit(1).get();
        if (snapshot.docs.isNotEmpty) return snapshot.docs.first.id;
      } catch (e) {
        debugPrint('findUserIdByNormalizedUsername $field failed: $e');
      }
    }

    DocumentSnapshot? lastDoc;
    while (true) {
      var query = _usersRef.orderBy(FieldPath.documentId).limit(200);
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) return null;

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data is! Map<String, dynamic>) continue;
        if (_normalizedUsernameFromMap(data) == lower) {
          return doc.id;
        }
      }

      if (snapshot.docs.length < 200) return null;
      lastDoc = snapshot.docs.last;
    }
  }

  /// Returns true when [username] is not used by another user.
  Future<bool> isUsernameAvailable(
    String username, {
    required String excludeUserId,
  }) async {
    final lower = UsernameUtils.normalize(username);
    if (lower.isEmpty) return false;

    final existingId = await findUserIdByNormalizedUsername(lower);
    if (existingId == null) return true;
    return existingId == excludeUserId;
  }

  /// Get user email by username
  Future<String?> getUserEmailByUsername(String username) async {
    final lower = UsernameUtils.normalize(username);
    if (lower.isEmpty) return null;

    final userId = await findUserIdByNormalizedUsername(lower);
    if (userId == null) return null;

    final doc = await _usersRef.doc(userId).get();
    if (!doc.exists) return null;
    return (doc.data() as Map<String, dynamic>?)?['email'] as String?;
  }

  /// Follow a user
  Future<void> followUser(String currentUserId, String targetUserId, String currentUsername) async {
    debugPrint('FirestoreService: followUser $currentUserId -> $targetUserId');
    try {
      final targetDoc = await _usersRef.doc(targetUserId).get();
      if (!targetDoc.exists) return;

      final targetData = targetDoc.data() as Map<String, dynamic>;
      final isPrivate = targetData['isPrivateAccount'] as bool? ?? false;
      if (isPrivate) {
        await requestFollowUser(currentUserId, targetUserId, currentUsername);
        return;
      }

      final currentRef = _usersRef.doc(currentUserId);
      final targetRef = _usersRef.doc(targetUserId);

      final didFollow = await _firestore.runTransaction<bool>((tx) async {
        final currentSnap = await tx.get(currentRef);
        final targetSnap = await tx.get(targetRef);
        if (!currentSnap.exists || !targetSnap.exists) return false;

        final currentData = currentSnap.data() as Map<String, dynamic>;
        final targetDataTx = targetSnap.data() as Map<String, dynamic>;

        final following = List<String>.from(currentData['following'] ?? const <String>[]);
        if (following.contains(targetUserId)) {
          return false;
        }

        final currentFollowingCount = (currentData['followingCount'] as int?) ?? 0;
        final targetFollowerCount = (targetDataTx['followerCount'] as int?) ?? 0;

        tx.update(currentRef, {
          'following': FieldValue.arrayUnion([targetUserId]),
          'followingCount': currentFollowingCount + 1,
        });
        tx.update(targetRef, {
          'followers': FieldValue.arrayUnion([currentUserId]),
          'followerCount': targetFollowerCount + 1,
        });
        return true;
      });

      if (didFollow) {
        final fromUserAvatarUrl = await _getUserAvatarUrl(currentUserId);
        await _firestore.collection('notifications').add({
          'type': 'NEW_FOLLOWER',
          'toUserId': targetUserId,
          'fromUserId': currentUserId,
          'fromUsername': UsernameUtils.normalize(currentUsername),
          if (fromUserAvatarUrl != null) 'fromUserAvatarUrl': fromUserAvatarUrl,
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      debugPrint('FirestoreService: followUser SUCCESS');
    } catch (e) {
      debugPrint('FirestoreService: followUser ERROR: $e');
      rethrow;
    }
  }

  /// Unfollow a user
  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    final targetDoc = await _usersRef.doc(targetUserId).get();
    if (!targetDoc.exists) return;

    final targetData = targetDoc.data() as Map<String, dynamic>;
    final pending = List<String>.from(targetData['followRequests'] ?? const <String>[]);
    if (pending.contains(currentUserId)) {
      await cancelFollowRequest(currentUserId, targetUserId);
      return;
    }

    final currentRef = _usersRef.doc(currentUserId);
    final targetRef = _usersRef.doc(targetUserId);

    await _firestore.runTransaction<void>((tx) async {
      final currentSnap = await tx.get(currentRef);
      final targetSnap = await tx.get(targetRef);
      if (!currentSnap.exists || !targetSnap.exists) return;

      final currentData = currentSnap.data() as Map<String, dynamic>;
      final targetDataTx = targetSnap.data() as Map<String, dynamic>;

      final following = List<String>.from(currentData['following'] ?? const <String>[]);
      if (!following.contains(targetUserId)) {
        return;
      }

      final currentFollowingCount = (currentData['followingCount'] as int?) ?? 0;
      final targetFollowerCount = (targetDataTx['followerCount'] as int?) ?? 0;

      tx.update(currentRef, {
        'following': FieldValue.arrayRemove([targetUserId]),
        'followingCount': (currentFollowingCount - 1) < 0 ? 0 : (currentFollowingCount - 1),
      });
      tx.update(targetRef, {
        'followers': FieldValue.arrayRemove([currentUserId]),
        'followerCount': (targetFollowerCount - 1) < 0 ? 0 : (targetFollowerCount - 1),
      });
    });
  }

  // ==================== COLLECTION OPERATIONS ====================

  /// Get collections for a user (Stream)
  Stream<List<CollectionEntity>> getUserCollectionsStream(String userId) {
    debugPrint('FirestoreService: Creating collections stream for userId: $userId');
    return _collectionsRef
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
          debugPrint('FirestoreService: Collections snapshot updated - ${snapshot.docs.length} documents');
          final collections = snapshot.docs
              .map((doc) => CollectionEntity.fromMap(
                  doc.data() as Map<String, dynamic>, doc.id))
              .toList();
          _sortCollectionsByContentActivity(collections);
          return collections;
        });
  }

  /// Get collections for a user (Future)
  Future<List<CollectionEntity>> getUserCollections(String userId) async {
    final snapshot = await _collectionsRef
        .where('userId', isEqualTo: userId)
        .get();
    final collections = snapshot.docs
        .map((doc) => CollectionEntity.fromMap(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    _sortCollectionsByContentActivity(collections);
    return collections;
  }

  int _savedAtForUser(
    CollectionEntity collection,
    String userId, {
    Map<String, int>? userSavedAt,
  }) {
    final fromUser = userSavedAt?[collection.id];
    if (fromUser != null && fromUser > 0) return fromUser;
    return collection.savedAt[userId] ?? 0;
  }

  /// Whether [userId] has saved [collection] (user doc is source of truth).
  bool isCollectionSavedByUser({
    required CollectionEntity collection,
    required String userId,
    List<String>? userSavedCollectionIds,
  }) {
    if (userSavedCollectionIds != null &&
        userSavedCollectionIds.contains(collection.id)) {
      return true;
    }
    return collection.savedBy.contains(userId);
  }

  Future<List<CollectionEntity>> _fetchCollectionsByIds(List<String> ids) async {
    final uniqueIds = ids.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (uniqueIds.isEmpty) return [];

    final byId = <String, CollectionEntity>{};
    for (final chunk in _chunk(uniqueIds, 10)) {
      final snapshot = await _collectionsRef
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        byId[doc.id] = CollectionEntity.fromMap(
          doc.data() as Map<String, dynamic>,
          doc.id,
        );
      }
    }

    return uniqueIds
        .map((id) => byId[id])
        .whereType<CollectionEntity>()
        .toList();
  }

  /// Get saved collections for a user
  Future<List<CollectionEntity>> getSavedCollections(String userId) async {
    final user = await getUser(userId);
    if (user == null || user.savedCollections.isEmpty) {
      return [];
    }

    final collections = await _fetchCollectionsByIds(user.savedCollections);
    _sortSavedCollections(
      collections,
      userId,
      userSavedAt: user.savedCollectionsAt,
    );
    return collections;
  }

  void _sortSavedCollections(
    List<CollectionEntity> collections,
    String userId, {
    Map<String, int>? userSavedAt,
  }) {
    collections.sort((a, b) {
      final aTime = _savedAtForUser(a, userId, userSavedAt: userSavedAt);
      final bTime = _savedAtForUser(b, userId, userSavedAt: userSavedAt);
      return bTime.compareTo(aTime);
    });
  }

  /// Get saved collections for a user (Stream)
  Stream<List<CollectionEntity>> getSavedCollectionsStream(String userId) {
    return getUserStream(userId).asyncExpand((user) {
      if (user == null || user.savedCollections.isEmpty) {
        return Stream.value(<CollectionEntity>[]);
      }

      final ids = user.savedCollections.where((id) => id.trim().isNotEmpty).toList();
      if (ids.isEmpty) return Stream.value(<CollectionEntity>[]);

      final streams = ids.map((id) {
        return _collectionsRef.doc(id).snapshots().map((doc) {
          if (!doc.exists) return null;
          return CollectionEntity.fromMap(
            doc.data() as Map<String, dynamic>,
            doc.id,
          );
        });
      }).toList();

      return Rx.combineLatestList<CollectionEntity?>(streams).map((collections) {
        final byId = <String, CollectionEntity>{
          for (final c in collections)
            if (c != null) c.id: c,
        };
        final ordered = ids.map((id) => byId[id]).whereType<CollectionEntity>().toList();
        _sortSavedCollections(
          ordered,
          userId,
          userSavedAt: user.savedCollectionsAt,
        );
        return ordered;
      });
    });
  }

  /// Get public collections feed
  Stream<List<CollectionEntity>> getPublicCollections({int limit = 20}) {
    return _collectionsRef
        .where('isPublic', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CollectionEntity.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  /// Get public collections as a list (Future)
  Future<List<CollectionEntity>> getPublicCollectionsList({int limit = 20}) async {
    final snapshot = await _collectionsRef
        .where('isPublic', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snapshot.docs
        .map((doc) => CollectionEntity.fromMap(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  /// Get public collections as a real-time stream
  Stream<List<CollectionEntity>> getPublicCollectionsStream({int limit = 20}) {
    return _collectionsRef
        .where('isPublic', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CollectionEntity.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  /// Get collections for a specific user (for ImportLinkScreen)
  Future<List<CollectionEntity>> getUserCollectionsList(String userId) async {
    final snapshot = await _collectionsRef
        .where('userId', isEqualTo: userId)
        .get();
    final collections = snapshot.docs
        .map((doc) => CollectionEntity.fromMap(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    _sortCollectionsByContentActivity(collections);
    return collections.take(50).toList();
  }

  /// Add a link-only item to a collection
  Future<void> addLinkItem({
    required String collectionId,
    required String userId,
    required String userName,
    required String title,
    required String websiteUrl,
    String? description,
  }) async {
    final trimmedDescription = description?.trim();
    final docRef = _collectionItemsRef.doc();
    final collectionRef = _collectionsRef.doc(collectionId);

  final itemData = {
      'collectionId': collectionId,
      'userId': userId,
      'userName': UsernameUtils.normalize(userName),
      'title': title,
      'websiteUrl': websiteUrl,
      'description': (trimmedDescription != null && trimmedDescription.isNotEmpty)
          ? trimmedDescription
          : null,
      'imageUrls': [],
      'likes': 0,
      'likedBy': [],
      'rating': 0.0,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _firestore.runTransaction((tx) async {
      final collectionSnap = await tx.get(collectionRef);
      if (!collectionSnap.exists) {
        throw Exception('Collection not found');
      }

      final data = collectionSnap.data() as Map<String, dynamic>;
      final currentItemCount = (data['itemCount'] as int?) ?? 0;

      tx.set(docRef, {...itemData, 'order': currentItemCount});
      tx.update(collectionRef, {
        'itemCount': currentItemCount + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<CollectionEntity?> getCollection(String collectionId) async {
    final doc = await _collectionsRef.doc(collectionId).get();
    if (!doc.exists) return null;
    return CollectionEntity.fromMap(
        doc.data() as Map<String, dynamic>, doc.id);
  }

  /// Get a single collection as a real-time stream
  Stream<CollectionEntity?> getCollectionStream(String collectionId) {
    return _collectionsRef.doc(collectionId).snapshots().map((snapshot) {
      if (!snapshot.exists) return null;
      return CollectionEntity.fromMap(snapshot.data() as Map<String, dynamic>, snapshot.id);
    });
  }

  /// Create a new collection
  Future<String> createCollection(CollectionEntity collection) async {
    var userName = UsernameUtils.normalize(collection.userName.trim());
    var userAvatarUrl = collection.userAvatarUrl;

    if (userName.isEmpty) {
      final user = await getUser(collection.userId);
      userName = UsernameUtils.normalize(user?.userName.trim() ?? '');
      userAvatarUrl ??= user?.avatarUrl;
    }
    if (userName.isEmpty) {
      final resolved = await _getUsername(collection.userId);
      userName = UsernameUtils.normalize(
        resolved == 'Someone' ? 'User' : resolved,
      );
    }

    final resolvedCollection = collection.copyWith(
      userName: userName,
      userAvatarUrl: userAvatarUrl,
    );

    final searchKeywords = await _buildSearchKeywords(
      resolvedCollection,
      items: const [],
    );

    final docRef = await _collectionsRef.add({
      ...resolvedCollection.toMap(),
      'searchKeywords': searchKeywords,
      'savedBy': resolvedCollection.savedBy,
      'contributorIds': resolvedCollection.contributorIds,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    await _usersRef.doc(collection.userId).update({
      'collectionsCount': FieldValue.increment(1),
    });

    return docRef.id;
  }

  /// Update a collection
  Future<void> updateCollection(CollectionEntity collection) async {
    final searchKeywords = await _buildSearchKeywords(collection);
    await _collectionsRef.doc(collection.id).update({
      ...collection.toMap(),
      'searchKeywords': searchKeywords,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a collection and its items (and related comments).
  Future<void> deleteCollection(String collectionId, String userId) async {
    final collectionRef = _collectionsRef.doc(collectionId);
    final collectionSnap = await collectionRef.get();
    if (!collectionSnap.exists) return;

    final ownerId =
        (collectionSnap.data() as Map<String, dynamic>?)?['userId'] as String? ??
            userId;

    await _deleteQueryDocumentsInBatches(
      _collectionItemsRef.where('collectionId', isEqualTo: collectionId),
    );
    await _deleteQueryDocumentsInBatches(
      _commentsRef.where('collectionId', isEqualTo: collectionId),
    );

    await collectionRef.delete();

    try {
      await _usersRef.doc(ownerId).update({
        'collectionsCount': FieldValue.increment(-1),
      });
    } catch (e) {
      debugPrint('Could not decrement collectionsCount after delete: $e');
    }
  }

  /// Like a collection
  Future<void> likeCollection(String collectionId, String userId) async {
    debugPrint('FirestoreService: likeCollection $collectionId by $userId');
    try {
      await _collectionsRef.doc(collectionId).update({
        'likedBy': FieldValue.arrayUnion([userId]),
        'likes': FieldValue.increment(1),
      });
      debugPrint('FirestoreService: likeCollection SUCCESS');
    } catch (e) {
      debugPrint('FirestoreService: likeCollection ERROR: $e');
      rethrow;
    }
  }

  Future<void> toggleCollectionLike(String collectionId, String userId) async {
    debugPrint('FirestoreService: toggleCollectionLike $collectionId by $userId');
    try {
      final fromUsername = await _getUsername(userId);
      final docRef = _collectionsRef.doc(collectionId);

      // Read current state
      final snap = await docRef.get();
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final likedBy = List<String>.from(data['likedBy'] ?? const <String>[]);
      final ownerId = (data['userId'] as String?) ?? '';
      final title = (data['title'] as String?) ?? '';
      final isLiked = likedBy.contains(userId);

      // Update collection document (best-effort for non-owners)
      try {
        if (isLiked) {
          await docRef.update({
            'likedBy': FieldValue.arrayRemove([userId]),
            'likes': FieldValue.increment(-1),
          });
        } else {
          await docRef.update({
            'likedBy': FieldValue.arrayUnion([userId]),
            'likes': FieldValue.increment(1),
          });
        }
      } catch (e) {
        debugPrint('Could not update collection likes (permission): $e');
        // Don't rethrow — the user's intent is recorded via optimistic UI
        return;
      }

      // Send notification on new like
      if (!isLiked) {
        try {
          await _createLikeNotification(
            toUserId: ownerId,
            fromUserId: userId,
            fromUsername: fromUsername,
            collectionId: collectionId,
            collectionTitle: title,
            type: 'LIKE_COLLECTION',
          );
        } catch (e) {
          debugPrint('FirestoreService: toggleCollectionLike notification ERROR: $e');
        }
      }
      debugPrint('FirestoreService: toggleCollectionLike SUCCESS');
    } catch (e) {
      debugPrint('FirestoreService: toggleCollectionLike ERROR: $e');
      rethrow;
    }
  }

  /// Unlike a collection
  Future<void> unlikeCollection(String collectionId, String userId) async {
    debugPrint('FirestoreService: unlikeCollection $collectionId by $userId');
    try {
      await _collectionsRef.doc(collectionId).update({
        'likedBy': FieldValue.arrayRemove([userId]),
        'likes': FieldValue.increment(-1),
      });
      debugPrint('FirestoreService: unlikeCollection SUCCESS');
    } catch (e) {
      debugPrint('FirestoreService: unlikeCollection ERROR: $e');
      rethrow;
    }
  }

  /// Save a collection (user doc is source of truth; collection doc is best-effort).
  Future<void> saveCollection(String collectionId, String userId) async {
    await _usersRef.doc(userId).update({
      'savedCollections': FieldValue.arrayUnion([collectionId]),
      'savedCollectionsAt.$collectionId': FieldValue.serverTimestamp(),
    });

    try {
      await _collectionsRef.doc(collectionId).update({
        'savedBy': FieldValue.arrayUnion([userId]),
        'saveCount': FieldValue.increment(1),
        'savedAt.$userId': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Could not update collection savedBy (permission): $e');
    }
  }

  Future<void> toggleCollectionSave(String collectionId, String userId) async {
    final collectionRef = _collectionsRef.doc(collectionId);
    final userRef = _usersRef.doc(userId);

    final userSnap = await userRef.get();
    final userData = userSnap.data() as Map<String, dynamic>?;
    final userSaved = List<String>.from(userData?['savedCollections'] ?? const <String>[]);
    var isSaved = userSaved.contains(collectionId);

    if (!isSaved) {
      final collectionSnap = await collectionRef.get();
      if (collectionSnap.exists) {
        final data = collectionSnap.data() as Map<String, dynamic>;
        final savedBy = List<String>.from(data['savedBy'] ?? const <String>[]);
        isSaved = savedBy.contains(userId);
      }
    }

    if (isSaved) {
      await userRef.update({
        'savedCollections': FieldValue.arrayRemove([collectionId]),
        'savedCollectionsAt.$collectionId': FieldValue.delete(),
      });
    } else {
      await userRef.update({
        'savedCollections': FieldValue.arrayUnion([collectionId]),
        'savedCollectionsAt.$collectionId': FieldValue.serverTimestamp(),
      });
    }

    try {
      if (isSaved) {
        await collectionRef.update({
          'savedBy': FieldValue.arrayRemove([userId]),
          'saveCount': FieldValue.increment(-1),
          'savedAt.$userId': FieldValue.delete(),
        });
      } else {
        await collectionRef.update({
          'savedBy': FieldValue.arrayUnion([userId]),
          'saveCount': FieldValue.increment(1),
          'savedAt.$userId': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Could not update collection savedBy (permission): $e');
    }
  }

  /// Unsave a collection
  Future<void> unsaveCollection(String collectionId, String userId) async {
    await _usersRef.doc(userId).update({
      'savedCollections': FieldValue.arrayRemove([collectionId]),
      'savedCollectionsAt.$collectionId': FieldValue.delete(),
    });

    try {
      await _collectionsRef.doc(collectionId).update({
        'savedBy': FieldValue.arrayRemove([userId]),
        'saveCount': FieldValue.increment(-1),
        'savedAt.$userId': FieldValue.delete(),
      });
    } catch (e) {
      debugPrint('Could not update collection savedBy (permission): $e');
    }
  }

  // ==================== COLLABORATOR OPERATIONS ====================

  /// Add a collaborator to a collection
  Future<void> addCollaborator({
    required String collectionId,
    required String userId,
    required String username,
    required String role,
    required String currentUserId,
    required String currentUsername,
    required String collectionTitle,
  }) async {
    final collectionRef = _collectionsRef.doc(collectionId);
    final normalizedRole = role.toUpperCase();
    var collectionCategory = CategoryType.other.name;

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(collectionRef);
      if (!snap.exists) {
        throw Exception('Collection not found');
      }

      final data = snap.data() as Map<String, dynamic>;
      collectionCategory = _collectionCategoryFromMap(data);
      final collaborators = (data['collaborators'] as List?)
              ?.map((entry) => Map<String, dynamic>.from(entry as Map))
              .toList() ??
          <Map<String, dynamic>>[];

      if (collaborators.any((c) => c['userId'] == userId)) {
        return;
      }

      collaborators.add({
        'userId': userId,
        'username': UsernameUtils.normalize(username),
        'role': normalizedRole,
        'addedAt': DateTime.now().millisecondsSinceEpoch,
      });

      final updates = <String, dynamic>{
        'collaborators': collaborators,
      };

      if (normalizedRole == 'EDITOR') {
        updates['editors'] = FieldValue.arrayUnion([userId]);
      } else {
        updates['viewers'] = FieldValue.arrayUnion([userId]);
      }

      tx.update(collectionRef, updates);
    });

    // Create notification for the invited user
    final fromUserAvatarUrl = await _getUserAvatarUrl(currentUserId);
    await _firestore.collection('notifications').add({
      'type': 'COLLABORATION_INVITE',
      'toUserId': userId,
      'fromUserId': currentUserId,
      'fromUsername': UsernameUtils.normalize(currentUsername),
      if (fromUserAvatarUrl != null) 'fromUserAvatarUrl': fromUserAvatarUrl,
      'collectionId': collectionId,
      'collectionTitle': collectionTitle,
      'collectionCategory': collectionCategory,
      'role': normalizedRole,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Remove a collaborator from a collection
  Future<void> removeCollaborator({
    required String collectionId,
    required String userId,
  }) async {
    // Get current collaborators
    final doc = await _collectionsRef.doc(collectionId).get();
    if (!doc.exists) return;

    final data = doc.data() as Map<String, dynamic>;
    final collaborators = List<Map<String, dynamic>>.from(data['collaborators'] ?? []);
    
    // Remove the collaborator
    collaborators.removeWhere((c) => c['userId'] == userId);
    
    await _collectionsRef.doc(collectionId).update({
      'collaborators': collaborators,
      'editors': FieldValue.arrayRemove([userId]),
      'viewers': FieldValue.arrayRemove([userId]),
    });
  }

  // ==================== FOLLOW REQUEST OPERATIONS ====================

  /// Request to follow a user (for private accounts)
  Future<void> requestFollowUser(String currentUserId, String targetUserId, String currentUsername) async {
    // Add to target's pending requests
    await _usersRef.doc(targetUserId).update({
      'followRequests': FieldValue.arrayUnion([currentUserId]),
    });

    // Create notification
    final fromUserAvatarUrl = await _getUserAvatarUrl(currentUserId);
    await _firestore.collection('notifications').add({
      'type': 'FOLLOW_REQUEST',
      'toUserId': targetUserId,
      'fromUserId': currentUserId,
      'fromUsername': UsernameUtils.normalize(currentUsername),
      if (fromUserAvatarUrl != null) 'fromUserAvatarUrl': fromUserAvatarUrl,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Accept a follow request
  Future<void> acceptFollowRequest(String currentUserId, String requesterId) async {
    final batch = _firestore.batch();
    
    // Remove from pending requests
    batch.update(_usersRef.doc(currentUserId), {
      'followRequests': FieldValue.arrayRemove([requesterId]),
    });
    
    // Add follower relationship
    batch.update(_usersRef.doc(currentUserId), {
      'followers': FieldValue.arrayUnion([requesterId]),
      'followerCount': FieldValue.increment(1),
    });
    batch.update(_usersRef.doc(requesterId), {
      'following': FieldValue.arrayUnion([currentUserId]),
      'followingCount': FieldValue.increment(1),
    });
    
    await batch.commit();
  }

  /// Decline a follow request
  Future<void> declineFollowRequest(String currentUserId, String requesterId) async {
    await _usersRef.doc(currentUserId).update({
      'followRequests': FieldValue.arrayRemove([requesterId]),
    });
  }

  /// Cancel a sent follow request
  Future<void> cancelFollowRequest(String currentUserId, String targetUserId) async {
    await _usersRef.doc(targetUserId).update({
      'followRequests': FieldValue.arrayRemove([currentUserId]),
    });
  }


  // ==================== ITEM OPERATIONS ====================

  /// Get items for a collection
  Stream<List<CollectionItemEntity>> getCollectionItems(String collectionId) {
    debugPrint('FirestoreService: Fetching items for collection: $collectionId');
    return _collectionItemsRef
        .where('collectionId', isEqualTo: collectionId)
        .orderBy('order')
        .snapshots()
        .handleError((error) {
          debugPrint('FirestoreService: Error loading items: $error');
        })
        .map((snapshot) {
          debugPrint('FirestoreService: Got ${snapshot.docs.length} items');
          return snapshot.docs
              .map((doc) => CollectionItemEntity.fromMap(
                  doc.data() as Map<String, dynamic>, doc.id))
              .toList();
        });
  }

  Future<List<CollectionItemEntity>> getCollectionItemsPreview(String collectionId, {int limit = 2}) async {
    final snapshot = await _collectionItemsRef
        .where('collectionId', isEqualTo: collectionId)
        .orderBy('order')
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => CollectionItemEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  /// Get collection items preview as a real-time stream
  Stream<List<CollectionItemEntity>> getCollectionItemsPreviewStream(String collectionId, {int limit = 2}) {
    return _collectionItemsRef
        .where('collectionId', isEqualTo: collectionId)
        .orderBy('order')
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CollectionItemEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }



  /// Add item to collection
  Future<String> addCollectionItem(String collectionId, CollectionItemEntity item) async {
    final docRef = _collectionItemsRef.doc();
    final collectionRef = _collectionsRef.doc(collectionId);

    final itemData = {
      'collectionId': collectionId,
      'userId': item.userId,
      'userName': item.userName,
      'title': item.title,
      'description': item.description,
      'rating': item.rating,
      'imageUrls': item.imageUrls,
      'googleMapsUrl': item.googleMapsUrl,
      'websiteUrl': item.websiteUrl,
      'likes': item.likes,
      'likedBy': item.likedBy,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      // Full transaction: add item + update collection metadata (works for owners)
      await _firestore.runTransaction((tx) async {
        final collectionSnap = await tx.get(collectionRef);
        if (!collectionSnap.exists) {
          throw Exception('Collection not found');
        }

        final data = collectionSnap.data() as Map<String, dynamic>;
        final currentItemCount = (data['itemCount'] as int?) ?? 0;
        final contributorIds = List<String>.from(data['contributorIds'] ?? const <String>[]);
        final currentContributorCount = (data['contributorCount'] as int?) ?? 0;
        final currentPreviewImages = List<String>.from(data['previewImageUrls'] ?? const <String>[]);

        final isNewContributor = !contributorIds.contains(item.userId);
        final computedOrder = currentItemCount;

        tx.update(collectionRef, {
          'itemCount': currentItemCount + 1,
          'updatedAt': FieldValue.serverTimestamp(),
          if (isNewContributor) 'contributorIds': FieldValue.arrayUnion([item.userId]),
          if (isNewContributor) 'contributorCount': currentContributorCount + 1,
        });

        if (item.imageUrls.isNotEmpty) {
          final merged = <String>[...item.imageUrls, ...currentPreviewImages];
          final distinct = <String>[];
          for (final url in merged) {
            if (!distinct.contains(url)) distinct.add(url);
            if (distinct.length >= 5) break;
          }
          tx.update(collectionRef, {'previewImageUrls': distinct});
        }

        tx.set(docRef, {...itemData, 'order': computedOrder});
      });
    } catch (e) {
      // Fallback for open-collaboration contributors who lack collection write permission
      if (e.toString().contains('permission-denied')) {
        debugPrint('Transaction permission-denied, falling back to direct item add');
        await docRef.set({...itemData, 'order': 0});
        // Best-effort update of collection metadata (may also fail, that's OK)
        try {
          await collectionRef.update({
            'itemCount': FieldValue.increment(1),
            'contributorIds': FieldValue.arrayUnion([item.userId]),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } catch (_) {
          debugPrint('Could not update collection metadata (contributor) — will sync later');
        }
      } else {
        rethrow;
      }
    }

    await _refreshCollectionSearchKeywords(collectionId);

    return docRef.id;
  }

  /// Update an item
  Future<void> updateCollectionItem(String collectionId, CollectionItemEntity item) async {
    await _collectionItemsRef.doc(item.id).update({
      ...item.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _touchCollectionContentUpdatedAt(collectionId);
    await _refreshCollectionSearchKeywords(collectionId);
  }

  /// Delete an item
  Future<void> deleteItem(String collectionId, String itemId) async {
    await _collectionItemsRef.doc(itemId).delete();

    // Best-effort update of collection item count (may fail for non-owners)
    try {
      await _collectionsRef.doc(collectionId).update({
        'itemCount': FieldValue.increment(-1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Could not update collection itemCount after delete: $e');
    }

    await _refreshCollectionSearchKeywords(collectionId);
  }

  /// Toggle like on an item
  Future<void> toggleItemLike(String itemId, String userId) async {
    debugPrint('FirestoreService: toggleItemLike $itemId by $userId');
    try {
      final fromUsername = await _getUsername(userId);
      final itemRef = _collectionItemsRef.doc(itemId);

      final result = await _firestore.runTransaction<(bool, String, String, String, String)>((tx) async {
        final snap = await tx.get(itemRef);
        if (!snap.exists) return (false, '', '', '', '');

        final data = snap.data() as Map<String, dynamic>;
        final likedBy = List<String>.from(data['likedBy'] ?? const <String>[]);
        final currentLikes = (data['likes'] as int?) ?? 0;
        final ownerId = (data['userId'] as String?) ?? '';
        final itemTitle = (data['title'] as String?) ?? '';
        final collectionId = (data['collectionId'] as String?) ?? '';

        var collectionTitle = '';
        if (collectionId.isNotEmpty) {
          final collectionRef = _collectionsRef.doc(collectionId);
          final cSnap = await tx.get(collectionRef);
          if (cSnap.exists) {
            final c = cSnap.data() as Map<String, dynamic>;
            collectionTitle = (c['title'] as String?) ?? '';
          }
        }

        if (likedBy.contains(userId)) {
          tx.update(itemRef, {
            'likedBy': FieldValue.arrayRemove([userId]),
            'likes': (currentLikes - 1) < 0 ? 0 : (currentLikes - 1),
          });
          return (false, ownerId, itemTitle, collectionId, collectionTitle);
        } else {
          tx.update(itemRef, {
            'likedBy': FieldValue.arrayUnion([userId]),
            'likes': currentLikes + 1,
          });
          return (true, ownerId, itemTitle, collectionId, collectionTitle);
        }
      });

      if (result.$1 && result.$4.isNotEmpty) {
        try {
          await _createLikeNotification(
            toUserId: result.$2,
            fromUserId: userId,
            fromUsername: fromUsername,
            collectionId: result.$4,
            collectionTitle: result.$5,
            itemId: itemId,
            itemTitle: result.$3,
            type: 'LIKE_ITEM',
          );
        } catch (e) {
          debugPrint('FirestoreService: toggleItemLike notification ERROR: $e');
        }
      }
      debugPrint('FirestoreService: toggleItemLike SUCCESS');
    } on FirebaseException catch (e) {
      debugPrint(
          'FirestoreService: toggleItemLike FirebaseException code=${e.code} message=${e.message}');
      rethrow;
    } catch (e) {
      debugPrint('FirestoreService: toggleItemLike ERROR: $e');
      rethrow;
    }
  }

  /// Reorder items in a collection
  Future<void> reorderItems(String collectionId, List<CollectionItemEntity> items) async {
    final batch = _firestore.batch();
    for (int i = 0; i < items.length; i++) {
      batch.update(_collectionItemsRef.doc(items[i].id), {
        'order': i,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    await _touchCollectionContentUpdatedAt(collectionId);
  }

  /// Duplicate a collection with all its items
  Future<String> duplicateCollection({
    required String originalCollectionId,
    required String newOwnerId,
    required String newOwnerName,
    String? newTitle,
    String? newDescription,
  }) async {
    // Get original collection
    final originalDoc = await _collectionsRef.doc(originalCollectionId).get();
    if (!originalDoc.exists) throw Exception('Original collection not found');

    final originalData = originalDoc.data() as Map<String, dynamic>;

    // Create new collection — copies default to private regardless of original visibility
    final newCollectionData = {
      ...originalData,
      'userId': newOwnerId,
      'userName': UsernameUtils.normalize(newOwnerName),
      'title': newTitle ?? '${originalData['title']} (Copy)',
      'description': newDescription ?? originalData['description'],
      'websiteUrl': originalData['websiteUrl'],
      'googleMapsUrl': originalData['googleMapsUrl'],
      'isPublic': false,
      'visibility': 'PRIVATE',
      'likes': 0,
      'likedBy': [],
      'saveCount': 0,
      'savedBy': [],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'inspiredBy': originalCollectionId,
      'inspiredByUserId': originalData['userId'],
      'itemCount': 0,
      'previewImageUrls': [],
      'contributors': [],
    };

    final newCollectionRef = await _collectionsRef.add(newCollectionData);

    // Copy all items
    final itemsSnapshot = await _collectionItemsRef
        .where('collectionId', isEqualTo: originalCollectionId)
        .get();

    int itemCount = 0;
    for (final itemDoc in itemsSnapshot.docs) {
      final itemData = itemDoc.data() as Map<String, dynamic>;
      await _collectionItemsRef.add({
        ...itemData,
        'collectionId': newCollectionRef.id,
        'userId': newOwnerId,
        'userName': UsernameUtils.normalize(newOwnerName),
        'likes': 0,
        'likedBy': [],
        'createdAt': FieldValue.serverTimestamp(),
      });
      itemCount++;
    }

    // Update item count
    await _collectionsRef.doc(newCollectionRef.id).update({
      'itemCount': itemCount,
    });

    // Update user's collection count
    await _usersRef.doc(newOwnerId).update({
      'collectionsCount': FieldValue.increment(1),
    });

    return newCollectionRef.id;
  }

  /// Check if [currentUserId] follows [targetUserId] (uses the current user's
  /// `following` list — same source as the Following tab).
  Future<bool> isFollowing(String currentUserId, String targetUserId) async {
    if (currentUserId.isEmpty || targetUserId.isEmpty) return false;
    if (currentUserId == targetUserId) return false;

    try {
      final doc = await _usersRef.doc(currentUserId).get();
      if (!doc.exists) return false;

      final data = doc.data() as Map<String, dynamic>;
      final following = List<String>.from(data['following'] ?? []);
      final follows = following.contains(targetUserId);
      if (!follows) return false;

      // Repair one-sided data: in following but missing from target's followers.
      try {
        final targetSnap = await _usersRef.doc(targetUserId).get();
        if (!targetSnap.exists) return true;

        final targetFollowers = List<String>.from(
          (targetSnap.data() as Map<String, dynamic>)['followers'] ?? [],
        );
        if (!targetFollowers.contains(currentUserId)) {
          await _usersRef.doc(targetUserId).update({
            'followers': FieldValue.arrayUnion([currentUserId]),
            'followerCount': FieldValue.increment(1),
          });
        }
      } catch (e) {
        debugPrint('Could not repair followers list for $targetUserId: $e');
      }

      return true;
    } catch (e) {
      debugPrint('isFollowing failed: $e');
      return false;
    }
  }

  /// One-time legacy catch-up for collections created before search indexing.
  ///
  /// New users are skipped automatically when their collections are already indexed
  /// (e.g. created via [createCollection] after this shipped). Runs at most once per
  /// user, tracked by `searchIndexInitialSync` on the user doc.
  Future<void> runLegacySearchIndexSyncIfNeeded(String userId) async {
    if (userId.isEmpty) return;
    if (await _hasCompletedSearchIndexInitialSync(userId)) return;

    final collections = await getUserCollections(userId);
    if (await _anyOwnedCollectionNeedsReindex(collections)) {
      await reindexEditableCollections(
        collections,
        currentUserId: userId,
      );
    }

    await _markSearchIndexInitialSyncComplete(userId);
  }

  Future<bool> _anyOwnedCollectionNeedsReindex(
    List<CollectionEntity> collections,
  ) async {
    for (final collection in collections) {
      final items = collection.itemCount > 0
          ? await _getCollectionItemsForSearch(collection.id)
          : const <CollectionItemEntity>[];

      if (SearchTokenizer.needsReindex(
        existingKeywords: collection.searchKeywords,
        title: collection.title,
        description: collection.description,
        tags: collection.tags,
        category: collection.category.name,
        categoryDisplayName: collection.category.displayName,
        items: _toSearchIndexedItems(items),
      )) {
        return true;
      }

      if (collection.itemCount > 0 && items.isEmpty) {
        return true;
      }
    }
    return false;
  }

  Future<void> reindexEditableCollections(
    List<CollectionEntity> collections, {
    required String currentUserId,
  }) async {
    for (final collection in collections) {
      if (!_canUserUpdateSearchIndex(collection, currentUserId)) {
        continue;
      }

      final items = collection.itemCount > 0
          ? await _getCollectionItemsForSearch(collection.id)
          : const <CollectionItemEntity>[];
      final indexedItems = _toSearchIndexedItems(items);

      var needsRefresh = SearchTokenizer.needsReindex(
        existingKeywords: collection.searchKeywords,
        title: collection.title,
        description: collection.description,
        tags: collection.tags,
        category: collection.category.name,
        categoryDisplayName: collection.category.displayName,
        items: indexedItems,
      );

      if (!needsRefresh && collection.itemCount > 0 && indexedItems.isEmpty) {
        needsRefresh = true;
      }

      if (!needsRefresh) continue;

      try {
        final keywords = await _buildSearchKeywords(
          collection,
          items: items,
        );
        if (keywords.isEmpty) continue;

        await _collectionsRef.doc(collection.id).update({
          'searchKeywords': keywords,
        });
        debugPrint('Reindexed search keywords for collection ${collection.id}');
      } catch (e) {
        debugPrint('Failed to reindex keywords for ${collection.id}: $e');
      }
    }
  }

  Future<bool> _hasCompletedSearchIndexInitialSync(String userId) async {
    try {
      final doc = await _usersRef.doc(userId).get();
      if (!doc.exists) return false;
      final data = doc.data() as Map<String, dynamic>?;
      return data?['searchIndexInitialSync'] == true;
    } catch (e) {
      debugPrint('Failed to read search index sync flag: $e');
      return false;
    }
  }

  Future<void> _markSearchIndexInitialSyncComplete(String userId) async {
    try {
      await _usersRef.doc(userId).update({
        'searchIndexInitialSync': true,
        'searchIndexInitialSyncAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Failed to mark search index initial sync complete: $e');
    }
  }

  bool _canUserUpdateSearchIndex(
    CollectionEntity collection,
    String currentUserId,
  ) {
    if (currentUserId.isEmpty) return false;
    if (collection.userId == currentUserId) return true;
    return collection.editors.contains(currentUserId);
  }

  Future<List<CollectionItemEntity>> _getCollectionItemsForSearch(
    String collectionId,
  ) async {
    final snapshot = await _collectionItemsRef
        .where('collectionId', isEqualTo: collectionId)
        .orderBy('order')
        .get();

    return snapshot.docs
        .map((doc) => CollectionItemEntity.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            ))
        .toList();
  }

  List<SearchIndexedItem> _toSearchIndexedItems(
    List<CollectionItemEntity> items,
  ) {
    return items
        .map(
          (item) => SearchIndexedItem(
            title: item.title,
            description: item.description,
          ),
        )
        .toList();
  }

  Future<List<String>> _buildSearchKeywords(
    CollectionEntity collection, {
    List<CollectionItemEntity>? items,
  }) async {
    final resolvedItems =
        items ?? await _getCollectionItemsForSearch(collection.id);

    return CollectionEntity.generateKeywords(
      title: collection.title,
      description: collection.description,
      tags: collection.tags,
      category: collection.category.name,
      categoryDisplayName: collection.category.displayName,
      userName: collection.userName,
      items: _toSearchIndexedItems(resolvedItems),
    );
  }

  Future<void> _refreshCollectionSearchKeywords(String collectionId) async {
    try {
      final collection = await getCollection(collectionId);
      if (collection == null) return;

      final keywords = await _buildSearchKeywords(collection);
      if (keywords.isEmpty) return;

      await _collectionsRef.doc(collectionId).update({
        'searchKeywords': keywords,
      });
    } catch (e) {
      debugPrint('Failed to refresh search keywords for $collectionId: $e');
    }
  }

  List<String> _ephemeralSearchKeywords(
    CollectionEntity collection, {
    List<SearchIndexedItem> items = const [],
  }) {
    return CollectionEntity.generateKeywords(
      title: collection.title,
      description: collection.description,
      tags: collection.tags,
      category: collection.category.name,
      categoryDisplayName: collection.category.displayName,
      userName: collection.userName,
      items: items,
    );
  }

  int _searchRelevanceScore(CollectionEntity collection, List<String> terms) {
    final keywords = collection.searchKeywords.isNotEmpty
        ? collection.searchKeywords
        : _ephemeralSearchKeywords(collection);

    return SearchTokenizer.relevanceScore(
      queryTerms: terms,
      title: collection.title,
      description: collection.description,
      tags: collection.tags,
      category: collection.category.name,
      categoryDisplayName: collection.category.displayName,
      indexedKeywords: keywords,
    );
  }


  // ==================== SEARCH OPERATIONS ====================


  /// Search public collections by tokenized title, description, tags, category,
  /// and indexed item text.
  ///
  /// [supplementalCollections] enables client-side matching for collections whose
  /// search index could not be updated (e.g. owned by another user).
  Future<List<CollectionEntity>> searchCollections(
    String query, {
    List<CollectionEntity>? supplementalCollections,
  }) async {
    if (query.trim().isEmpty) return [];

    final terms = SearchTokenizer.tokenizeQuery(query);
    if (terms.isEmpty) return [];

    final firestoreTerms =
        terms.length > 10 ? terms.sublist(0, 10) : List<String>.from(terms);

    final snapshot = await _collectionsRef
        .where('isPublic', isEqualTo: true)
        .where('searchKeywords', arrayContainsAny: firestoreTerms)
        .limit(75)
        .get();

    final indexedResults = snapshot.docs
        .map((doc) =>
            CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .where(
          (collection) => SearchTokenizer.matchesAllTerms(
            collection.searchKeywords,
            terms,
          ),
        )
        .toList();

    final resultIds = indexedResults.map((collection) => collection.id).toSet();
    final supplementalResults = (supplementalCollections ?? const [])
        .where((collection) {
          if (!collection.isPublic || resultIds.contains(collection.id)) {
            return false;
          }

          final keywords = collection.searchKeywords.isNotEmpty
              ? collection.searchKeywords
              : _ephemeralSearchKeywords(collection);
          return SearchTokenizer.matchesAllTerms(keywords, terms);
        })
        .toList();

    final collections = [...indexedResults, ...supplementalResults];

    collections.sort(
      (a, b) => _searchRelevanceScore(b, terms)
          .compareTo(_searchRelevanceScore(a, terms)),
    );

    return collections;
  }

  /// Get trending collections (most liked)
  Future<List<CollectionEntity>> getTrendingCollections({int limit = 10}) async {
    final snapshot = await _collectionsRef
        .where('isPublic', isEqualTo: true)
        .orderBy('likes', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) =>
            CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  Future<List<CollectionEntity>> getTrendingNowCollections({int limit = 10}) async {
    final since = DateTime.now().subtract(const Duration(days: 2));
    return getPublicCollectionsSince(since: since, limit: 50);
  }

  Future<List<CollectionEntity>> getTopLikedCollections({DateTime? since, int limit = 10}) async {
    final prefetch = since == null ? limit : (limit * 10).clamp(50, 200);

    if (since != null) {
      try {
        final recent = await getPublicCollectionsSince(since: since, limit: prefetch);
        final sorted = [...recent]..sort((a, b) => b.likes.compareTo(a.likes));
        return sorted.take(limit).toList();
      } catch (e) {
        debugPrint('getTopLikedCollections: createdAt-since query failed, falling back: $e');
      }
    }

    final snapshot = await _collectionsRef
        .where('isPublic', isEqualTo: true)
        .orderBy('likes', descending: true)
        .limit(prefetch)
        .get();

    final all = snapshot.docs
        .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    return all.take(limit).toList();
  }

  Future<List<CollectionEntity>> getPublicCollectionsSince({required DateTime since, int limit = 50}) async {
    final sinceMs = since.millisecondsSinceEpoch;
    final byId = <String, CollectionEntity>{};
    final baseQuery = _collectionsRef.where('isPublic', isEqualTo: true);

    Future<void> mergeQueryResults(Query query, String label) async {
      try {
        final snapshot = await query.limit(limit).get();
        for (final doc in snapshot.docs) {
          final data = doc.data();
          if (data is! Map<String, dynamic>) continue;
          byId[doc.id] = CollectionEntity.fromMap(data, doc.id);
        }
      } catch (e) {
        debugPrint('getPublicCollectionsSince: $label query failed: $e');
      }
    }

    // Some docs store createdAt as Timestamp, others as int millis — query both.
    await mergeQueryResults(
      baseQuery
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .orderBy('createdAt', descending: true),
      'Timestamp createdAt',
    );
    await mergeQueryResults(
      baseQuery
          .where('createdAt', isGreaterThanOrEqualTo: sinceMs)
          .orderBy('createdAt', descending: true),
      'int createdAt',
    );

    if (byId.isNotEmpty) {
      final merged = byId.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return merged.take(limit).toList();
    }

    // Last resort: fetch recent public collections and filter client-side.
    try {
      final snapshot = await baseQuery
          .orderBy('createdAt', descending: true)
          .limit(limit * 4)
          .get();

      final filtered = <CollectionEntity>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data is! Map<String, dynamic>) continue;
        final collection = CollectionEntity.fromMap(data, doc.id);
        if (collection.createdAt >= sinceMs) {
          filtered.add(collection);
        }
        if (filtered.length >= limit) break;
      }
      return filtered;
    } catch (e) {
      debugPrint('getPublicCollectionsSince: client-side fallback failed: $e');
      rethrow;
    }
  }

  Future<List<CollectionEntity>> getCollectionsByCategory(
      String category, {int limit = 20}) async {
    final snapshot = await _collectionsRef
        .where('isPublic', isEqualTo: true)
        .where('category', isEqualTo: category.toUpperCase())
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) =>
            CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  /// Get collections from followed users
  Future<List<CollectionEntity>> getFollowingCollections(String userId) async {
    try {
      // 1. Get following list
      final userDoc = await _usersRef.doc(userId).get();
      if (!userDoc.exists) return [];
      
      final data = userDoc.data() as Map<String, dynamic>;
      final following = List<String>.from(data['following'] ?? []);
      
      if (following.isEmpty) return [];

      // 1b. Determine which followed users have accepted this user as a follower
      final acceptedFollowerUserIds = <String>[];
      const int userBatchSize = 10;
      for (int i = 0; i < following.length; i += userBatchSize) {
        final end = (i + userBatchSize < following.length) ? i + userBatchSize : following.length;
        final chunk = following.sublist(i, end);
        if (chunk.isEmpty) continue;

        final usersSnap = await _usersRef
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in usersSnap.docs) {
          final u = doc.data() as Map<String, dynamic>;
          final followers = List<String>.from(u['followers'] ?? const <String>[]);
          if (followers.contains(userId)) {
            acceptedFollowerUserIds.add(doc.id);
          }
        }
      }

      // 2. Fetch all public collections per followed user so older collections
      // still appear when someone newly follows an existing creator.
      List<CollectionEntity> allCollections = [];
      const int batchSize = 10;

      final publicSnapshots = await Future.wait(
        following.map(
          (followedUserId) => _collectionsRef
              .where('userId', isEqualTo: followedUserId)
              .where('isPublic', isEqualTo: true)
              .get(),
        ),
      );

      for (final snapshot in publicSnapshots) {
        allCollections.addAll(
          snapshot.docs.map(
            (doc) => CollectionEntity.fromMap(
              doc.data() as Map<String, dynamic>,
              doc.id,
            ),
          ),
        );
      }

      // 2b. Also include FOLLOWERS-visibility collections for accepted followers
      for (int i = 0; i < acceptedFollowerUserIds.length; i += batchSize) {
        final end = (i + batchSize < acceptedFollowerUserIds.length)
            ? i + batchSize
            : acceptedFollowerUserIds.length;
        final chunk = acceptedFollowerUserIds.sublist(i, end);
        if (chunk.isEmpty) continue;

        final snapshot = await _collectionsRef
            .where('userId', whereIn: chunk)
            .where('visibility', isEqualTo: 'FOLLOWERS')
            .get();

        final chunkCollections = snapshot.docs
            .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList();

        allCollections.addAll(chunkCollections);
      }
      
      // 3. Sort merged results in memory
      _sortCollectionsByContentActivity(allCollections);
      
      return allCollections;
    } catch (e) {
      // ignore: avoid_print
      print('Error fetching following collections: $e');
      return [];
    }
  }

  /// Get collections from followed users as a real-time stream
  Stream<List<CollectionEntity>> getFollowingCollectionsStream(String userId) {
    return getUserStream(userId).asyncExpand((user) {
      if (user == null || user.following.isEmpty) {
        return Stream.value(<CollectionEntity>[]);
      }

      final following =
          user.following.where((id) => id.trim().isNotEmpty).toList();
      if (following.isEmpty) return Stream.value(<CollectionEntity>[]);

      final streams = following.map((followedUserId) {
        return _collectionsRef
            .where('userId', isEqualTo: followedUserId)
            .where('isPublic', isEqualTo: true)
            .snapshots()
            .map((snapshot) => snapshot.docs
                .map((doc) => CollectionEntity.fromMap(
                    doc.data() as Map<String, dynamic>, doc.id))
                .toList());
      }).toList();

      return Rx.combineLatestList<List<CollectionEntity>>(streams).map((batches) {
        final byId = <String, CollectionEntity>{};
        for (final batch in batches) {
          for (final collection in batch) {
            byId[collection.id] = collection;
          }
        }
        final merged = byId.values.toList();
        _sortCollectionsByContentActivity(merged);
        return merged;
      });
    });
  }

  /// Get open collaboration collections
  Future<List<CollectionEntity>> getOpenCollaborationCollections({int limit = 20}) async {
    final snapshot = await _collectionsRef
        .where('isPublic', isEqualTo: true)
        .where('isOpenForContribution', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) =>
            CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  /// Get open collaboration collections as a real-time stream
  Stream<List<CollectionEntity>> getOpenCollaborationCollectionsStream({int limit = 20}) {
    return _collectionsRef
        .where('isPublic', isEqualTo: true)
        .where('isOpenForContribution', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  Future<List<CollectionEntity>> getUserCollaborations(String userId) async {
    try {
      final editorsSnap = await _collectionsRef
          .where('editors', arrayContains: userId)
          .get();

      final list = editorsSnap.docs
          .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .where((c) => c.userId != userId && !c.isOpenForContribution)
          .toList();

      _sortCollectionsByContentActivity(list);
      return list;
    } catch (e) {
      debugPrint('Error loading collaborations for user $userId: $e');
      return const <CollectionEntity>[];
    }
  }

  /// Get user collaborations as a stream (editor access only; excludes view-only).
  Stream<List<CollectionEntity>> getUserCollaborationsStream(String userId) {
    return _collectionsRef
        .where('editors', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs
          .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .where((c) => c.userId != userId && !c.isOpenForContribution)
          .toList();

      _sortCollectionsByContentActivity(list);
      return list;
    });
  }

  // ==================== NOTIFICATION OPERATIONS ====================

  /// Get unread notification count as a stream for the badge
  Stream<int> getUnreadNotificationCount(String userId) {
    return _firestore
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  /// Get user notifications as a stream
  Stream<List<Map<String, dynamic>>> getNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => {'id': doc.id, ...doc.data()})
            .toList());
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  /// Mark all notifications as read
  Future<void> markAllNotificationsAsRead(String userId) async {
    final batch = _firestore.batch();
    final snapshot = await _firestore
        .collection('notifications')
        .where('toUserId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  /// Delete a notification
  Future<void> deleteNotification(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).delete();
  }

  // ==================== USER SEARCH OPERATIONS ====================

  String _normalizedUsernameFromMap(Map<String, dynamic> data) {
    final storedLower = data['usernameLower'] as String?;
    if (storedLower != null && storedLower.trim().isNotEmpty) {
      return storedLower.trim().toLowerCase();
    }

    final username = (data['username'] ?? data['userName'] ?? '').toString().trim();
    return username.toLowerCase();
  }

  List<UserEntity> _filterUsersByUsernamePrefix(
    Iterable<QueryDocumentSnapshot<Object?>> docs,
    String lowerQuery, {
    int limit = 20,
  }) {
    final users = docs
        .map((doc) => UserEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .where((user) => user.username.toLowerCase().startsWith(lowerQuery))
        .take(limit)
        .toList();
    users.sort((a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()));
    return users;
  }

  /// Resolve exact usernames to user records for @mentions.
  Future<List<UserEntity>> getUsersByUsernames(List<String> usernames) async {
    if (usernames.isEmpty) return const [];

    final lowerUsernames = usernames
        .map((username) => username.trim().toLowerCase())
        .where((username) => username.isNotEmpty)
        .toSet()
        .toList();
    if (lowerUsernames.isEmpty) return const [];

    final users = <UserEntity>[];
    final foundUsernames = <String>{};

    for (var i = 0; i < lowerUsernames.length; i += 10) {
      final batch = lowerUsernames.sublist(
        i,
        i + 10 > lowerUsernames.length ? lowerUsernames.length : i + 10,
      );
      try {
        final snapshot = await _usersRef.where('usernameLower', whereIn: batch).get();
        for (final doc in snapshot.docs) {
          final user = UserEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id);
          final lower = user.username.toLowerCase();
          if (foundUsernames.add(lower)) {
            users.add(user);
          }
        }
      } catch (e) {
        debugPrint('getUsersByUsernames batch lookup failed: $e');
      }
    }

    if (foundUsernames.length == lowerUsernames.length) {
      return users;
    }

    final missing = lowerUsernames.where((username) => !foundUsernames.contains(username)).toList();
    if (missing.isEmpty) return users;

    final fallbackSnapshot = await _usersRef.limit(200).get();
    for (final doc in fallbackSnapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final lower = _normalizedUsernameFromMap(data);
      if (lower.isEmpty) continue;
      if (missing.contains(lower) && foundUsernames.add(lower)) {
        users.add(UserEntity.fromMap(data, doc.id));
      }
    }

    return users;
  }

  /// User suggestions while typing @mentions in comments.
  Future<List<UserEntity>> getMentionUserSuggestions(String query) async {
    try {
      final lowerQuery = query.trim().toLowerCase();
      final snapshot = await _usersRef.limit(150).get();
      final users = snapshot.docs
          .map((doc) => UserEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .where((user) => user.username.trim().isNotEmpty)
          .toList();

      users.sort(
        (a, b) => a.username.toLowerCase().compareTo(b.username.toLowerCase()),
      );

      if (lowerQuery.isEmpty) {
        return users.take(15).toList();
      }

      return users
          .where((user) => user.username.toLowerCase().startsWith(lowerQuery))
          .take(20)
          .toList();
    } catch (e) {
      debugPrint('getMentionUserSuggestions failed: $e');
      return const [];
    }
  }

  /// Search users by username
  Future<List<UserEntity>> searchUsers(String query) async {
    if (query.isEmpty) return [];

    final lowerQuery = query.toLowerCase();

    // Prefer indexed lookup when usernameLower exists on user docs.
    try {
      final snapshot = await _usersRef
          .orderBy('usernameLower')
          .startAt([lowerQuery])
          .endAt(['$lowerQuery\uf8ff'])
          .limit(20)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs
            .map((doc) => UserEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList();
      }
    } catch (e) {
      debugPrint('Search by usernameLower failed or not indexed: $e');
    }

    // Read-only fallback: scan a batch and filter locally. Never write other users' docs.
    final fallbackSnapshot = await _usersRef.limit(100).get();
    return _filterUsersByUsernamePrefix(fallbackSnapshot.docs, lowerQuery);
  }

  // ==================== STORAGE OPERATIONS ====================

  /// Upload an image and return the download URL
  Future<String?> uploadImage(File file, String path) async {
    try {
      final ref = _storage.ref().child(path);
      final uploadTask = await ref.putFile(file);
      final url = await uploadTask.ref.getDownloadURL();
      return url;
    } catch (e) {
      // ignore: avoid_print
      print('Error uploading image: $e');
      return null;
    }
  }

  /// Permanently deletes all Firestore data associated with [userId].
  Future<void> deleteUserAccount(String userId) async {
    debugPrint('FirestoreService: deleteUserAccount $userId');

    final collectionsSnap =
        await _collectionsRef.where('userId', isEqualTo: userId).get();
    for (final doc in collectionsSnap.docs) {
      await _runAccountDeletionStep(
        'delete collection ${doc.id}',
        () => deleteCollection(doc.id, userId),
      );
    }

    await _runAccountDeletionStep(
      'delete comments',
      () => _deleteQueryDocumentsInBatches(
        _commentsRef.where('userId', isEqualTo: userId),
      ),
    );

    await _runAccountDeletionStep(
      'delete incoming notifications',
      () => _deleteQueryDocumentsInBatches(
        _firestore.collection('notifications').where('toUserId', isEqualTo: userId),
      ),
    );
    await _runAccountDeletionStep(
      'delete outgoing notifications',
      () => _deleteQueryDocumentsInBatches(
        _firestore.collection('notifications').where('fromUserId', isEqualTo: userId),
      ),
    );

    await _runAccountDeletionStep(
      'delete reports',
      () => _deleteQueryDocumentsInBatches(
        _reportsRef.where('reporterUserId', isEqualTo: userId),
      ),
    );

    // Best-effort cleanup on other users' docs — often blocked by security rules.
    await _runAccountDeletionStep(
      'remove likes from other collections',
      () => _updateQueryDocumentsInBatches(
        _collectionsRef.where('likedBy', arrayContains: userId),
        {'likedBy': FieldValue.arrayRemove([userId])},
      ),
    );
    await _runAccountDeletionStep(
      'remove from other users followers',
      () => _updateQueryDocumentsInBatches(
        _usersRef.where('followers', arrayContains: userId),
        {'followers': FieldValue.arrayRemove([userId])},
      ),
    );
    await _runAccountDeletionStep(
      'remove from other users following',
      () => _updateQueryDocumentsInBatches(
        _usersRef.where('following', arrayContains: userId),
        {'following': FieldValue.arrayRemove([userId])},
      ),
    );
    await _runAccountDeletionStep(
      'remove pending follow requests',
      () => _updateQueryDocumentsInBatches(
        _usersRef.where('followRequests', arrayContains: userId),
        {'followRequests': FieldValue.arrayRemove([userId])},
      ),
    );

    await _runAccountDeletionStep(
      'delete avatar',
      () => _storage.ref().child('avatars/$userId.jpg').delete(),
    );

    await _usersRef.doc(userId).delete();
  }

  Future<void> _runAccountDeletionStep(
    String label,
    Future<void> Function() step,
  ) async {
    try {
      await step();
    } catch (e, stackTrace) {
      debugPrint('deleteUserAccount: $label failed: $e');
      debugPrint('$stackTrace');
    }
  }

  /// Submits a user report for a collection (moderation queue).
  Future<void> reportCollection({
    required String collectionId,
    required String reporterUserId,
    required String collectionOwnerId,
    required String collectionTitle,
  }) async {
    await _reportsRef.add({
      'type': 'collection',
      'collectionId': collectionId,
      'collectionOwnerId': collectionOwnerId,
      'collectionTitle': collectionTitle,
      'reporterUserId': reporterUserId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}

/// Simple Rx-like combination helper since we don't have rxdart
class Rx {
  static Stream<T> combineLatest2<A, B, T>(
    Stream<A> streamA,
    Stream<B> streamB,
    T Function(A a, B b) combiner,
  ) async* {
    A? lastA;
    B? lastB;
    bool hasA = false;
    bool hasB = false;

    await for (final value in StreamGroup.merge([
      streamA.map((a) => _CombinedValue(0, a)),
      streamB.map((b) => _CombinedValue(1, b)),
    ])) {
      if (value.index == 0) {
        lastA = value.value as A;
        hasA = true;
      } else {
        lastB = value.value as B;
        hasB = true;
      }

      if (hasA && hasB) {
        yield combiner(lastA!, lastB!);
      }
    }
  }

  static Stream<List<T>> combineLatestList<T>(List<Stream<T>> streams) async* {
    if (streams.isEmpty) {
      yield <T>[];
      return;
    }

    final values = List<T?>.filled(streams.length, null);
    final hasValue = List<bool>.filled(streams.length, false);

    await for (final event in StreamGroup.merge(
      streams.asMap().entries.map(
        (entry) => entry.value.map((value) => _CombinedValue(entry.key, value)),
      ),
    )) {
      values[event.index] = event.value as T;
      hasValue[event.index] = true;
      if (hasValue.every((ready) => ready)) {
        yield values.cast<T>().toList();
      }
    }
  }
}

class _CombinedValue {
  final int index;
  final dynamic value;
  _CombinedValue(this.index, this.value);
}

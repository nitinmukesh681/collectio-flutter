import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:async/async.dart';
import 'dart:io';
import '../models/collection_entity.dart';
import '../models/collection_item_entity.dart';
import '../models/user_entity.dart';
import '../models/comment_entity.dart';


/// Firestore service for database operations
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Collection references
  CollectionReference get _usersRef => _firestore.collection('users');
  CollectionReference get _collectionsRef => _firestore.collection('collections');
  CollectionReference get _collectionItemsRef => _firestore.collection('collectionItems');

  /// Bumps collection `updatedAt` when items or other collection content changes.
  Future<void> _touchCollectionUpdatedAt(String collectionId) async {
    try {
      await _collectionsRef.doc(collectionId).update({
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Could not update collection updatedAt: $e');
    }
  }
  CollectionReference get _commentsRef => _firestore.collection('comments');

  // ==================== COMMENTS ====================

  Stream<List<CommentEntity>> getCommentsStream(String collectionId) {
    return _commentsRef
        .where('collectionId', isEqualTo: collectionId)
        .orderBy('createdAt', descending: false)
        .snapshots()
        .handleError((e) {
          debugPrint('Comments stream error (may need Firestore index): $e');
        })
        .map((snap) => snap.docs.map((d) => CommentEntity.fromMap(d.data() as Map<String, dynamic>, d.id)).toList());
  }

  Future<String> addComment({
    required String collectionId,
    required String userId,
    required String userName,
    String? userAvatarUrl,
    required String text,
    String? parentCommentId,
  }) async {
    final docRef = await _commentsRef.add({
      'collectionId': collectionId,
      'userId': userId,
      'userName': userName,
      'userAvatarUrl': userAvatarUrl,
      'text': text,
      'parentCommentId': parentCommentId,
      'likes': 0,
      'likedBy': [],
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Send notification to collection owner
    try {
      final collectionSnap = await _collectionsRef.doc(collectionId).get();
      if (collectionSnap.exists) {
        final data = collectionSnap.data() as Map<String, dynamic>;
        final ownerId = data['userId'] as String? ?? '';
        final title = data['title'] as String? ?? '';
        if (ownerId.isNotEmpty && ownerId != userId) {
          await _firestore.collection('notifications').add({
            'toUserId': ownerId,
            'type': parentCommentId != null ? 'COMMENT_REPLY' : 'COMMENT',
            'fromUserId': userId,
            'fromUsername': userName,
            'fromUserAvatarUrl': userAvatarUrl,
            'collectionId': collectionId,
            'collectionTitle': title,
            'message': text,
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    } catch (e) {
      debugPrint('Comment notification error: $e');
    }

    await _touchCollectionUpdatedAt(collectionId);
    return docRef.id;
  }

  Future<void> toggleCommentLike(String commentId, String userId) async {
    final ref = _commentsRef.doc(commentId);
    final snap = await ref.get();
    if (!snap.exists) return;
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
        if (commentUserId.isNotEmpty && commentUserId != userId) {
          final fromUsername = await _getUsername(userId);
          await _firestore.collection('notifications').add({
            'toUserId': commentUserId,
            'type': 'COMMENT_LIKE',
            'fromUserId': userId,
            'fromUsername': fromUsername,
            'collectionId': data['collectionId'] ?? '',
            'message': data['text'] ?? '',
            'isRead': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      } catch (_) {}
    }
  }

  Future<void> deleteComment(String commentId) async {
    final snap = await _commentsRef.doc(commentId).get();
    final collectionId = snap.data() != null
        ? (snap.data() as Map<String, dynamic>)['collectionId'] as String?
        : null;
    await _commentsRef.doc(commentId).delete();
    if (collectionId != null && collectionId.isNotEmpty) {
      await _touchCollectionUpdatedAt(collectionId);
    }
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
    return trimmed.isNotEmpty ? trimmed : 'Someone';
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
      'fromUsername': fromUsername,
      'collectionId': collectionId,
      'collectionTitle': collectionTitle,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    };
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

  /// Create or update user
  Future<void> saveUser(UserEntity user) async {
    await _usersRef.doc(user.id).set(user.toMap(), SetOptions(merge: true));
  }

  /// Update username
  Future<void> updateUsername(String userId, String username) async {
    await _usersRef.doc(userId).update({'username': username});
  }

  /// Get user email by username
  Future<String?> getUserEmailByUsername(String username) async {
    final querySnapshot = await _usersRef
        .where('username', isEqualTo: username)
        .limit(1)
        .get();

    if (querySnapshot.docs.isEmpty) return null;
    return (querySnapshot.docs.first.data() as Map<String, dynamic>)['email'] as String?;
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
        await _firestore.collection('notifications').add({
          'type': 'NEW_FOLLOWER',
          'toUserId': targetUserId,
          'fromUserId': currentUserId,
          'fromUsername': currentUsername,
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
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          debugPrint('FirestoreService: Collections snapshot updated - ${snapshot.docs.length} documents');
          final collections = snapshot.docs
              .map((doc) => CollectionEntity.fromMap(
                  doc.data() as Map<String, dynamic>, doc.id))
              .toList();
          
          // Defensive client-side sort to ensure proper chronological ordering
          collections.sort((a, b) {
            final aTime = a.createdAt;
            final bTime = b.createdAt;
            return bTime.compareTo(aTime); // descending (newest first)
          });
          
          // Debug: Print the order of collections with timestamps and dates
          for (int i = 0; i < collections.length; i++) {
            final collection = collections[i];
            final timestamp = collection.createdAt;
            final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
            debugPrint('FirestoreService: Collection $i: "${collection.title}" - Timestamp: $timestamp, Date: $date');
          }
          
          // Also check if the ordering is correct
          for (int i = 0; i < collections.length - 1; i++) {
            final current = collections[i].createdAt;
            final next = collections[i + 1].createdAt;
            if (current < next) {
              debugPrint('FirestoreService: ORDERING ERROR! Collection $i has older timestamp than collection ${i + 1}');
            }
          }
          
          return collections;
        });
  }

  /// Get collections for a user (Future)
  Future<List<CollectionEntity>> getUserCollections(String userId) async {
    final snapshot = await _collectionsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();
    final collections = snapshot.docs
        .map((doc) => CollectionEntity.fromMap(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    
    // Additional defensive sort to ensure proper chronological ordering
    collections.sort((a, b) {
      final aTime = a.createdAt;
      final bTime = b.createdAt;
      // Handle null/missing timestamps by treating them as oldest
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;  // a is older
      if (bTime == null) return -1; // b is older
      return bTime.compareTo(aTime); // descending (newest first)
    });
    
    // Debug: Log the final order for troubleshooting
    debugPrint('=== getUserCollections for userId: $userId ===');
    for (int i = 0; i < collections.length; i++) {
      final collection = collections[i];
      final timestamp = collection.createdAt;
      final date = timestamp != null ? DateTime.fromMillisecondsSinceEpoch(timestamp) : null;
      debugPrint('Collection $i: "${collection.title}" - createdAt: $timestamp ($date)');
    }
    debugPrint('=== End Collections ===');
    
    return collections;
  }

  /// Get saved collections for a user
  Future<List<CollectionEntity>> getSavedCollections(String userId) async {
    final snapshot = await _collectionsRef
        .where('savedBy', arrayContains: userId)
        .get();

    final collections = snapshot.docs
        .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    
    // Sort by when the user saved them (savedAt timestamp), not when they were created
    collections.sort((a, b) {
      final aSavedAt = a.savedAt[userId] ?? 0;
      final bSavedAt = b.savedAt[userId] ?? 0;
      // If no savedAt timestamp, fall back to createdAt
      final aTime = aSavedAt > 0 ? aSavedAt : a.createdAt;
      final bTime = bSavedAt > 0 ? bSavedAt : b.createdAt;
      return bTime.compareTo(aTime); // descending (most recently saved first)
    });
    
    return collections;
  }

  /// Get saved collections for a user (Stream)
  Stream<List<CollectionEntity>> getSavedCollectionsStream(String userId) {
    return _collectionsRef
        .where('savedBy', arrayContains: userId)
        .snapshots()
        .map((snapshot) {
          final collections = snapshot.docs
              .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
              .toList();
          
          // Sort by when the user saved them (savedAt timestamp), not when they were created
          collections.sort((a, b) {
            final aSavedAt = a.savedAt[userId] ?? 0;
            final bSavedAt = b.savedAt[userId] ?? 0;
            // If no savedAt timestamp, fall back to createdAt
            final aTime = aSavedAt > 0 ? aSavedAt : a.createdAt;
            final bTime = bSavedAt > 0 ? bSavedAt : b.createdAt;
            return bTime.compareTo(aTime); // descending (most recently saved first)
          });
          
          return collections;
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
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();
    return snapshot.docs
        .map((doc) => CollectionEntity.fromMap(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList();
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
      'userName': userName,
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
    var userName = collection.userName.trim();
    var userAvatarUrl = collection.userAvatarUrl;

    if (userName.isEmpty) {
      final user = await getUser(collection.userId);
      userName = user?.userName.trim() ?? '';
      userAvatarUrl ??= user?.avatarUrl;
    }
    if (userName.isEmpty) {
      final resolved = await _getUsername(collection.userId);
      userName = resolved == 'Someone' ? 'User' : resolved;
    }

    final resolvedCollection = collection.copyWith(
      userName: userName,
      userAvatarUrl: userAvatarUrl,
    );

    final docRef = await _collectionsRef.add({
      ...resolvedCollection.toMap(),
      'searchKeywords': resolvedCollection.searchKeywords,
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
    await _collectionsRef.doc(collection.id).update({
      ...collection.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete a collection
  Future<void> deleteCollection(String collectionId, String userId) async {
    final items = await _collectionItemsRef.where('collectionId', isEqualTo: collectionId).get();
    final batch = _firestore.batch();
    for (final item in items.docs) {
      batch.delete(item.reference);
    }
    batch.delete(_collectionsRef.doc(collectionId));
    await batch.commit();

    // Decrement user's collection count
    await _usersRef.doc(userId).update({
      'collectionsCount': FieldValue.increment(-1),
    });
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

  /// Save a collection
  Future<void> saveCollection(String collectionId, String userId) async {
    final batch = _firestore.batch();
    batch.update(_usersRef.doc(userId), {
      'savedCollections': FieldValue.arrayUnion([collectionId]),
    });
    batch.update(_collectionsRef.doc(collectionId), {
      'savedBy': FieldValue.arrayUnion([userId]),
      'saveCount': FieldValue.increment(1),
    });
    await batch.commit();
  }

  Future<void> toggleCollectionSave(String collectionId, String userId) async {
    final collectionRef = _collectionsRef.doc(collectionId);
    final userRef = _usersRef.doc(userId);

    // Read current state
    final snap = await collectionRef.get();
    if (!snap.exists) return;
    final data = snap.data() as Map<String, dynamic>;
    final savedBy = List<String>.from(data['savedBy'] ?? const <String>[]);
    final isSaved = savedBy.contains(userId);

    // Always update user's own document first (user has permission on their own doc)
    if (isSaved) {
      await userRef.update({
        'savedCollections': FieldValue.arrayRemove([collectionId]),
      });
    } else {
      await userRef.update({
        'savedCollections': FieldValue.arrayUnion([collectionId]),
      });
    }

    // Best-effort update of collection document (may fail if user is not owner)
    try {
      if (isSaved) {
        await collectionRef.update({
          'savedBy': FieldValue.arrayRemove([userId]),
          'saveCount': FieldValue.increment(-1),
        });
      } else {
        await collectionRef.update({
          'savedBy': FieldValue.arrayUnion([userId]),
          'saveCount': FieldValue.increment(1),
        });
      }
    } catch (e) {
      debugPrint('Could not update collection savedBy (permission): $e');
    }
  }

  /// Unsave a collection
  Future<void> unsaveCollection(String collectionId, String userId) async {
    final batch = _firestore.batch();
    batch.update(_usersRef.doc(userId), {
      'savedCollections': FieldValue.arrayRemove([collectionId]),
    });
    batch.update(_collectionsRef.doc(collectionId), {
      'savedBy': FieldValue.arrayRemove([userId]),
      'saveCount': FieldValue.increment(-1),
    });
    await batch.commit();
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
    // Add to collection's collaborators array
    await _collectionsRef.doc(collectionId).update({
      'collaborators': FieldValue.arrayUnion([{
        'userId': userId,
        'username': username,
        'role': role.toUpperCase(),
        'addedAt': FieldValue.serverTimestamp(),
      }]),
      if (role.toUpperCase() == 'EDITOR')
        'editors': FieldValue.arrayUnion([userId])
      else
        'viewers': FieldValue.arrayUnion([userId]),
    });

    // Create notification for the invited user
    await _firestore.collection('notifications').add({
      'type': 'COLLABORATION_INVITE',
      'toUserId': userId,
      'fromUserId': currentUserId,
      'fromUsername': currentUsername,
      'collectionId': collectionId,
      'collectionTitle': collectionTitle,
      'role': role.toUpperCase(),
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
    await _firestore.collection('notifications').add({
      'type': 'FOLLOW_REQUEST',
      'toUserId': targetUserId,
      'fromUserId': currentUserId,
      'fromUsername': currentUsername,
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

    return docRef.id;
  }

  /// Update an item
  Future<void> updateCollectionItem(String collectionId, CollectionItemEntity item) async {
    await _collectionItemsRef.doc(item.id).update({
      ...item.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await _touchCollectionUpdatedAt(collectionId);
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
    await _touchCollectionUpdatedAt(collectionId);
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
      'userName': newOwnerName,
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
        'userName': newOwnerName,
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

  /// Check if user is following another user
  Future<bool> isFollowing(String currentUserId, String targetUserId) async {
    try {
      final doc = await _usersRef.doc(currentUserId).get();
      if (!doc.exists) return false;
      
      final data = doc.data() as Map<String, dynamic>;
      final following = List<String>.from(data['following'] ?? []);
      return following.contains(targetUserId);
    } catch (e) {
      return false;
    }
  }


  // ==================== SEARCH OPERATIONS ====================


  /// Search collections by title
  /// Search collections by keywords (case-insensitive)
  Future<List<CollectionEntity>> searchCollections(String query) async {
    if (query.trim().isEmpty) return [];

    // Split query into terms and lowercase them
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
    if (terms.isEmpty) return [];
    
    final primaryTerm = terms.first;

    // Use primary term for Firestore query
    final snapshot = await _collectionsRef
        .where('isPublic', isEqualTo: true)
        .where('searchKeywords', arrayContains: primaryTerm)
        .limit(50) // Fetch more to allow for client-side filtering
        .get();

    final collections = snapshot.docs
        .map((doc) =>
            CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();

    // Client-side filtering if multiple terms
    if (terms.length > 1) {
      return collections.where((collection) {
        return terms.skip(1).every((term) =>
            collection.searchKeywords.any((keyword) => keyword.contains(term)));
      }).toList();
    }

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
    Query query = _collectionsRef.where('isPublic', isEqualTo: true);

    try {
      final snapshot = await query
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(since))
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      debugPrint('getPublicCollectionsSince: Timestamp createdAt query failed: $e');
    }

    try {
      final snapshot = await query
          .where('createdAt', isGreaterThanOrEqualTo: since.millisecondsSinceEpoch)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();

      return snapshot.docs
          .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
    } catch (e) {
      debugPrint('getPublicCollectionsSince: int createdAt query failed: $e');
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

      // 2. Chunk processing (Firestore limit of 10 for IN queries)
      List<CollectionEntity> allCollections = [];
      const int batchSize = 10;
      
      for (int i = 0; i < following.length; i += batchSize) {
        final end = (i + batchSize < following.length) ? i + batchSize : following.length;
        final chunk = following.sublist(i, end);
        
        if (chunk.isEmpty) continue;

        final snapshot = await _collectionsRef
            .where('userId', whereIn: chunk)
            .where('isPublic', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .limit(10) // Limit per chunk to avoid fetching too many
            .get();
            
        final chunkCollections = snapshot.docs.map((doc) => 
          CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id)
        ).toList();
        
        allCollections.addAll(chunkCollections);
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
      allCollections.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      
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
        return Stream.value([]);
      }
      
      final following = user.following;
      if (following.isEmpty) return Stream.value([]);

      try {
        // Use snapshots() for real-time updates instead of get()
        return _collectionsRef
            .where('userId', whereIn: following.take(10))
            .where('isPublic', isEqualTo: true)
            .orderBy('createdAt', descending: true)
            .limit(50)
            .snapshots()
            .map((snapshot) {
              final collections = snapshot.docs
                  .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
                  .toList();
              
              collections.sort((a, b) => b.createdAt.compareTo(a.createdAt));
              return collections;
            });
      } catch (e) {
        debugPrint('Error fetching following collections: $e');
        return Stream.value([]);
      }
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
      final results = <String, CollectionEntity>{};

      final editorsSnap = await _collectionsRef
          .where('editors', arrayContains: userId)
          .get();
      for (final doc in editorsSnap.docs) {
        final c = CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        if (c.userId != userId) {
          results[doc.id] = c;
        }
      }

      final viewersSnap = await _collectionsRef
          .where('viewers', arrayContains: userId)
          .get();
      for (final doc in viewersSnap.docs) {
        final c = CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id);
        if (c.userId != userId) {
          results[doc.id] = c;
        }
      }

      final list = results.values.toList();
      // Defensive sort to ensure proper chronological ordering
      list.sort((a, b) {
        final aTime = a.createdAt;
        final bTime = b.createdAt;
        // Handle null/missing timestamps by treating them as oldest
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;  // a is older
        if (bTime == null) return -1; // b is older
        return bTime.compareTo(aTime); // descending (newest first)
      });
      return list;
    } catch (e) {
      debugPrint('Error loading collaborations for user $userId: $e');
      return const <CollectionEntity>[];
    }
  }

  /// Get user collaborations as a stream
  Stream<List<CollectionEntity>> getUserCollaborationsStream(String userId) {
    // We combine viewers and editors queries
    final editorsStream = _collectionsRef
        .where('editors', arrayContains: userId)
        .snapshots();
    
    final viewersStream = _collectionsRef
        .where('viewers', arrayContains: userId)
        .snapshots();

    return Rx.combineLatest2<QuerySnapshot, QuerySnapshot, List<CollectionEntity>>(
      editorsStream,
      viewersStream,
      (editors, viewers) {
        final results = <String, CollectionEntity>{};
        
        for (final doc in editors.docs) {
          final c = CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id);
          if (c.userId != userId) results[doc.id] = c;
        }
        
        for (final doc in viewers.docs) {
          final c = CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id);
          if (c.userId != userId) results[doc.id] = c;
        }
        
        final list = results.values.toList();
        // Defensive sort to ensure proper chronological ordering
        list.sort((a, b) {
          final aTime = a.createdAt;
          final bTime = b.createdAt;
          // Handle null/missing timestamps by treating them as oldest
          if (aTime == null && bTime == null) return 0;
          if (aTime == null) return 1;  // a is older
          if (bTime == null) return -1; // b is older
          return bTime.compareTo(aTime); // descending (newest first)
        });
        return list;
      },
    );
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

  /// Search users by username
  Future<List<UserEntity>> searchUsers(String query) async {
    if (query.isEmpty) return [];
    
    final lowerQuery = query.toLowerCase();
    final snapshot = await _usersRef
        .orderBy('username')
        .startAt([lowerQuery])
        .endAt(['$lowerQuery\uf8ff'])
        .limit(20)
        .get();

    return snapshot.docs
        .map((doc) => UserEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
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
}

class _CombinedValue {
  final int index;
  final dynamic value;
  _CombinedValue(this.index, this.value);
}

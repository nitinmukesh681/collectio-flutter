import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../models/collection_entity.dart';
import '../models/collection_item_entity.dart';
import '../models/user_entity.dart';


/// Firestore service for database operations
class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Collection references
  CollectionReference get _usersRef => _firestore.collection('users');
  CollectionReference get _collectionsRef => _firestore.collection('collections');
  CollectionReference get _collectionItemsRef => _firestore.collection('collectionItems');


  Future<String> _getUsername(String userId) async {
    final userDoc = await _usersRef.doc(userId).get();
    if (!userDoc.exists) return 'Someone';
    final data = userDoc.data() as Map<String, dynamic>;
    return (data['username'] as String?) ?? 'Someone';
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
    return _collectionsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => CollectionEntity.fromMap(
                doc.data() as Map<String, dynamic>, doc.id))
            .toList());
  }

  /// Get collections for a user (Future)
  Future<List<CollectionEntity>> getUserCollections(String userId) async {
    final snapshot = await _collectionsRef
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => CollectionEntity.fromMap(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList();
  }

  /// Get saved collections for a user
  Future<List<CollectionEntity>> getSavedCollections(String userId) async {
    final snapshot = await _collectionsRef
        .where('savedBy', arrayContains: userId)
        .get();

    final collections = snapshot.docs
        .map((doc) => CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
    collections.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return collections;
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
  }) async {
    await _collectionItemsRef.add({
      'collectionId': collectionId,
      'userId': userId,
      'userName': userName,
      'title': title,
      'websiteUrl': websiteUrl,
      'description': null,
      'imageUrls': [],
      'order': await _getNextItemOrder(collectionId),
      'likes': 0,
      'likedBy': [],
      'rating': 0.0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    
    // Update collection item count
    await _collectionsRef.doc(collectionId).update({
      'itemCount': FieldValue.increment(1),
    });
  }

  /// Get next order number for items in a collection
  Future<int> _getNextItemOrder(String collectionId) async {
    // NOTE: Avoid a composite index requirement (where + orderBy) by fetching items
    // by collectionId and determining max order client-side.
    final snapshot = await _collectionItemsRef
        .where('collectionId', isEqualTo: collectionId)
        .get();

    var maxOrder = -1;
    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final order = data['order'];
      if (order is int && order > maxOrder) {
        maxOrder = order;
      }
    }
    return maxOrder + 1;
  }


  Future<CollectionEntity?> getCollection(String collectionId) async {
    final doc = await _collectionsRef.doc(collectionId).get();
    if (!doc.exists) return null;
    return CollectionEntity.fromMap(
        doc.data() as Map<String, dynamic>, doc.id);
  }

  /// Create a new collection
  Future<String> createCollection(CollectionEntity collection) async {
    final docRef = await _collectionsRef.add({
      ...collection.toMap(),
      'searchKeywords': collection.searchKeywords,
      'savedBy': collection.savedBy,
      'contributorIds': collection.contributorIds,
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

      final result = await _firestore.runTransaction<(bool, String, String)>((tx) async {
        final snap = await tx.get(docRef);
        if (!snap.exists) return (false, '', '');

        final data = snap.data() as Map<String, dynamic>;
        final likedBy = List<String>.from(data['likedBy'] ?? const <String>[]);
        final currentLikes = (data['likes'] as int?) ?? 0;
        final ownerId = (data['userId'] as String?) ?? '';
        final title = (data['title'] as String?) ?? '';

        if (likedBy.contains(userId)) {
          tx.update(docRef, {
            'likedBy': FieldValue.arrayRemove([userId]),
            'likes': (currentLikes - 1) < 0 ? 0 : (currentLikes - 1),
          });
          return (false, ownerId, title);
        } else {
          tx.update(docRef, {
            'likedBy': FieldValue.arrayUnion([userId]),
            'likes': currentLikes + 1,
          });
          return (true, ownerId, title);
        }
      });

      if (result.$1) {
        try {
          await _createLikeNotification(
            toUserId: result.$2,
            fromUserId: userId,
            fromUsername: fromUsername,
            collectionId: collectionId,
            collectionTitle: result.$3,
            type: 'LIKE_COLLECTION',
          );
        } catch (e) {
          debugPrint('FirestoreService: toggleCollectionLike notification ERROR: $e');
        }
      }
      debugPrint('FirestoreService: toggleCollectionLike SUCCESS');
    } on FirebaseException catch (e) {
      debugPrint(
          'FirestoreService: toggleCollectionLike FirebaseException code=${e.code} message=${e.message}');
      rethrow;
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

    await _firestore.runTransaction<void>((tx) async {
      final snap = await tx.get(collectionRef);
      if (!snap.exists) return;
      final data = snap.data() as Map<String, dynamic>;
      final savedBy = List<String>.from(data['savedBy'] ?? const <String>[]);
      final currentSaves = (data['saveCount'] as int?) ?? 0;

      if (savedBy.contains(userId)) {
        tx.update(collectionRef, {
          'savedBy': FieldValue.arrayRemove([userId]),
          'saveCount': (currentSaves - 1) < 0 ? 0 : (currentSaves - 1),
        });
        tx.update(userRef, {
          'savedCollections': FieldValue.arrayRemove([collectionId]),
        });
      } else {
        tx.update(collectionRef, {
          'savedBy': FieldValue.arrayUnion([userId]),
          'saveCount': currentSaves + 1,
        });
        tx.update(userRef, {
          'savedCollections': FieldValue.arrayUnion([collectionId]),
        });
      }
    });
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



  /// Add item to collection
  Future<String> addCollectionItem(String collectionId, CollectionItemEntity item) async {
    final docRef = _collectionItemsRef.doc();
    final collectionRef = _collectionsRef.doc(collectionId);

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

      tx.set(docRef, {
        'collectionId': collectionId,
        'userId': item.userId,
        'userName': item.userName,
        'title': item.title,
        'description': item.description,
        'rating': item.rating,
        'imageUrls': item.imageUrls,
        'notes': item.notes,
        'googleMapsUrl': item.googleMapsUrl,
        'websiteUrl': item.websiteUrl,
        'order': computedOrder,
        'likes': item.likes,
        'likedBy': item.likedBy,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    return docRef.id;
  }

  /// Update an item
  Future<void> updateCollectionItem(String collectionId, CollectionItemEntity item) async {
    await _collectionItemsRef.doc(item.id).update({
      ...item.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Delete an item
  Future<void> deleteItem(String collectionId, String itemId) async {
    await _collectionItemsRef.doc(itemId).delete();

    // Update collection item count
    await _collectionsRef.doc(collectionId).update({
      'itemCount': FieldValue.increment(-1),
    });
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

    // Create new collection
    final newCollectionData = {
      ...originalData,
      'userId': newOwnerId,
      'userName': newOwnerName,
      'title': newTitle ?? '${originalData['title']} (Copy)',
      'description': newDescription ?? originalData['description'],
      'websiteUrl': originalData['websiteUrl'],
      'googleMapsUrl': originalData['googleMapsUrl'],
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
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      debugPrint('Error loading collaborations for user $userId: $e');
      return const <CollectionEntity>[];
    }
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


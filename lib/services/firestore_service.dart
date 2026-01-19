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


  // ==================== USER OPERATIONS ====================

  /// Get user by ID
  Future<UserEntity?> getUser(String userId) async {
    final doc = await _usersRef.doc(userId).get();
    if (!doc.exists) return null;
    return UserEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id);
  }

  /// Create or update user
  Future<void> saveUser(UserEntity user) async {
    await _usersRef.doc(user.id).set(user.toMap(), SetOptions(merge: true));
  }

  /// Update username
  Future<void> updateUsername(String userId, String username) async {
    await _usersRef.doc(userId).update({'userName': username});
  }

  /// Follow a user
  Future<void> followUser(String currentUserId, String targetUserId, String currentUsername) async {
    debugPrint('FirestoreService: followUser $currentUserId -> $targetUserId');
    try {
      final batch = _firestore.batch();
      batch.update(_usersRef.doc(currentUserId), {
        'following': FieldValue.arrayUnion([targetUserId]),
        'followingCount': FieldValue.increment(1),
      });
      batch.update(_usersRef.doc(targetUserId), {
        'followers': FieldValue.arrayUnion([currentUserId]),
        'followersCount': FieldValue.increment(1),
      });
      
      // Create notification for public profiles or general follow
      // (For private profiles, requestFollowUser should be used instead - logic handled in UI)
      final notificationRef = _firestore.collection('notifications').doc();
      batch.set(notificationRef, {
        'type': 'follow',
        'toUserId': targetUserId,
        'fromUserId': currentUserId,
        'fromUsername': currentUsername,
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();
      debugPrint('FirestoreService: followUser SUCCESS');
    } catch (e) {
      debugPrint('FirestoreService: followUser ERROR: $e');
      rethrow;
    }
  }

  /// Unfollow a user
  Future<void> unfollowUser(String currentUserId, String targetUserId) async {
    final batch = _firestore.batch();
    batch.update(_usersRef.doc(currentUserId), {
      'following': FieldValue.arrayRemove([targetUserId]),
      'followingCount': FieldValue.increment(-1),
    });
    batch.update(_usersRef.doc(targetUserId), {
      'followers': FieldValue.arrayRemove([currentUserId]),
      'followersCount': FieldValue.increment(-1),
    });
    await batch.commit();
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
    final userDoc = await _usersRef.doc(userId).get();
    if (!userDoc.exists) return [];
    
    final userData = userDoc.data() as Map<String, dynamic>;
    final savedIds = List<String>.from(userData['savedCollections'] ?? []);
    
    if (savedIds.isEmpty) return [];

    final collections = <CollectionEntity>[];
    for (final id in savedIds) {
      final collection = await getCollection(id);
      if (collection != null) {
        collections.add(collection);
      }
    }
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
    final snapshot = await _collectionItemsRef
        .where('collectionId', isEqualTo: collectionId)
        .orderBy('order', descending: true)
        .limit(1)
        .get();
    
    if (snapshot.docs.isEmpty) return 0;
    return ((snapshot.docs.first.data() as Map<String, dynamic>)['order'] as int? ?? 0) + 1;
  }


  Future<CollectionEntity?> getCollection(String collectionId) async {
    final doc = await _collectionsRef.doc(collectionId).get();
    if (!doc.exists) return null;
    return CollectionEntity.fromMap(
        doc.data() as Map<String, dynamic>, doc.id);
  }

  /// Create a new collection
  Future<String> createCollection(CollectionEntity collection) async {
    final docRef = await _collectionsRef.add(collection.toMap());
    // Increment user's collection count
    await _usersRef.doc(collection.userId).update({
      'collectionsCount': FieldValue.increment(1),
    });
    return docRef.id;
  }

  /// Update a collection
  Future<void> updateCollection(CollectionEntity collection) async {
    await _collectionsRef.doc(collection.id).update(collection.toMap());
  }

  /// Delete a collection
  Future<void> deleteCollection(String collectionId, String userId) async {
    // Delete all items in the collection
    final items = await _collectionsRef.doc(collectionId).collection('items').get();
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
    await _usersRef.doc(userId).update({
      'savedCollections': FieldValue.arrayUnion([collectionId]),
    });
    await _collectionsRef.doc(collectionId).update({
      'saveCount': FieldValue.increment(1),
    });
  }

  /// Unsave a collection
  Future<void> unsaveCollection(String collectionId, String userId) async {
    await _usersRef.doc(userId).update({
      'savedCollections': FieldValue.arrayRemove([collectionId]),
    });
    await _collectionsRef.doc(collectionId).update({
      'saveCount': FieldValue.increment(-1),
    });
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
        'role': role,
      }]),
    });

    // Create notification for the invited user
    await _firestore.collection('notifications').add({
      'type': 'collaboration_invite',
      'toUserId': userId,
      'fromUserId': currentUserId,
      'fromUsername': currentUsername,
      'collectionId': collectionId,
      'collectionTitle': collectionTitle,
      'role': role,
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
    });
  }

  // ==================== FOLLOW REQUEST OPERATIONS ====================

  /// Request to follow a user (for private accounts)
  Future<void> requestFollowUser(String currentUserId, String targetUserId, String currentUsername) async {
    // Add to target's pending requests
    await _usersRef.doc(targetUserId).update({
      'pendingFollowRequests': FieldValue.arrayUnion([currentUserId]),
    });

    // Create notification
    await _firestore.collection('notifications').add({
      'type': 'follow_request',
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
      'pendingFollowRequests': FieldValue.arrayRemove([requesterId]),
    });
    
    // Add follower relationship
    batch.update(_usersRef.doc(currentUserId), {
      'followers': FieldValue.arrayUnion([requesterId]),
      'followersCount': FieldValue.increment(1),
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
      'pendingFollowRequests': FieldValue.arrayRemove([requesterId]),
    });
  }

  /// Cancel a sent follow request
  Future<void> cancelFollowRequest(String currentUserId, String targetUserId) async {
    await _usersRef.doc(targetUserId).update({
      'pendingFollowRequests': FieldValue.arrayRemove([currentUserId]),
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



  /// Add item to collection
  Future<String> addCollectionItem(String collectionId, CollectionItemEntity item) async {
    final itemWithCollectionId = item.copyWith(collectionId: collectionId);
    final docRef = await _collectionItemsRef.add(itemWithCollectionId.toMap());

    // Update collection item count
    await _collectionsRef.doc(collectionId).update({
      'itemCount': FieldValue.increment(1),
    });

    return docRef.id;
  }

  /// Update an item
  Future<void> updateCollectionItem(String collectionId, CollectionItemEntity item) async {
    await _collectionItemsRef.doc(item.id).update(item.toMap());
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
    final itemDoc = await _collectionItemsRef.doc(itemId).get();
    if (!itemDoc.exists) return;

    final data = itemDoc.data() as Map<String, dynamic>;
    final likedBy = List<String>.from(data['likedBy'] ?? []);
    final isLiked = likedBy.contains(userId);

    if (isLiked) {
      await _collectionItemsRef.doc(itemId).update({
        'likedBy': FieldValue.arrayRemove([userId]),
        'likes': FieldValue.increment(-1),
      });
    } else {
      await _collectionItemsRef.doc(itemId).update({
        'likedBy': FieldValue.arrayUnion([userId]),
        'likes': FieldValue.increment(1),
      });
    }
  }

  /// Duplicate a collection with all its items
  Future<String> duplicateCollection({
    required String originalCollectionId,
    required String newOwnerId,
    required String newOwnerName,
    required String newTitle,
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
      'title': newTitle,
      'description': newDescription ?? originalData['description'],
      'likes': 0,
      'likedBy': [],
      'saveCount': 0,
      'itemCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
      'collaborators': [],
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

  /// Get collections from users that current user follows
  Future<List<CollectionEntity>> getFollowingCollections(String userId) async {
    // Get user's following list
    final userDoc = await _usersRef.doc(userId).get();
    if (!userDoc.exists) return [];

    final userData = userDoc.data() as Map<String, dynamic>;
    final following = List<String>.from(userData['following'] ?? []);

    if (following.isEmpty) return [];

    // Firestore 'in' queries are limited to 30 items
    final limitedFollowing = following.take(30).toList();

    final snapshot = await _collectionsRef
        .where('userId', whereIn: limitedFollowing)
        .where('isPublic', isEqualTo: true)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .get();

    return snapshot.docs
        .map((doc) => CollectionEntity.fromMap(
            doc.data() as Map<String, dynamic>, doc.id))
        .toList();
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

  /// Get collections by category
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

  /// Get open collaboration collections
  Future<List<CollectionEntity>> getOpenCollaborationCollections() async {
    final snapshot = await _collectionsRef
        .where('isPublic', isEqualTo: true)
        .where('isOpenForContribution', isEqualTo: true)
        .orderBy('contributorCount', descending: true)
        .limit(10)
        .get();

    return snapshot.docs
        .map((doc) =>
            CollectionEntity.fromMap(doc.data() as Map<String, dynamic>, doc.id))
        .toList();
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
        .orderBy('userName')
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


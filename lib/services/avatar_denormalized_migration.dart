import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// One-time migration: align denormalized avatar URLs on collections, comments,
/// and notifications with each user's canonical [avatarUrl] on their profile.
class AvatarDenormalizedMigration {
  AvatarDenormalizedMigration._();

  static const _migrationId = 'denormalized_avatar_sync_v1';
  static const _metaDocPath = 'app_settings/migrations';

  static Future<void> runIfNeeded(FirebaseFirestore firestore) async {
    if (await _isComplete(firestore, _migrationId)) return;

    debugPrint('[Migration] Starting denormalized avatar sync...');
    final avatarByUserId = await _loadUserAvatars(firestore);
    var updatedCount = 0;

    updatedCount += await _paginateCollection(
      firestore: firestore,
      collectionPath: 'collections',
      userIdField: 'userId',
      avatarField: 'userAvatarUrl',
      avatarByUserId: avatarByUserId,
    );

    updatedCount += await _paginateCollection(
      firestore: firestore,
      collectionPath: 'comments',
      userIdField: 'userId',
      avatarField: 'userAvatarUrl',
      avatarByUserId: avatarByUserId,
    );

    updatedCount += await _paginateCollection(
      firestore: firestore,
      collectionPath: 'notifications',
      userIdField: 'fromUserId',
      avatarField: 'fromUserAvatarUrl',
      avatarByUserId: avatarByUserId,
    );

    await _markComplete(firestore, _migrationId, updatedCount);
    debugPrint(
      '[Migration] Denormalized avatar sync complete ($updatedCount documents updated)',
    );
  }

  static Future<Map<String, String?>> _loadUserAvatars(
    FirebaseFirestore firestore,
  ) async {
    final avatarByUserId = <String, String?>{};
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;

    while (true) {
      Query<Map<String, dynamic>> query = firestore
          .collection('users')
          .orderBy(FieldPath.documentId)
          .limit(200);
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) break;

      for (final doc in snapshot.docs) {
        avatarByUserId[doc.id] = _canonicalAvatar(doc.data()['avatarUrl']);
      }

      lastDoc = snapshot.docs.last;
      if (snapshot.docs.length < 200) break;
    }

    return avatarByUserId;
  }

  static String? _canonicalAvatar(Object? raw) {
    final trimmed = raw?.toString().trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static Map<String, dynamic>? _buildAvatarUpdates({
    required Map<String, dynamic> data,
    required String userIdField,
    required String avatarField,
    required Map<String, String?> avatarByUserId,
  }) {
    final userId = data[userIdField]?.toString().trim();
    if (userId == null || userId.isEmpty) return null;

    final canonical = avatarByUserId[userId];
    final stored = _canonicalAvatar(data[avatarField]);

    if (canonical == null) {
      if (stored == null) return null;
      return {avatarField: FieldValue.delete()};
    }

    if (stored == canonical) return null;
    return {avatarField: canonical};
  }

  static Future<bool> _isComplete(
    FirebaseFirestore firestore,
    String migrationId,
  ) async {
    final meta = await firestore.doc(_metaDocPath).get();
    return meta.data()?[migrationId] == true;
  }

  static Future<void> _markComplete(
    FirebaseFirestore firestore,
    String migrationId,
    int updatedCount,
  ) async {
    await firestore.doc(_metaDocPath).set(
      {
        migrationId: true,
        '${migrationId}_completedAt': FieldValue.serverTimestamp(),
        '${migrationId}_updatedCount': updatedCount,
      },
      SetOptions(merge: true),
    );
  }

  static Future<int> _paginateCollection({
    required FirebaseFirestore firestore,
    required String collectionPath,
    required String userIdField,
    required String avatarField,
    required Map<String, String?> avatarByUserId,
  }) async {
    var updatedCount = 0;
    DocumentSnapshot<Map<String, dynamic>>? lastDoc;

    while (true) {
      Query<Map<String, dynamic>> query = firestore
          .collection(collectionPath)
          .orderBy(FieldPath.documentId)
          .limit(200);
      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) break;

      final batch = firestore.batch();
      var batchOps = 0;

      for (final doc in snapshot.docs) {
        final updates = _buildAvatarUpdates(
          data: doc.data(),
          userIdField: userIdField,
          avatarField: avatarField,
          avatarByUserId: avatarByUserId,
        );
        if (updates == null || updates.isEmpty) continue;
        batch.update(doc.reference, updates);
        batchOps++;
        updatedCount++;
      }

      if (batchOps > 0) {
        await batch.commit();
      }

      lastDoc = snapshot.docs.last;
      if (snapshot.docs.length < 200) break;
    }

    return updatedCount;
  }
}

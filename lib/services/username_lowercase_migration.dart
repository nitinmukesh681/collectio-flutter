import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../utils/username_utils.dart';

/// One-time migrations to lowercase usernames across Firestore.
class UsernameLowercaseMigration {
  UsernameLowercaseMigration._();

  static const _usersMigrationId = 'username_lowercase_v1';
  static const _denormalizedMigrationId = 'denormalized_username_lowercase_v1';
  static const _metaDocPath = 'app_settings/migrations';

  static Future<void> runIfNeeded(FirebaseFirestore firestore) async {
    await _migrateUsers(firestore);
    await _migrateDenormalizedUsernames(firestore);
  }

  static Future<void> _migrateUsers(FirebaseFirestore firestore) async {
    if (await _isComplete(firestore, _usersMigrationId)) return;

    debugPrint('[Migration] Starting user username lowercase migration...');
    final updatedCount = await _paginateCollection(
      firestore: firestore,
      collectionPath: 'users',
      buildUpdates: (data) {
        final raw =
            (data['username'] ?? data['userName'] ?? '').toString().trim();
        if (raw.isEmpty) return null;
        final normalized = UsernameUtils.normalize(raw);
        if (raw == normalized) return null;
        return {
          'username': normalized,
          'usernameLower': normalized,
        };
      },
    );

    await _markComplete(
      firestore,
      _usersMigrationId,
      updatedCount,
    );
    debugPrint(
      '[Migration] User username migration complete ($updatedCount updated)',
    );
  }

  static Future<void> _migrateDenormalizedUsernames(
    FirebaseFirestore firestore,
  ) async {
    if (await _isComplete(firestore, _denormalizedMigrationId)) return;

    debugPrint('[Migration] Starting denormalized username lowercase migration...');
    var updatedCount = 0;

    updatedCount += await _paginateCollection(
      firestore: firestore,
      collectionPath: 'collections',
      buildUpdates: (data) {
        final updates = <String, dynamic>{};

        final rawUserName =
            (data['userName'] ?? data['username'] ?? '').toString().trim();
        if (rawUserName.isNotEmpty) {
          final normalized = UsernameUtils.normalize(rawUserName);
          if (rawUserName != normalized) {
            updates['userName'] = normalized;
          }
        }

        final collaborators = data['collaborators'];
        if (collaborators is List) {
          var changed = false;
          final next = collaborators.map((entry) {
            if (entry is! Map) return entry;
            final map = Map<String, dynamic>.from(entry);
            final username = map['username']?.toString();
            if (username == null || username.isEmpty) return map;
            final normalized = UsernameUtils.normalize(username);
            if (username == normalized) return map;
            changed = true;
            map['username'] = normalized;
            return map;
          }).toList();
          if (changed) {
            updates['collaborators'] = next;
          }
        }

        return updates.isEmpty ? null : updates;
      },
    );

    updatedCount += await _paginateCollection(
      firestore: firestore,
      collectionPath: 'collectionItems',
      buildUpdates: (data) => _singleUsernameFieldUpdate(data, 'userName'),
    );

    updatedCount += await _paginateCollection(
      firestore: firestore,
      collectionPath: 'comments',
      buildUpdates: (data) {
        final updates = <String, dynamic>{};
        final userNameUpdate = _singleUsernameFieldUpdate(data, 'userName');
        if (userNameUpdate != null) {
          updates.addAll(userNameUpdate);
        }

        final mentions = data['mentions'];
        if (mentions is List) {
          var changed = false;
          final next = mentions.map((entry) {
            if (entry is! Map) return entry;
            final map = Map<String, dynamic>.from(entry);
            final username = map['username']?.toString();
            if (username == null || username.isEmpty) return map;
            final normalized = UsernameUtils.normalize(username);
            if (username == normalized) return map;
            changed = true;
            map['username'] = normalized;
            return map;
          }).toList();
          if (changed) {
            updates['mentions'] = next;
          }
        }

        return updates.isEmpty ? null : updates;
      },
    );

    updatedCount += await _paginateCollection(
      firestore: firestore,
      collectionPath: 'notifications',
      buildUpdates: (data) => _singleUsernameFieldUpdate(data, 'fromUsername'),
    );

    await _markComplete(
      firestore,
      _denormalizedMigrationId,
      updatedCount,
    );
    debugPrint(
      '[Migration] Denormalized username migration complete ($updatedCount updated)',
    );
  }

  static Map<String, dynamic>? _singleUsernameFieldUpdate(
    Map<String, dynamic> data,
    String field,
  ) {
    final raw = (data[field] ?? '').toString().trim();
    if (raw.isEmpty) return null;
    final normalized = UsernameUtils.normalize(raw);
    if (raw == normalized) return null;
    return {field: normalized};
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
    required Map<String, dynamic>? Function(Map<String, dynamic> data) buildUpdates,
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
        final updates = buildUpdates(doc.data());
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

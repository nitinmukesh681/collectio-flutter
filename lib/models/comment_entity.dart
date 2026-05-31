import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/comment_mentions.dart';
import '../utils/username_utils.dart';

class CommentEntity {
  final String id;
  final String collectionId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String text;
  final String? parentCommentId;
  final List<CommentMention> mentions;
  final int likes;
  final List<String> likedBy;
  final int createdAt;

  CommentEntity({
    required this.id,
    required this.collectionId,
    required this.userId,
    required String userName,
    this.userAvatarUrl,
    required this.text,
    this.parentCommentId,
    this.mentions = const [],
    this.likes = 0,
    this.likedBy = const [],
    required this.createdAt,
  }) : userName = UsernameUtils.normalize(userName);

  factory CommentEntity.fromMap(Map<String, dynamic> map, String docId) {
    int createdAtValue;
    final rawCreatedAt = map['createdAt'];
    if (rawCreatedAt is Timestamp) {
      createdAtValue = rawCreatedAt.millisecondsSinceEpoch;
    } else if (rawCreatedAt is int) {
      createdAtValue = rawCreatedAt;
    } else {
      createdAtValue = DateTime.now().millisecondsSinceEpoch;
    }

    return CommentEntity(
      id: docId,
      collectionId: map['collectionId'] ?? '',
      userId: map['userId'] ?? '',
      userName: UsernameUtils.normalize(
        (map['userName'] ?? map['username'] ?? '').toString(),
      ),
      userAvatarUrl: map['userAvatarUrl'],
      text: map['text'] ?? '',
      parentCommentId: _normalizeParentCommentId(map['parentCommentId']),
      mentions: _parseMentions(map['mentions']),
      likes: map['likes'] ?? 0,
      likedBy: List<String>.from(map['likedBy'] ?? []),
      createdAt: createdAtValue,
    );
  }

  static String? _normalizeParentCommentId(dynamic value) {
    if (value == null) return null;
    final trimmed = value.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<CommentMention> _parseMentions(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((entry) => CommentMention.fromMap(Map<String, dynamic>.from(entry)))
        .where((mention) => mention.userId.isNotEmpty && mention.username.isNotEmpty)
        .toList(growable: false);
  }

  Map<String, dynamic> toMap() {
    return {
      'collectionId': collectionId,
      'userId': userId,
      'userName': userName,
      'userAvatarUrl': userAvatarUrl,
      'text': text,
      'parentCommentId': parentCommentId,
      if (mentions.isNotEmpty) 'mentions': mentions.map((m) => m.toMap()).toList(),
      'likes': likes,
      'likedBy': likedBy,
      'createdAt': createdAt,
    };
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class CommentEntity {
  final String id;
  final String collectionId;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String text;
  final String? parentCommentId;
  final int likes;
  final List<String> likedBy;
  final int createdAt;

  CommentEntity({
    required this.id,
    required this.collectionId,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.text,
    this.parentCommentId,
    this.likes = 0,
    this.likedBy = const [],
    required this.createdAt,
  });

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
      userName: map['userName'] ?? map['username'] ?? '',
      userAvatarUrl: map['userAvatarUrl'],
      text: map['text'] ?? '',
      parentCommentId: map['parentCommentId'],
      likes: map['likes'] ?? 0,
      likedBy: List<String>.from(map['likedBy'] ?? []),
      createdAt: createdAtValue,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'collectionId': collectionId,
      'userId': userId,
      'userName': userName,
      'userAvatarUrl': userAvatarUrl,
      'text': text,
      'parentCommentId': parentCommentId,
      'likes': likes,
      'likedBy': likedBy,
      'createdAt': createdAt,
    };
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

/// Domain entity representing a user
class UserEntity {
  final String id;
  final String email;
  final String userName;
  final String? avatarUrl;
  final String? bio;
  final int collectionsCount;
  final int followersCount;
  final int followingCount;
  final List<String> followers;
  final List<String> following;
  final int createdAt;

  UserEntity({
    required this.id,
    required this.email,
    required this.userName,
    this.avatarUrl,
    this.bio,
    this.collectionsCount = 0,
    this.followersCount = 0,
    this.followingCount = 0,
    this.followers = const [],
    this.following = const [],
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Create from Firestore document
  factory UserEntity.fromMap(Map<String, dynamic> map, String docId) {
    // Handle Firestore Timestamp conversion
    int createdAtValue;
    final rawCreatedAt = map['createdAt'];
    if (rawCreatedAt is Timestamp) {
      createdAtValue = rawCreatedAt.millisecondsSinceEpoch;
    } else if (rawCreatedAt is int) {
      createdAtValue = rawCreatedAt;
    } else {
      createdAtValue = DateTime.now().millisecondsSinceEpoch;
    }

    return UserEntity(
      id: docId,
      email: map['email'] ?? '',
      userName: map['userName'] ?? '',
      avatarUrl: map['avatarUrl'],
      bio: map['bio'],
      collectionsCount: map['collectionsCount'] ?? 0,
      followersCount: map['followersCount'] ?? 0,
      followingCount: map['followingCount'] ?? 0,
      followers: List<String>.from(map['followers'] ?? []),
      following: List<String>.from(map['following'] ?? []),
      createdAt: createdAtValue,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'userName': userName,
      'avatarUrl': avatarUrl,
      'bio': bio,
      'collectionsCount': collectionsCount,
      'followersCount': followersCount,
      'followingCount': followingCount,
      'followers': followers,
      'following': following,
      'createdAt': createdAt,
    };
  }

  UserEntity copyWith({
    String? id,
    String? email,
    String? userName,
    String? avatarUrl,
    String? bio,
    int? collectionsCount,
    int? followersCount,
    int? followingCount,
    List<String>? followers,
    List<String>? following,
    int? createdAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      email: email ?? this.email,
      userName: userName ?? this.userName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      collectionsCount: collectionsCount ?? this.collectionsCount,
      followersCount: followersCount ?? this.followersCount,
      followingCount: followingCount ?? this.followingCount,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

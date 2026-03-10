import 'package:cloud_firestore/cloud_firestore.dart';

/// Domain entity representing a user
class UserEntity {
  final String id;
  final String displayName;
  final String email;
  final String username;
  final String? avatarUrl;
  final String? bio;
  final bool isPrivateAccount;
  final int collectionsCount;
  final int followerCount;
  final int followingCount;
  final List<String> followers;
  final List<String> following;
  final List<String> followRequests;
  final List<String> savedCollections;
  final int createdAt;

  UserEntity({
    required this.id,
    this.displayName = '',
    required this.email,
    required this.username,
    this.avatarUrl,
    this.bio,
    this.isPrivateAccount = false,
    this.collectionsCount = 0,
    this.followerCount = 0,
    this.followingCount = 0,
    this.followers = const [],
    this.following = const [],
    this.followRequests = const [],
    this.savedCollections = const [],
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  String get userName => username;
  int get followersCount => followerCount;

  UserEntity copyWith({
    String? id,
    String? displayName,
    String? email,
    String? username,
    String? avatarUrl,
    String? bio,
    bool? isPrivateAccount,
    int? collectionsCount,
    int? followerCount,
    int? followingCount,
    List<String>? followers,
    List<String>? following,
    List<String>? followRequests,
    List<String>? savedCollections,
    int? createdAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      isPrivateAccount: isPrivateAccount ?? this.isPrivateAccount,
      collectionsCount: collectionsCount ?? this.collectionsCount,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      followers: followers ?? this.followers,
      following: following ?? this.following,
      followRequests: followRequests ?? this.followRequests,
      savedCollections: savedCollections ?? this.savedCollections,
      createdAt: createdAt ?? this.createdAt,
    );
  }

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
      displayName: map['displayName'] ?? '',
      email: map['email'] ?? '',
      username: map['username'] ?? map['userName'] ?? '',
      avatarUrl: map['avatarUrl'],
      bio: map['bio'],
      collectionsCount: map['collectionsCount'] ?? 0,
      isPrivateAccount: map['isPrivateAccount'] ?? false,
      followerCount: map['followerCount'] ?? map['followersCount'] ?? 0,
      followingCount: map['followingCount'] ?? 0,
      followers: List<String>.from(map['followers'] ?? []),
      following: List<String>.from(map['following'] ?? []),
      followRequests: List<String>.from(map['followRequests'] ?? map['pendingFollowRequests'] ?? []),
      savedCollections: List<String>.from(map['savedCollections'] ?? []),
      createdAt: createdAtValue,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'displayName': displayName,
      'email': email,
      'username': username,
      'avatarUrl': avatarUrl,
      'bio': bio,
      'isPrivateAccount': isPrivateAccount,
      'collectionsCount': collectionsCount,
      'followerCount': followerCount,
      'followingCount': followingCount,
      'followers': followers,
      'following': following,
      'followRequests': followRequests,
      'savedCollections': savedCollections,
      'createdAt': createdAt,
    };
  }
}

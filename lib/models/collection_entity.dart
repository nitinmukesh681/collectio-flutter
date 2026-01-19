import 'package:cloud_firestore/cloud_firestore.dart';
import 'category_type.dart';

/// Visibility options for collections
enum CollectionVisibility { public, private, followers }

/// User roles for collections
enum UserRole { owner, collaborator, contributor, none }

/// Helper to convert Firestore Timestamp to int
int _timestampToInt(dynamic value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  } else if (value is int) {
    return value;
  }
  return DateTime.now().millisecondsSinceEpoch;
}

/// Domain entity representing a collection
class CollectionEntity {
  final String id;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String title;
  final String? description;
  final CategoryType category;
  final List<String> tags;
  final String? coverImageUrl;
  final List<String> previewImageUrls;
  final CollectionVisibility visibility;
  final bool isPublic;
  final int itemCount;
  final bool isOpenForContribution;
  final int likes;
  final List<String> likedBy;
  final bool isLiked;
  final int saveCount;
  final bool isSaved;
  final String? inspiredBy;
  final String? inspiredByUserId;
  final UserRole userRole;
  final int contributorCount;
  final int collaboratorCount;
  final int createdAt;
  final List<String> searchKeywords;

  CollectionEntity({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.title,
    this.description,
    this.category = CategoryType.other,
    this.tags = const [],
    this.coverImageUrl,
    this.previewImageUrls = const [],
    this.visibility = CollectionVisibility.public,
    this.isPublic = true,
    this.itemCount = 0,
    this.isOpenForContribution = false,
    this.likes = 0,
    this.likedBy = const [],
    this.isLiked = false,
    this.saveCount = 0,
    this.isSaved = false,
    this.inspiredBy,
    this.inspiredByUserId,
    this.userRole = UserRole.none,
    this.contributorCount = 0,
    this.collaboratorCount = 0,
    this.searchKeywords = const [],
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Create from Firestore document
  factory CollectionEntity.fromMap(Map<String, dynamic> map, String docId) {
    return CollectionEntity(
      id: docId,
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userAvatarUrl: map['userAvatarUrl'],
      title: map['title'] ?? '',
      description: map['description'],
      category: CategoryType.fromString(map['category']),
      tags: List<String>.from(map['tags'] ?? []),
      coverImageUrl: map['coverImageUrl'],
      previewImageUrls: List<String>.from(map['previewImageUrls'] ?? []),
      visibility: CollectionVisibility.values.firstWhere(
        (e) => e.name == (map['visibility'] ?? 'public'),
        orElse: () => CollectionVisibility.public,
      ),
      isPublic: map['isPublic'] ?? true,
      itemCount: map['itemCount'] ?? 0,
      isOpenForContribution: map['isOpenForContribution'] ?? false,
      likes: map['likes'] ?? 0,
      likedBy: List<String>.from(map['likedBy'] ?? []),
      saveCount: map['saveCount'] ?? 0,
      inspiredBy: map['inspiredBy'],
      inspiredByUserId: map['inspiredByUserId'],
      contributorCount: map['contributorCount'] ?? 0,
      collaboratorCount: map['collaboratorCount'] ?? 0,
      searchKeywords: List<String>.from(map['searchKeywords'] ?? []),
      createdAt: _timestampToInt(map['createdAt']),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userAvatarUrl': userAvatarUrl,
      'title': title,
      'description': description,
      'category': category.name.toUpperCase(),
      'tags': tags,
      'coverImageUrl': coverImageUrl,
      'previewImageUrls': previewImageUrls,
      'visibility': visibility.name,
      'isPublic': isPublic,
      'itemCount': itemCount,
      'isOpenForContribution': isOpenForContribution,
      'likes': likes,
      'likedBy': likedBy,
      'saveCount': saveCount,
      'inspiredBy': inspiredBy,
      'inspiredByUserId': inspiredByUserId,
      'contributorCount': contributorCount,
      'collaboratorCount': collaboratorCount,
      'searchKeywords': searchKeywords,
      'createdAt': createdAt,
    };
  }

  CollectionEntity copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userAvatarUrl,
    String? title,
    String? description,
    CategoryType? category,
    List<String>? tags,
    String? coverImageUrl,
    List<String>? previewImageUrls,
    CollectionVisibility? visibility,
    bool? isPublic,
    int? itemCount,
    bool? isOpenForContribution,
    int? likes,
    List<String>? likedBy,
    bool? isLiked,
    int? saveCount,
    bool? isSaved,
    String? inspiredBy,
    String? inspiredByUserId,
    UserRole? userRole,
    int? contributorCount,
    int? collaboratorCount,
    List<String>? searchKeywords,
    int? createdAt,
  }) {
    return CollectionEntity(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userAvatarUrl: userAvatarUrl ?? this.userAvatarUrl,
      title: title ?? this.title,
      description: description ?? this.description,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      previewImageUrls: previewImageUrls ?? this.previewImageUrls,
      visibility: visibility ?? this.visibility,
      isPublic: isPublic ?? this.isPublic,
      itemCount: itemCount ?? this.itemCount,
      isOpenForContribution: isOpenForContribution ?? this.isOpenForContribution,
      likes: likes ?? this.likes,
      likedBy: likedBy ?? this.likedBy,
      isLiked: isLiked ?? this.isLiked,
      saveCount: saveCount ?? this.saveCount,
      isSaved: isSaved ?? this.isSaved,
      inspiredBy: inspiredBy ?? this.inspiredBy,
      inspiredByUserId: inspiredByUserId ?? this.inspiredByUserId,
      userRole: userRole ?? this.userRole,
      contributorCount: contributorCount ?? this.contributorCount,
      collaboratorCount: collaboratorCount ?? this.collaboratorCount,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

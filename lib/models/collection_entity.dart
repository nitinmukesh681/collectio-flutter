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
  static const Object _unset = Object();

  final String id;
  final String userId;
  final String userName;
  final String? userAvatarUrl;
  final String title;
  final String? description;
  final String? websiteUrl;
  final String? googleMapsUrl;
  final CategoryType category;
  final List<String> tags;
  final String? coverImageUrl;
  final List<String> previewImageUrls;
  final CollectionVisibility visibility;
  final bool isPublic;
  final int itemCount;
  final bool isOpenForContribution;
  final int contributorCount;
  final List<String> contributorIds;
  final int likes;
  final List<String> likedBy;
  final bool isLiked;
  final int saveCount;
  final bool isSaved;
  final List<String> savedBy;
  final String? inspiredBy;
  final String? inspiredByUserId;
  final UserRole userRole;
  final int collaboratorCount;
  final List<Map<String, dynamic>> collaborators;
  final List<String> editors;
  final List<String> viewers;
  final int createdAt;
  final List<String> searchKeywords;

  CollectionEntity({
    required this.id,
    required this.userId,
    required this.userName,
    this.userAvatarUrl,
    required this.title,
    this.description,
    this.websiteUrl,
    this.googleMapsUrl,
    this.category = CategoryType.other,
    this.tags = const [],
    this.coverImageUrl,
    this.previewImageUrls = const [],
    this.visibility = CollectionVisibility.public,
    this.isPublic = true,
    this.itemCount = 0,
    this.isOpenForContribution = false,
    this.contributorCount = 0,
    this.contributorIds = const [],
    this.likes = 0,
    this.likedBy = const [],
    this.isLiked = false,
    this.saveCount = 0,
    this.isSaved = false,
    this.savedBy = const [],
    this.inspiredBy,
    this.inspiredByUserId,
    this.userRole = UserRole.none,
    this.collaboratorCount = 0,
    this.collaborators = const [],
    this.editors = const [],
    this.viewers = const [],
    this.searchKeywords = const [],
    int? createdAt,
  }) : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Create from Firestore document
  factory CollectionEntity.fromMap(Map<String, dynamic> map, String docId) {
    final rawVisibility = (map['visibility'] as String?)?.toUpperCase();

    final rawCover = map['coverImageUrl'];
    final coverImageUrl = rawCover is String ? rawCover.trim() : null;

    final rawPreview = map['previewImageUrls'];
    final previewImageUrls = (rawPreview is List)
        ? rawPreview.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        : const <String>[];

    return CollectionEntity(
      id: docId,
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      userAvatarUrl: map['userAvatarUrl'],
      title: map['title'] ?? '',
      description: map['description'],
      websiteUrl: map['websiteUrl'],
      googleMapsUrl: map['googleMapsUrl'],
      category: CategoryType.fromString(map['category']),
      tags: List<String>.from(map['tags'] ?? []),
      coverImageUrl: (coverImageUrl != null && coverImageUrl.isNotEmpty) ? coverImageUrl : null,
      previewImageUrls: previewImageUrls,
      visibility: CollectionVisibility.values.firstWhere(
        (e) => e.name == (rawVisibility ?? 'PUBLIC').toLowerCase(),
        orElse: () {
          if (rawVisibility == 'FOLLOWERS') return CollectionVisibility.followers;
          if (rawVisibility == 'PRIVATE') return CollectionVisibility.private;
          return CollectionVisibility.public;
        },
      ),
      isPublic: map['isPublic'] ?? true,
      itemCount: map['itemCount'] ?? 0,
      isOpenForContribution: map['isOpenForContribution'] ?? false,
      contributorCount: map['contributorCount'] ?? 0,
      contributorIds: List<String>.from(map['contributorIds'] ?? []),
      likes: map['likes'] ?? 0,
      likedBy: List<String>.from(map['likedBy'] ?? []),
      saveCount: map['saveCount'] ?? 0,
      inspiredBy: map['inspiredBy'],
      inspiredByUserId: map['inspiredByUserId'],
      collaboratorCount: map['collaboratorCount'] ?? 0,
      savedBy: List<String>.from(map['savedBy'] ?? []),
      collaborators: (map['collaborators'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          const [],
      editors: List<String>.from(map['editors'] ?? []),
      viewers: List<String>.from(map['viewers'] ?? []),
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
      'websiteUrl': websiteUrl,
      'googleMapsUrl': googleMapsUrl,
      'category': category.name.toUpperCase(),
      'tags': tags,
      'coverImageUrl': coverImageUrl,
      'previewImageUrls': previewImageUrls,
      'visibility': visibility.name.toUpperCase(),
      'isPublic': isPublic,
      'itemCount': itemCount,
      'isOpenForContribution': isOpenForContribution,
      'contributorCount': contributorCount,
      'contributorIds': contributorIds,
      'likes': likes,
      'likedBy': likedBy,
      'saveCount': saveCount,
      'savedBy': savedBy,
      'inspiredBy': inspiredBy,
      'inspiredByUserId': inspiredByUserId,
      'collaboratorCount': collaboratorCount,
      'collaborators': collaborators,
      'editors': editors,
      'viewers': viewers,
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
    Object? websiteUrl = _unset,
    Object? googleMapsUrl = _unset,
    CategoryType? category,
    List<String>? tags,
    String? coverImageUrl,
    List<String>? previewImageUrls,
    CollectionVisibility? visibility,
    bool? isPublic,
    int? itemCount,
    bool? isOpenForContribution,
    int? contributorCount,
    List<String>? contributorIds,
    int? likes,
    List<String>? likedBy,
    bool? isLiked,
    int? saveCount,
    bool? isSaved,
    List<String>? savedBy,
    String? inspiredBy,
    String? inspiredByUserId,
    UserRole? userRole,
    int? collaboratorCount,
    List<Map<String, dynamic>>? collaborators,
    List<String>? editors,
    List<String>? viewers,
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
      websiteUrl: identical(websiteUrl, _unset) ? this.websiteUrl : websiteUrl as String?,
      googleMapsUrl: identical(googleMapsUrl, _unset) ? this.googleMapsUrl : googleMapsUrl as String?,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      previewImageUrls: previewImageUrls ?? this.previewImageUrls,
      visibility: visibility ?? this.visibility,
      isPublic: isPublic ?? this.isPublic,
      itemCount: itemCount ?? this.itemCount,
      isOpenForContribution: isOpenForContribution ?? this.isOpenForContribution,
      contributorCount: contributorCount ?? this.contributorCount,
      contributorIds: contributorIds ?? this.contributorIds,
      likes: likes ?? this.likes,
      likedBy: likedBy ?? this.likedBy,
      isLiked: isLiked ?? this.isLiked,
      saveCount: saveCount ?? this.saveCount,
      isSaved: isSaved ?? this.isSaved,
      savedBy: savedBy ?? this.savedBy,
      inspiredBy: inspiredBy ?? this.inspiredBy,
      inspiredByUserId: inspiredByUserId ?? this.inspiredByUserId,
      userRole: userRole ?? this.userRole,
      collaboratorCount: collaboratorCount ?? this.collaboratorCount,
      collaborators: collaborators ?? this.collaborators,
      editors: editors ?? this.editors,
      viewers: viewers ?? this.viewers,
      searchKeywords: searchKeywords ?? this.searchKeywords,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

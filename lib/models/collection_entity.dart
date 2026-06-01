import 'package:cloud_firestore/cloud_firestore.dart';
import 'category_type.dart';
import '../utils/search_tokenizer.dart';
import '../utils/username_utils.dart';

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
  final Map<String, int> savedAt;
  final String? inspiredBy;
  final String? inspiredByUserId;
  final UserRole userRole;
  final int collaboratorCount;
  final List<Map<String, dynamic>> collaborators;
  final List<String> editors;
  final List<String> viewers;
  final int createdAt;
  final int updatedAt;
  final List<String> searchKeywords;

  static List<String> generateKeywords({
    required String title,
    String? description,
    required List<String> tags,
    required String category,
    String? categoryDisplayName,
    required String userName,
    List<SearchIndexedItem> items = const [],
  }) {
    return SearchTokenizer.generateKeywords(
      title: title,
      description: description,
      tags: tags,
      category: category,
      categoryDisplayName: categoryDisplayName,
      userName: userName,
      items: items,
    );
  }

  CollectionEntity({
    required this.id,
    required this.userId,
    required String userName,
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
    this.savedAt = const {},
    this.inspiredBy,
    this.inspiredByUserId,
    this.userRole = UserRole.none,
    this.collaboratorCount = 0,
    this.collaborators = const [],
    this.editors = const [],
    this.viewers = const [],
    List<String>? searchKeywords,
    int? createdAt,
    int? updatedAt,
  })  : userName = UsernameUtils.normalize(userName),
        searchKeywords = searchKeywords ?? generateKeywords(
          title: title,
          description: description,
          tags: tags,
          category: category.name,
          categoryDisplayName: category.displayName,
          userName: UsernameUtils.normalize(userName),
        ),
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? createdAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Latest content change (items, title, description, cover, etc.).
  int get lastContentActivityAt =>
      updatedAt > 0 ? updatedAt : createdAt;

  /// Create from Firestore document
  factory CollectionEntity.fromMap(Map<String, dynamic> map, String docId) {
    final rawVisibility = (map['visibility'] as String?)?.toUpperCase();
    final isPublic = map['isPublic'] as bool? ?? true;
    final visibility = _visibilityFromFields(isPublic: isPublic, rawVisibility: rawVisibility);

    final rawCover = map['coverImageUrl'];
    final coverImageUrl = rawCover is String ? rawCover.trim() : null;

    final rawPreview = map['previewImageUrls'];
    final previewImageUrls = (rawPreview is List)
        ? rawPreview.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
        : const <String>[];

    return CollectionEntity(
      id: docId,
      userId: map['userId'] ?? '',
      userName: UsernameUtils.normalize(
        (map['userName'] ?? map['username'] ?? '').toString(),
      ),
      userAvatarUrl: map['userAvatarUrl'],
      title: map['title'] ?? '',
      description: map['description'],
      websiteUrl: map['websiteUrl'],
      googleMapsUrl: map['googleMapsUrl'],
      category: CategoryType.fromString(map['category']),
      tags: List<String>.from(map['tags'] ?? []),
      coverImageUrl: (coverImageUrl != null && coverImageUrl.isNotEmpty) ? coverImageUrl : null,
      previewImageUrls: previewImageUrls,
      visibility: visibility,
      isPublic: isPublic,
      itemCount: map['itemCount'] ?? 0,
      isOpenForContribution: map['isOpenForContribution'] ?? false,
      contributorCount: map['contributorCount'] ?? 0,
      contributorIds: List<String>.from(map['contributorIds'] ?? []),
      likes: map['likes'] ?? 0,
      likedBy: List<String>.from(map['likedBy'] ?? []),
      saveCount: map['saveCount'] ?? 0,
      savedAt: (map['savedAt'] is Map)
          ? Map<String, int>.from(
              (map['savedAt'] as Map).map(
                (k, v) => MapEntry(k.toString(), _timestampToInt(v)),
              ),
            )
          : const {},
      inspiredBy: map['inspiredBy'],
      inspiredByUserId: map['inspiredByUserId'],
      collaboratorCount: map['collaboratorCount'] ?? 0,
      savedBy: List<String>.from(map['savedBy'] ?? []),
      collaborators: (map['collaborators'] as List?)
              ?.whereType<Map>()
              .map((e) {
                final entry = Map<String, dynamic>.from(e);
                final username = entry['username'];
                if (username is String && username.isNotEmpty) {
                  entry['username'] = UsernameUtils.normalize(username);
                }
                return entry;
              })
              .toList() ??
          const [],
      editors: List<String>.from(map['editors'] ?? []),
      viewers: List<String>.from(map['viewers'] ?? []),
      searchKeywords: (map['searchKeywords'] != null && (map['searchKeywords'] as List).isNotEmpty)
          ? List<String>.from(map['searchKeywords'])
          : null,
      createdAt: _timestampToInt(map['createdAt']),
      updatedAt: map['updatedAt'] != null
          ? _timestampToInt(map['updatedAt'])
          : _timestampToInt(map['createdAt']),
    );
  }

  static CollectionVisibility _visibilityFromFields({
    required bool isPublic,
    String? rawVisibility,
  }) {
    if (rawVisibility == 'FOLLOWERS') return CollectionVisibility.followers;
    if (!isPublic || rawVisibility == 'PRIVATE') return CollectionVisibility.private;
    return CollectionVisibility.public;
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
      'savedAt': savedAt,
      'inspiredBy': inspiredBy,
      'inspiredByUserId': inspiredByUserId,
      'collaboratorCount': collaboratorCount,
      'collaborators': collaborators,
      'editors': editors,
      'viewers': viewers,
      'searchKeywords': searchKeywords,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
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
    Map<String, int>? savedAt,
    String? inspiredBy,
    String? inspiredByUserId,
    UserRole? userRole,
    int? collaboratorCount,
    List<Map<String, dynamic>>? collaborators,
    List<String>? editors,
    List<String>? viewers,
    List<String>? searchKeywords,
    int? createdAt,
    int? updatedAt,
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
      savedAt: savedAt ?? this.savedAt,
      inspiredBy: inspiredBy ?? this.inspiredBy,
      inspiredByUserId: inspiredByUserId ?? this.inspiredByUserId,
      userRole: userRole ?? this.userRole,
      collaboratorCount: collaboratorCount ?? this.collaboratorCount,
      collaborators: collaborators ?? this.collaborators,
      editors: editors ?? this.editors,
      viewers: viewers ?? this.viewers,
      searchKeywords: searchKeywords ?? generateKeywords(
        title: title ?? this.title,
        description: description ?? this.description,
        tags: tags ?? this.tags,
        category: (category ?? this.category).name,
        categoryDisplayName: (category ?? this.category).displayName,
        userName: userName ?? this.userName,
      ),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

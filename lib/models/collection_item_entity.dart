import 'package:cloud_firestore/cloud_firestore.dart';

/// Helper to convert Firestore Timestamp to int
int _timestampToInt(dynamic value) {
  if (value is Timestamp) {
    return value.millisecondsSinceEpoch;
  } else if (value is int) {
    return value;
  }
  return DateTime.now().millisecondsSinceEpoch;
}

/// Domain entity representing a collection item
class CollectionItemEntity {
  final String id;
  final String collectionId;
  final String userId;
  final String userName;
  final String title;
  final String? description;
  final double rating;
  final List<String> imageUrls;
  final String? googleMapsUrl;
  final String? websiteUrl;
  final int order;
  final int likes;
  final List<String> likedBy;
  final bool isLiked;
  final int createdAt;
  final int updatedAt;

  CollectionItemEntity({
    required this.id,
    required this.collectionId,
    required this.userId,
    required this.userName,
    required this.title,
    this.description,
    this.rating = 0.0,
    this.imageUrls = const [],
    this.googleMapsUrl,
    this.websiteUrl,
    this.order = 0,
    this.likes = 0,
    this.likedBy = const [],
    this.isLiked = false,
    int? createdAt,
    int? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch,
        updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  /// Create from Firestore document
  factory CollectionItemEntity.fromMap(Map<String, dynamic> map, String docId) {
    return CollectionItemEntity(
      id: docId,
      collectionId: map['collectionId'] ?? '',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      title: map['title'] ?? '',
      description: map['description'],
      rating: (map['rating'] ?? 0).toDouble(),
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      googleMapsUrl: map['googleMapsUrl'],
      websiteUrl: map['websiteUrl'],
      order: map['order'] ?? 0,
      likes: map['likes'] ?? 0,
      likedBy: List<String>.from(map['likedBy'] ?? []),
      createdAt: _timestampToInt(map['createdAt']),
      updatedAt: _timestampToInt(map['updatedAt']),
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toMap() {
    return {
      'collectionId': collectionId,
      'userId': userId,
      'userName': userName,
      'title': title,
      'description': description,
      'rating': rating,
      'imageUrls': imageUrls,
      'googleMapsUrl': googleMapsUrl,
      'websiteUrl': websiteUrl,
      'order': order,
      'likes': likes,
      'likedBy': likedBy,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  CollectionItemEntity copyWith({
    String? id,
    String? collectionId,
    String? userId,
    String? userName,
    String? title,
    String? description,
    double? rating,
    List<String>? imageUrls,
    String? googleMapsUrl,
    String? websiteUrl,
    int? order,
    int? likes,
    List<String>? likedBy,
    bool? isLiked,
    int? createdAt,
    int? updatedAt,
  }) {
    return CollectionItemEntity(
      id: id ?? this.id,
      collectionId: collectionId ?? this.collectionId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      title: title ?? this.title,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      imageUrls: imageUrls ?? this.imageUrls,
      googleMapsUrl: googleMapsUrl ?? this.googleMapsUrl,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      order: order ?? this.order,
      likes: likes ?? this.likes,
      likedBy: likedBy ?? this.likedBy,
      isLiked: isLiked ?? this.isLiked,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

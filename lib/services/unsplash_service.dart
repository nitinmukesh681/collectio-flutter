import 'dart:convert';
import 'package:http/http.dart' as http;

/// Model for Unsplash photo
class UnsplashPhoto {
  final String id;
  final String? description;
  final UnsplashUrls urls;
  final UnsplashUser user;

  UnsplashPhoto({
    required this.id,
    this.description,
    required this.urls,
    required this.user,
  });

  factory UnsplashPhoto.fromJson(Map<String, dynamic> json) {
    return UnsplashPhoto(
      id: json['id'] ?? '',
      description: json['description'] ?? json['alt_description'],
      urls: UnsplashUrls.fromJson(json['urls'] ?? {}),
      user: UnsplashUser.fromJson(json['user'] ?? {}),
    );
  }
}

class UnsplashUrls {
  final String raw;
  final String full;
  final String regular;
  final String small;
  final String thumb;

  UnsplashUrls({
    required this.raw,
    required this.full,
    required this.regular,
    required this.small,
    required this.thumb,
  });

  factory UnsplashUrls.fromJson(Map<String, dynamic> json) {
    return UnsplashUrls(
      raw: json['raw'] ?? '',
      full: json['full'] ?? '',
      regular: json['regular'] ?? '',
      small: json['small'] ?? '',
      thumb: json['thumb'] ?? '',
    );
  }
}

class UnsplashUser {
  final String name;
  final String username;

  UnsplashUser({
    required this.name,
    required this.username,
  });

  factory UnsplashUser.fromJson(Map<String, dynamic> json) {
    return UnsplashUser(
      name: json['name'] ?? '',
      username: json['username'] ?? '',
    );
  }
}

/// Service for Unsplash API
class UnsplashService {
  static const String _baseUrl = 'https://api.unsplash.com';
  static const String _accessKey = 'FTlu3tf9MRFZO5rgVjTkD63quKH8rXxwa7WeE4QNSyc';

  /// Search for photos
  Future<List<UnsplashPhoto>> searchPhotos(String query, {int page = 1, int perPage = 20}) async {
    if (query.isEmpty) return [];

    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/search/photos?query=$query&page=$page&per_page=$perPage'),
        headers: {
          'Authorization': 'Client-ID $_accessKey',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final results = data['results'] as List;
        return results.map((photo) => UnsplashPhoto.fromJson(photo)).toList();
      } else {
        throw Exception('Failed to search photos: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching Unsplash: $e');
    }
  }

  /// Get a random photo
  Future<UnsplashPhoto?> getRandomPhoto({String? query}) async {
    try {
      var url = '$_baseUrl/photos/random';
      if (query != null && query.isNotEmpty) {
        url += '?query=$query';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Client-ID $_accessKey',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return UnsplashPhoto.fromJson(data);
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import 'avatar_fallback.dart';

/// Displays a user profile photo with gs:// resolution.
/// Uses [avatarUrl] when provided; otherwise loads from Firestore via [userId].
/// When [trustProvidedAvatar] is true, [avatarUrl] is authoritative (null = no photo).
class UserAvatar extends StatefulWidget {
  final String name;
  final double size;
  final String? avatarUrl;
  final String? userId;
  final bool trustProvidedAvatar;

  const UserAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.avatarUrl,
    this.userId,
    this.trustProvidedAvatar = false,
  });

  static Future<String?> resolveAvatarUrl({
    String? avatarUrl,
    String? userId,
    bool trustProvidedAvatar = false,
  }) async {
    if (trustProvidedAvatar) {
      return _resolveRawAvatarUrl(avatarUrl?.trim());
    }

    var raw = avatarUrl?.trim();
    if (raw == null || raw.isEmpty) {
      if (userId != null && userId.isNotEmpty) {
        try {
          raw = (await FirestoreService().getUser(userId))?.avatarUrl?.trim();
        } catch (_) {
          raw = null;
        }
      }
    }
    return _resolveRawAvatarUrl(raw);
  }

  static Future<String?> _resolveRawAvatarUrl(String? raw) async {
    if (raw == null || raw.isEmpty) return null;

    if (raw.startsWith('gs://')) {
      try {
        return await FirebaseStorage.instance.refFromURL(raw).getDownloadURL();
      } catch (_) {
        return null;
      }
    }

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    return null;
  }

  @override
  State<UserAvatar> createState() => _UserAvatarState();
}

class _UserAvatarState extends State<UserAvatar> {
  late Future<String?> _urlFuture;

  void _refreshUrlFuture() {
    _urlFuture = UserAvatar.resolveAvatarUrl(
      avatarUrl: widget.avatarUrl,
      userId: widget.userId,
      trustProvidedAvatar: widget.trustProvidedAvatar,
    );
  }

  @override
  void initState() {
    super.initState();
    _refreshUrlFuture();
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl ||
        oldWidget.userId != widget.userId ||
        oldWidget.trustProvidedAvatar != widget.trustProvidedAvatar) {
      _refreshUrlFuture();
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = AvatarFallback(name: widget.name, size: widget.size);
    final cacheKey = widget.trustProvidedAvatar
        ? 'provided|${widget.avatarUrl ?? ''}'
        : '${widget.userId}|${widget.avatarUrl}';

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipOval(
        child: FutureBuilder<String?>(
          key: ValueKey(cacheKey),
          future: _urlFuture,
          builder: (context, snapshot) {
            final url = snapshot.data;
            if (url != null && url.isNotEmpty) {
              return CachedNetworkImage(
                key: ValueKey(url),
                imageUrl: url,
                cacheKey: url,
                fit: BoxFit.cover,
                width: widget.size,
                height: widget.size,
                fadeInDuration: Duration.zero,
                errorWidget: (_, __, ___) => fallback,
              );
            }
            return fallback;
          },
        ),
      ),
    );
  }
}

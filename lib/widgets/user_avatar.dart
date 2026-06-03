import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import 'avatar_fallback.dart';

/// Displays a user profile photo with gs:// resolution.
/// Uses [avatarUrl] when provided; otherwise loads from Firestore via [userId].
class UserAvatar extends StatefulWidget {
  final String name;
  final double size;
  final String? avatarUrl;
  final String? userId;

  const UserAvatar({
    super.key,
    required this.name,
    this.size = 44,
    this.avatarUrl,
    this.userId,
  });

  static Future<String?> resolveAvatarUrl({
    String? avatarUrl,
    String? userId,
  }) async {
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

  @override
  void initState() {
    super.initState();
    _urlFuture = UserAvatar.resolveAvatarUrl(
      avatarUrl: widget.avatarUrl,
      userId: widget.userId,
    );
  }

  @override
  void didUpdateWidget(UserAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarUrl != widget.avatarUrl || oldWidget.userId != widget.userId) {
      _urlFuture = UserAvatar.resolveAvatarUrl(
        avatarUrl: widget.avatarUrl,
        userId: widget.userId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallback = AvatarFallback(name: widget.name, size: widget.size);

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ClipOval(
        child: FutureBuilder<String?>(
          key: ValueKey('${widget.userId}|${widget.avatarUrl}'),
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

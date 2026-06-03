import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_entity.dart';
import '../providers/auth_provider.dart';
import '../services/firestore_service.dart';
import '../utils/avatar_display_utils.dart';
import 'avatar_fallback.dart';

/// Displays a user profile photo with gs:// resolution.
/// When [userId] is set, loads the canonical avatar from the user profile (not
/// denormalized collection/comment copies) unless [trustProvidedAvatar] is true.
/// For the signed-in user, always prefers the live profile URL from [AuthProvider].
class UserAvatar extends StatelessWidget {
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

    final uid = userId?.trim() ?? '';
    if (uid.isNotEmpty) {
      try {
        final live = (await FirestoreService().getUser(uid))?.avatarUrl?.trim();
        if (live != null && live.isNotEmpty) {
          return _resolveRawAvatarUrl(live);
        }
      } catch (_) {}
    }

    return _resolveRawAvatarUrl(avatarUrl?.trim());
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
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final uid = userId?.trim() ?? '';
    final isCurrentUser = uid.isNotEmpty && uid == auth.userId;

    final effectiveUrl = uid.isNotEmpty
        ? displayAvatarUrl(
            storedAvatarUrl: avatarUrl,
            subjectUserId: uid,
            currentUserId: auth.userId,
            currentUserAvatarUrl: auth.userEntity?.avatarUrl,
          )
        : avatarUrl;

    final trusted = trustProvidedAvatar || isCurrentUser;
    final fallback = AvatarFallback(name: name, size: size);

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: uid.isNotEmpty && !trusted
            ? StreamBuilder<UserEntity?>(
                stream: FirestoreService().getUserStream(uid),
                builder: (context, userSnap) {
                  final liveRaw = userSnap.data?.avatarUrl?.trim();
                  final raw = (liveRaw != null && liveRaw.isNotEmpty)
                      ? liveRaw
                      : effectiveUrl?.trim();
                  return _ResolvedAvatarImage(
                    rawAvatar: raw,
                    userId: uid,
                    size: size,
                    fallback: fallback,
                  );
                },
              )
            : _ResolvedAvatarImage(
                rawAvatar: effectiveUrl?.trim(),
                userId: uid.isEmpty ? null : uid,
                size: size,
                fallback: fallback,
                trustProvidedAvatar: trusted,
              ),
      ),
    );
  }
}

class _ResolvedAvatarImage extends StatelessWidget {
  final String? rawAvatar;
  final String? userId;
  final double size;
  final Widget fallback;
  final bool trustProvidedAvatar;

  const _ResolvedAvatarImage({
    required this.rawAvatar,
    required this.userId,
    required this.size,
    required this.fallback,
    this.trustProvidedAvatar = true,
  });

  @override
  Widget build(BuildContext context) {
    final uid = userId?.trim() ?? '';
    final futureKey = trustProvidedAvatar
        ? 'provided|${rawAvatar ?? ''}'
        : 'user|$uid|${rawAvatar ?? ''}';

    return FutureBuilder<String?>(
      key: ValueKey(futureKey),
      future: UserAvatar.resolveAvatarUrl(
        avatarUrl: rawAvatar,
        userId: uid.isEmpty ? null : uid,
        trustProvidedAvatar: trustProvidedAvatar,
      ),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url != null && url.isNotEmpty) {
          return CachedNetworkImage(
            key: ValueKey('img|$uid|$url'),
            imageUrl: url,
            cacheKey: avatarImageCacheKey(userId: uid.isEmpty ? null : uid, url: url),
            fit: BoxFit.cover,
            width: size,
            height: size,
            fadeInDuration: Duration.zero,
            errorWidget: (_, __, ___) => fallback,
          );
        }
        return fallback;
      },
    );
  }
}

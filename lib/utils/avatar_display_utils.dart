import 'package:cached_network_image/cached_network_image.dart';

/// Picks the avatar URL to show, preferring the signed-in user's live profile URL.
String? displayAvatarUrl({
  required String? storedAvatarUrl,
  required String subjectUserId,
  required String? currentUserId,
  required String? currentUserAvatarUrl,
}) {
  if (currentUserId != null &&
      currentUserId.isNotEmpty &&
      subjectUserId == currentUserId) {
    final live = currentUserAvatarUrl?.trim();
    if (live != null && live.isNotEmpty) return live;
  }
  final stored = storedAvatarUrl?.trim();
  return stored != null && stored.isNotEmpty ? stored : null;
}

/// Clears cached network images for avatar URLs (e.g. after profile photo change).
Future<void> evictAvatarImageCache({String? previousUrl, String? newUrl}) async {
  for (final url in {previousUrl?.trim(), newUrl?.trim()}) {
    if (url == null || url.isEmpty) continue;
    if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
    try {
      await CachedNetworkImage.evictFromCache(url);
    } catch (_) {
      // Best-effort cache bust.
    }
  }
}

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
    // Never use stale denormalized URLs on the signed-in user's own content.
    return null;
  }
  final stored = storedAvatarUrl?.trim();
  return stored != null && stored.isNotEmpty ? stored : null;
}

/// Clears cached network images for avatar URLs (e.g. after profile photo change).
Future<void> evictAvatarImageCache({String? previousUrl, String? newUrl}) async {
  final urls = <String>{};
  for (final raw in [previousUrl, newUrl]) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) continue;
    urls.add(trimmed);
    final base = trimmed.split('?').first;
    if (base.isNotEmpty) urls.add(base);
  }

  for (final url in urls) {
    if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
    try {
      await CachedNetworkImage.evictFromCache(url);
    } catch (_) {
      // Best-effort cache bust.
    }
  }
}

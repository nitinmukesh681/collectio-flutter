class LinkTitleUtils {
  LinkTitleUtils._();

  static String resolveItemTitle({
    String? sharedTitle,
    String? shareText,
    required String url,
  }) {
    if (sharedTitle != null && sharedTitle.trim().isNotEmpty) {
      return sharedTitle.trim();
    }

    try {
      final uri = Uri.parse(url);
      final host = uri.host.replaceAll('www.', '');
      if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.isNotEmpty) {
        final lastSegment = uri.pathSegments.last;
        // Turn segment-like-this into Segment Like This
        final name = lastSegment
            .split(RegExp(r'[-_]'))
            .map((e) => e.isNotEmpty ? '${e[0].toUpperCase()}${e.substring(1)}' : '')
            .join(' ');
        if (name.trim().isNotEmpty) {
          return name;
        }
      }
      return host;
    } catch (_) {
      return 'Shared Link';
    }
  }
}

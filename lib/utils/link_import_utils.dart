/// Helpers for parsing shared / imported link URLs.
class LinkImportUtils {
  LinkImportUtils._();

  static String? extractCollectionId(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      if (host == 'collectio-b6b15.web.app' ||
          host.endsWith('.collectio.app') ||
          host == 'collectio.app' ||
          host == 'localhost') {
        final pathSegments = uri.pathSegments;
        if (pathSegments.length >= 2 && pathSegments[0] == 'collection') {
          return pathSegments[1];
        }
      }
    } catch (_) {
      // Ignore malformed URLs.
    }
    return null;
  }
}

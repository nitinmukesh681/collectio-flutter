import 'package:firebase_storage/firebase_storage.dart';

/// Resolves Firebase Storage `gs://` URLs to HTTPS download URLs.
Future<String?> resolveStorageImageUrl(String? raw) async {
  final candidate = raw?.trim() ?? '';
  if (candidate.isEmpty) return null;

  if (candidate.startsWith('http://') || candidate.startsWith('https://')) {
    return candidate;
  }

  if (candidate.startsWith('gs://')) {
    try {
      return await FirebaseStorage.instance.refFromURL(candidate).getDownloadURL();
    } catch (_) {
      return null;
    }
  }

  return null;
}

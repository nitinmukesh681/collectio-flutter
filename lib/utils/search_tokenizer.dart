/// Searchable item fields denormalized onto a collection's keyword index.
class SearchIndexedItem {
  final String title;
  final String? description;

  const SearchIndexedItem({
    required this.title,
    this.description,
  });
}

/// Tokenization and keyword generation for lexical collection search.
class SearchTokenizer {
  static const int maxDescriptionWords = 40;
  static const int maxItemDescriptionWords = 12;
  static const int maxIndexedItems = 40;
  static const int maxKeywords = 800;
  static const int minTokenLength = 2;
  static const int maxPrefixLength = 24;

  static final RegExp _splitPattern = RegExp(
    r'[\s!@#\$%^&*()_\-+={[}\]|\\:;"<,>.?/~`\u2019\u201c\u201d]+',
  );
  static final RegExp _nonWordPattern = RegExp(r'[^\w]');

  /// Split [text] into normalized search tokens (words).
  static List<String> tokenize(String text) {
    if (text.trim().isEmpty) return const [];

    return text
        .toLowerCase()
        .trim()
        .split(_splitPattern)
        .map((token) => token.replaceAll(_nonWordPattern, ''))
        .where((token) => token.length >= minTokenLength)
        .toList();
  }

  /// Tokenize a user search query using the same rules as indexing.
  static List<String> tokenizeQuery(String query) => tokenize(query);

  /// Prefix tokens for partial / autocomplete matching.
  static Iterable<String> prefixTokens(String word) {
    final cleaned = word.toLowerCase().replaceAll(_nonWordPattern, '');
    if (cleaned.length < minTokenLength) return const [];

    final maxLen = cleaned.length.clamp(minTokenLength, maxPrefixLength);
    return [
      for (var i = minTokenLength; i <= maxLen; i++) cleaned.substring(0, i),
    ];
  }

  /// Build the Firestore `searchKeywords` array from searchable fields.
  static List<String> generateKeywords({
    required String title,
    String? description,
    required List<String> tags,
    String? category,
    String? categoryDisplayName,
    String? userName,
    List<SearchIndexedItem> items = const [],
  }) {
    final keywords = <String>{};

    void addFromText(String text, {int? maxWords}) {
      var tokens = tokenize(text);
      if (maxWords != null && tokens.length > maxWords) {
        tokens = tokens.sublist(0, maxWords);
      }
      for (final token in tokens) {
        keywords.add(token);
        keywords.addAll(prefixTokens(token));
      }
    }

    addFromText(title);

    if (description != null && description.isNotEmpty) {
      addFromText(description, maxWords: maxDescriptionWords);
    }

    for (final tag in tags) {
      addFromText(tag);
    }

    if (category != null && category.isNotEmpty) {
      addFromText(category);
    }

    if (categoryDisplayName != null && categoryDisplayName.isNotEmpty) {
      addFromText(categoryDisplayName);
    }

    for (final item in items.take(maxIndexedItems)) {
      addFromText(item.title);
      if (item.description != null && item.description!.isNotEmpty) {
        addFromText(item.description!, maxWords: maxItemDescriptionWords);
      }
    }

    if (userName != null && userName.isNotEmpty) {
      addFromText(userName);
    }

    final result = keywords.toList();
    if (result.length > maxKeywords) {
      return result.sublist(0, maxKeywords);
    }
    return result;
  }

  /// True when every query term matches at least one indexed keyword.
  static bool matchesAllTerms(
    List<String> indexedKeywords,
    List<String> queryTerms,
  ) {
    if (queryTerms.isEmpty) return false;

    return queryTerms.every(
      (term) => indexedKeywords.any((keyword) => keyword.startsWith(term)),
    );
  }

  /// Higher score = better match. Title > tags > items > description > category.
  static int relevanceScore({
    required List<String> queryTerms,
    required String title,
    String? description,
    required List<String> tags,
    String? category,
    String? categoryDisplayName,
    List<SearchIndexedItem> items = const [],
    required List<String> indexedKeywords,
  }) {
    if (queryTerms.isEmpty) return 0;

    final titleTokens = tokenize(title);
    final descriptionTokens =
        description != null ? tokenize(description) : const <String>[];
    final tagTokens = tags.expand(tokenize).toList();
    final categoryTokens = <String>{
      if (category != null) ...tokenize(category),
      if (categoryDisplayName != null) ...tokenize(categoryDisplayName),
    };
    final itemTokens = items
        .take(maxIndexedItems)
        .expand(
          (item) => [
            ...tokenize(item.title),
            if (item.description != null)
              ...tokenize(item.description!).take(maxItemDescriptionWords),
          ],
        )
        .toList();

    var score = 0;
    for (final term in queryTerms) {
      if (titleTokens.any((token) => token.startsWith(term))) {
        score += 20;
      }
      if (tagTokens.any((token) => token.startsWith(term))) {
        score += 12;
      }
      if (itemTokens.any((token) => token.startsWith(term))) {
        score += 10;
      }
      if (descriptionTokens.any((token) => token.startsWith(term))) {
        score += 6;
      }
      if (categoryTokens.any((token) => token.startsWith(term))) {
        score += 4;
      }
      if (indexedKeywords.any((keyword) => keyword.startsWith(term))) {
        score += 1;
      }
    }
    return score;
  }

  /// Detect stale or missing keyword indexes (e.g. after tokenizer changes).
  static bool needsReindex({
    required List<String> existingKeywords,
    required String title,
    String? description,
    required List<String> tags,
    String? category,
    String? categoryDisplayName,
    List<SearchIndexedItem> items = const [],
  }) {
    if (existingKeywords.isEmpty) return true;

    final expectedTokens = <String>{
      ...tokenize(title),
      if (description != null && description.isNotEmpty)
        ...tokenize(description).take(maxDescriptionWords),
      ...tags.expand(tokenize),
      if (category != null && category.isNotEmpty) ...tokenize(category),
      if (categoryDisplayName != null && categoryDisplayName.isNotEmpty)
        ...tokenize(categoryDisplayName),
      ...items.take(maxIndexedItems).expand(
            (item) => [
              ...tokenize(item.title),
              if (item.description != null && item.description!.isNotEmpty)
                ...tokenize(item.description!).take(maxItemDescriptionWords),
            ],
          ),
    };

    if (expectedTokens.isEmpty) return false;

    return expectedTokens.any((token) => !existingKeywords.contains(token));
  }
}

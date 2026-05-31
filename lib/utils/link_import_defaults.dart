import 'dart:math';

class LinkImportDefaults {
  LinkImportDefaults._();

  static final List<String> _descriptions = [
    'A curated resource worth saving.',
    'Saved to my collection for future reference.',
    'Thought-provoking content to revisit later.',
    'Interesting bookmark I discovered today.',
    'Adding this to my personal inspiration board.',
  ];

  static String randomDescription() {
    final random = Random();
    return _descriptions[random.nextInt(_descriptions.length)];
  }
}

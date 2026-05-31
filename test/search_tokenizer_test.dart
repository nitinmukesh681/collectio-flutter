import 'package:flutter_test/flutter_test.dart';
import 'package:collectio/utils/search_tokenizer.dart';

void main() {
  group('SearchTokenizer', () {
    test('tokenizes title, description, and tags consistently', () {
      expect(
        SearchTokenizer.tokenize('Best Coffee Shops!'),
        ['best', 'coffee', 'shops'],
      );
      expect(
        SearchTokenizer.tokenize('#travel-inspo'),
        ['travel', 'inspo'],
      );
      expect(
        SearchTokenizer.tokenizeQuery('  Coffee   SHOP  '),
        ['coffee', 'shop'],
      );
    });

    test('generateKeywords indexes searchable fields', () {
      final keywords = SearchTokenizer.generateKeywords(
        title: 'Hidden Cafes',
        description: 'Quiet spots for reading and espresso tasting downtown.',
        tags: ['coffee', '#cafes'],
        category: 'food',
        categoryDisplayName: 'Food',
        userName: 'alex',
      );

      expect(keywords, contains('hidden'));
      expect(keywords, contains('cafes'));
      expect(keywords, contains('espresso'));
      expect(keywords, contains('coffee'));
      expect(keywords, contains('food'));
      expect(keywords, contains('hid')); // prefix token
    });

    test('generateKeywords indexes collection items', () {
      final keywords = SearchTokenizer.generateKeywords(
        title: 'Weekend Picks',
        description: null,
        tags: const [],
        category: 'travel',
        categoryDisplayName: 'Travel',
        items: const [
          SearchIndexedItem(
            title: 'Blue Bottle Coffee',
            description: 'Great pour-over in Hayes Valley.',
          ),
        ],
      );

      expect(keywords, contains('blue'));
      expect(keywords, contains('bottle'));
      expect(keywords, contains('pour'));
      expect(keywords, contains('travel'));
    });

    test('matchesAllTerms requires every query token', () {
      const indexed = ['coffee', 'shop', 'caf', 'cafe', 'cafes'];
      expect(
        SearchTokenizer.matchesAllTerms(indexed, ['coffee', 'shop']),
        isTrue,
      );
      expect(
        SearchTokenizer.matchesAllTerms(indexed, ['coffee', 'bakery']),
        isFalse,
      );
      expect(
        SearchTokenizer.matchesAllTerms(indexed, ['caf']),
        isTrue,
      );
    });

    test('relevanceScore prefers title matches', () {
      final titleScore = SearchTokenizer.relevanceScore(
        queryTerms: ['coffee'],
        title: 'Coffee Guide',
        description: null,
        tags: const [],
        indexedKeywords: const ['coffee'],
      );
      final tagScore = SearchTokenizer.relevanceScore(
        queryTerms: ['coffee'],
        title: 'Weekend Plans',
        description: null,
        tags: const ['coffee'],
        indexedKeywords: const ['coffee'],
      );

      expect(titleScore, greaterThan(tagScore));
    });

    test('needsReindex detects missing category and item tokens', () {
      expect(
        SearchTokenizer.needsReindex(
          existingKeywords: const ['weekend', 'picks'],
          title: 'Weekend Picks',
          description: null,
          tags: const [],
          category: 'travel',
          categoryDisplayName: 'Travel',
        ),
        isTrue,
      );
      expect(
        SearchTokenizer.needsReindex(
          existingKeywords: const ['weekend', 'picks', 'blue', 'bottle', 'coffee'],
          title: 'Weekend Picks',
          description: null,
          tags: const [],
          items: const [
            SearchIndexedItem(title: 'Blue Bottle Coffee'),
          ],
        ),
        isFalse,
      );
    });
  });
}

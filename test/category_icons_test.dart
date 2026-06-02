import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:collectio/utils/category_icons.dart';
import 'package:collectio/utils/collection_cover_placeholder.dart';
import 'package:collectio/models/category_type.dart';

void main() {
  testWidgets('Phosphor fill primary category icon renders', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CategoryPhosphorIcon(
            category: CategoryType.travel,
            size: 24,
            color: Colors.white,
          ),
        ),
      ),
    );

    expect(find.byType(Icon), findsOneWidget);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon!.fontFamily, 'PhosphorFill');
    expect(icon.icon!.fontPackage, isNull);
  });

  testWidgets('collection cover placeholder uses Phosphor cover pool', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CollectionCoverPlaceholder(
            category: CategoryType.travel,
            seed: collectionCoverSeed(
              collectionId: 'melbourne-test-id',
              title: 'Test',
            ),
            gradientColors: const [Colors.blue, Colors.indigo],
          ),
        ),
      ),
    );

    expect(find.byType(Icon), findsOneWidget);
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.icon!.fontFamily, 'PhosphorFill');
    expect(icon.icon, categoryCoverIcon(
      CategoryType.travel,
      collectionCoverSeed(
        collectionId: 'melbourne-test-id',
        title: 'Test',
      ),
    ));
  });

  testWidgets('cover icon picker is stable for the same seed', (tester) async {
    const seed = collectionCoverSeed(
      collectionId: 'stable-collection-id',
      title: 'My Collection',
    );
    final first = categoryCoverIcon(CategoryType.food, seed);
    final second = categoryCoverIcon(CategoryType.food, seed);
    expect(first.codePoint, second.codePoint);
  });

  testWidgets('different titles pick different cover icons when possible', () {
    final melbourne = categoryCoverIcon(
      CategoryType.travel,
      collectionCoverSeed(
        collectionId: 'id-a',
        title: 'best places to visit in Melbourne',
      ),
    );
    final manali = categoryCoverIcon(
      CategoryType.travel,
      collectionCoverSeed(
        collectionId: 'id-b',
        title: 'Beauty of Manali',
      ),
    );
    expect(melbourne.codePoint, isNot(equals(manali.codePoint)));
  });
}

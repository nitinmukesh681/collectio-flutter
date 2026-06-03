import 'dart:io';

void main() {
  final content = File('lib/utils/category_icons.dart').readAsStringSync();
  final poolPattern = RegExp(
    r'final Map<CategoryType, List<IconData>> (_\w+) = \{([^;]+)\};',
    dotAll: true,
  );

  final iconToCategories = <String, Set<String>>{};

  for (final poolMatch in poolPattern.allMatches(content)) {
    final poolName = poolMatch.group(1)!;
    final poolBody = poolMatch.group(2)!;

    final categoryPattern = RegExp(
      r'CategoryType\.(\w+): \[([^\]]+)\]',
      dotAll: true,
    );

    for (final catMatch in categoryPattern.allMatches(poolBody)) {
      final cat = catMatch.group(1)!;
      final iconsBlock = catMatch.group(2)!;
      final iconPattern = RegExp(r'PhosphorIconsFill\.(\w+)');
      for (final iconMatch in iconPattern.allMatches(iconsBlock)) {
        final icon = iconMatch.group(1)!;
        iconToCategories.putIfAbsent(icon, () => {}).add('$poolName:$cat');
      }
    }
  }

  stdout.writeln('=== Cross-category duplicates (all pools) ===');
  var count = 0;
  final dupes = iconToCategories.entries.where((e) {
    final categories = e.value.map((v) => v.split(':').last).toSet();
    return categories.length > 1;
  }).toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));

  for (final e in dupes) {
    final categories = e.value.map((v) => v.split(':').last).toSet();
    stdout.writeln('${e.key}: ${categories.join(', ')}');
    count++;
  }
  stdout.writeln('Total cross-category dupes: $count');
}

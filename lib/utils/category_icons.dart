import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../models/category_type.dart';

/// App-bundled Phosphor Fill font (see pubspec.yaml).
const _phosphorFillFamily = 'PhosphorFill';

IconData _fillIcon(PhosphorIconData source) => IconData(
      source.codePoint,
      fontFamily: _phosphorFillFamily,
      matchTextDirection: true,
    );

/// Primary Phosphor fill icon per category (first item) — used for chips and headers.
final Map<CategoryType, List<IconData>> _primaryIconPools = {
  CategoryType.food: [
    _fillIcon(PhosphorIconsFill.coffee),
    _fillIcon(PhosphorIconsFill.forkKnife),
    _fillIcon(PhosphorIconsFill.cookingPot),
    _fillIcon(PhosphorIconsFill.bowlFood),
    _fillIcon(PhosphorIconsFill.pizza),
    _fillIcon(PhosphorIconsFill.cake),
    _fillIcon(PhosphorIconsFill.cookie),
  ],
  CategoryType.finance: [
    _fillIcon(PhosphorIconsFill.piggyBank),
    _fillIcon(PhosphorIconsFill.wallet),
    _fillIcon(PhosphorIconsFill.coins),
    _fillIcon(PhosphorIconsFill.currencyDollar),
    _fillIcon(PhosphorIconsFill.chartLineUp),
    _fillIcon(PhosphorIconsFill.bank),
  ],
  CategoryType.wellness: [
    _fillIcon(PhosphorIconsFill.flowerLotus),
    _fillIcon(PhosphorIconsFill.heart),
    _fillIcon(PhosphorIconsFill.leaf),
    _fillIcon(PhosphorIconsFill.sun),
    _fillIcon(PhosphorIconsFill.personSimpleRun),
    _fillIcon(PhosphorIconsFill.heartbeat),
  ],
  CategoryType.career: [
    _fillIcon(PhosphorIconsFill.briefcase),
    _fillIcon(PhosphorIconsFill.graduationCap),
    _fillIcon(PhosphorIconsFill.chalkboardTeacher),
    _fillIcon(PhosphorIconsFill.identificationBadge),
    _fillIcon(PhosphorIconsFill.chartLineUp),
    _fillIcon(PhosphorIconsFill.laptop),
  ],
  CategoryType.home: [
    _fillIcon(PhosphorIconsFill.house),
    _fillIcon(PhosphorIconsFill.armchair),
    _fillIcon(PhosphorIconsFill.lamp),
    _fillIcon(PhosphorIconsFill.plant),
    _fillIcon(PhosphorIconsFill.door),
    _fillIcon(PhosphorIconsFill.coatHanger),
  ],
  CategoryType.travel: [
    _fillIcon(PhosphorIconsFill.airplane),
    _fillIcon(PhosphorIconsFill.suitcase),
    _fillIcon(PhosphorIconsFill.mapPin),
    _fillIcon(PhosphorIconsFill.globeHemisphereWest),
    _fillIcon(PhosphorIconsFill.compass),
    _fillIcon(PhosphorIconsFill.camera),
  ],
  CategoryType.tech: [
    _fillIcon(PhosphorIconsFill.code),
    _fillIcon(PhosphorIconsFill.terminal),
    _fillIcon(PhosphorIconsFill.circuitry),
    _fillIcon(PhosphorIconsFill.cpu),
    _fillIcon(PhosphorIconsFill.robot),
    _fillIcon(PhosphorIconsFill.gearSix),
  ],
  CategoryType.gaming: [
    _fillIcon(PhosphorIconsFill.gameController),
    _fillIcon(PhosphorIconsFill.joystick),
    _fillIcon(PhosphorIconsFill.diceFive),
    _fillIcon(PhosphorIconsFill.trophy),
    _fillIcon(PhosphorIconsFill.target),
    _fillIcon(PhosphorIconsFill.puzzlePiece),
  ],
  CategoryType.entertainment: [
    _fillIcon(PhosphorIconsFill.filmStrip),
    _fillIcon(PhosphorIconsFill.popcorn),
    _fillIcon(PhosphorIconsFill.musicNotes),
    _fillIcon(PhosphorIconsFill.television),
    _fillIcon(PhosphorIconsFill.maskHappy),
    _fillIcon(PhosphorIconsFill.microphoneStage),
  ],
  CategoryType.shopping: [
    _fillIcon(PhosphorIconsFill.shoppingBag),
    _fillIcon(PhosphorIconsFill.storefront),
    _fillIcon(PhosphorIconsFill.tag),
    _fillIcon(PhosphorIconsFill.gift),
    _fillIcon(PhosphorIconsFill.basket),
    _fillIcon(PhosphorIconsFill.shoppingCart),
  ],
  CategoryType.style: [
    _fillIcon(PhosphorIconsFill.tShirt),
    _fillIcon(PhosphorIconsFill.highHeel),
    _fillIcon(PhosphorIconsFill.sparkle),
    _fillIcon(PhosphorIconsFill.sunglasses),
    _fillIcon(PhosphorIconsFill.coatHanger),
    _fillIcon(PhosphorIconsFill.handbag),
  ],
  CategoryType.books: [
    _fillIcon(PhosphorIconsFill.bookOpen),
    _fillIcon(PhosphorIconsFill.books),
    _fillIcon(PhosphorIconsFill.bookmark),
    _fillIcon(PhosphorIconsFill.notebook),
    _fillIcon(PhosphorIconsFill.scroll),
    _fillIcon(PhosphorIconsFill.quotes),
  ],
  CategoryType.growth: [
    _fillIcon(PhosphorIconsFill.plant),
    _fillIcon(PhosphorIconsFill.tree),
    _fillIcon(PhosphorIconsFill.lightbulb),
    _fillIcon(PhosphorIconsFill.rocket),
    _fillIcon(PhosphorIconsFill.chartLineUp),
    _fillIcon(PhosphorIconsFill.target),
  ],
  CategoryType.projects: [
    _fillIcon(PhosphorIconsFill.kanban),
    _fillIcon(PhosphorIconsFill.hardHat),
    _fillIcon(PhosphorIconsFill.blueprint),
    _fillIcon(PhosphorIconsFill.listChecks),
    _fillIcon(PhosphorIconsFill.clipboardText),
    _fillIcon(PhosphorIconsFill.folderOpen),
  ],
  CategoryType.creativity: [
    _fillIcon(PhosphorIconsFill.paintBrush),
    _fillIcon(PhosphorIconsFill.palette),
    _fillIcon(PhosphorIconsFill.penNib),
    _fillIcon(PhosphorIconsFill.scissors),
    _fillIcon(PhosphorIconsFill.sparkle),
    _fillIcon(PhosphorIconsFill.camera),
  ],
  CategoryType.sports: [
    _fillIcon(PhosphorIconsFill.cricket),
    _fillIcon(PhosphorIconsFill.trophy),
    _fillIcon(PhosphorIconsFill.medal),
    _fillIcon(PhosphorIconsFill.soccerBall),
    _fillIcon(PhosphorIconsFill.basketball),
    _fillIcon(PhosphorIconsFill.tennisBall),
  ],
  CategoryType.other: [
    _fillIcon(PhosphorIconsFill.star),
    _fillIcon(PhosphorIconsFill.sparkle),
    _fillIcon(PhosphorIconsFill.heart),
    _fillIcon(PhosphorIconsFill.compass),
    _fillIcon(PhosphorIconsFill.package),
    _fillIcon(PhosphorIconsFill.acorn),
  ],
};

/// Curated Phosphor fill icons for collection cover placeholders (highly category-relevant).
final Map<CategoryType, List<IconData>> _coverIconPools = {
  CategoryType.food: [
    _fillIcon(PhosphorIconsFill.forkKnife),
    _fillIcon(PhosphorIconsFill.cookingPot),
    _fillIcon(PhosphorIconsFill.bowlFood),
    _fillIcon(PhosphorIconsFill.pizza),
    _fillIcon(PhosphorIconsFill.cake),
    _fillIcon(PhosphorIconsFill.cookie),
    _fillIcon(PhosphorIconsFill.wine),
  ],
  CategoryType.finance: [
    _fillIcon(PhosphorIconsFill.wallet),
    _fillIcon(PhosphorIconsFill.coins),
    _fillIcon(PhosphorIconsFill.currencyDollar),
    _fillIcon(PhosphorIconsFill.piggyBank),
    _fillIcon(PhosphorIconsFill.bank),
    _fillIcon(PhosphorIconsFill.chartLineUp),
  ],
  CategoryType.wellness: [
    _fillIcon(PhosphorIconsFill.flowerLotus),
    _fillIcon(PhosphorIconsFill.heartbeat),
    _fillIcon(PhosphorIconsFill.personSimpleRun),
    _fillIcon(PhosphorIconsFill.leaf),
    _fillIcon(PhosphorIconsFill.sun),
    _fillIcon(PhosphorIconsFill.barbell),
  ],
  CategoryType.career: [
    _fillIcon(PhosphorIconsFill.graduationCap),
    _fillIcon(PhosphorIconsFill.chalkboardTeacher),
    _fillIcon(PhosphorIconsFill.identificationBadge),
    _fillIcon(PhosphorIconsFill.laptop),
    _fillIcon(PhosphorIconsFill.chartLineUp),
    _fillIcon(PhosphorIconsFill.briefcase),
  ],
  CategoryType.home: [
    _fillIcon(PhosphorIconsFill.armchair),
    _fillIcon(PhosphorIconsFill.lamp),
    _fillIcon(PhosphorIconsFill.plant),
    _fillIcon(PhosphorIconsFill.door),
    _fillIcon(PhosphorIconsFill.coatHanger),
    _fillIcon(PhosphorIconsFill.house),
  ],
  CategoryType.travel: [
    _fillIcon(PhosphorIconsFill.suitcaseRolling),
    _fillIcon(PhosphorIconsFill.mapPin),
    _fillIcon(PhosphorIconsFill.globeHemisphereWest),
    _fillIcon(PhosphorIconsFill.compass),
    _fillIcon(PhosphorIconsFill.mountains),
    _fillIcon(PhosphorIconsFill.backpack),
    _fillIcon(PhosphorIconsFill.binoculars),
    _fillIcon(PhosphorIconsFill.ticket),
    _fillIcon(PhosphorIconsFill.airplaneTakeoff),
  ],
  CategoryType.tech: [
    _fillIcon(PhosphorIconsFill.terminal),
    _fillIcon(PhosphorIconsFill.circuitry),
    _fillIcon(PhosphorIconsFill.cpu),
    _fillIcon(PhosphorIconsFill.robot),
    _fillIcon(PhosphorIconsFill.deviceMobile),
    _fillIcon(PhosphorIconsFill.gearSix),
  ],
  CategoryType.gaming: [
    _fillIcon(PhosphorIconsFill.joystick),
    _fillIcon(PhosphorIconsFill.diceFive),
    _fillIcon(PhosphorIconsFill.trophy),
    _fillIcon(PhosphorIconsFill.gameController),
    _fillIcon(PhosphorIconsFill.puzzlePiece),
  ],
  CategoryType.entertainment: [
    _fillIcon(PhosphorIconsFill.popcorn),
    _fillIcon(PhosphorIconsFill.musicNotes),
    _fillIcon(PhosphorIconsFill.television),
    _fillIcon(PhosphorIconsFill.filmStrip),
    _fillIcon(PhosphorIconsFill.maskHappy),
    _fillIcon(PhosphorIconsFill.microphoneStage),
  ],
  CategoryType.shopping: [
    _fillIcon(PhosphorIconsFill.storefront),
    _fillIcon(PhosphorIconsFill.tag),
    _fillIcon(PhosphorIconsFill.gift),
    _fillIcon(PhosphorIconsFill.basket),
    _fillIcon(PhosphorIconsFill.shoppingCart),
    _fillIcon(PhosphorIconsFill.shoppingBag),
  ],
  CategoryType.style: [
    _fillIcon(PhosphorIconsFill.highHeel),
    _fillIcon(PhosphorIconsFill.sunglasses),
    _fillIcon(PhosphorIconsFill.handbag),
    _fillIcon(PhosphorIconsFill.coatHanger),
    _fillIcon(PhosphorIconsFill.sparkle),
    _fillIcon(PhosphorIconsFill.tShirt),
  ],
  CategoryType.books: [
    _fillIcon(PhosphorIconsFill.books),
    _fillIcon(PhosphorIconsFill.bookmark),
    _fillIcon(PhosphorIconsFill.notebook),
    _fillIcon(PhosphorIconsFill.scroll),
    _fillIcon(PhosphorIconsFill.quotes),
    _fillIcon(PhosphorIconsFill.bookOpen),
  ],
  CategoryType.growth: [
    _fillIcon(PhosphorIconsFill.tree),
    _fillIcon(PhosphorIconsFill.lightbulb),
    _fillIcon(PhosphorIconsFill.rocket),
    _fillIcon(PhosphorIconsFill.chartLineUp),
    _fillIcon(PhosphorIconsFill.target),
    _fillIcon(PhosphorIconsFill.plant),
  ],
  CategoryType.projects: [
    _fillIcon(PhosphorIconsFill.hardHat),
    _fillIcon(PhosphorIconsFill.blueprint),
    _fillIcon(PhosphorIconsFill.listChecks),
    _fillIcon(PhosphorIconsFill.clipboardText),
    _fillIcon(PhosphorIconsFill.folderOpen),
    _fillIcon(PhosphorIconsFill.kanban),
  ],
  CategoryType.creativity: [
    _fillIcon(PhosphorIconsFill.palette),
    _fillIcon(PhosphorIconsFill.penNib),
    _fillIcon(PhosphorIconsFill.scissors),
    _fillIcon(PhosphorIconsFill.paintBrush),
    _fillIcon(PhosphorIconsFill.sparkle),
    _fillIcon(PhosphorIconsFill.camera),
  ],
  CategoryType.sports: [
    _fillIcon(PhosphorIconsFill.baseball),
    _fillIcon(PhosphorIconsFill.trophy),
    _fillIcon(PhosphorIconsFill.medal),
    _fillIcon(PhosphorIconsFill.soccerBall),
    _fillIcon(PhosphorIconsFill.basketball),
    _fillIcon(PhosphorIconsFill.tennisBall),
  ],
  CategoryType.other: [
    _fillIcon(PhosphorIconsFill.sparkle),
    _fillIcon(PhosphorIconsFill.heart),
    _fillIcon(PhosphorIconsFill.compass),
    _fillIcon(PhosphorIconsFill.package),
    _fillIcon(PhosphorIconsFill.star),
    _fillIcon(PhosphorIconsFill.acorn),
  ],
};

List<IconData> _poolFor(CategoryType category) =>
    _primaryIconPools[category] ?? _primaryIconPools[CategoryType.other]!;

List<IconData> _coverPoolFor(CategoryType category) =>
    _coverIconPools[category] ?? _coverIconPools[CategoryType.other]!;

/// Stable seed so different collections in the same category get different icons.
String collectionCoverSeed({
  required String collectionId,
  String? title,
}) {
  final normalizedTitle = title?.trim() ?? '';
  if (normalizedTitle.isEmpty) return collectionId;
  return '$collectionId|$normalizedTitle';
}

int _coverPoolIndex(String seed, int poolLength, CategoryType category) {
  var hash = category.index + 1;
  for (final unit in seed.codeUnits) {
    hash = (hash * 33) ^ unit;
    hash &= 0x7fffffff;
  }
  return hash % poolLength;
}

/// Picks a stable cover icon from the Phosphor pool based on collection id/title.
IconData categoryCoverIcon(CategoryType category, String seed) {
  final pool = _coverPoolFor(category);
  final index = _coverPoolIndex(seed, pool.length, category);
  return pool[index];
}

/// Representative Phosphor fill icon for category chips and navigation headers.
IconData categoryIcon(CategoryType category) => _poolFor(category).first;

/// Renders a Phosphor fill icon for category chips or cover placeholders.
class CategoryPhosphorIcon extends StatelessWidget {
  const CategoryPhosphorIcon({
    super.key,
    required this.category,
    this.seed,
    this.size = 24,
    this.color,
  });

  final CategoryType category;
  final String? seed;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final icon = seed != null
        ? categoryCoverIcon(category, seed!)
        : categoryIcon(category);
    return Icon(icon, size: size, color: color);
  }
}

/// Fire icon used for trending lists.
IconData get trendingCoverIcon => _fillIcon(PhosphorIconsFill.fire);

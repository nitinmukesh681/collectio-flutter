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
  CategoryType.fitness: [
    _fillIcon(PhosphorIconsFill.barbell),
    _fillIcon(PhosphorIconsFill.personSimpleRun),
    _fillIcon(PhosphorIconsFill.heartbeat),
    _fillIcon(PhosphorIconsFill.bicycle),
    _fillIcon(PhosphorIconsFill.personSimpleTaiChi),
    _fillIcon(PhosphorIconsFill.sneaker),
  ],
  CategoryType.career: [
    _fillIcon(PhosphorIconsFill.briefcase),
    _fillIcon(PhosphorIconsFill.certificate),
    _fillIcon(PhosphorIconsFill.newspaper),
    _fillIcon(PhosphorIconsFill.identificationBadge),
    _fillIcon(PhosphorIconsFill.presentationChart),
    _fillIcon(PhosphorIconsFill.laptop),
  ],
  CategoryType.home: [
    _fillIcon(PhosphorIconsFill.house),
    _fillIcon(PhosphorIconsFill.armchair),
    _fillIcon(PhosphorIconsFill.lamp),
    _fillIcon(PhosphorIconsFill.plant),
    _fillIcon(PhosphorIconsFill.door),
    _fillIcon(PhosphorIconsFill.bed),
  ],
  CategoryType.travel: [
    _fillIcon(PhosphorIconsFill.airplane),
    _fillIcon(PhosphorIconsFill.suitcase),
    _fillIcon(PhosphorIconsFill.mapPin),
    _fillIcon(PhosphorIconsFill.globeHemisphereWest),
    _fillIcon(PhosphorIconsFill.compass),
    _fillIcon(PhosphorIconsFill.train),
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
    _fillIcon(PhosphorIconsFill.ranking),
    _fillIcon(PhosphorIconsFill.target),
    _fillIcon(PhosphorIconsFill.puzzlePiece),
  ],
  CategoryType.entertainment: [
    _fillIcon(PhosphorIconsFill.filmStrip),
    _fillIcon(PhosphorIconsFill.popcorn),
    _fillIcon(PhosphorIconsFill.television),
    _fillIcon(PhosphorIconsFill.maskHappy),
    _fillIcon(PhosphorIconsFill.microphoneStage),
    _fillIcon(PhosphorIconsFill.ticket),
  ],
  CategoryType.shopping: [
    _fillIcon(PhosphorIconsFill.shoppingBag),
    _fillIcon(PhosphorIconsFill.storefront),
    _fillIcon(PhosphorIconsFill.tag),
    _fillIcon(PhosphorIconsFill.basket),
    _fillIcon(PhosphorIconsFill.shoppingCart),
    _fillIcon(PhosphorIconsFill.receipt),
  ],
  CategoryType.fashion: [
    _fillIcon(PhosphorIconsFill.tShirt),
    _fillIcon(PhosphorIconsFill.highHeel),
    _fillIcon(PhosphorIconsFill.crownSimple),
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
  CategoryType.diy: [
    _fillIcon(PhosphorIconsFill.hammer),
    _fillIcon(PhosphorIconsFill.wrench),
    _fillIcon(PhosphorIconsFill.screwdriver),
    _fillIcon(PhosphorIconsFill.toolbox),
    _fillIcon(PhosphorIconsFill.paintRoller),
    _fillIcon(PhosphorIconsFill.hardHat),
  ],
  CategoryType.creativity: [
    _fillIcon(PhosphorIconsFill.paintBrush),
    _fillIcon(PhosphorIconsFill.palette),
    _fillIcon(PhosphorIconsFill.penNib),
    _fillIcon(PhosphorIconsFill.scissors),
    _fillIcon(PhosphorIconsFill.swatches),
    _fillIcon(PhosphorIconsFill.filmSlate),
  ],
  CategoryType.sports: [
    _fillIcon(PhosphorIconsFill.cricket),
    _fillIcon(PhosphorIconsFill.trophy),
    _fillIcon(PhosphorIconsFill.medal),
    _fillIcon(PhosphorIconsFill.soccerBall),
    _fillIcon(PhosphorIconsFill.basketball),
    _fillIcon(PhosphorIconsFill.tennisBall),
  ],
  CategoryType.beauty: [
    _fillIcon(PhosphorIconsFill.sparkle),
    _fillIcon(PhosphorIconsFill.eyeglasses),
    _fillIcon(PhosphorIconsFill.drop),
    _fillIcon(PhosphorIconsFill.flower),
    _fillIcon(PhosphorIconsFill.flowerTulip),
    _fillIcon(PhosphorIconsFill.heartStraight),
  ],
  CategoryType.learning: [
    _fillIcon(PhosphorIconsFill.graduationCap),
    _fillIcon(PhosphorIconsFill.brain),
    _fillIcon(PhosphorIconsFill.student),
    _fillIcon(PhosphorIconsFill.chalkboardTeacher),
    _fillIcon(PhosphorIconsFill.exam),
    _fillIcon(PhosphorIconsFill.lightbulb),
  ],
  CategoryType.business: [
    _fillIcon(PhosphorIconsFill.briefcaseMetal),
    _fillIcon(PhosphorIconsFill.buildings),
    _fillIcon(PhosphorIconsFill.chartBar),
    _fillIcon(PhosphorIconsFill.handshake),
    _fillIcon(PhosphorIconsFill.money),
    _fillIcon(PhosphorIconsFill.desktopTower),
  ],
  CategoryType.events: [
    _fillIcon(PhosphorIconsFill.confetti),
    _fillIcon(PhosphorIconsFill.calendar),
    _fillIcon(PhosphorIconsFill.megaphone),
    _fillIcon(PhosphorIconsFill.champagne),
    _fillIcon(PhosphorIconsFill.balloon),
    _fillIcon(PhosphorIconsFill.calendarStar),
  ],
  CategoryType.pets: [
    _fillIcon(PhosphorIconsFill.pawPrint),
    _fillIcon(PhosphorIconsFill.dog),
    _fillIcon(PhosphorIconsFill.cat),
    _fillIcon(PhosphorIconsFill.fish),
    _fillIcon(PhosphorIconsFill.bird),
    _fillIcon(PhosphorIconsFill.rabbit),
  ],
  CategoryType.gifting: [
    _fillIcon(PhosphorIconsFill.gift),
    _fillIcon(PhosphorIconsFill.handHeart),
    _fillIcon(PhosphorIconsFill.heart),
    _fillIcon(PhosphorIconsFill.package),
    _fillIcon(PhosphorIconsFill.stamp),
    _fillIcon(PhosphorIconsFill.envelope),
  ],
  CategoryType.music: [
    _fillIcon(PhosphorIconsFill.musicNotes),
    _fillIcon(PhosphorIconsFill.guitar),
    _fillIcon(PhosphorIconsFill.headphones),
    _fillIcon(PhosphorIconsFill.microphone),
    _fillIcon(PhosphorIconsFill.speakerHigh),
    _fillIcon(PhosphorIconsFill.pianoKeys),
  ],
  CategoryType.photography: [
    _fillIcon(PhosphorIconsFill.camera),
    _fillIcon(PhosphorIconsFill.aperture),
    _fillIcon(PhosphorIconsFill.image),
    _fillIcon(PhosphorIconsFill.cameraRotate),
    _fillIcon(PhosphorIconsFill.images),
    _fillIcon(PhosphorIconsFill.frameCorners),
  ],
  CategoryType.spirituality: [
    _fillIcon(PhosphorIconsFill.handsPraying),
    _fillIcon(PhosphorIconsFill.yinYang),
    _fillIcon(PhosphorIconsFill.moonStars),
    _fillIcon(PhosphorIconsFill.flowerLotus),
    _fillIcon(PhosphorIconsFill.peace),
    _fillIcon(PhosphorIconsFill.star),
  ],
  CategoryType.random: [
    _fillIcon(PhosphorIconsFill.shuffle),
    _fillIcon(PhosphorIconsFill.shuffleAngular),
    _fillIcon(PhosphorIconsFill.asterisk),
    _fillIcon(PhosphorIconsFill.question),
    _fillIcon(PhosphorIconsFill.sealQuestion),
    _fillIcon(PhosphorIconsFill.magicWand),
  ],
  CategoryType.other: [
    _fillIcon(PhosphorIconsFill.bookmarkSimple),
    _fillIcon(PhosphorIconsFill.circleDashed),
    _fillIcon(PhosphorIconsFill.leaf),
    _fillIcon(PhosphorIconsFill.archive),
    _fillIcon(PhosphorIconsFill.folderOpen),
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
  CategoryType.fitness: [
    _fillIcon(PhosphorIconsFill.barbell),
    _fillIcon(PhosphorIconsFill.personSimpleRun),
    _fillIcon(PhosphorIconsFill.heartbeat),
    _fillIcon(PhosphorIconsFill.bicycle),
    _fillIcon(PhosphorIconsFill.sneaker),
    _fillIcon(PhosphorIconsFill.personSimpleTaiChi),
  ],
  CategoryType.career: [
    _fillIcon(PhosphorIconsFill.briefcase),
    _fillIcon(PhosphorIconsFill.certificate),
    _fillIcon(PhosphorIconsFill.newspaper),
    _fillIcon(PhosphorIconsFill.identificationBadge),
    _fillIcon(PhosphorIconsFill.presentationChart),
    _fillIcon(PhosphorIconsFill.laptop),
  ],
  CategoryType.home: [
    _fillIcon(PhosphorIconsFill.armchair),
    _fillIcon(PhosphorIconsFill.lamp),
    _fillIcon(PhosphorIconsFill.plant),
    _fillIcon(PhosphorIconsFill.door),
    _fillIcon(PhosphorIconsFill.bed),
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
    _fillIcon(PhosphorIconsFill.mapTrifold),
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
    _fillIcon(PhosphorIconsFill.ranking),
    _fillIcon(PhosphorIconsFill.gameController),
    _fillIcon(PhosphorIconsFill.puzzlePiece),
  ],
  CategoryType.entertainment: [
    _fillIcon(PhosphorIconsFill.popcorn),
    _fillIcon(PhosphorIconsFill.television),
    _fillIcon(PhosphorIconsFill.filmStrip),
    _fillIcon(PhosphorIconsFill.maskHappy),
    _fillIcon(PhosphorIconsFill.microphoneStage),
    _fillIcon(PhosphorIconsFill.ticket),
  ],
  CategoryType.shopping: [
    _fillIcon(PhosphorIconsFill.storefront),
    _fillIcon(PhosphorIconsFill.tag),
    _fillIcon(PhosphorIconsFill.basket),
    _fillIcon(PhosphorIconsFill.shoppingCart),
    _fillIcon(PhosphorIconsFill.shoppingBag),
    _fillIcon(PhosphorIconsFill.receipt),
  ],
  CategoryType.fashion: [
    _fillIcon(PhosphorIconsFill.highHeel),
    _fillIcon(PhosphorIconsFill.sunglasses),
    _fillIcon(PhosphorIconsFill.handbag),
    _fillIcon(PhosphorIconsFill.coatHanger),
    _fillIcon(PhosphorIconsFill.crownSimple),
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
  CategoryType.diy: [
    _fillIcon(PhosphorIconsFill.hardHat),
    _fillIcon(PhosphorIconsFill.wrench),
    _fillIcon(PhosphorIconsFill.screwdriver),
    _fillIcon(PhosphorIconsFill.toolbox),
    _fillIcon(PhosphorIconsFill.paintRoller),
    _fillIcon(PhosphorIconsFill.hammer),
  ],
  CategoryType.creativity: [
    _fillIcon(PhosphorIconsFill.palette),
    _fillIcon(PhosphorIconsFill.penNib),
    _fillIcon(PhosphorIconsFill.scissors),
    _fillIcon(PhosphorIconsFill.paintBrush),
    _fillIcon(PhosphorIconsFill.swatches),
    _fillIcon(PhosphorIconsFill.filmSlate),
  ],
  CategoryType.sports: [
    _fillIcon(PhosphorIconsFill.baseball),
    _fillIcon(PhosphorIconsFill.trophy),
    _fillIcon(PhosphorIconsFill.medal),
    _fillIcon(PhosphorIconsFill.soccerBall),
    _fillIcon(PhosphorIconsFill.basketball),
    _fillIcon(PhosphorIconsFill.tennisBall),
  ],
  CategoryType.beauty: [
    _fillIcon(PhosphorIconsFill.eyeglasses),
    _fillIcon(PhosphorIconsFill.drop),
    _fillIcon(PhosphorIconsFill.flower),
    _fillIcon(PhosphorIconsFill.flowerTulip),
    _fillIcon(PhosphorIconsFill.sparkle),
    _fillIcon(PhosphorIconsFill.heartStraight),
  ],
  CategoryType.learning: [
    _fillIcon(PhosphorIconsFill.student),
    _fillIcon(PhosphorIconsFill.chalkboardTeacher),
    _fillIcon(PhosphorIconsFill.exam),
    _fillIcon(PhosphorIconsFill.lightbulb),
    _fillIcon(PhosphorIconsFill.brain),
    _fillIcon(PhosphorIconsFill.graduationCap),
  ],
  CategoryType.business: [
    _fillIcon(PhosphorIconsFill.buildings),
    _fillIcon(PhosphorIconsFill.handshake),
    _fillIcon(PhosphorIconsFill.chartBar),
    _fillIcon(PhosphorIconsFill.invoice),
    _fillIcon(PhosphorIconsFill.desktopTower),
    _fillIcon(PhosphorIconsFill.money),
  ],
  CategoryType.events: [
    _fillIcon(PhosphorIconsFill.calendar),
    _fillIcon(PhosphorIconsFill.megaphone),
    _fillIcon(PhosphorIconsFill.champagne),
    _fillIcon(PhosphorIconsFill.balloon),
    _fillIcon(PhosphorIconsFill.calendarStar),
    _fillIcon(PhosphorIconsFill.confetti),
  ],
  CategoryType.pets: [
    _fillIcon(PhosphorIconsFill.dog),
    _fillIcon(PhosphorIconsFill.cat),
    _fillIcon(PhosphorIconsFill.fish),
    _fillIcon(PhosphorIconsFill.bird),
    _fillIcon(PhosphorIconsFill.rabbit),
    _fillIcon(PhosphorIconsFill.pawPrint),
  ],
  CategoryType.gifting: [
    _fillIcon(PhosphorIconsFill.handHeart),
    _fillIcon(PhosphorIconsFill.heart),
    _fillIcon(PhosphorIconsFill.package),
    _fillIcon(PhosphorIconsFill.stamp),
    _fillIcon(PhosphorIconsFill.envelope),
    _fillIcon(PhosphorIconsFill.gift),
  ],
  CategoryType.music: [
    _fillIcon(PhosphorIconsFill.guitar),
    _fillIcon(PhosphorIconsFill.headphones),
    _fillIcon(PhosphorIconsFill.microphone),
    _fillIcon(PhosphorIconsFill.speakerHigh),
    _fillIcon(PhosphorIconsFill.pianoKeys),
    _fillIcon(PhosphorIconsFill.musicNotes),
  ],
  CategoryType.photography: [
    _fillIcon(PhosphorIconsFill.aperture),
    _fillIcon(PhosphorIconsFill.image),
    _fillIcon(PhosphorIconsFill.cameraRotate),
    _fillIcon(PhosphorIconsFill.images),
    _fillIcon(PhosphorIconsFill.frameCorners),
    _fillIcon(PhosphorIconsFill.camera),
  ],
  CategoryType.spirituality: [
    _fillIcon(PhosphorIconsFill.yinYang),
    _fillIcon(PhosphorIconsFill.moonStars),
    _fillIcon(PhosphorIconsFill.flowerLotus),
    _fillIcon(PhosphorIconsFill.peace),
    _fillIcon(PhosphorIconsFill.star),
    _fillIcon(PhosphorIconsFill.handsPraying),
  ],
  CategoryType.random: [
    _fillIcon(PhosphorIconsFill.shuffleAngular),
    _fillIcon(PhosphorIconsFill.asterisk),
    _fillIcon(PhosphorIconsFill.question),
    _fillIcon(PhosphorIconsFill.sealQuestion),
    _fillIcon(PhosphorIconsFill.magicWand),
    _fillIcon(PhosphorIconsFill.shuffle),
  ],
  CategoryType.other: [
    _fillIcon(PhosphorIconsFill.bookmarkSimple),
    _fillIcon(PhosphorIconsFill.leaf),
    _fillIcon(PhosphorIconsFill.archive),
    _fillIcon(PhosphorIconsFill.folderOpen),
    _fillIcon(PhosphorIconsFill.circleDashed),
    _fillIcon(PhosphorIconsFill.acorn),
  ],
};

List<IconData> _poolFor(CategoryType category) =>
    _primaryIconPools[category] ?? _primaryIconPools[CategoryType.other]!;

List<IconData> _coverPoolFor(CategoryType category) =>
    _coverIconPools[category] ?? _coverIconPools[CategoryType.other]!;

/// Returns icon code points that appear in more than one [CategoryType].
Set<int> findCrossCategoryIconCodePointDuplicates() {
  final iconToCategories = <int, Set<CategoryType>>{};
  for (final pool in [_primaryIconPools, _coverIconPools]) {
    for (final entry in pool.entries) {
      for (final icon in entry.value) {
        iconToCategories.putIfAbsent(icon.codePoint, () => {}).add(entry.key);
      }
    }
  }
  return iconToCategories.entries
      .where((entry) => entry.value.length > 1)
      .map((entry) => entry.key)
      .toSet();
}

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

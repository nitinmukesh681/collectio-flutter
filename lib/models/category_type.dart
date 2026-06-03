/// Available categories for collections
enum CategoryType {
  food('Food', '🍕'),
  finance('Finance', '💰'),
  fitness('Fitness', '💪'),
  career('Career', '🧑‍💼'),
  home('Home', '🏠'),
  travel('Travel', '✈️'),
  tech('Tech', '💻'),
  gaming('Gaming', '🎮'),
  entertainment('Entertainment', '🎬'),
  shopping('Shopping', '🛍️'),
  fashion('Fashion', '👗'),
  books('Books', '📚'),
  diy('DIY', '🛠️'),
  creativity('Creativity', '🎨'),
  sports('Sports', '🏅'),
  beauty('Beauty', '💄'),
  learning('Learning', '📖'),
  business('Business', '💼'),
  events('Events', '🎉'),
  pets('Pets', '🐾'),
  gifting('Gifting', '🎁'),
  music('Music', '🎵'),
  photography('Photography', '📷'),
  spirituality('Spirituality', '🕯️'),
  random('Random', '🎲'),
  other('Others', '⭐');

  final String displayName;
  final String emoji;

  const CategoryType(this.displayName, this.emoji);

  static const _legacyNames = <String, CategoryType>{
    'wellness': CategoryType.fitness,
    'style': CategoryType.fashion,
    'projects': CategoryType.diy,
    'growth': CategoryType.other,
  };

  static CategoryType fromString(String? value) {
    if (value == null || value.isEmpty) return CategoryType.other;
    final v = value.trim().toLowerCase();
    final legacy = _legacyNames[v];
    if (legacy != null) return legacy;
    return CategoryType.values.firstWhere(
      (e) => e.name == v,
      orElse: () => CategoryType.other,
    );
  }
}

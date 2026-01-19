/// Available categories for collections
enum CategoryType {
  food('Food', '🍕'),
  finance('Finance', '💰'),
  wellness('Wellness', '🧘'),
  career('Career', '🧑‍💼'),
  home('Home', '🏠'),
  travel('Travel', '✈️'),
  tech('Tech', '💻'),
  gaming('Gaming', '🎮'),
  entertainment('Entertainment', '🎬'),
  shopping('Shopping', '🛍️'),
  style('Style', '✨'),
  books('Books', '📚'),
  growth('Growth', '🌱'),
  projects('Projects', '🛠️'),
  creativity('Creativity', '🎨'),
  sports('Sports', '🏅'),
  other('Other', '⭐');

  final String displayName;
  final String emoji;

  const CategoryType(this.displayName, this.emoji);

  static CategoryType fromString(String? value) {
    if (value == null || value.isEmpty) return CategoryType.other;
    final v = value.trim().toLowerCase();
    return CategoryType.values.firstWhere(
      (e) => e.name == v,
      orElse: () => CategoryType.other,
    );
  }
}

class SuggestionReward {
  final String suggestionId;
  final String name;
  final int xp;

  const SuggestionReward({
    required this.suggestionId,
    required this.name,
    required this.xp,
  });

  factory SuggestionReward.fromMap(Map<String, dynamic> map) {
    return SuggestionReward(
      suggestionId: map['suggestionId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      xp: (map['xp'] as num?)?.toInt() ?? 0,
    );
  }
}

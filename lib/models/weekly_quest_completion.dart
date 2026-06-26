class WeeklyQuestCompletionInfo {
  final String questKey;
  final String questName;
  final String emoji;
  final String description;
  final int xpReward;

  const WeeklyQuestCompletionInfo({
    required this.questKey,
    required this.questName,
    required this.emoji,
    required this.description,
    required this.xpReward,
  });

  static const Map<String, WeeklyQuestCompletionInfo> definitions = {
    'ilkAdim': WeeklyQuestCompletionInfo(
      questKey: 'ilkAdim',
      questName: 'İlk Adım',
      emoji: '🎉',
      description: 'Haftanın ilk mekanını keşfettin',
      xpReward: 50,
    ),
    'kasifRuhu': WeeklyQuestCompletionInfo(
      questKey: 'kasifRuhu',
      questName: 'Kaşif Ruhu',
      emoji: '🗺️',
      description: 'Bu hafta 5 mekan gezdin!',
      xpReward: 100,
    ),
    'cesitliKasif': WeeklyQuestCompletionInfo(
      questKey: 'cesitliKasif',
      questName: 'Çeşitli Kaşif',
      emoji: '🏛️',
      description: '2 farklı kategori keşfettin!',
      xpReward: 75,
    ),
    'duzenliGezgin': WeeklyQuestCompletionInfo(
      questKey: 'duzenliGezgin',
      questName: 'Düzenli Gezgin',
      emoji: '📅',
      description: '3 farklı günde keşfe çıktın!',
      xpReward: 75,
    ),
    'takimOyuncusu': WeeklyQuestCompletionInfo(
      questKey: 'takimOyuncusu',
      questName: 'Takım Oyuncusu',
      emoji: '🤝',
      description: 'İlk co-op keşfini tamamladın!',
      xpReward: 100,
    ),
    'takimKasifi': WeeklyQuestCompletionInfo(
      questKey: 'takimKasifi',
      questName: 'Takım Kaşifi',
      emoji: '👥',
      description: 'Co-op\'ta 5 mekan gezdin!',
      xpReward: 100,
    ),
    'tamHafta': WeeklyQuestCompletionInfo(
      questKey: 'tamHafta',
      questName: 'Tam Hafta',
      emoji: '🏆',
      description: '5 gün üst üste keşfettin!',
      xpReward: 300,
    ),
  };

  /// Total XP available from all weekly quests.
  static const int weeklyXPGoal = 800;
}

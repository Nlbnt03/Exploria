import '../../auth/domain/models/badge.dart';

class BadgeDefinition {
  const BadgeDefinition({
    required this.id,
    required this.name,
    required this.description,
    required this.tier,
    required this.category,
    required this.isHidden,
    this.xpReward,
  });

  final String id;
  final String name;
  final String description;
  final BadgeTier tier;
  final BadgeCategory category;
  final bool isHidden;
  final int? xpReward;

  bool condition(BadgeCheckContext context) {
    switch (id) {
      // Exploration
      case 'first_step':
        return context.totalVisited >= 1;
      case 'curious':
        return context.totalVisited >= 5;
      case 'explorer':
        return context.totalVisited >= 25;
      case 'history_hunter':
        return context.historicBuildingVisited >= 10;
      case 'spiritual':
        return context.mosqueVisited >= 10;
      case 'multi_city':
        return context.distinctCitiesVisited >= 3;
      case 'fatih_conqueror':
        return context.lastVisitedMapId == 'fatih' &&
            (context.lastVisitedMapCompletion ?? 0) >= 1.0;
      case 'legend_explorer':
        return context.totalVisited >= 100;

      // Social
      case 'team_player':
        return context.coopSessionsCompleted >= 1;
      case 'team_captain':
        return context.distinctCoopPartners >= 3;
      case 'weekly_leader':
        return context.weeklyLeaderboardRank == 1;
      case 'co_conqueror':
        return context.coopMapJustCompleted;

      // Streak
      case 'flame':
        return context.currentStreak >= 3;
      case 'unstoppable':
        return context.currentStreak >= 7;
      case 'perfectionist':
        return context.allWeeklyQuestsJustCompleted;
      case 'legend_streak':
        return context.currentStreak >= 30;

      // Secret
      case 'night_explorer':
        final hour = context.visitTime.hour;
        return hour >= 23 || hour < 5;
      case 'early_bird':
        final hour = context.visitTime.hour;
        return hour >= 6 && hour < 7;
      case 'speed_explorer':
        // 5 places in 60 minutes
        if (context.recentVisitTimes.length < 5) return false;
        final times = context.recentVisitTimes..sort();
        // check if any window of 5 places falls within 60 minutes
        for (var i = 0; i <= times.length - 5; i++) {
          final diff = times[i + 4].difference(times[i]);
          if (diff.inMinutes <= 60) return true;
        }
        return false;
      case 'winter_traveler':
        final month = context.visitTime.month;
        return month == 12 || month == 1 || month == 2;

      default:
        return false;
    }
  }
}

class BadgeCheckContext {
  const BadgeCheckContext({
    required this.totalVisited,
    required this.historicBuildingVisited,
    required this.mosqueVisited,
    required this.distinctCitiesVisited,
    required this.coopSessionsCompleted,
    required this.distinctCoopPartners,
    required this.coopMapJustCompleted,
    required this.currentStreak,
    required this.allWeeklyQuestsJustCompleted,
    required this.visitTime,
    required this.recentVisitTimes,
    this.lastVisitedMapId,
    this.lastVisitedMapCompletion,
    this.weeklyLeaderboardRank,
  });

  final int totalVisited;
  final int historicBuildingVisited;
  final int mosqueVisited;
  final int distinctCitiesVisited;
  final String? lastVisitedMapId;
  final double? lastVisitedMapCompletion;
  final int coopSessionsCompleted;
  final int distinctCoopPartners;
  final bool coopMapJustCompleted;
  final int currentStreak;
  final bool allWeeklyQuestsJustCompleted;
  final DateTime visitTime;
  final int? weeklyLeaderboardRank;
  final List<DateTime> recentVisitTimes;
}

const badgeDefinitions = <BadgeDefinition>[
  // KEŞİF
  BadgeDefinition(
    id: 'first_step',
    name: 'İlk Adım',
    description: '1 mekan ziyaret ettin.',
    tier: BadgeTier.bronze,
    category: BadgeCategory.exploration,
    isHidden: false,
    xpReward: 50,
  ),
  BadgeDefinition(
    id: 'curious',
    name: 'Meraklı',
    description: '5 mekan ziyaret ettin.',
    tier: BadgeTier.bronze,
    category: BadgeCategory.exploration,
    isHidden: false,
    xpReward: 50,
  ),
  BadgeDefinition(
    id: 'explorer',
    name: 'Gezgin',
    description: '25 mekan ziyaret ettin.',
    tier: BadgeTier.silver,
    category: BadgeCategory.exploration,
    isHidden: false,
    xpReward: 150,
  ),
  BadgeDefinition(
    id: 'history_hunter',
    name: 'Tarih Avcısı',
    description: '10 tarihi bina ziyaret ettin.',
    tier: BadgeTier.silver,
    category: BadgeCategory.exploration,
    isHidden: false,
    xpReward: 150,
  ),
  BadgeDefinition(
    id: 'spiritual',
    name: 'Manevi Yolcu',
    description: '10 cami/türbe ziyaret ettin.',
    tier: BadgeTier.silver,
    category: BadgeCategory.exploration,
    isHidden: false,
    xpReward: 150,
  ),
  BadgeDefinition(
    id: 'multi_city',
    name: 'Çok Şehirli',
    description: 'En az 3 farklı şehirde mekan ziyaret ettin.',
    tier: BadgeTier.silver,
    category: BadgeCategory.exploration,
    isHidden: false,
    xpReward: 150,
  ),
  BadgeDefinition(
    id: 'fatih_conqueror',
    name: 'Fatih\'in Fatihi',
    description: 'Fatih bölgesindeki tüm mekanları %100 tamamla.',
    tier: BadgeTier.gold,
    category: BadgeCategory.exploration,
    isHidden: false,
    xpReward: 500,
  ),
  BadgeDefinition(
    id: 'legend_explorer',
    name: 'Efsane Kaşif',
    description: '100 mekan ziyaret ettin.',
    tier: BadgeTier.gold,
    category: BadgeCategory.exploration,
    isHidden: false,
    xpReward: 500,
  ),

  // SOSYAL
  BadgeDefinition(
    id: 'team_player',
    name: 'Takım Oyuncusu',
    description: 'Co-op modunda bir seans tamamladın.',
    tier: BadgeTier.bronze,
    category: BadgeCategory.social,
    isHidden: false,
    xpReward: 50,
  ),
  BadgeDefinition(
    id: 'team_captain',
    name: 'Ekip Kaptanı',
    description: 'Farklı 3 kişiyle co-op yaptın.',
    tier: BadgeTier.silver,
    category: BadgeCategory.social,
    isHidden: false,
    xpReward: 150,
  ),
  BadgeDefinition(
    id: 'weekly_leader',
    name: 'Lider',
    description: 'Haftalık liderlik tablosunda 1. oldun.',
    tier: BadgeTier.gold,
    category: BadgeCategory.social,
    isHidden: false,
    xpReward: 500,
  ),
  BadgeDefinition(
    id: 'co_conqueror',
    name: 'Birlikte Fethettik',
    description: 'Biriyle birlikte bir bölgeyi tamamen bitirdin.',
    tier: BadgeTier.gold,
    category: BadgeCategory.social,
    isHidden: false,
    xpReward: 500,
  ),

  // STREAK
  BadgeDefinition(
    id: 'flame',
    name: 'Alev',
    description: '3 gün üst üste gez!',
    tier: BadgeTier.bronze,
    category: BadgeCategory.streak,
    isHidden: false,
    xpReward: 50,
  ),
  BadgeDefinition(
    id: 'unstoppable',
    name: 'Vazgeçmez',
    description: '7 gün üst üste gezdin.',
    tier: BadgeTier.silver,
    category: BadgeCategory.streak,
    isHidden: false,
    xpReward: 150,
  ),
  BadgeDefinition(
    id: 'perfectionist',
    name: 'Mükemmeliyetçi',
    description: 'Tüm haftalık görevleri tamamla.',
    tier: BadgeTier.silver,
    category: BadgeCategory.streak,
    isHidden: false,
    xpReward: 150,
  ),
  BadgeDefinition(
    id: 'legend_streak',
    name: 'Efsane Streak',
    description: '30 gün üst üste hiç durmadan gez!',
    tier: BadgeTier.gold,
    category: BadgeCategory.streak,
    isHidden: false,
    xpReward: 500,
  ),

  // GİZLİ
  BadgeDefinition(
    id: 'night_explorer',
    name: 'Gece Kaşifi',
    description: 'Gece 23:00 - 05:00 saatleri arasında mekan ziyaret ettin!',
    tier: BadgeTier.secret,
    category: BadgeCategory.secret,
    isHidden: true,
    xpReward: 300,
  ),
  BadgeDefinition(
    id: 'early_bird',
    name: 'Erken Kuş',
    description: 'Sabah 06:00 - 07:00 arasında uyumadın gezdin!',
    tier: BadgeTier.secret,
    category: BadgeCategory.secret,
    isHidden: true,
    xpReward: 300,
  ),
  BadgeDefinition(
    id: 'speed_explorer',
    name: 'Hız Kaşifi',
    description: '60 dakika içerisinde 5 mekana birden gittin.',
    tier: BadgeTier.secret,
    category: BadgeCategory.secret,
    isHidden: true,
    xpReward: 300,
  ),
  BadgeDefinition(
    id: 'winter_traveler',
    name: 'Kış Gezgini',
    description: 'Aralık, Ocak veya Şubat aylarında zorlu şartlarda gezdin.',
    tier: BadgeTier.secret,
    category: BadgeCategory.secret,
    isHidden: true,
    xpReward: 300,
  ),
];

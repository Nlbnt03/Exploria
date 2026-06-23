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
    this.isActive = true,
    this.conditionField,
    this.conditionOperator,
    this.conditionValue,
    this.iconName,
    this.images = const <String, String>{},
  });

  final String id;
  final String name;
  final String description;
  final BadgeTier tier;
  final BadgeCategory category;
  final bool isHidden;
  final int? xpReward;
  final bool isActive;
  final String? conditionField;
  final String? conditionOperator;
  final dynamic conditionValue;
  final String? iconName;
  final Map<String, String> images;

  String? get premiumImageUrl => images['a'];
  String? get socialCardImageUrl => images['b'];
  String? get listImageUrl => images['c'];

  factory BadgeDefinition.fromJson(Map<String, dynamic> json, String id) {
    return BadgeDefinition(
      id: id,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      tier: BadgeTier.values.firstWhere(
        (e) => e.name == json['tier'],
        orElse: () => BadgeTier.bronze,
      ),
      category: BadgeCategory.values.firstWhere(
        (e) => e.name == json['category'],
        orElse: () => BadgeCategory.exploration,
      ),
      isHidden: json['isHidden'] as bool? ?? false,
      xpReward: json['xpReward'] as int?,
      isActive: json['isActive'] as bool? ?? true,
      conditionField: json['conditionField'] as String?,
      conditionOperator: json['conditionOperator'] as String?,
      conditionValue: json['conditionValue'],
      iconName: json['iconName'] as String?,
      images: _parseImages(json['images']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'tier': tier.name,
      'category': category.name,
      'isHidden': isHidden,
      'xpReward': xpReward,
      'isActive': isActive,
      if (conditionField != null) 'conditionField': conditionField,
      if (conditionOperator != null) 'conditionOperator': conditionOperator,
      if (conditionValue != null) 'conditionValue': conditionValue,
      if (iconName != null) 'iconName': iconName,
      'images': images,
    };
  }

  static Map<String, String> _parseImages(dynamic rawImages) {
    if (rawImages is! Map) return const <String, String>{};
    return <String, String>{
      for (final entry in rawImages.entries)
        if (entry.value is String && (entry.value as String).trim().isNotEmpty)
          entry.key.toString(): (entry.value as String).trim(),
    };
  }

  bool condition(BadgeCheckContext context) {
    if (conditionField == null ||
        conditionOperator == null ||
        conditionValue == null) {
      return false;
    }

    dynamic contextValue;
    switch (conditionField) {
      case 'totalVisited':
        contextValue = context.totalVisited;
        break;
      case 'historicBuildingVisited':
        contextValue = context.historicBuildingVisited;
        break;
      case 'mosqueVisited':
        contextValue = context.mosqueVisited;
        break;
      case 'distinctCitiesVisited':
        contextValue = context.distinctCitiesVisited;
        break;
      case 'coopSessionsCompleted':
        contextValue = context.coopSessionsCompleted;
        break;
      case 'distinctCoopPartners':
        contextValue = context.distinctCoopPartners;
        break;
      case 'coopMapJustCompleted':
        contextValue = context.coopMapJustCompleted;
        break;
      case 'currentStreak':
        contextValue = context.currentStreak;
        break;
      case 'allWeeklyQuestsJustCompleted':
        contextValue = context.allWeeklyQuestsJustCompleted;
        break;
      case 'weeklyLeaderboardRank':
        contextValue = context.weeklyLeaderboardRank ?? 999999;
        break;
      // Özel Gizli/Karmaşık Durumlar (Pseudo-fields)
      case 'fatihAreaCompleted':
        contextValue =
            (context.lastVisitedMapId == 'fatih' &&
                (context.lastVisitedMapCompletion ?? 0) >= 1.0);
        break;
      case 'isNightTime':
        final hour = context.visitTime.hour;
        contextValue = hour >= 23 || hour < 5;
        break;
      case 'isEarlyBird':
        final hour = context.visitTime.hour;
        contextValue = hour >= 6 && hour < 7;
        break;
      case 'isSpeedExplorer':
        if (context.recentVisitTimes.length < 5) {
          contextValue = false;
          break;
        }
        final times = context.recentVisitTimes..sort();
        bool achieved = false;
        for (var i = 0; i <= times.length - 5; i++) {
          final diff = times[i + 4].difference(times[i]);
          if (diff.inMinutes <= 60) {
            achieved = true;
            break;
          }
        }
        contextValue = achieved;
        break;
      case 'isWinterTraveler':
        final month = context.visitTime.month;
        contextValue = month == 12 || month == 1 || month == 2;
        break;
      default:
        return false;
    }

    if (contextValue is num && conditionValue is num) {
      final cv = contextValue.toDouble();
      final target = conditionValue.toDouble();
      switch (conditionOperator) {
        case '>':
          return cv > target;
        case '>=':
          return cv >= target;
        case '<':
          return cv < target;
        case '<=':
          return cv <= target;
        case '==':
          return cv == target;
        case '!=':
          return cv != target;
        default:
          return false;
      }
    } else if (contextValue is bool && conditionValue is bool) {
      switch (conditionOperator) {
        case '==':
          return contextValue == conditionValue;
        case '!=':
          return contextValue != conditionValue;
        default:
          return false;
      }
    } else if (contextValue is String && conditionValue is String) {
      switch (conditionOperator) {
        case '==':
          return contextValue == conditionValue;
        case '!=':
          return contextValue != conditionValue;
        default:
          return false;
      }
    }
    return false;
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

// ARTIK BU LİSTE SADECE MİGRASYON (FIREBASE'E İLK YÜKLEME) İÇİN KULLANILACAKTIR.

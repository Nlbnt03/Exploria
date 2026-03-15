class WeeklyQuestItem {
  final String key;
  final int current; // or derived from categories/activeDays
  final int target;
  final bool done;
  final List<String> categories;
  final List<String> activeDays;

  const WeeklyQuestItem({
    required this.key,
    this.current = 0,
    required this.target,
    this.done = false,
    this.categories = const [],
    this.activeDays = const [],
  });

  double get progressPercent {
    if (key == 'cesitliKasif') {
      return (categories.length / target).clamp(0.0, 1.0);
    } else if (key == 'duzenliGezgin' || key == 'tamHafta') {
      return (activeDays.length / target).clamp(0.0, 1.0);
    }
    return (current / target).clamp(0.0, 1.0);
  }

  int get displayCurrent {
    if (key == 'cesitliKasif') {
      return categories.length;
    } else if (key == 'duzenliGezgin' || key == 'tamHafta') {
      return activeDays.length;
    }
    return current;
  }

  Map<String, dynamic> toMap() {
    return {
      if (key == 'cesitliKasif') 'categories': categories,
      if (key == 'duzenliGezgin' || key == 'tamHafta') 'activeDays': activeDays,
      if (key != 'cesitliKasif' && key != 'duzenliGezgin' && key != 'tamHafta') 'current': current,
      'target': target,
      'done': done,
    };
  }

  factory WeeklyQuestItem.fromMap(String key, Map<String, dynamic> map) {
    return WeeklyQuestItem(
      key: key,
      current: map['current'] ?? 0,
      target: map['target'] ?? 1,
      done: map['done'] ?? false,
      categories: List<String>.from(map['categories'] ?? []),
      activeDays: List<String>.from(map['activeDays'] ?? []),
    );
  }

  WeeklyQuestItem copyWith({
    int? current,
    int? target,
    bool? done,
    List<String>? categories,
    List<String>? activeDays,
  }) {
    return WeeklyQuestItem(
      key: key,
      current: current ?? this.current,
      target: target ?? this.target,
      done: done ?? this.done,
      categories: categories ?? this.categories,
      activeDays: activeDays ?? this.activeDays,
    );
  }
}

class WeeklyQuests {
  final String weekStart;
  final WeeklyQuestItem ilkAdim;
  final WeeklyQuestItem kasifRuhu;
  final WeeklyQuestItem cesitliKasif;
  final WeeklyQuestItem duzenliGezgin;
  final WeeklyQuestItem takimOyuncusu;
  final WeeklyQuestItem takimKasifi;
  final WeeklyQuestItem tamHafta;

  const WeeklyQuests({
    required this.weekStart,
    required this.ilkAdim,
    required this.kasifRuhu,
    required this.cesitliKasif,
    required this.duzenliGezgin,
    required this.takimOyuncusu,
    required this.takimKasifi,
    required this.tamHafta,
  });

  factory WeeklyQuests.fromMap(Map<String, dynamic>? map) {
    final defaultStart = getWeekStart(DateTime.now());
    if (map == null || map['weekStart'] != defaultStart) {
      return WeeklyQuests.empty();
    }
    return WeeklyQuests(
      weekStart: map['weekStart'] ?? defaultStart,
      ilkAdim: WeeklyQuestItem.fromMap('ilkAdim', map['ilkAdim'] ?? {'target': 1}),
      kasifRuhu: WeeklyQuestItem.fromMap('kasifRuhu', map['kasifRuhu'] ?? {'target': 5}),
      cesitliKasif: WeeklyQuestItem.fromMap('cesitliKasif', map['cesitliKasif'] ?? {'target': 2, 'categories': []}),
      duzenliGezgin: WeeklyQuestItem.fromMap('duzenliGezgin', map['duzenliGezgin'] ?? {'target': 3, 'activeDays': []}),
      takimOyuncusu: WeeklyQuestItem.fromMap('takimOyuncusu', map['takimOyuncusu'] ?? {'target': 1}),
      takimKasifi: WeeklyQuestItem.fromMap('takimKasifi', map['takimKasifi'] ?? {'target': 5}),
      tamHafta: WeeklyQuestItem.fromMap('tamHafta', map['tamHafta'] ?? {'target': 5, 'activeDays': []}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'weekStart': weekStart,
      'ilkAdim': ilkAdim.toMap(),
      'kasifRuhu': kasifRuhu.toMap(),
      'cesitliKasif': cesitliKasif.toMap(),
      'duzenliGezgin': duzenliGezgin.toMap(),
      'takimOyuncusu': takimOyuncusu.toMap(),
      'takimKasifi': takimKasifi.toMap(),
      'tamHafta': tamHafta.toMap(),
    };
  }

  factory WeeklyQuests.empty() {
    return WeeklyQuests(
      weekStart: getWeekStart(DateTime.now()),
      ilkAdim: const WeeklyQuestItem(key: 'ilkAdim', target: 1),
      kasifRuhu: const WeeklyQuestItem(key: 'kasifRuhu', target: 5),
      cesitliKasif: const WeeklyQuestItem(key: 'cesitliKasif', target: 2),
      duzenliGezgin: const WeeklyQuestItem(key: 'duzenliGezgin', target: 3),
      takimOyuncusu: const WeeklyQuestItem(key: 'takimOyuncusu', target: 1),
      takimKasifi: const WeeklyQuestItem(key: 'takimKasifi', target: 5),
      tamHafta: const WeeklyQuestItem(key: 'tamHafta', target: 5),
    );
  }

  static String getWeekStart(DateTime date) {
    final weekday = date.weekday;
    final monday = date.subtract(Duration(days: weekday - 1));
    return "${monday.year}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}";
  }
  
  bool get hasAnyIncomplete => 
    !ilkAdim.done || !kasifRuhu.done || !cesitliKasif.done || 
    !duzenliGezgin.done || !takimOyuncusu.done || !takimKasifi.done || !tamHafta.done;
}

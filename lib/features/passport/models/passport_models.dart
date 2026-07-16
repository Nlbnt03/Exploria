enum PassportPoiCategory {
  historic,
  nature,
  beach,
  religious,
  pier,
  museum,
  food,
  park,
  other;

  static PassportPoiCategory fromRaw(String raw) {
    final value = raw.trim().toLowerCase();
    if (value.contains('tarih') ||
        value.contains('saray') ||
        value.contains('kale') ||
        value.contains('anı')) {
      return historic;
    }
    if (value.contains('doğa') ||
        value.contains('doga') ||
        value.contains('orman')) {
      return nature;
    }
    if (value.contains('plaj') || value.contains('sahil')) return beach;
    if (value.contains('cami') ||
        value.contains('kilise') ||
        value.contains('dini') ||
        value.contains('sinagog')) {
      return religious;
    }
    if (value.contains('iskele') ||
        value.contains('liman') ||
        value.contains('vapur')) {
      return pier;
    }
    if (value.contains('müze') || value.contains('muze')) return museum;
    if (value.contains('yeme') ||
        value.contains('restoran') ||
        value.contains('kafe') ||
        value.contains('gastronomi')) {
      return food;
    }
    if (value.contains('park') || value.contains('bahçe')) return park;
    return other;
  }
}

class PassportStampSlot {
  const PassportStampSlot({
    required this.poiId,
    required this.poiName,
    required this.category,
    this.visitedAt,
  });

  final String poiId;
  final String poiName;
  final PassportPoiCategory category;
  final DateTime? visitedAt;

  bool get isVisited => visitedAt != null;

  String get initial {
    final trimmed = poiName.trim();
    return trimmed.isEmpty ? '?' : trimmed.substring(0, 1).toUpperCase();
  }
}

class PassportRegionPage {
  const PassportRegionPage({
    required this.areaId,
    required this.regionName,
    required this.colorHex,
    required this.totalPoiCount,
    required this.slots,
    required this.firstStartedAt,
    this.completedAt,
  });

  final String areaId;
  final String regionName;
  final String colorHex;
  final int totalPoiCount;
  final List<PassportStampSlot> slots;
  final DateTime firstStartedAt;
  final DateTime? completedAt;

  int get visitedPoiCount => slots.where((slot) => slot.isVisited).length;

  double get completion {
    if (totalPoiCount <= 0) return 0;
    return (visitedPoiCount / totalPoiCount).clamp(0.0, 1.0);
  }

  int get completionPercent => (completion * 100).round();
  bool get sealed => totalPoiCount > 0 && visitedPoiCount >= totalPoiCount;
  int get sealYear => (completedAt ?? DateTime.now()).year;
}

class PassportCollection {
  const PassportCollection({required this.pages});

  final List<PassportRegionPage> pages;

  int get stampCount =>
      pages.fold(0, (sum, page) => sum + page.visitedPoiCount);
  int get regionCount => pages.length;
  int get sealedRegionCount => pages.where((page) => page.sealed).length;
}

abstract final class PassportRegionPalette {
  static const List<String> colors = <String>[
    '#16B8A6',
    '#F2A93B',
    '#8B5CF6',
    '#EC4899',
    '#F9733D',
  ];

  static const Map<String, String> _known = <String, String>{
    'istanbul_fatih': '#F2A93B',
    'istanbul_beyoglu': '#EC4899',
    'istanbul_uskudar': '#16B8A6',
    'istanbul_kadikoy': '#8B5CF6',
    'gebze_teknik_universitesi': '#F9733D',
    'gebze_kyk': '#16B8A6',
    'ankara_merkez': '#F2A93B',
  };

  static String forArea(String areaId) {
    final known = _known[areaId];
    if (known != null) return known;
    final hash = areaId.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return colors[hash % colors.length];
  }

  static String sanitize(String? raw, String areaId) {
    final value = raw?.trim().toUpperCase();
    if (value != null && RegExp(r'^#[0-9A-F]{6}$').hasMatch(value)) {
      return value;
    }
    return forArea(areaId);
  }
}

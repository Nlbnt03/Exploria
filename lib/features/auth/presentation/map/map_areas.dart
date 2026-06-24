import 'dart:math' as math;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const String defaultMapStyleUri =
    'mapbox://styles/ynalbant/cmm88zj0i001701sh7fzxcnen';
const String mapAreaGtu = 'gebze_teknik_universitesi';
const String mapAreaGebzeKyk = 'gebze_kyk';
const String mapAreaFatih = 'istanbul_fatih';
const String mapAreaBeyoglu = 'istanbul_beyoglu';
const String mapAreaUskudar = 'istanbul_uskudar';
const String mapAreaKadikoy = 'istanbul_kadikoy';

const String mapGroupAnkara = 'ankara';
const String mapAreaAnkara = 'ankara_merkez';

const String defaultMapAreaId = mapAreaGtu;


class MapAreaConfig {
  const MapAreaConfig({
    required this.id,
    required this.title,
    required this.subtitle,
    this.city = '',
    this.cityCategory = 'diger',
    this.totalPois = 0,
    required this.styleUri,
    required this.center,
    required this.boundary,
    this.gridSizeMeters = 50,
    this.minZoom = 14.8,
  });

  final String id;
  final String title;
  final String subtitle;
  final String city;
  final String cityCategory;
  final int totalPois;
  final String styleUri;
  final Position center;
  final List<Position> boundary;
  final double gridSizeMeters;
  final double minZoom;

  static MapAreaConfig fromFirestoreData(String id, Map<String, dynamic> data) {
    final bounds = Map<String, dynamic>.from(
      data['bounds'] as Map? ?? const <String, dynamic>{},
    );
    final west = (bounds['west'] as num?)?.toDouble();
    final east = (bounds['east'] as num?)?.toDouble();
    final south = (bounds['south'] as num?)?.toDouble() ?? 0;
    final north = (bounds['north'] as num?)?.toDouble() ?? 0;

    if (west == null ||
        east == null ||
        bounds['south'] is! num ||
        bounds['north'] is! num ||
        west >= east ||
        south >= north) {
      throw FormatException('maps/$id belgesinde geçerli bounds alanı yok.');
    }

    final boundary = [
      Position(west, south),
      Position(east, south),
      Position(east, north),
      Position(west, north),
    ];

    final mapName = (data['mapName'] as String?)?.trim() ?? '';
    final city = (data['city'] as String?)?.trim() ?? '';
    final cityCategory =
        (data['cityCategory'] as String?)?.trim().toLowerCase() ?? 'diger';

    return MapAreaConfig(
      id: id,
      title: mapName.isEmpty ? id : mapName,
      subtitle: '${(data['totalPois'] as num?)?.toInt() ?? 0} mekan',
      city: city.isEmpty ? 'Diğer' : city,
      cityCategory: cityCategory.isEmpty ? 'diger' : cityCategory,
      totalPois: (data['totalPois'] as num?)?.toInt() ?? 0,
      styleUri: defaultMapStyleUri,
      center: Position((west + east) / 2, (south + north) / 2),
      boundary: boundary,
    );
  }
}

const String gtuStyleUri = defaultMapStyleUri;

final Position gebzeTeknikCenter = Position(29.361052, 40.809886);

final List<Position> gebzeTeknikBoundary = <Position>[
  Position(29.354666, 40.809329),
  Position(29.353445, 40.805435),
  Position(29.354666, 40.803008),
  Position(29.355096, 40.802736),
  Position(29.359188, 40.802936),
  Position(29.364477, 40.804765),
  Position(29.365984, 40.811104),
  Position(29.363328, 40.813586),
  Position(29.360995, 40.817011),
  Position(29.360297, 40.816708),
  Position(29.358934, 40.813032),
  Position(29.358213, 40.813116),
  Position(29.357086, 40.81212),
  Position(29.354962, 40.811919),
  Position(29.353842, 40.813501),
  Position(29.351778, 40.814006),
  Position(29.350304, 40.813636),
  Position(29.349873, 40.812387),
  Position(29.349289, 40.810545),
  Position(29.351921, 40.80999),
  Position(29.353689, 40.809635),
  Position(29.354666, 40.809329),
];

final Position gebzeKykCenter = Position(29.492377, 40.789251);

final List<Position> gebzeKykBoundary = <Position>[
  Position(29.489638, 40.789002),
  Position(29.492604, 40.790494),
  Position(29.493774, 40.790501),
  Position(29.494954, 40.789388),
  Position(29.494813, 40.788875),
  Position(29.490703, 40.788529),
  Position(29.489691, 40.788529),
  Position(29.489638, 40.789002),
];

final Position fatihCenter = Position(28.953576, 41.011997);

final List<Position> fatihBoundary = <Position>[
  Position(28.946156, 41.035446),
  Position(28.936507, 41.031611),
  Position(28.923641, 41.019087),
  Position(28.921358, 41.014389),
  Position(28.920113, 40.999434),
  Position(28.919179, 40.988548),
  Position(28.927791, 40.992542),
  Position(28.934224, 40.999982),
  Position(28.940138, 41.002488),
  Position(28.948232, 41.001705),
  Position(28.957363, 41.003819),
  Position(28.969191, 41.002488),
  Position(28.976351, 41.001078),
  Position(28.985066, 41.006011),
  Position(28.987972, 41.011962),
  Position(28.985897, 41.017129),
  Position(28.972719, 41.018069),
  Position(28.963588, 41.021435),
  Position(28.958504, 41.027149),
  Position(28.952278, 41.03028),
  Position(28.948854, 41.032785),
  Position(28.946156, 41.035446),
];

final Position beyogluCenter = Position(28.97900, 41.03150);

final List<Position> beyogluBoundary = <Position>[
  Position(28.96800, 41.02100),
  Position(28.97200, 41.02050),
  Position(28.97800, 41.02000),
  Position(28.98400, 41.02200),
  Position(28.98900, 41.02500),
  Position(28.99100, 41.02900),
  Position(28.99200, 41.03400),
  Position(28.99000, 41.03800),
  Position(28.98800, 41.04100),
  Position(28.98400, 41.04200),
  Position(28.97800, 41.04100),
  Position(28.97200, 41.03900),
  Position(28.96800, 41.03600),
  Position(28.96600, 41.03200),
  Position(28.96600, 41.02700),
  Position(28.96700, 41.02300),
  Position(28.96800, 41.02100),
];

final Position uskudarCenter = Position(29.0300, 41.0250);

final List<Position> uskudarBoundary = <Position>[
  Position(29.0000, 41.0000),
  Position(29.0800, 41.0000),
  Position(29.0800, 41.0600),
  Position(29.0000, 41.0600),
  Position(29.0000, 41.0000),
];

final Position kadikoyCenter = Position(29.0250, 40.9850);

final List<Position> kadikoyBoundary = <Position>[
  Position(28.9800, 40.9500),
  Position(29.1000, 40.9500),
  Position(29.1000, 41.0100),
  Position(28.9800, 41.0100),
  Position(28.9800, 40.9500),
];

final Position ankaraCenter = Position(32.8597, 39.9250);

final List<Position> ankaraBoundary = <Position>[
  Position(32.5000, 39.7000),
  Position(33.1000, 39.7000),
  Position(33.1000, 40.2000),
  Position(32.5000, 40.2000),
  Position(32.5000, 39.7000),
];

final List<MapAreaConfig> selectableMapAreas = <MapAreaConfig>[
  MapAreaConfig(
    id: mapAreaGtu,
    title: 'Gebze Teknik Üniversitesi',
    subtitle: 'GTÜ kampüs sınırları',
    styleUri: defaultMapStyleUri,
    center: gebzeTeknikCenter,
    boundary: gebzeTeknikBoundary,
    gridSizeMeters: 65,
    minZoom: 14.0,
  ),
  MapAreaConfig(
    id: mapAreaGebzeKyk,
    title: 'Gebze KYK',
    subtitle: 'Gebze öğrenci yurdu sınırları',
    styleUri: defaultMapStyleUri,
    center: gebzeKykCenter,
    boundary: gebzeKykBoundary,
    gridSizeMeters: 65,
    minZoom: 13.0,
  ),
  MapAreaConfig(
    id: mapAreaFatih,
    title: 'İstanbul / Fatih',
    subtitle: 'Fatih ilçesi sınırları',
    styleUri: defaultMapStyleUri,
    center: fatihCenter,
    boundary: fatihBoundary,
    gridSizeMeters: 65,
    minZoom: 12.5,
  ),
  MapAreaConfig(
    id: mapAreaBeyoglu,
    title: 'İstanbul / Beyoğlu',
    subtitle: 'Beyoğlu ilçesi sınırları',
    styleUri: defaultMapStyleUri,
    center: beyogluCenter,
    boundary: beyogluBoundary,
    gridSizeMeters: 65,
    minZoom: 12.5,
  ),
  MapAreaConfig(
    id: mapAreaUskudar,
    title: 'İstanbul / Üsküdar',
    subtitle: 'Üsküdar ilçesi sınırları',
    styleUri: defaultMapStyleUri,
    center: uskudarCenter,
    boundary: uskudarBoundary,
    gridSizeMeters: 65,
    minZoom: 12.5,
  ),
  MapAreaConfig(
    id: mapAreaKadikoy,
    title: 'İstanbul / Kadıköy',
    subtitle: 'Kadıköy ilçesi ve Moda sahili',
    styleUri: defaultMapStyleUri,
    center: kadikoyCenter,
    boundary: kadikoyBoundary,
    gridSizeMeters: 65,
    minZoom: 14.5,
  ),
  MapAreaConfig(
    id: mapAreaAnkara,
    title: 'Ankara',
    subtitle: 'Başkent ve çevresi',
    styleUri: defaultMapStyleUri,
    center: ankaraCenter,
    boundary: ankaraBoundary,
    gridSizeMeters: 65,
    minZoom: 12.0,
  ),
];

class MapAreaGroup {
  const MapAreaGroup({
    required this.title,
    required this.icon,
    required this.areas,
  });

  final String title;
  final int icon; // IconData.codePoint (to keep const)
  final List<MapAreaConfig> areas;
}

final List<MapAreaGroup> selectableMapGroups = <MapAreaGroup>[
  MapAreaGroup(
    title: 'İstanbul Haritaları',
    icon: 0xe3ab, // Icons.location_city_rounded
    areas: [
      selectableMapAreas.firstWhere((a) => a.id == mapAreaFatih),
      selectableMapAreas.firstWhere((a) => a.id == mapAreaBeyoglu),
      selectableMapAreas.firstWhere((a) => a.id == mapAreaUskudar),
      selectableMapAreas.firstWhere((a) => a.id == mapAreaKadikoy),
    ],
  ),
  MapAreaGroup(
    title: 'Gebze Haritaları',
    icon: 0xe559, // Icons.school_rounded
    areas: [
      selectableMapAreas.firstWhere((a) => a.id == mapAreaGtu),
      selectableMapAreas.firstWhere((a) => a.id == mapAreaGebzeKyk),
    ],
  ),
  MapAreaGroup(
    title: 'Ankara Haritaları',
    icon: 0xe3ab, // Icons.location_city_rounded
    areas: [selectableMapAreas.firstWhere((a) => a.id == mapAreaAnkara)],
  ),
];

final Map<String, MapAreaConfig> _mapAreaById = <String, MapAreaConfig>{
  for (final area in selectableMapAreas) area.id: area,
};

MapAreaConfig resolveMapArea(String areaId) {
  return _mapAreaById[areaId] ?? _mapAreaById[defaultMapAreaId]!;
}

class MapAreaBounds {
  const MapAreaBounds({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  double get midLat => (minLat + maxLat) / 2;

  CoordinateBounds toCoordinateBounds() {
    return CoordinateBounds(
      southwest: Point(coordinates: Position(minLng, minLat)),
      northeast: Point(coordinates: Position(maxLng, maxLat)),
      infiniteBounds: false,
    );
  }
}

MapAreaBounds calculatePolygonBounds(List<Position> polygon) {
  var minLat = double.infinity;
  var maxLat = -double.infinity;
  var minLng = double.infinity;
  var maxLng = -double.infinity;

  for (final point in polygon) {
    final lat = point.lat.toDouble();
    final lng = point.lng.toDouble();
    if (lat < minLat) minLat = lat;
    if (lat > maxLat) maxLat = lat;
    if (lng < minLng) minLng = lng;
    if (lng > maxLng) maxLng = lng;
  }

  return MapAreaBounds(
    minLat: minLat,
    maxLat: maxLat,
    minLng: minLng,
    maxLng: maxLng,
  );
}

bool isPointInsidePolygon(Position point, List<Position> polygon) {
  final x = point.lng.toDouble();
  final y = point.lat.toDouble();
  var inside = false;

  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i].lng.toDouble();
    final yi = polygon[i].lat.toDouble();
    final xj = polygon[j].lng.toDouble();
    final yj = polygon[j].lat.toDouble();
    final denominator = yj - yi;
    if (denominator.abs() < 1e-12) {
      continue;
    }

    final intersects =
        ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / denominator + xi);

    if (intersects) inside = !inside;
  }

  return inside;
}

double haversineDistanceMeters(Position a, Position b) {
  const earthRadiusMeters = 6371000.0;
  final dLat = _toRadians(b.lat.toDouble() - a.lat.toDouble());
  final dLon = _toRadians(b.lng.toDouble() - a.lng.toDouble());
  final startLat = _toRadians(a.lat.toDouble());
  final endLat = _toRadians(b.lat.toDouble());

  final haversine =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(startLat) *
          math.cos(endLat) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);

  final angularDistance =
      2 * math.atan2(math.sqrt(haversine), math.sqrt(1 - haversine));
  return earthRadiusMeters * angularDistance;
}

double _toRadians(double degree) => degree * (math.pi / 180.0);

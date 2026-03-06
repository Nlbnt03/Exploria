import 'dart:math' as math;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const String defaultMapStyleUri =
    'mapbox://styles/ynalbant/cmm88zj0i001701sh7fzxcnen';
const String mapAreaGtu = 'gebze_teknik_universitesi';
const String mapAreaGebzeKyk = 'gebze_kyk';
const String defaultMapAreaId = mapAreaGtu;

class MapAreaConfig {
  const MapAreaConfig({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.styleUri,
    required this.center,
    required this.boundary,
    this.gridSizeMeters = 50,
  });

  final String id;
  final String title;
  final String subtitle;
  final String styleUri;
  final Position center;
  final List<Position> boundary;
  final double gridSizeMeters;
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

final List<MapAreaConfig> selectableMapAreas = <MapAreaConfig>[
  MapAreaConfig(
    id: mapAreaGtu,
    title: 'Gebze Teknik Universitesi',
    subtitle: 'Sadece GTU kampus sinirlari',
    styleUri: defaultMapStyleUri,
    center: gebzeTeknikCenter,
    boundary: gebzeTeknikBoundary,
    gridSizeMeters: 30,
  ),
  MapAreaConfig(
    id: mapAreaGebzeKyk,
    title: 'Gebze KYK',
    subtitle: 'Gebze ogrenci yurdu sinirlari',
    styleUri: defaultMapStyleUri,
    center: gebzeKykCenter,
    boundary: gebzeKykBoundary,
    gridSizeMeters: 30,
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

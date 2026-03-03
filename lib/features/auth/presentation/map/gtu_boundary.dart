import 'dart:math' as math;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

const String defaultMapStyleUri =
    'mapbox://styles/ynalbant/cmm88zj0i001701sh7fzxcnen';
const String campusAreaGtu = 'gebze_teknik_universitesi';
const String campusAreaGebzeKyk = 'gebze_kyk';
const String defaultCampusAreaId = campusAreaGtu;

class CampusAreaConfig {
  const CampusAreaConfig({
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

final Position gtuCampusCenter = Position(29.3682, 40.8105);

final List<Position> gtuCampusBoundary = <Position>[
  Position(29.3548, 40.8012),
  Position(29.3622, 40.7998),
  Position(29.3698, 40.8006),
  Position(29.3774, 40.8034),
  Position(29.3846, 40.8079),
  Position(29.3862, 40.8139),
  Position(29.3834, 40.8193),
  Position(29.3766, 40.8214),
  Position(29.3688, 40.8210),
  Position(29.3609, 40.8188),
  Position(29.3553, 40.8137),
  Position(29.3532, 40.8074),
  Position(29.3548, 40.8012),
];

final Position gebzeKykCenter = Position(29.492377, 40.789251);

final List<Position> gebzeKykBoundary = <Position>[
  Position(29.489850, 40.788250),
  Position(29.494450, 40.788250),
  Position(29.494650, 40.790050),
  Position(29.493700, 40.790850),
  Position(29.490050, 40.790450),
  Position(29.489850, 40.788250),
];

final List<CampusAreaConfig> selectableCampusAreas = <CampusAreaConfig>[
  CampusAreaConfig(
    id: campusAreaGtu,
    title: 'Gebze Teknik Universitesi',
    subtitle: 'Sadece GTU kampus sinirlari',
    styleUri: defaultMapStyleUri,
    center: gtuCampusCenter,
    boundary: gtuCampusBoundary,
    gridSizeMeters: 30,
  ),
  CampusAreaConfig(
    id: campusAreaGebzeKyk,
    title: 'Gebze KYK',
    subtitle: 'Gebze ogrenci yurdu sinirlari',
    styleUri: defaultMapStyleUri,
    center: gebzeKykCenter,
    boundary: gebzeKykBoundary,
    gridSizeMeters: 30,
  ),
];

final Map<String, CampusAreaConfig> _campusAreaById =
    <String, CampusAreaConfig>{
      for (final area in selectableCampusAreas) area.id: area,
    };

CampusAreaConfig resolveCampusArea(String areaId) {
  return _campusAreaById[areaId] ?? _campusAreaById[defaultCampusAreaId]!;
}

class CampusBounds {
  const CampusBounds({
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

CampusBounds calculateBounds(List<Position> polygon) {
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

  return CampusBounds(
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

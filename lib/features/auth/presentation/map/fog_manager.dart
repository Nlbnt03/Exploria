import 'dart:convert';
import 'dart:math' as math;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'gtu_boundary.dart';

class FogManager {
  FogManager({
    required this.campusBoundary,
    this.gridSizeMeters = 50,
    this.baseFogOpacity = 0.65,
    this.revealRadiusMeters = 28,
  }) : _campusBounds = calculateBounds(campusBoundary);

  final List<Position> campusBoundary;
  final double gridSizeMeters;
  final double baseFogOpacity;
  final double revealRadiusMeters;
  final CampusBounds _campusBounds;

  final Map<String, _FogCell> _cells = <String, _FogCell>{};
  final Set<String> _revealedCellIds = <String>{};
  final Map<String, int> _fadingCellStepById = <String, int>{};

  bool _initialized = false;
  late final double _latStepDeg;
  late final double _lonStepDeg;
  static const double _viewportBufferRatio = 0.28;
  static const List<double> _fadeOpacitySteps = <double>[0.5, 0.3, 0.1, 0.0];

  CampusBounds get bounds => _campusBounds;
  int get revealedCount => _revealedCellIds.length + _fadingCellStepById.length;
  int get totalCount => _cells.length;
  bool get hasPendingRevealAnimation => _fadingCellStepById.isNotEmpty;

  bool contains(Position point) => isPointInsidePolygon(point, campusBoundary);

  List<String> snapshotRevealedCellIds() {
    final ids = <String>{..._revealedCellIds, ..._fadingCellStepById.keys};
    final normalized = ids.toList(growable: false)..sort();
    return normalized;
  }

  Future<void> initialize() async {
    if (_initialized) return;

    const metersPerDegreeLat = 111320.0;
    _latStepDeg = gridSizeMeters / metersPerDegreeLat;

    final cosLat = math.cos(_campusBounds.midLat * math.pi / 180.0).abs();
    final safeCos = cosLat < 0.15 ? 0.15 : cosLat;
    _lonStepDeg = gridSizeMeters / (metersPerDegreeLat * safeCos);

    var row = 0;
    for (
      double lat = _campusBounds.minLat;
      lat < _campusBounds.maxLat;
      lat += _latStepDeg, row++
    ) {
      var col = 0;
      for (
        double lon = _campusBounds.minLng;
        lon < _campusBounds.maxLng;
        lon += _lonStepDeg, col++
      ) {
        final center = Position(
          lon + (_lonStepDeg / 2),
          lat + (_latStepDeg / 2),
        );
        if (!contains(center)) continue;

        final id = '${row}_$col';
        _cells[id] = _FogCell(
          id: id,
          center: center,
          minLat: lat,
          maxLat: lat + _latStepDeg,
          minLng: lon,
          maxLng: lon + _lonStepDeg,
          ring: <List<double>>[
            <double>[lon, lat],
            <double>[lon + _lonStepDeg, lat],
            <double>[lon + _lonStepDeg, lat + _latStepDeg],
            <double>[lon, lat + _latStepDeg],
            <double>[lon, lat],
          ],
        );
      }
    }

    _initialized = true;
  }

  void restoreRevealedCells(Iterable<String> cellIds) {
    if (!_initialized) return;

    _revealedCellIds.clear();
    _fadingCellStepById.clear();

    for (final id in cellIds) {
      if (!_cells.containsKey(id)) continue;
      _revealedCellIds.add(id);
    }
  }

  bool revealForPosition(Position point) {
    if (!_initialized || !contains(point)) return false;

    var changed = false;
    final candidateCells = _cellsIntersectingRevealCircle(
      center: point,
      radiusMeters: revealRadiusMeters,
    );
    for (final cell in candidateCells) {
      if (_revealedCellIds.contains(cell.id)) {
        continue;
      }
      if (_fadingCellStepById.containsKey(cell.id)) {
        continue;
      }
      _fadingCellStepById[cell.id] = 0;
      changed = true;
    }

    return changed;
  }

  bool advanceRevealAnimationStep() {
    if (_fadingCellStepById.isEmpty) return false;

    var changed = false;
    final completedCellIds = <String>[];
    final ids = _fadingCellStepById.keys.toList(growable: false);
    for (final id in ids) {
      final currentStep = _fadingCellStepById[id];
      if (currentStep == null) continue;

      final nextStep = currentStep + 1;
      if (nextStep >= _fadeOpacitySteps.length) {
        completedCellIds.add(id);
      } else {
        _fadingCellStepById[id] = nextStep;
      }
      changed = true;
    }

    for (final id in completedCellIds) {
      _fadingCellStepById.remove(id);
      _revealedCellIds.add(id);
    }

    return changed;
  }

  String geoJsonForViewport({
    required Position southwest,
    required Position northeast,
  }) {
    if (!_initialized) {
      return _emptyFeatureCollection;
    }

    final swLat = southwest.lat.toDouble();
    final neLat = northeast.lat.toDouble();
    final swLng = southwest.lng.toDouble();
    final neLng = northeast.lng.toDouble();

    final minLat = math.min(swLat, neLat);
    final maxLat = math.max(swLat, neLat);
    final minLng = math.min(swLng, neLng);
    final maxLng = math.max(swLng, neLng);
    final latBuffer = math.max(
      _latStepDeg * 1.5,
      (maxLat - minLat).abs() * _viewportBufferRatio,
    );
    final lngBuffer = math.max(
      _lonStepDeg * 1.5,
      (maxLng - minLng).abs() * _viewportBufferRatio,
    );
    final paddedMinLat = minLat - latBuffer;
    final paddedMaxLat = maxLat + latBuffer;
    final paddedMinLng = minLng - lngBuffer;
    final paddedMaxLng = maxLng + lngBuffer;

    final features = <Map<String, Object?>>[];
    for (final cell in _cells.values) {
      if (_revealedCellIds.contains(cell.id)) continue;

      final intersectsViewport =
          cell.maxLat >= paddedMinLat &&
          cell.minLat <= paddedMaxLat &&
          cell.maxLng >= paddedMinLng &&
          cell.minLng <= paddedMaxLng;
      if (!intersectsViewport) {
        continue;
      }

      final fadeStep = _fadingCellStepById[cell.id];
      final opacity =
          fadeStep == null ? baseFogOpacity : _fadeOpacitySteps[fadeStep];

      features.add(<String, Object?>{
        'type': 'Feature',
        'id': cell.id,
        'properties': <String, Object?>{'grid_id': cell.id, 'opacity': opacity},
        'geometry': <String, Object?>{
          'type': 'Polygon',
          'coordinates': <Object>[cell.ring],
        },
      });
    }

    return jsonEncode(<String, Object?>{
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  String get _emptyFeatureCollection =>
      '{"type":"FeatureCollection","features":[]}';

  List<_FogCell> _cellsIntersectingRevealCircle({
    required Position center,
    required double radiusMeters,
  }) {
    final centerLat = center.lat.toDouble();
    final centerLng = center.lng.toDouble();
    final latRadiusDeg = radiusMeters / 111320.0;
    final cosLat = math.cos(centerLat * math.pi / 180.0).abs();
    final safeCos = cosLat < 0.15 ? 0.15 : cosLat;
    final lonRadiusDeg = radiusMeters / (111320.0 * safeCos);

    final minRow =
        ((centerLat - latRadiusDeg - _campusBounds.minLat) / _latStepDeg)
            .floor() -
        1;
    final maxRow =
        ((centerLat + latRadiusDeg - _campusBounds.minLat) / _latStepDeg)
            .ceil() +
        1;
    final minCol =
        ((centerLng - lonRadiusDeg - _campusBounds.minLng) / _lonStepDeg)
            .floor() -
        1;
    final maxCol =
        ((centerLng + lonRadiusDeg - _campusBounds.minLng) / _lonStepDeg)
            .ceil() +
        1;

    final matched = <_FogCell>[];
    final metersPerDegLon = 111320.0 * safeCos;
    for (int row = minRow; row <= maxRow; row++) {
      for (int col = minCol; col <= maxCol; col++) {
        final id = '${row}_$col';
        final cell = _cells[id];
        if (cell == null) continue;

        if (_circleIntersectsCell(
          centerLat: centerLat,
          centerLng: centerLng,
          radiusMeters: radiusMeters,
          metersPerDegLon: metersPerDegLon,
          cell: cell,
        )) {
          matched.add(cell);
        }
      }
    }

    return matched;
  }

  bool _circleIntersectsCell({
    required double centerLat,
    required double centerLng,
    required double radiusMeters,
    required double metersPerDegLon,
    required _FogCell cell,
  }) {
    const metersPerDegLat = 111320.0;
    final minX = (cell.minLng - centerLng) * metersPerDegLon;
    final maxX = (cell.maxLng - centerLng) * metersPerDegLon;
    final minY = (cell.minLat - centerLat) * metersPerDegLat;
    final maxY = (cell.maxLat - centerLat) * metersPerDegLat;
    final closestX = _clampDouble(0, minX, maxX);
    final closestY = _clampDouble(0, minY, maxY);
    return (closestX * closestX + closestY * closestY) <=
        radiusMeters * radiusMeters;
  }

  double _clampDouble(double value, double min, double max) {
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }
}

class _FogCell {
  const _FogCell({
    required this.id,
    required this.center,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.ring,
  });

  final String id;
  final Position center;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final List<List<double>> ring;
}

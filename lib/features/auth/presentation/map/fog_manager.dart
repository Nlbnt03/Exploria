import 'dart:convert';
import 'dart:math' as math;

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'map_areas.dart';

class FogManager {
  FogManager({
    required this.campusBoundary,
    this.gridSizeMeters = 50,
    this.baseFogOpacity = 0.85,
    this.revealRadiusMeters = 28,
  }) : _campusBounds = calculatePolygonBounds(campusBoundary);

  final List<Position> campusBoundary;
  final double gridSizeMeters;
  final double baseFogOpacity;
  final double revealRadiusMeters;
  final MapAreaBounds _campusBounds;

  final Map<String, _FogCell> _cells = <String, _FogCell>{};
  final Set<String> _revealedCellIds = <String>{};
  final Map<String, int> _fadingCellStepById = <String, int>{};

  bool _initialized = false;
  late final double _latStepDeg;
  late final double _lonStepDeg;
  int _renderRevision = 0;
  int _cachedRenderRevision = -1;
  int _cachedCloudDetail = -1;
  _PaddedViewport? _cachedCoverage;
  static const double _viewportBufferRatio = 0.18;
  static const double _cachedViewportBufferRatio = 0.48;
  static const List<double> _fadeOpacitySteps = <double>[0.5, 0.3, 0.1, 0.0];
  static const int _cloudPuffsPerCell = 10;

  MapAreaBounds get bounds => _campusBounds;
  int get revealedCount => _revealedCellIds.length + _fadingCellStepById.length;
  int get totalCount => _cells.length;
  bool get hasPendingRevealAnimation => _fadingCellStepById.isNotEmpty;

  bool contains(Position point) => isPointInsidePolygon(point, campusBoundary);

  List<String> snapshotRevealedCellIds() {
    final ids = <String>{..._revealedCellIds, ..._fadingCellStepById.keys};
    final normalized = ids.toList(growable: false)..sort();
    return normalized;
  }

  void invalidateRenderCache() {
    _cachedCoverage = null;
    _cachedRenderRevision = -1;
    _cachedCloudDetail = -1;
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
          row: row,
          column: col,
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
    _renderRevision++;
  }

  void restoreRevealedCells(Iterable<String> cellIds) {
    if (!_initialized) return;

    _revealedCellIds.clear();
    _fadingCellStepById.clear();

    for (final id in cellIds) {
      if (!_cells.containsKey(id)) continue;
      _revealedCellIds.add(id);
    }
    _renderRevision++;
  }

  /// Merges cells from teammates without clearing existing revealed state.
  void mergeRevealedCells(Iterable<String> cellIds) {
    if (!_initialized) return;
    var changed = false;
    for (final id in cellIds) {
      if (!_cells.containsKey(id)) continue;
      changed = _revealedCellIds.add(id) || changed;
      changed = _fadingCellStepById.remove(id) != null || changed;
    }
    if (changed) _renderRevision++;
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

    if (changed) _renderRevision++;
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

    if (changed) _renderRevision++;
    return changed;
  }

  /// Builds both original fog sources in one pass and keeps a larger offscreen
  /// coverage window cached. Small camera movements can then be rendered by
  /// Mapbox without rebuilding or transferring the same GeoJSON again.
  FogRenderUpdate? renderForViewport({
    required Position southwest,
    required Position northeast,
    required double zoom,
    bool force = false,
  }) {
    if (!_initialized) {
      return const FogRenderUpdate(
        fogGeoJson: '{"type":"FeatureCollection","features":[]}',
        cloudGeoJson: '{"type":"FeatureCollection","features":[]}',
      );
    }

    final requiredViewport = _buildPaddedViewport(
      southwest: southwest,
      northeast: northeast,
    );
    final cloudDetail = _cloudDetailForZoom(zoom);
    final cachedCoverage = _cachedCoverage;
    if (!force &&
        _cachedRenderRevision == _renderRevision &&
        _cachedCloudDetail == cloudDetail &&
        cachedCoverage != null &&
        cachedCoverage.contains(requiredViewport)) {
      return null;
    }

    final coverage = _buildPaddedViewport(
      southwest: southwest,
      northeast: northeast,
      bufferRatio: _cachedViewportBufferRatio,
    );
    final fogFeatures = <Map<String, Object?>>[];
    final cloudFeatures = <Map<String, Object?>>[];
    final detail = _cloudDetail(cloudDetail);
    for (final cell in _visibleFogCells(coverage)) {
      final opacity = _opacityForCell(cell.id);
      fogFeatures.add(_fogFeature(cell, opacity));
      if (opacity <= 0.01 || !_shouldRenderCloudCell(cell, detail.stride)) {
        continue;
      }
      _appendCloudFeatures(
        cloudFeatures,
        cell: cell,
        cellOpacity: opacity,
        puffCount: detail.puffCount,
      );
    }

    _cachedCoverage = coverage;
    _cachedRenderRevision = _renderRevision;
    _cachedCloudDetail = cloudDetail;
    return FogRenderUpdate(
      fogGeoJson: jsonEncode(<String, Object?>{
        'type': 'FeatureCollection',
        'features': fogFeatures,
      }),
      cloudGeoJson: jsonEncode(<String, Object?>{
        'type': 'FeatureCollection',
        'features': cloudFeatures,
      }),
    );
  }

  String geoJsonForViewport({
    required Position southwest,
    required Position northeast,
  }) {
    if (!_initialized) {
      return _emptyFeatureCollection;
    }

    final viewport = _buildPaddedViewport(
      southwest: southwest,
      northeast: northeast,
    );

    final features = <Map<String, Object?>>[];
    for (final cell in _visibleFogCells(viewport)) {
      final opacity = _opacityForCell(cell.id);
      features.add(_fogFeature(cell, opacity));
    }

    return jsonEncode(<String, Object?>{
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  String cloudGeoJsonForViewport({
    required Position southwest,
    required Position northeast,
  }) {
    if (!_initialized) {
      return _emptyFeatureCollection;
    }

    final viewport = _buildPaddedViewport(
      southwest: southwest,
      northeast: northeast,
    );

    final features = <Map<String, Object?>>[];
    for (final cell in _visibleFogCells(viewport)) {
      final cellOpacity = _opacityForCell(cell.id);
      if (cellOpacity <= 0.01) {
        continue;
      }
      _appendCloudFeatures(
        features,
        cell: cell,
        cellOpacity: cellOpacity,
        puffCount: _cloudPuffsPerCell,
      );
    }

    return jsonEncode(<String, Object?>{
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  String get _emptyFeatureCollection =>
      '{"type":"FeatureCollection","features":[]}';

  Map<String, Object?> _fogFeature(_FogCell cell, double opacity) {
    return <String, Object?>{
      'type': 'Feature',
      'id': cell.id,
      'properties': <String, Object?>{'grid_id': cell.id, 'opacity': opacity},
      'geometry': <String, Object?>{
        'type': 'Polygon',
        'coordinates': <Object>[cell.ring],
      },
    };
  }

  void _appendCloudFeatures(
    List<Map<String, Object?>> target, {
    required _FogCell cell,
    required double cellOpacity,
    required int puffCount,
  }) {
    final centerLng = cell.center.lng.toDouble();
    final centerLat = cell.center.lat.toDouble();
    final cellLngSpan = (cell.maxLng - cell.minLng).abs();
    final cellLatSpan = (cell.maxLat - cell.minLat).abs();
    final lonSpreadDeg = cellLngSpan * 1.85;
    final latSpreadDeg = cellLatSpan * 1.85;

    for (var puffIndex = 0; puffIndex < puffCount; puffIndex++) {
      final seed = _stableHash('${cell.id}#$puffIndex');
      final lng = centerLng + ((_rand(seed, 1) - 0.5) * lonSpreadDeg);
      final lat = centerLat + ((_rand(seed, 2) - 0.5) * latSpreadDeg);

      final texture = 0.42 + (_rand(seed, 3) * 0.35);
      final opacity = (cellOpacity * texture).clamp(0.0, 1.0);
      final radius = 36.0 + (_rand(seed, 4) * 32.0);

      target.add(<String, Object?>{
        'type': 'Feature',
        'id': '${cell.id}#cloud_$puffIndex',
        'properties': <String, Object?>{
          'grid_id': cell.id,
          'opacity': opacity,
          'radius': radius,
        },
        'geometry': <String, Object?>{
          'type': 'Point',
          'coordinates': <double>[lng, lat],
        },
      });
    }
  }

  int _cloudDetailForZoom(double zoom) {
    if (zoom >= 15.5) return 4;
    if (zoom >= 14.5) return 3;
    if (zoom >= 13.5) return 2;
    if (zoom >= 12.5) return 1;
    return 0;
  }

  _CloudDetail _cloudDetail(int detail) {
    return switch (detail) {
      4 => const _CloudDetail(stride: 1, puffCount: 10),
      3 => const _CloudDetail(stride: 1, puffCount: 6),
      2 => const _CloudDetail(stride: 1, puffCount: 3),
      1 => const _CloudDetail(stride: 2, puffCount: 1),
      _ => const _CloudDetail(stride: 4, puffCount: 1),
    };
  }

  bool _shouldRenderCloudCell(_FogCell cell, int stride) {
    return stride == 1 || (cell.row % stride == 0 && cell.column % stride == 0);
  }

  _PaddedViewport _buildPaddedViewport({
    required Position southwest,
    required Position northeast,
    double bufferRatio = _viewportBufferRatio,
  }) {
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
      (maxLat - minLat).abs() * bufferRatio,
    );
    final lngBuffer = math.max(
      _lonStepDeg * 1.5,
      (maxLng - minLng).abs() * bufferRatio,
    );

    return _PaddedViewport(
      minLat: minLat - latBuffer,
      maxLat: maxLat + latBuffer,
      minLng: minLng - lngBuffer,
      maxLng: maxLng + lngBuffer,
    );
  }

  Iterable<_FogCell> _visibleFogCells(_PaddedViewport viewport) sync* {
    final minRow =
        ((viewport.minLat - _campusBounds.minLat) / _latStepDeg).floor();
    final maxRow =
        ((viewport.maxLat - _campusBounds.minLat) / _latStepDeg).ceil();
    final minCol =
        ((viewport.minLng - _campusBounds.minLng) / _lonStepDeg).floor();
    final maxCol =
        ((viewport.maxLng - _campusBounds.minLng) / _lonStepDeg).ceil();

    for (int row = minRow; row <= maxRow; row++) {
      for (int col = minCol; col <= maxCol; col++) {
        final id = '${row}_$col';
        final cell = _cells[id];
        if (cell == null) continue;
        if (_revealedCellIds.contains(cell.id)) continue;
        yield cell;
      }
    }
  }

  double _opacityForCell(String cellId) {
    final fadeStep = _fadingCellStepById[cellId];
    return fadeStep == null ? baseFogOpacity : _fadeOpacitySteps[fadeStep];
  }

  int _stableHash(String input) {
    var hash = 2166136261;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 16777619) & 0x7fffffff;
    }
    return hash;
  }

  double _rand(int seed, int salt) {
    var value = seed ^ (salt * 0x45d9f3b);
    value = (value ^ (value >> 16)) * 0x45d9f3b;
    value = value ^ (value >> 16);
    return (value & 0x7fffffff) / 0x7fffffff;
  }

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

class FogRenderUpdate {
  const FogRenderUpdate({required this.fogGeoJson, required this.cloudGeoJson});

  final String fogGeoJson;
  final String cloudGeoJson;
}

class _CloudDetail {
  const _CloudDetail({required this.stride, required this.puffCount});

  final int stride;
  final int puffCount;
}

class _FogCell {
  const _FogCell({
    required this.id,
    required this.row,
    required this.column,
    required this.center,
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
    required this.ring,
  });

  final String id;
  final int row;
  final int column;
  final Position center;
  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;
  final List<List<double>> ring;
}

class _PaddedViewport {
  const _PaddedViewport({
    required this.minLat,
    required this.maxLat,
    required this.minLng,
    required this.maxLng,
  });

  final double minLat;
  final double maxLat;
  final double minLng;
  final double maxLng;

  bool contains(_PaddedViewport other) {
    return minLat <= other.minLat &&
        maxLat >= other.maxLat &&
        minLng <= other.minLng &&
        maxLng >= other.maxLng;
  }
}

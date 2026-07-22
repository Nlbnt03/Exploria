import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../domain/models/share_map_scene.dart';

/// Published Mapbox Studio style used for share-card snapshots. Reuses the
/// live app's own style until a dedicated, lighter share style is published.
const String shareLightStyleUri =
    'mapbox://styles/ynalbant/cmm88zj0i001701sh7fzxcnen';

class ShareMapSnapshotService {
  const ShareMapSnapshotService();

  static const int width = 1080;
  static const int height = 820;
  static const double pixelRatio = 1;
  static const double maxZoom = 15.5;
  static const double _minimumRouteExtentMeters = 250;
  static const int _maximumNumberedPois = 10;
  static const double _nearRoutePoiMeters = 220;

  static const String _boundarySourceId = 'share-boundary-source';
  static const String _boundaryMaskSourceId = 'share-boundary-mask-source';
  static const String _routeSourceId = 'share-route-source';
  static const String _transitionSourceId = 'share-transition-source';
  static const String _poiSourceId = 'share-poi-source';
  static const String _markerSourceId = 'share-marker-source';
  static const String _labelSourceId = 'share-label-source';

  Future<Uint8List> createSnapshot(
    ShareMapScene scene, {
    String styleUri = shareLightStyleUri,
  }) async {
    final routePoints = _validPositions(scene.routePoints);
    if (routePoints.length < 2) {
      throw ArgumentError.value(
        scene.sessions,
        'scene.sessions',
        'Paylaşım haritası için en az iki geçerli rota noktası gerekli.',
      );
    }

    // mapbox_maps_flutter 2.19.1 converts Android snapshot Size from logical
    // pixels to device pixels inside its platform bridge. Compensating here
    // keeps the native Snapshotter output exactly 1080×820 while pixelRatio
    // remains 1; iOS already accepts the requested size directly.
    final androidDensity =
        Platform.isAndroid
            ? (PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1)
            : 1.0;
    final logicalWidth = width / androidDensity;
    final logicalHeight = height / androidDensity;
    final styleReady = Completer<void>();
    final snapshotter = await Snapshotter.create(
      options: MapSnapshotOptions(
        size: Size(width: logicalWidth, height: logicalHeight),
        pixelRatio: pixelRatio,
        showsLogo: false,
        showsAttribution: false,
      ),
      onStyleLoadedListener: (_) {
        if (!styleReady.isCompleted) styleReady.complete();
      },
      onMapLoadErrorListener: (error) {
        if (error.type == MapLoadErrorType.STYLE && !styleReady.isCompleted) {
          styleReady.completeError(
            StateError('Mapbox açık stili yüklenemedi: ${error.message}'),
          );
        }
      },
    );

    try {
      await snapshotter.style.setStyleURI(styleUri);
      await styleReady.future.timeout(
        const Duration(seconds: 20),
        onTimeout:
            () =>
                throw TimeoutException(
                  'Mapbox açık stili zaman aşımına uğradı.',
                ),
      );

      final boundary = _parseBoundary(scene.boundaryGeoJson);
      await _addBoundaryLayers(snapshotter.style, boundary);
      await _addSceneLayers(snapshotter.style, scene, routePoints);

      final cameraCoordinates = _cameraCoordinates(
        scene: scene,
        routePoints: routePoints,
        boundary: boundary,
      );
      // ~65px of breathing room around the route so it fills most of the
      // frame instead of the wide 10%-of-canvas padding used previously.
      final cameraPadding = 65 / androidDensity;
      final fittedCamera = await snapshotter.camera(
        coordinates: cameraCoordinates
            .map((position) => Point(coordinates: position))
            .toList(growable: false),
        padding: MbxEdgeInsets(
          top: cameraPadding,
          left: cameraPadding,
          bottom: cameraPadding,
          right: cameraPadding,
        ),
        bearing: 0,
        pitch: 0,
      );
      await snapshotter.setCamera(
        CameraOptions(
          center: fittedCamera.center,
          padding: fittedCamera.padding,
          zoom: math.min(fittedCamera.zoom ?? maxZoom, maxZoom),
          bearing: 0,
          pitch: 0,
        ),
      );

      final snapshot = await snapshotter.start();
      if (snapshot == null || snapshot.isEmpty) {
        throw StateError('Mapbox boş snapshot döndürdü.');
      }
      _validatePngDimensions(snapshot);
      await _writeDebugSnapshot(snapshot, scene.mapName);
      return snapshot;
    } finally {
      await snapshotter.dispose();
    }
  }

  Future<void> _addBoundaryLayers(
    StyleManager style,
    _BoundaryData? boundary,
  ) async {
    if (boundary == null) return;

    await style.addSource(
      GeoJsonSource(id: _boundarySourceId, data: boundary.geoJson),
    );
    if (boundary.outsideMaskGeoJson != null) {
      await style.addSource(
        GeoJsonSource(
          id: _boundaryMaskSourceId,
          data: boundary.outsideMaskGeoJson!,
        ),
      );
      await style.addLayer(
        FillLayer(
          id: 'share-boundary-outside-mask',
          sourceId: _boundaryMaskSourceId,
          fillColor: 0xFFF4F2ED,
          fillOpacity: 0.52,
        ),
      );
    }
    await style.addLayer(
      FillLayer(
        id: 'share-boundary-fill',
        sourceId: _boundarySourceId,
        fillColor: 0xFFFFF8EA,
        fillOpacity: 0.18,
      ),
    );
    await style.addLayer(
      LineLayer(
        id: 'share-boundary-line',
        sourceId: _boundarySourceId,
        lineColor: 0xFFBFC2C2,
        lineWidth: 1.5,
        lineOpacity: 0.82,
      ),
    );
  }

  Future<void> _addSceneLayers(
    StyleManager style,
    ShareMapScene scene,
    List<Position> routePoints,
  ) async {
    final sessions = scene.sessions.toList(growable: false)
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final routeFeatures = <Map<String, Object?>>[];
    final validSessions = <List<Position>>[];
    for (final session in sessions) {
      final points = _validPositions(session.points);
      if (points.length < 2) continue;
      validSessions.add(points);
      routeFeatures.add(_lineFeature(id: session.id, positions: points));
    }
    if (routeFeatures.isEmpty) {
      throw StateError('Snapshot için çizilebilir rota oturumu bulunamadı.');
    }

    final transitionFeatures = <Map<String, Object?>>[];
    for (var index = 1; index < validSessions.length; index++) {
      transitionFeatures.add(
        _lineFeature(
          id: 'transition-$index',
          positions: <Position>[
            validSessions[index - 1].last,
            validSessions[index].first,
          ],
        ),
      );
    }

    final orderedPois = scene.discoveredPois
      .where((poi) => _isValidPosition(poi.position))
      .toList(growable: false)..sort((a, b) {
      final byTime = a.visitedAt.compareTo(b.visitedAt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    final numberedPois = orderedPois.take(_maximumNumberedPois).toList();
    final startPoint =
        _isValidPosition(scene.startPoint)
            ? scene.startPoint
            : routePoints.first;
    final endPoint =
        _isValidPosition(scene.endPoint) ? scene.endPoint : routePoints.last;
    final poiFeatures = <Map<String, Object?>>[
      for (final entry in numberedPois.indexed)
        _pointFeature(
          id: entry.$2.id,
          position: entry.$2.position,
          properties: <String, Object?>{
            'number': entry.$1 + 1,
            'name': entry.$2.name ?? '',
          },
        ),
    ];

    final markerFeatures = <Map<String, Object?>>[
      _pointFeature(
        id: 'start',
        position: startPoint,
        properties: const <String, Object?>{'kind': 'start'},
      ),
      _pointFeature(
        id: 'finish',
        position: endPoint,
        properties: const <String, Object?>{'kind': 'finish'},
      ),
    ];
    final labelFeatures = _importantLabelFeatures(
      pois: numberedPois,
      start: startPoint,
      end: endPoint,
    );

    await style.addSource(
      GeoJsonSource(
        id: _routeSourceId,
        data: _featureCollection(routeFeatures),
      ),
    );
    await style.addSource(
      GeoJsonSource(
        id: _transitionSourceId,
        data: _featureCollection(transitionFeatures),
      ),
    );
    await style.addSource(
      GeoJsonSource(id: _poiSourceId, data: _featureCollection(poiFeatures)),
    );
    await style.addSource(
      GeoJsonSource(
        id: _markerSourceId,
        data: _featureCollection(markerFeatures),
      ),
    );
    await style.addSource(
      GeoJsonSource(
        id: _labelSourceId,
        data: _featureCollection(labelFeatures),
      ),
    );

    await style.addLayer(
      LineLayer(
        id: 'share-route-glow',
        sourceId: _routeSourceId,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineColor: 0xFFFF2D76,
        lineWidth: 18,
        lineOpacity: 0.25,
        lineBlur: 10,
      ),
    );
    await style.addLayer(
      LineLayer(
        id: 'share-route-main',
        sourceId: _routeSourceId,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineColor: 0xFFFF176B,
        lineWidth: 8,
      ),
    );
    await style.addLayer(
      LineLayer(
        id: 'share-route-center',
        sourceId: _routeSourceId,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineColor: 0xFFFFFFFF,
        lineWidth: 2.5,
        lineOpacity: 0.95,
      ),
    );
    await style.addLayer(
      LineLayer(
        id: 'share-session-transitions',
        sourceId: _transitionSourceId,
        lineCap: LineCap.ROUND,
        lineColor: 0xFFFF2D76,
        lineWidth: 2.5,
        lineOpacity: 0.42,
        lineDasharray: const <double?>[1.3, 2.2],
      ),
    );
    await style.addLayer(
      CircleLayer(
        id: 'share-poi-circles',
        sourceId: _poiSourceId,
        circleRadius: 11,
        circleColor: 0xFF951052,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 1.5,
      ),
    );
    await style.addLayer(
      SymbolLayer(
        id: 'share-poi-numbers',
        sourceId: _poiSourceId,
        textFieldExpression: const <Object>[
          'to-string',
          <Object>['get', 'number'],
        ],
        textFont: const <String>['Open Sans Bold', 'Arial Unicode MS Bold'],
        textSize: 12,
        textColor: 0xFFFFFFFF,
        textAnchor: TextAnchor.CENTER,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
    );
    await style.addLayer(
      CircleLayer(
        id: 'share-start-point',
        sourceId: _markerSourceId,
        filter: const <Object>[
          '==',
          <Object>['get', 'kind'],
          'start',
        ],
        circleRadius: 10,
        circleColor: 0xFF00C853,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 3,
      ),
    );
    await style.addLayer(
      CircleLayer(
        id: 'share-finish-point',
        sourceId: _markerSourceId,
        filter: const <Object>[
          '==',
          <Object>['get', 'kind'],
          'finish',
        ],
        circleRadius: 10,
        circleColor: 0xFFFF641F,
        circleStrokeColor: 0xFFFFFFFF,
        circleStrokeWidth: 3,
      ),
    );

    await style.addLayer(
      SymbolLayer(
        id: 'share-finish-flag-pole',
        sourceId: _markerSourceId,
        filter: const <Object>[
          '==',
          <Object>['get', 'kind'],
          'finish',
        ],
        textField: '│',
        textFont: const <String>['Arial Unicode MS Regular'],
        textSize: 21,
        textColor: 0xFF171A22,
        textHaloColor: 0xFFFFFFFF,
        textHaloWidth: 0.8,
        textOffset: const <double?>[0.58, -0.65],
        textAnchor: TextAnchor.BOTTOM_LEFT,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
    );
    await style.addLayer(
      SymbolLayer(
        id: 'share-finish-flag-checkers',
        sourceId: _markerSourceId,
        filter: const <Object>[
          '==',
          <Object>['get', 'kind'],
          'finish',
        ],
        textField: '▦',
        textFont: const <String>['Arial Unicode MS Regular'],
        textSize: 15,
        textColor: 0xFF171A22,
        textHaloColor: 0xFFFFFFFF,
        textHaloWidth: 0.8,
        textOffset: const <double?>[0.82, -1.48],
        textAnchor: TextAnchor.BOTTOM_LEFT,
        textAllowOverlap: true,
        textIgnorePlacement: true,
      ),
    );
    await style.addLayer(
      SymbolLayer(
        id: 'share-important-poi-labels',
        sourceId: _labelSourceId,
        textFieldExpression: const <Object>['get', 'name'],
        textFont: const <String>['Open Sans Bold', 'Arial Unicode MS Bold'],
        textSize: 13,
        textColor: 0xFF11162F,
        textHaloColor: 0xFFF9F7F1,
        textHaloWidth: 1.5,
        textOffset: const <double?>[0, 1.35],
        textAnchor: TextAnchor.TOP,
        textAllowOverlap: false,
        textIgnorePlacement: false,
      ),
    );
  }

  List<Map<String, Object?>> _importantLabelFeatures({
    required List<DiscoveredPoi> pois,
    required Position start,
    required Position end,
  }) {
    final named = pois
        .where((poi) => (poi.name ?? '').trim().isNotEmpty)
        .toList(growable: false);
    if (named.isEmpty) return const <Map<String, Object?>>[];

    final selected = <DiscoveredPoi>[];
    void addIfNew(DiscoveredPoi? poi) {
      if (poi == null || selected.any((item) => item.id == poi.id)) return;
      selected.add(poi);
    }

    addIfNew(_nearestPoi(named, start, maximumMeters: 180));
    addIfNew(
      named.cast<DiscoveredPoi?>().firstWhere(
        (poi) => poi?.isImportant ?? false,
        orElse: () => named[named.length ~/ 2],
      ),
    );
    addIfNew(_nearestPoi(named, end, maximumMeters: 180));

    return <Map<String, Object?>>[
      for (final poi in selected.take(3))
        _pointFeature(
          id: 'label-${poi.id}',
          position: poi.position,
          properties: <String, Object?>{'name': poi.name!.trim()},
        ),
    ];
  }

  List<Position> _cameraCoordinates({
    required ShareMapScene scene,
    required List<Position> routePoints,
    required _BoundaryData? boundary,
  }) {
    final coordinates = <Position>[...routePoints];
    for (final poi in scene.discoveredPois) {
      if (_isValidPosition(poi.position) &&
          _distanceToRouteMeters(poi.position, routePoints) <=
              _nearRoutePoiMeters) {
        coordinates.add(poi.position);
      }
    }

    final routeExtent = _extentMeters(routePoints);
    if (boundary != null &&
        boundary.positions.isNotEmpty &&
        _extentMeters(boundary.positions) <=
            math.max(_minimumRouteExtentMeters, routeExtent) * 2.4) {
      coordinates.addAll(boundary.positions);
    }

    if (_extentMeters(coordinates) < _minimumRouteExtentMeters) {
      final center = _geographicCenter(routePoints);
      for (final bearing in const <double>[0, 90, 180, 270]) {
        coordinates.add(
          _destination(
            center,
            bearingDegrees: bearing,
            distanceMeters: _minimumRouteExtentMeters / 2,
          ),
        );
      }
    }
    return coordinates;
  }

  _BoundaryData? _parseBoundary(String? rawGeoJson) {
    if (rawGeoJson == null || rawGeoJson.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(rawGeoJson);
      if (decoded is! Map<String, dynamic>) return null;
      final rings = <List<List<double>>>[];
      final positions = <Position>[];
      _collectBoundaryGeometry(decoded, rings, positions);
      if (rings.isEmpty || positions.length < 3) return null;

      final outerWorldRing = <List<double>>[
        <double>[-180, -85],
        <double>[180, -85],
        <double>[180, 85],
        <double>[-180, 85],
        <double>[-180, -85],
      ];
      final maskRings = <List<List<double>>>[
        _ensureWinding(outerWorldRing, clockwise: false),
        for (final ring in rings) _ensureWinding(ring, clockwise: true),
      ];
      final outsideMask = jsonEncode(<String, Object?>{
        'type': 'Feature',
        'properties': const <String, Object?>{},
        'geometry': <String, Object?>{
          'type': 'Polygon',
          'coordinates': maskRings,
        },
      });
      return _BoundaryData(
        geoJson: jsonEncode(decoded),
        positions: positions,
        outsideMaskGeoJson: outsideMask,
      );
    } on FormatException {
      return null;
    }
  }

  void _collectBoundaryGeometry(
    Map<String, dynamic> value,
    List<List<List<double>>> rings,
    List<Position> positions,
  ) {
    final type = value['type'];
    if (type == 'FeatureCollection') {
      for (final feature in (value['features'] as List<dynamic>? ?? const [])) {
        if (feature is Map<String, dynamic>) {
          _collectBoundaryGeometry(feature, rings, positions);
        }
      }
      return;
    }
    if (type == 'Feature') {
      final geometry = value['geometry'];
      if (geometry is Map<String, dynamic>) {
        _collectBoundaryGeometry(geometry, rings, positions);
      }
      return;
    }

    final coordinates = value['coordinates'];
    if (type == 'Polygon' && coordinates is List<dynamic>) {
      _addPolygonExterior(coordinates, rings, positions);
    } else if (type == 'MultiPolygon' && coordinates is List<dynamic>) {
      for (final polygon in coordinates) {
        if (polygon is List<dynamic>) {
          _addPolygonExterior(polygon, rings, positions);
        }
      }
    }
  }

  void _addPolygonExterior(
    List<dynamic> polygon,
    List<List<List<double>>> rings,
    List<Position> positions,
  ) {
    if (polygon.isEmpty || polygon.first is! List<dynamic>) return;
    final exterior = <List<double>>[];
    for (final coordinate in polygon.first as List<dynamic>) {
      if (coordinate is! List<dynamic> || coordinate.length < 2) continue;
      final lng = (coordinate[0] as num?)?.toDouble();
      final lat = (coordinate[1] as num?)?.toDouble();
      if (lng == null || lat == null) continue;
      final position = Position(lng, lat);
      if (!_isValidPosition(position)) continue;
      exterior.add(<double>[lng, lat]);
      positions.add(position);
    }
    if (exterior.length < 3) return;
    if (exterior.first[0] != exterior.last[0] ||
        exterior.first[1] != exterior.last[1]) {
      exterior.add(List<double>.from(exterior.first));
    }
    rings.add(exterior);
  }

  List<List<double>> _ensureWinding(
    List<List<double>> ring, {
    required bool clockwise,
  }) {
    var signedArea = 0.0;
    for (var index = 0; index < ring.length - 1; index++) {
      signedArea +=
          ring[index][0] * ring[index + 1][1] -
          ring[index + 1][0] * ring[index][1];
    }
    final isClockwise = signedArea < 0;
    return isClockwise == clockwise
        ? ring.map(List<double>.from).toList(growable: false)
        : ring.reversed.map(List<double>.from).toList(growable: false);
  }

  Map<String, Object?> _lineFeature({
    required String id,
    required List<Position> positions,
  }) {
    return <String, Object?>{
      'type': 'Feature',
      'id': id,
      'properties': const <String, Object?>{},
      'geometry': <String, Object?>{
        'type': 'LineString',
        'coordinates': <List<double>>[
          for (final position in positions)
            <double>[position.lng.toDouble(), position.lat.toDouble()],
        ],
      },
    };
  }

  Map<String, Object?> _pointFeature({
    required String id,
    required Position position,
    required Map<String, Object?> properties,
  }) {
    return <String, Object?>{
      'type': 'Feature',
      'id': id,
      'properties': properties,
      'geometry': <String, Object?>{
        'type': 'Point',
        'coordinates': <double>[
          position.lng.toDouble(),
          position.lat.toDouble(),
        ],
      },
    };
  }

  String _featureCollection(List<Map<String, Object?>> features) {
    return jsonEncode(<String, Object?>{
      'type': 'FeatureCollection',
      'features': features,
    });
  }

  List<Position> _validPositions(Iterable<Position> positions) {
    return positions.where(_isValidPosition).toList(growable: false);
  }

  bool _isValidPosition(Position position) {
    final lng = position.lng.toDouble();
    final lat = position.lat.toDouble();
    return lng.isFinite &&
        lat.isFinite &&
        lng >= -180 &&
        lng <= 180 &&
        lat >= -85 &&
        lat <= 85;
  }

  DiscoveredPoi? _nearestPoi(
    List<DiscoveredPoi> pois,
    Position position, {
    required double maximumMeters,
  }) {
    DiscoveredPoi? closest;
    var closestDistance = maximumMeters;
    for (final poi in pois) {
      final distance = _distanceMeters(position, poi.position);
      if (distance <= closestDistance) {
        closest = poi;
        closestDistance = distance;
      }
    }
    return closest;
  }

  double _distanceToRouteMeters(Position point, List<Position> route) {
    var closest = double.infinity;
    for (var index = 1; index < route.length; index++) {
      closest = math.min(
        closest,
        _distanceToSegmentMeters(point, route[index - 1], route[index]),
      );
    }
    return closest;
  }

  double _distanceToSegmentMeters(Position point, Position a, Position b) {
    final referenceLat = point.lat.toDouble() * math.pi / 180;
    double x(Position value) =>
        (value.lng.toDouble() - point.lng.toDouble()) *
        math.pi /
        180 *
        6371000 *
        math.cos(referenceLat);
    double y(Position value) =>
        (value.lat.toDouble() - point.lat.toDouble()) * math.pi / 180 * 6371000;
    final ax = x(a);
    final ay = y(a);
    final bx = x(b);
    final by = y(b);
    final dx = bx - ax;
    final dy = by - ay;
    final denominator = dx * dx + dy * dy;
    final t =
        denominator == 0
            ? 0.0
            : (-(ax * dx + ay * dy) / denominator).clamp(0.0, 1.0);
    final nearestX = ax + dx * t;
    final nearestY = ay + dy * t;
    return math.sqrt(nearestX * nearestX + nearestY * nearestY);
  }

  double _extentMeters(List<Position> positions) {
    if (positions.length < 2) return 0;
    var minLat = double.infinity;
    var maxLat = -double.infinity;
    var minLng = double.infinity;
    var maxLng = -double.infinity;
    for (final position in positions) {
      minLat = math.min(minLat, position.lat.toDouble());
      maxLat = math.max(maxLat, position.lat.toDouble());
      minLng = math.min(minLng, position.lng.toDouble());
      maxLng = math.max(maxLng, position.lng.toDouble());
    }
    return _distanceMeters(Position(minLng, minLat), Position(maxLng, maxLat));
  }

  Position _geographicCenter(List<Position> positions) {
    var x = 0.0;
    var y = 0.0;
    var z = 0.0;
    for (final position in positions) {
      final lat = position.lat.toDouble() * math.pi / 180;
      final lng = position.lng.toDouble() * math.pi / 180;
      x += math.cos(lat) * math.cos(lng);
      y += math.cos(lat) * math.sin(lng);
      z += math.sin(lat);
    }
    x /= positions.length;
    y /= positions.length;
    z /= positions.length;
    final lng = math.atan2(y, x);
    final hyp = math.sqrt(x * x + y * y);
    final lat = math.atan2(z, hyp);
    return Position(lng * 180 / math.pi, lat * 180 / math.pi);
  }

  Position _destination(
    Position origin, {
    required double bearingDegrees,
    required double distanceMeters,
  }) {
    const earthRadius = 6371000.0;
    final angularDistance = distanceMeters / earthRadius;
    final bearing = bearingDegrees * math.pi / 180;
    final lat1 = origin.lat.toDouble() * math.pi / 180;
    final lng1 = origin.lng.toDouble() * math.pi / 180;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angularDistance) +
          math.cos(lat1) * math.sin(angularDistance) * math.cos(bearing),
    );
    final lng2 =
        lng1 +
        math.atan2(
          math.sin(bearing) * math.sin(angularDistance) * math.cos(lat1),
          math.cos(angularDistance) - math.sin(lat1) * math.sin(lat2),
        );
    return Position(lng2 * 180 / math.pi, lat2 * 180 / math.pi);
  }

  double _distanceMeters(Position a, Position b) {
    const earthRadius = 6371000.0;
    final lat1 = a.lat.toDouble() * math.pi / 180;
    final lat2 = b.lat.toDouble() * math.pi / 180;
    final deltaLat = lat2 - lat1;
    final deltaLng = (b.lng.toDouble() - a.lng.toDouble()) * math.pi / 180;
    final value =
        math.sin(deltaLat / 2) * math.sin(deltaLat / 2) +
        math.cos(lat1) *
            math.cos(lat2) *
            math.sin(deltaLng / 2) *
            math.sin(deltaLng / 2);
    return earthRadius * 2 * math.atan2(math.sqrt(value), math.sqrt(1 - value));
  }

  void _validatePngDimensions(Uint8List bytes) {
    if (bytes.length < 24 ||
        bytes[0] != 0x89 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4E ||
        bytes[3] != 0x47) {
      throw StateError('Mapbox snapshot geçerli bir PNG değil.');
    }
    final data = ByteData.sublistView(bytes);
    final pngWidth = data.getUint32(16);
    final pngHeight = data.getUint32(20);
    if (pngWidth != width || pngHeight != height) {
      throw StateError(
        'Mapbox snapshot $pngWidth×$pngHeight üretildi; '
        '$width×$height bekleniyordu.',
      );
    }
  }

  Future<void> _writeDebugSnapshot(Uint8List bytes, String mapName) async {
    if (!kDebugMode) return;
    final safeName = mapName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final file = File(
      '${Directory.systemTemp.path}/kesfedio-share-map-'
      '${safeName.isEmpty ? 'preview' : safeName}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    debugPrint('[ShareMapSnapshot] Debug PNG: ${file.path}');
  }
}

class _BoundaryData {
  const _BoundaryData({
    required this.geoJson,
    required this.positions,
    required this.outsideMaskGeoJson,
  });

  final String geoJson;
  final List<Position> positions;
  final String? outsideMaskGeoJson;
}

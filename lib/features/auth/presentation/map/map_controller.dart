import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../domain/models/campus_map_state.dart';
import 'fog_manager.dart';
import 'map_areas.dart';
import 'location_service.dart';

class CampusMapController extends ChangeNotifier {
  CampusMapController({
    required this.fogManager,
    required this.locationService,
    required this.defaultCenter,
    this.initialUserPosition,
    this.restoredState,
    this.onPersistStateRequested,
    this.testMode = false,
  }) : _lastInsidePosition =
           restoredState?.lastInsidePosition ?? initialUserPosition,
       _currentZoom = restoredState?.zoom ?? 16.0,
       visitedPoiIds = restoredState?.visitedPoiIds.toList() ?? <String>[];

  static const String _fogSourceId = 'gtu-fog-source';
  static const String _fogLayerId = 'gtu-fog-layer';
  static const String _cloudSourceId = 'gtu-cloud-source';
  static const String _cloudLayerId = 'gtu-cloud-layer';

  final FogManager fogManager;
  final LocationService locationService;
  final Position defaultCenter;
  final Position? initialUserPosition;
  final CampusMapState? restoredState;
  final Future<void> Function(CampusMapState state)? onPersistStateRequested;
  final bool testMode;

  GeoJsonSource? _fogSource;
  GeoJsonSource? _cloudSource;
  CameraState? _latestCameraState;
  StreamSubscription<Position>? _locationSubscription;
  Timer? _fogUpdateDebounce;
  Timer? _revealAnimationTicker;
  Timer? _persistDebounce;
  final _poiTappedController = StreamController<Map<String, dynamic>>.broadcast();

  MapboxMap? _mapboxMap;
  bool _cameraCorrectionInFlight = false;
  bool _persistInFlight = false;
  bool _persistQueued = false;
  bool _isDisposed = false;
  int? _lastPersistFingerprint;

  List<String> visitedPoiIds;

  bool _styleReady = false;
  bool _trackingReady = false;
  bool _isOutOfCampus = false;
  String? _statusMessage;
  double _currentZoom;
  Position? _lastInsidePosition;
  String? _lastRenderedFogGeoJson;
  String? _lastRenderedCloudGeoJson;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;

  bool get styleReady => _styleReady;
  bool get trackingReady => _trackingReady;
  bool get isOutOfCampus => _isOutOfCampus;
  String? get statusMessage => _statusMessage;
  double get currentZoom => _currentZoom;
  int get revealedCellCount => fogManager.revealedCount;
  int get totalCellCount => fogManager.totalCount;

  double get minZoom => 14.8;
  double get maxZoom => 19.2;
  
  Stream<Map<String, dynamic>> get onPoiTapped => _poiTappedController.stream;

  Future<void> onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
  }

  Future<void> onStyleLoaded() async {
    final map = _mapboxMap;
    if (map == null) return;

    await fogManager.initialize();
    fogManager.restoreRevealedCells(
      restoredState?.revealedCellIds ?? const <String>[],
    );

    if (!testMode) {
      await map.setBounds(
        CameraBoundsOptions(
          bounds: fogManager.bounds.toCoordinateBounds(),
          minZoom: minZoom,
          maxZoom: maxZoom,
          minPitch: 0,
          maxPitch: 75,
        ),
      );

      await _upsertFogSourceAndLayer();
    }
    await _enableLocationPuck();

    _latestCameraState = await map.getCameraState();
    _currentZoom = _latestCameraState?.zoom ?? _currentZoom;
    _styleReady = true;
    notifyListeners();

    if (!testMode) {
      await _startLocationTracking();
      _scheduleFogRefresh();
      _schedulePersist(delay: const Duration(milliseconds: 500));
    }
  }

  void handleMapTap(MapContentGestureContext context) {
    final map = _mapboxMap;
    if (map == null || _isOutOfCampus) return;

    final touchPosition = context.touchPosition;
    unawaited(_queryTappedFeatures(touchPosition));
  }

  Future<void> _queryTappedFeatures(ScreenCoordinate touchPosition) async {
    final map = _mapboxMap;
    if (map == null) return;

    try {
      final features = await map.queryRenderedFeatures(
        RenderedQueryGeometry.fromScreenBox(
          ScreenBox(
            min: ScreenCoordinate(
              x: touchPosition.x - 20,
              y: touchPosition.y - 20,
            ),
            max: ScreenCoordinate(
              x: touchPosition.x + 20,
              y: touchPosition.y + 20,
            ),
          ),
        ),
        RenderedQueryOptions(
          layerIds: ['poi-circle-layer', 'poi-label-layer'],
          filter: null,
        ),
      );

      if (features.isNotEmpty) {
        final feature = features.first;
        if (feature == null) return;
        
        final queriedFeature = feature.queriedFeature;
        final properties = queriedFeature.feature['properties'];
        final id = queriedFeature.feature['id'];

        if (properties is Map) {
          final payload = Map<String, dynamic>.from(properties);
          if (id != null) {
            payload['_feature_id'] = id;
          }
          _poiTappedController.add(payload);
        }
      }
    } catch (_) {
      // Ignore query errors
    }
  }

  /// Adds POI markers as a circle + symbol layer from raw GeoJSON string.
  Future<void> addPoiGeoJsonLayer(String geoJson) async {
    final map = _mapboxMap;
    if (map == null) return;

    const sourceId = 'poi-source';
    const circleLayerId = 'poi-circle-layer';
    const labelLayerId = 'poi-label-layer';

    final source = GeoJsonSource(id: sourceId, data: geoJson);
    try {
      await map.style.addSource(source);
    } on PlatformException catch (e) {
      if (!_isAlreadyExistsError(e)) rethrow;
    }

    // --- Circle layer with color by type, size by rarity ---
    try {
      await map.style.addLayer(
        CircleLayer(
          id: circleLayerId,
          sourceId: sourceId,
          circleRadiusExpression: <Object>[
            'match',
            <Object>['get', 'rarity'],
            // New formats
            'must-see', 14.0,
            'önerilen', 10.0,
            // Fallback old formats
            'legendary', 14.0,
            'epic', 11.0,
            'rare', 8.0,
            // Default size
            6.0,
          ],
          circleColorExpression: <Object>[
            'match',
            <Object>['get', 'poi_type'],
            // Specific category colors based on new JSON
            'Cami', '#10B981', // Green
            'Saray', '#F59E0B', // Amber
            'Müze', '#3B82F6', // Blue
            'Tarihi Yapı', '#6B7280', // Gray
            'Meydan', '#F43F5E', // Rose
            'Hamam', '#06B6D4', // Cyan
            'Çarşı & Pazar', '#8B5CF6', // Purple
            'Park & Bahçe', '#84CC16', // Lime
            'Semt & Cadde', '#F97316', // Orange
            'Kule & Tepe', '#EF4444', // Red
            'Sinagog & Kilise', '#A855F7', // Violet
            
            // Fallback old colors
            'historic', '#FFB300',
            'museum', '#42A5F5',
            'park', '#66BB6A',
            'tower', '#EF5350',
            
            // Default color
            '#E0E0E0',
          ],
          circleStrokeWidth: 1.5,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
          circleOpacityExpression: <Object>[
            'case',
            <Object>['==', <Object>['get', 'visited'], true],
            0.4,
            0.92,
          ],
        ),
      );
    } on PlatformException catch (e) {
      if (!_isAlreadyExistsError(e)) rethrow;
    }

    // --- Label layer ---
    try {
      await map.style.addLayer(
        SymbolLayer(
          id: labelLayerId,
          sourceId: sourceId,
          textFieldExpression: <Object>['get', 'name'],
          textSize: 12.0,
          textColor: const Color(0xFFFFFFFF).toARGB32(),
          textHaloColor: const Color(0xFF000000).toARGB32(),
          textHaloWidth: 1.5,
          textOpacityExpression: <Object>[
            'case',
            <Object>['==', <Object>['get', 'visited'], true],
            0.5,
            1.0,
          ],
          textOffset: <double>[0, 1.6],
          textMaxWidth: 10.0,
          textAllowOverlap: false,
          iconAllowOverlap: false,
        ),
      );
    } on PlatformException catch (e) {
      if (!_isAlreadyExistsError(e)) rethrow;
    }
  }

  void onCameraChanged(CameraChangedEventData data) {
    _latestCameraState = data.cameraState;
    final zoom = data.cameraState.zoom;
    if ((zoom - _currentZoom).abs() > 0.01) {
      _currentZoom = zoom;
      notifyListeners();
    } else {
      _currentZoom = zoom;
    }

    final map = _mapboxMap;
    final center = data.cameraState.center.coordinates;
    if (!_cameraCorrectionInFlight &&
        map != null &&
        !fogManager.contains(center)) {
      _cameraCorrectionInFlight = true;
      final fallbackCenter = _lastInsidePosition ?? defaultCenter;
      unawaited(
        map
            .easeTo(
              CameraOptions(center: Point(coordinates: fallbackCenter)),
              MapAnimationOptions(duration: 220, startDelay: 0),
            )
            .whenComplete(() => _cameraCorrectionInFlight = false),
      );
      return;
    }

    _scheduleFogRefresh();
    _schedulePersist();
  }

  Future<void> zoomBy(double delta) async {
    if (_isOutOfCampus) return;
    final map = _mapboxMap;
    if (map == null) return;

    final targetZoom = (_currentZoom + delta).clamp(minZoom, maxZoom);
    if ((targetZoom - _currentZoom).abs() < 0.01) return;

    await map.easeTo(
      CameraOptions(zoom: targetZoom),
      MapAnimationOptions(duration: 260, startDelay: 0),
    );
  }

  Future<void> disposeController() async {
    _persistDebounce?.cancel();
    _fogUpdateDebounce?.cancel();
    _revealAnimationTicker?.cancel();
    await _locationSubscription?.cancel();
    unawaited(_poiTappedController.close());
    await _persistState(force: true);
    _isDisposed = true;
    await locationService.dispose();
  }

  Future<void> _upsertFogSourceAndLayer() async {
    final map = _mapboxMap;
    if (map == null) return;

    _fogSource = GeoJsonSource(id: _fogSourceId, data: _emptyFeatureCollection);

    try {
      await map.style.addSource(_fogSource!);
    } on PlatformException catch (e) {
      if (_isAlreadyExistsError(e)) {
        final existingSource = await map.style.getSource(_fogSourceId);
        if (existingSource is GeoJsonSource) {
          _fogSource = existingSource;
        }
      } else {
        rethrow;
      }
    }
    await _fogSource?.updateGeoJSON(_emptyFeatureCollection);
    _lastRenderedFogGeoJson = _emptyFeatureCollection;

    try {
      await map.style.addLayer(
        FillLayer(
          id: _fogLayerId,
          sourceId: _fogSourceId,
          fillAntialias: false,
          fillColor: const Color(0xFFFFFFFF).toARGB32(),
          fillOpacityExpression: <Object>[
            '*',
            <Object>[
              'coalesce',
              <Object>['get', 'opacity'],
              fogManager.baseFogOpacity,
            ],
            0.06,
          ],
        ),
      );
    } on PlatformException catch (e) {
      if (!_isAlreadyExistsError(e)) {
        rethrow;
      }
    }

    _cloudSource = GeoJsonSource(
      id: _cloudSourceId,
      data: _emptyFeatureCollection,
    );
    try {
      await map.style.addSource(_cloudSource!);
    } on PlatformException catch (e) {
      if (_isAlreadyExistsError(e)) {
        final existingSource = await map.style.getSource(_cloudSourceId);
        if (existingSource is GeoJsonSource) {
          _cloudSource = existingSource;
        }
      } else {
        rethrow;
      }
    }
    await _cloudSource?.updateGeoJSON(_emptyFeatureCollection);
    _lastRenderedCloudGeoJson = _emptyFeatureCollection;

    try {
      await map.style.addLayer(
        CircleLayer(
          id: _cloudLayerId,
          sourceId: _cloudSourceId,
          circleColor: const Color(0xFFFFFFFF).toARGB32(),
          circleBlur: 0.96,
          circleOpacityExpression: <Object>[
            'min',
            0.95,
            <Object>[
              '*',
              <Object>[
                'coalesce',
                <Object>['get', 'opacity'],
                0.0,
              ],
              1.35,
            ],
          ],
          circleRadiusExpression: <Object>[
            'coalesce',
            <Object>['get', 'radius'],
            24.0,
          ],
        ),
      );
    } on PlatformException catch (e) {
      if (!_isAlreadyExistsError(e)) {
        rethrow;
      }
    }
  }

  Future<void> _startLocationTracking() async {
    _trackingReady = await locationService.start();
    if (!_trackingReady) {
      _statusMessage = 'Konum izni gerekli. Lütfen konum erişimini aç.';
      notifyListeners();
      return;
    }

    _statusMessage = null;
    notifyListeners();

    _locationSubscription?.cancel();
    _locationSubscription = locationService.positionStream.listen(
      _onLocationUpdate,
    );
  }

  Future<void> _onLocationUpdate(Position currentLocation) async {
    final map = _mapboxMap;
    if (map == null || !_styleReady) return;

    final insideCampus = fogManager.contains(currentLocation);
    if (!insideCampus) {
      if (!_isOutOfCampus) {
        _isOutOfCampus = true;
        _revealAnimationTicker?.cancel();
        _revealAnimationTicker = null;
        await _setMapInteractionEnabled(false);
        notifyListeners();
      }
      return;
    }

    if (_isOutOfCampus) {
      _isOutOfCampus = false;
      await _setMapInteractionEnabled(true);
      notifyListeners();
    }

    final revealed = fogManager.revealForPosition(currentLocation);
    if (revealed) {
      _startRevealAnimationTicker();
      _scheduleFogRefresh(delay: const Duration(milliseconds: 16));
      _schedulePersist(delay: const Duration(milliseconds: 600));
      notifyListeners();
    } else if (fogManager.hasPendingRevealAnimation) {
      _startRevealAnimationTicker();
    }

    final shouldMoveCamera =
        _lastInsidePosition == null ||
        haversineDistanceMeters(_lastInsidePosition!, currentLocation) > 8;

    if (shouldMoveCamera) {
      _lastInsidePosition = currentLocation;
      _schedulePersist();
      await map.easeTo(
        CameraOptions(center: Point(coordinates: currentLocation)),
        MapAnimationOptions(duration: 1000, startDelay: 0),
      );
    }
  }

  Future<void> _setMapInteractionEnabled(bool enabled) async {
    final map = _mapboxMap;
    if (map == null) return;

    await map.gestures.updateSettings(
      GesturesSettings(
        scrollEnabled: enabled,
        pinchToZoomEnabled: enabled,
        rotateEnabled: false,
        pitchEnabled: false,
        quickZoomEnabled: enabled,
        doubleTapToZoomInEnabled: enabled,
        doubleTouchToZoomOutEnabled: enabled,
        simultaneousRotateAndPinchToZoomEnabled: false,
        pinchPanEnabled: enabled,
      ),
    );
  }

  void _scheduleFogRefresh({
    Duration delay = const Duration(milliseconds: 120),
  }) {
    _fogUpdateDebounce?.cancel();
    _fogUpdateDebounce = Timer(delay, _refreshFog);
  }

  Future<void> _refreshFog() async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }

    _refreshInFlight = true;
    final map = _mapboxMap;
    final fogSource = _fogSource;
    final cloudSource = _cloudSource;
    final cameraState = _latestCameraState;

    if (map == null ||
        fogSource == null ||
        cloudSource == null ||
        cameraState == null) {
      _refreshInFlight = false;
      return;
    }

    try {
      final bounds = await map.coordinateBoundsForCamera(
        cameraState.toCameraOptions(),
      );
      final geoJson = fogManager.geoJsonForViewport(
        southwest: bounds.southwest.coordinates,
        northeast: bounds.northeast.coordinates,
      );
      if (geoJson != _lastRenderedFogGeoJson) {
        await fogSource.updateGeoJSON(geoJson);
        _lastRenderedFogGeoJson = geoJson;
      }

      final cloudGeoJson = fogManager.cloudGeoJsonForViewport(
        southwest: bounds.southwest.coordinates,
        northeast: bounds.northeast.coordinates,
      );
      if (cloudGeoJson != _lastRenderedCloudGeoJson) {
        await cloudSource.updateGeoJSON(cloudGeoJson);
        _lastRenderedCloudGeoJson = cloudGeoJson;
      }
    } finally {
      _refreshInFlight = false;
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(_refreshFog());
      }
    }
  }

  String get _emptyFeatureCollection =>
      '{"type":"FeatureCollection","features":[]}';

  bool _isAlreadyExistsError(PlatformException error) {
    final message =
        '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
    return message.contains('already exists') || message.contains('exists');
  }

  Future<void> _enableLocationPuck() async {
    final map = _mapboxMap;
    if (map == null) return;
    try {
      await map.location.updateSettings(
        LocationComponentSettings(
          enabled: true,
          pulsingEnabled: false,
          pulsingColor: const Color(0xFF00D7FF).toARGB32(),
          pulsingMaxRadius: 34,
          showAccuracyRing: false,
          accuracyRingColor: const Color(0x4400D7FF).toARGB32(),
          accuracyRingBorderColor: const Color(0xCC00D7FF).toARGB32(),
          puckBearingEnabled: true,
          puckBearing: PuckBearing.HEADING,
        ),
      );
    } on PlatformException {
      // Location puck setup failure should not block map rendering.
    }
  }

  void _startRevealAnimationTicker() {
    if (_revealAnimationTicker?.isActive ?? false) {
      return;
    }

    _revealAnimationTicker = Timer.periodic(const Duration(milliseconds: 70), (
      _,
    ) {
      if (_isOutOfCampus || !_styleReady) {
        return;
      }

      final changed = fogManager.advanceRevealAnimationStep();
      if (!changed) {
        _revealAnimationTicker?.cancel();
        _revealAnimationTicker = null;
        return;
      }

      _scheduleFogRefresh(delay: const Duration(milliseconds: 16));
      _schedulePersist(delay: const Duration(milliseconds: 600));
    });
  }

  void _schedulePersist({Duration delay = const Duration(seconds: 2)}) {
    if (_isDisposed || onPersistStateRequested == null) return;

    _persistDebounce?.cancel();
    _persistDebounce = Timer(delay, () => unawaited(_persistState()));
  }

  Future<void> _persistState({bool force = false}) async {
    final persistCallback = onPersistStateRequested;
    if (_isDisposed || persistCallback == null) return;

    final snapshot = _buildSnapshot();
    final fingerprint = _snapshotFingerprint(snapshot);
    if (!force && _lastPersistFingerprint == fingerprint) {
      return;
    }

    if (_persistInFlight) {
      _persistQueued = true;
      return;
    }

    _persistInFlight = true;
    try {
      await persistCallback(snapshot);
      _lastPersistFingerprint = fingerprint;
    } catch (_) {
      // Persistence failures should not block the map experience.
    } finally {
      _persistInFlight = false;
      if (_persistQueued) {
        _persistQueued = false;
        unawaited(_persistState());
      }
    }
  }

  CampusMapState _buildSnapshot() {
    return CampusMapState(
      revealedCellIds: fogManager.snapshotRevealedCellIds(),
      visitedPoiIds: visitedPoiIds,
      lastInsidePosition: _lastInsidePosition,
      cameraCenter: _latestCameraState?.center.coordinates,
      zoom: _latestCameraState?.zoom ?? _currentZoom,
    );
  }

  int _snapshotFingerprint(CampusMapState snapshot) {
    return Object.hash(
      _positionFingerprint(snapshot.lastInsidePosition),
      _positionFingerprint(snapshot.cameraCenter),
      snapshot.zoom?.toStringAsFixed(3),
      Object.hashAll(snapshot.revealedCellIds),
    );
  }

  String _positionFingerprint(Position? position) {
    if (position == null) return '';
    return '${position.lat.toStringAsFixed(6)},${position.lng.toStringAsFixed(6)}';
  }
}

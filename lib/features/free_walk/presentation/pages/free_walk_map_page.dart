import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/location_disclosure_dialog.dart';
import '../../../auth/presentation/map/location_service.dart';
import '../../../daily_exploration/data/services/share_map_snapshot_service.dart';
import '../../data/services/free_walk_history_service.dart';
import '../../domain/free_walk_tracker.dart';
import '../../domain/models/free_walk_result.dart';
import '../widgets/free_walk_summary_sheet.dart';
import 'free_walk_share_preview_page.dart';

enum _FreeWalkRunState { idle, active, paused, finished }

class FreeWalkMapPage extends StatefulWidget {
  const FreeWalkMapPage({super.key});

  @override
  State<FreeWalkMapPage> createState() => _FreeWalkMapPageState();
}

class _FreeWalkMapPageState extends State<FreeWalkMapPage> {
  static const String _routeSourceId = 'free-walk-route-source';
  static const String _userSourceId = 'free-walk-user-source';
  static const Color _ink = Color(0xFF11102F);
  static const Color _pink = Color(0xFFFF176B);
  static const Color _orange = Color(0xFFFF5A36);

  final FreeWalkTracker _tracker = FreeWalkTracker();
  final Stopwatch _activeStopwatch = Stopwatch();
  final FreeWalkHistoryService _historyService = FreeWalkHistoryService();
  final ShareMapSnapshotService _shareMapSnapshotService =
      const ShareMapSnapshotService();

  DateTime? _walkStartedAt;
  Position? _userPosition;
  MapboxMap? _mapboxMap;
  GeoJsonSource? _routeSource;
  GeoJsonSource? _userSource;
  StreamSubscription<geo.Position>? _trackingSubscription;
  Timer? _clockTimer;
  LocationAccessStatus? _locationError;
  _FreeWalkRunState _runState = _FreeWalkRunState.idle;

  bool _isLocating = true;
  bool _locationConsumerRegistered = false;
  bool _controlsLocked = false;
  bool _followUser = true;
  bool _routeUpdateInFlight = false;
  bool _routeUpdateQueued = false;
  double? _gpsAccuracy;
  String _mapStyleUri = MapboxStyles.OUTDOORS;
  DateTime? _lastCameraMoveAt;

  bool get _hasInProgressWalk =>
      _runState == _FreeWalkRunState.active ||
      _runState == _FreeWalkRunState.paused;

  bool get _isActive => _runState == _FreeWalkRunState.active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_locateUser());
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    unawaited(_trackingSubscription?.cancel());
    if (_locationConsumerRegistered) {
      LocationService().unregisterConsumer();
    }
    super.dispose();
  }

  Future<bool> _showLocationDisclosure() async {
    if (!mounted) return false;
    return showLocationDisclosureDialog(context);
  }

  Future<void> _locateUser() async {
    if (!_isLocating && mounted) {
      setState(() {
        _isLocating = true;
        _locationError = null;
      });
    }

    final result = await LocationService.requestSinglePosition(
      requestDisclosureConsent: _showLocationDisclosure,
    );
    if (!mounted) return;

    if (result.isGranted) {
      setState(() {
        _userPosition = result.position;
        _locationError = null;
        _isLocating = false;
      });
      return;
    }

    setState(() {
      _locationError = result.status;
      _isLocating = false;
    });
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
    try {
      await mapboxMap.gestures.updateSettings(
        GesturesSettings(
          scrollEnabled: true,
          pinchToZoomEnabled: true,
          rotateEnabled: false,
          pitchEnabled: false,
          quickZoomEnabled: true,
          doubleTapToZoomInEnabled: true,
          doubleTouchToZoomOutEnabled: true,
          simultaneousRotateAndPinchToZoomEnabled: false,
          pinchPanEnabled: true,
        ),
      );
      await mapboxMap.compass.updateSettings(CompassSettings(enabled: false));
      await mapboxMap.scaleBar.updateSettings(
        ScaleBarSettings(
          position: OrnamentPosition.BOTTOM_LEFT,
          marginLeft: 12,
          marginBottom: 12,
        ),
      );
    } catch (_) {
      // Ornament and gesture configuration is best-effort.
    }
  }

  Future<void> _onStyleLoaded() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    _routeSource = null;
    _userSource = null;

    try {
      await mapboxMap.location.updateSettings(
        LocationComponentSettings(enabled: false),
      );
    } catch (_) {
      // The map remains usable even if the native location puck is unavailable.
    }

    await _createRouteLayers(mapboxMap);
    await _createUserLocationLayers(mapboxMap);
    await _refreshRoute();
    await _refreshUserLocation();
  }

  Future<void> _createRouteLayers(MapboxMap mapboxMap) async {
    final style = mapboxMap.style;
    var source = GeoJsonSource(
      id: _routeSourceId,
      data: _emptyFeatureCollection,
    );
    try {
      await style.addSource(source);
    } on PlatformException {
      final existing = await style.getSource(_routeSourceId);
      if (existing is! GeoJsonSource) return;
      source = existing;
    }
    _routeSource = source;

    final layers = <LineLayer>[
      LineLayer(
        id: 'free-walk-route-glow',
        sourceId: _routeSourceId,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineColor: _pink.toARGB32(),
        lineWidth: 18,
        lineOpacity: 0.24,
        lineBlur: 9,
      ),
      LineLayer(
        id: 'free-walk-route-main',
        sourceId: _routeSourceId,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineColor: _pink.toARGB32(),
        lineWidth: 8,
      ),
      LineLayer(
        id: 'free-walk-route-center',
        sourceId: _routeSourceId,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
        lineColor: Colors.white.toARGB32(),
        lineWidth: 2.4,
        lineOpacity: 0.96,
      ),
    ];

    for (final layer in layers) {
      try {
        await style.addLayer(layer);
      } on PlatformException {
        // A repeated style callback can encounter an already-added layer.
      }
    }
  }

  Future<void> _createUserLocationLayers(MapboxMap mapboxMap) async {
    final style = mapboxMap.style;
    var source = GeoJsonSource(id: _userSourceId, data: _userLocationGeoJson());
    try {
      await style.addSource(source);
    } on PlatformException {
      final existing = await style.getSource(_userSourceId);
      if (existing is! GeoJsonSource) return;
      source = existing;
    }
    _userSource = source;

    final layers = <CircleLayer>[
      CircleLayer(
        id: 'free-walk-user-accuracy',
        sourceId: _userSourceId,
        circleRadius: 28,
        circleColor: const Color(0xFF2E7DEB).toARGB32(),
        circleOpacity: 0.16,
        circleStrokeColor: const Color(0x332E7DEB).toARGB32(),
        circleStrokeWidth: 1,
      ),
      CircleLayer(
        id: 'free-walk-user-puck',
        sourceId: _userSourceId,
        circleRadius: 9,
        circleColor: const Color(0xFF2E7DEB).toARGB32(),
        circleStrokeColor: Colors.white.toARGB32(),
        circleStrokeWidth: 4,
      ),
    ];
    for (final layer in layers) {
      try {
        await style.addLayer(layer);
      } on PlatformException {
        // A repeated style callback can encounter an already-added layer.
      }
    }
  }

  Future<void> _startWalk() async {
    if (_runState == _FreeWalkRunState.finished) {
      await _resetWalk();
    }

    final locationService = LocationService(
      pollingInterval: const Duration(seconds: 3),
      requestDisclosureConsent: _showLocationDisclosure,
    );
    if (!_locationConsumerRegistered) {
      locationService.registerConsumer();
      _locationConsumerRegistered = true;
    }

    await _trackingSubscription?.cancel();
    _trackingSubscription = locationService.trackingStream.listen(
      _onTrackingPosition,
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GPS bağlantısı geçici olarak kesildi.'),
          ),
        );
      },
      cancelOnError: false,
    );

    final started = await locationService.start();
    if (!started) {
      await _trackingSubscription?.cancel();
      _trackingSubscription = null;
      if (_locationConsumerRegistered) {
        locationService.unregisterConsumer();
        _locationConsumerRegistered = false;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yürüyüşü başlatmak için konum izni gerekli.'),
          ),
        );
      }
      return;
    }

    _tracker.start();
    _activeStopwatch
      ..reset()
      ..start();
    _walkStartedAt = DateTime.now();
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isActive) setState(() {});
    });
    if (!mounted) return;
    setState(() {
      _runState = _FreeWalkRunState.active;
      _controlsLocked = false;
      _followUser = true;
    });
  }

  void _onTrackingPosition(geo.Position position) {
    if (!mounted) return;
    final mapPosition = Position(position.longitude, position.latitude);
    final point = FreeWalkPoint(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp.toLocal(),
    );
    final decision = _tracker.add(point);

    setState(() {
      _userPosition = mapPosition;
      _gpsAccuracy = position.accuracy;
    });
    unawaited(_refreshUserLocation());

    if (decision == FreeWalkPointDecision.accepted) {
      unawaited(_refreshRoute());
      if (_followUser) unawaited(_moveCameraTo(mapPosition));
    }
  }

  void _pauseWalk() {
    if (!_isActive || _controlsLocked) return;
    _tracker.pause();
    _activeStopwatch.stop();
    setState(() => _runState = _FreeWalkRunState.paused);
  }

  void _resumeWalk() {
    if (_runState != _FreeWalkRunState.paused || _controlsLocked) return;
    _tracker.resume();
    _activeStopwatch.start();
    setState(() {
      _runState = _FreeWalkRunState.active;
      _followUser = true;
    });
  }

  Future<void> _requestFinishWalk() async {
    if (!_hasInProgressWalk || _controlsLocked) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const _FinishWalkDialog(),
    );
    if (confirmed != true || !mounted) return;

    _tracker.pause();
    _activeStopwatch.stop();
    _clockTimer?.cancel();
    await _stopLocationTracking();
    if (!mounted) return;

    final startedAt = _walkStartedAt ?? DateTime.now();
    final segments = _tracker.segments;
    final distanceMeters = _tracker.distanceMeters;
    final durationSeconds = _activeStopwatch.elapsed.inSeconds;

    setState(() {
      _runState = _FreeWalkRunState.finished;
      _controlsLocked = false;
    });

    unawaited(
      _finishWalkFlow(
        startedAt: startedAt,
        endedAt: DateTime.now(),
        segments: segments,
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
      ),
    );
  }

  Future<void> _finishWalkFlow({
    required DateTime startedAt,
    required DateTime endedAt,
    required List<List<FreeWalkPoint>> segments,
    required double distanceMeters,
    required int durationSeconds,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    var result = FreeWalkResult(
      id: '',
      userId: uid ?? '',
      startedAt: startedAt,
      endedAt: endedAt,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      segments: segments,
    );
    if (uid != null && result.hasRoute) {
      try {
        result = await _historyService.saveWalk(
          uid: uid,
          startedAt: startedAt,
          endedAt: endedAt,
          distanceMeters: distanceMeters,
          durationSeconds: durationSeconds,
          segments: segments,
        );
      } catch (error) {
        debugPrint('[FreeWalk] Yürüyüş kaydedilemedi: $error');
      }
    }
    if (!mounted) return;

    final action = await FreeWalkSummarySheet.show(context, result);
    if (!mounted || action != FreeWalkSummaryAction.share) return;

    try {
      final scene = result.toShareScene();
      final mapSnapshot = await _shareMapSnapshotService.createSnapshot(
        scene,
        styleUri: MapboxStyles.OUTDOORS,
      );
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder:
              (_) => FreeWalkSharePreviewPage(
                result: result,
                initialMapSnapshot: mapSnapshot,
                createMapSnapshot:
                    () => _shareMapSnapshotService.createSnapshot(
                      scene,
                      styleUri: MapboxStyles.OUTDOORS,
                    ),
              ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint('[FreeWalk] Kart oluşturulamadı: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kart oluşturulamadı: $error')),
      );
    }
  }

  Future<void> _resetWalk() async {
    _clockTimer?.cancel();
    _activeStopwatch
      ..stop()
      ..reset();
    _tracker.reset();
    _walkStartedAt = null;
    await _stopLocationTracking();
    if (!mounted) return;
    setState(() {
      _runState = _FreeWalkRunState.idle;
      _controlsLocked = false;
      _gpsAccuracy = null;
    });
    await _refreshRoute();
  }

  Future<void> _stopLocationTracking() async {
    await _trackingSubscription?.cancel();
    _trackingSubscription = null;
    if (_locationConsumerRegistered) {
      LocationService().unregisterConsumer();
      _locationConsumerRegistered = false;
    }
  }

  Future<void> _refreshRoute() async {
    if (_routeUpdateInFlight) {
      _routeUpdateQueued = true;
      return;
    }
    _routeUpdateInFlight = true;
    try {
      await _routeSource?.updateGeoJSON(_routeGeoJson());
    } catch (_) {
      // A style reload can temporarily invalidate the previous source.
    } finally {
      _routeUpdateInFlight = false;
      if (_routeUpdateQueued) {
        _routeUpdateQueued = false;
        unawaited(_refreshRoute());
      }
    }
  }

  String _routeGeoJson() {
    final coordinates = <List<List<double>>>[
      for (final segment in _tracker.segments)
        if (segment.length >= 2)
          <List<double>>[
            for (final point in segment)
              <double>[point.longitude, point.latitude],
          ],
    ];
    if (coordinates.isEmpty) return _emptyFeatureCollection;

    return jsonEncode(<String, Object>{
      'type': 'FeatureCollection',
      'features': <Object>[
        <String, Object>{
          'type': 'Feature',
          'properties': const <String, Object>{},
          'geometry': <String, Object>{
            'type': 'MultiLineString',
            'coordinates': coordinates,
          },
        },
      ],
    });
  }

  Future<void> _refreshUserLocation() async {
    try {
      await _userSource?.updateGeoJSON(_userLocationGeoJson());
    } catch (_) {
      // A style reload can temporarily invalidate the previous source.
    }
  }

  String _userLocationGeoJson() {
    final position = _userPosition;
    if (position == null) return _emptyFeatureCollection;
    return jsonEncode(<String, Object>{
      'type': 'FeatureCollection',
      'features': <Object>[
        <String, Object>{
          'type': 'Feature',
          'properties': const <String, Object>{},
          'geometry': <String, Object>{
            'type': 'Point',
            'coordinates': <double>[
              position.lng.toDouble(),
              position.lat.toDouble(),
            ],
          },
        },
      ],
    });
  }

  String get _emptyFeatureCollection =>
      '{"type":"FeatureCollection","features":[]}';

  Future<void> _moveCameraTo(Position position, {bool force = false}) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    final now = DateTime.now();
    if (!force &&
        _lastCameraMoveAt != null &&
        now.difference(_lastCameraMoveAt!) <
            const Duration(milliseconds: 650)) {
      return;
    }
    _lastCameraMoveAt = now;
    await mapboxMap.easeTo(
      CameraOptions(
        center: Point(coordinates: position),
        zoom: 16,
        bearing: 0,
        pitch: 0,
      ),
      MapAnimationOptions(duration: 500, startDelay: 0),
    );
  }

  Future<void> _recenter() async {
    final current = _userPosition;
    if (current == null) return;
    setState(() => _followUser = true);
    await _moveCameraTo(current, force: true);
  }

  Future<void> _toggleMapStyle() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) return;
    final next =
        _mapStyleUri == MapboxStyles.OUTDOORS
            ? MapboxStyles.LIGHT
            : MapboxStyles.OUTDOORS;
    _mapStyleUri = next;
    await mapboxMap.loadStyleURI(next);
    if (mounted) setState(() {});
  }

  Future<void> _showMoreMenu() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFFFFCF8),
      builder:
          (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.layers_rounded, color: _pink),
                    title: const Text('Harita görünümünü değiştir'),
                    subtitle: Text(
                      _mapStyleUri == MapboxStyles.OUTDOORS
                          ? 'Açık haritaya geç'
                          : 'Doğa haritasına geç',
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_toggleMapStyle());
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.my_location_rounded,
                      color: _pink,
                    ),
                    title: const Text('Konumuma dön'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_recenter());
                    },
                  ),
                  if (_runState == _FreeWalkRunState.finished)
                    ListTile(
                      leading: const Icon(
                        Icons.refresh_rounded,
                        color: _orange,
                      ),
                      title: const Text('Yeni yürüyüş hazırla'),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        unawaited(_resetWalk());
                      },
                    ),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _handleBack() async {
    if (!_hasInProgressWalk) {
      Navigator.of(context).pop();
      return;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Yürüyüş devam ediyor'),
            content: const Text(
              'Çıkarsan bu yürüyüşün mevcut kaydı silinecek.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Kal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Çık'),
              ),
            ],
          ),
    );
    if (shouldExit != true || !mounted) return;
    await _resetWalk();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openRelevantSettings() async {
    if (_locationError == LocationAccessStatus.serviceDisabled) {
      await geo.Geolocator.openLocationSettings();
      return;
    }
    await LocationService.openSettings();
  }

  String get _errorTitle => switch (_locationError) {
    LocationAccessStatus.serviceDisabled => 'Konum servisi kapalı',
    LocationAccessStatus.permissionDenied => 'Konum izni gerekli',
    LocationAccessStatus.permissionDeniedForever => 'Konum izni kapatılmış',
    _ => 'Konumun alınamadı',
  };

  String get _errorMessage => switch (_locationError) {
    LocationAccessStatus.serviceDisabled =>
      'Bulunduğun yerin haritasını açmak için cihazının konum servisini etkinleştir.',
    LocationAccessStatus.permissionDenied =>
      'Serbest yürüyüş haritasını bulunduğun konumda açabilmemiz için konum izni ver.',
    LocationAccessStatus.permissionDeniedForever =>
      'Konum izni cihaz ayarlarından kapatılmış. Ayarlardan izin verdikten sonra tekrar dene.',
    _ =>
      'GPS sinyali şu anda alınamıyor. Açık bir alanda tekrar deneyebilirsin.',
  };

  String get _gpsLabel {
    final accuracy = _gpsAccuracy;
    if (accuracy == null) return 'Konum bulundu';
    if (accuracy <= 15) return 'GPS güçlü';
    if (accuracy <= 30) return 'GPS orta';
    return 'GPS zayıf';
  }

  Color get _gpsColor {
    final accuracy = _gpsAccuracy;
    if (accuracy == null || accuracy <= 15) return const Color(0xFF19A85B);
    if (accuracy <= 30) return const Color(0xFFF4A62A);
    return const Color(0xFFE14C4C);
  }

  String get _activityLabel => switch (_runState) {
    _FreeWalkRunState.idle => 'Yürüyüş için hazır',
    _FreeWalkRunState.active =>
      _controlsLocked ? 'Kontroller kilitli' : 'Yürüyüş devam ediyor',
    _FreeWalkRunState.paused =>
      _controlsLocked ? 'Kontroller kilitli' : 'Yürüyüş duraklatıldı',
    _FreeWalkRunState.finished => 'Yürüyüş tamamlandı',
  };

  IconData get _activityIcon => switch (_runState) {
    _FreeWalkRunState.idle => Icons.directions_walk_rounded,
    _FreeWalkRunState.active => Icons.fiber_manual_record_rounded,
    _FreeWalkRunState.paused => Icons.pause_rounded,
    _FreeWalkRunState.finished => Icons.check_rounded,
  };

  String get _durationLabel {
    final elapsed = _activeStopwatch.elapsed;
    final hours = elapsed.inHours.toString().padLeft(2, '0');
    final minutes = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  String get _distanceLabel =>
      (_tracker.distanceMeters / 1000).toStringAsFixed(2).replaceAll('.', ',');

  String get _paceLabel {
    if (_tracker.distanceMeters < 50) return "--'--\"";
    final secondsPerKm =
        _activeStopwatch.elapsed.inSeconds / (_tracker.distanceMeters / 1000);
    final minutes = secondsPerKm ~/ 60;
    final seconds = (secondsPerKm.round() % 60).toString().padLeft(2, '0');
    return "$minutes'$seconds\"";
  }

  @override
  Widget build(BuildContext context) {
    final position = _userPosition;
    if (_isLocating || position == null) {
      return Scaffold(
        backgroundColor: AppColors.bgBottom,
        appBar: AppBar(
          backgroundColor: AppColors.bgTop,
          foregroundColor: AppColors.textMain,
          title: const Text('Serbest Yürüyüş'),
        ),
        body:
            _isLocating
                ? const _LocatingView()
                : _LocationErrorView(
                  title: _errorTitle,
                  message: _errorMessage,
                  showSettings:
                      _locationError == LocationAccessStatus.serviceDisabled ||
                      _locationError ==
                          LocationAccessStatus.permissionDeniedForever,
                  onSettings: _openRelevantSettings,
                  onRetry: _locateUser,
                ),
      );
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final panelHeight = (screenHeight * 0.39).clamp(310.0, 382.0);
    final topInset = MediaQuery.paddingOf(context).top;

    return PopScope(
      canPop: !_hasInProgressWalk,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF0EFE9),
        body: Stack(
          children: [
            Positioned.fill(
              child: MapWidget(
                key: const ValueKey('free-walk-map'),
                styleUri: _mapStyleUri,
                cameraOptions: CameraOptions(
                  center: Point(coordinates: position),
                  zoom: 16,
                  bearing: 0,
                  pitch: 0,
                ),
                onMapCreated:
                    (mapboxMap) => unawaited(_onMapCreated(mapboxMap)),
                onStyleLoadedListener: (_) => unawaited(_onStyleLoaded()),
                onScrollListener: (_) {
                  if (_followUser) setState(() => _followUser = false);
                },
              ),
            ),
            Positioned(
              top: topInset + 12,
              left: 16,
              right: 16,
              child: _TopBar(
                gpsLabel: _gpsLabel,
                gpsColor: _gpsColor,
                onBack: _handleBack,
                onMore: _showMoreMenu,
              ),
            ),
            Positioned(
              top: topInset + 90,
              left: 0,
              right: 0,
              child: Center(
                child: _ActivityStatusPill(
                  icon: _activityIcon,
                  label: _activityLabel,
                  active: _isActive,
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: panelHeight + 18,
              child: Column(
                children: [
                  _MapActionButton(
                    tooltip: 'Harita görünümünü değiştir',
                    icon: Icons.layers_rounded,
                    onPressed: _toggleMapStyle,
                  ),
                  const SizedBox(height: 12),
                  _MapActionButton(
                    tooltip: 'Konumuma dön',
                    icon: Icons.my_location_rounded,
                    selected: _followUser,
                    onPressed: _recenter,
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: panelHeight + safeBottom,
              child: _WalkSummaryPanel(
                runState: _runState,
                duration: _durationLabel,
                distance: _distanceLabel,
                pace: _paceLabel,
                controlsLocked: _controlsLocked,
                onToggleLock:
                    _hasInProgressWalk
                        ? () =>
                            setState(() => _controlsLocked = !_controlsLocked)
                        : null,
                onStart: _startWalk,
                onPause: _pauseWalk,
                onResume: _resumeWalk,
                onFinish: _requestFinishWalk,
                onReset: _resetWalk,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.gpsLabel,
    required this.gpsColor,
    required this.onBack,
    required this.onMore,
  });

  final String gpsLabel;
  final Color gpsColor;
  final VoidCallback onBack;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _FloatingCircleButton(
          tooltip: 'Geri',
          icon: Icons.arrow_back_rounded,
          onPressed: onBack,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: _floatingDecoration(radius: 30),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Serbest Yürüyüş',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _FreeWalkMapPageState._ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: gpsColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        gpsLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: gpsColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        _FloatingCircleButton(
          tooltip: 'Diğer seçenekler',
          icon: Icons.more_vert_rounded,
          onPressed: onMore,
        ),
      ],
    );
  }
}

class _ActivityStatusPill extends StatelessWidget {
  const _ActivityStatusPill({
    required this.icon,
    required this.label,
    required this.active,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 270),
      padding: const EdgeInsets.fromLTRB(14, 10, 18, 10),
      decoration: _floatingDecoration(radius: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _FreeWalkMapPageState._pink.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              boxShadow:
                  active
                      ? [
                        BoxShadow(
                          color: _FreeWalkMapPageState._pink.withValues(
                            alpha: 0.22,
                          ),
                          blurRadius: 12,
                          spreadRadius: 5,
                        ),
                      ]
                      : null,
            ),
            child: Icon(icon, color: _FreeWalkMapPageState._pink, size: 18),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _FreeWalkMapPageState._ink,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WalkSummaryPanel extends StatelessWidget {
  const _WalkSummaryPanel({
    required this.runState,
    required this.duration,
    required this.distance,
    required this.pace,
    required this.controlsLocked,
    required this.onToggleLock,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.onReset,
  });

  final _FreeWalkRunState runState;
  final String duration;
  final String distance;
  final String pace;
  final bool controlsLocked;
  final VoidCallback? onToggleLock;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final isIdle = runState == _FreeWalkRunState.idle;
    final isPaused = runState == _FreeWalkRunState.paused;
    final isFinished = runState == _FreeWalkRunState.finished;

    return Container(
      padding: EdgeInsets.fromLTRB(
        22,
        10,
        22,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFFDFBF8),
        borderRadius: BorderRadius.vertical(top: Radius.circular(34)),
        boxShadow: [
          BoxShadow(
            color: Color(0x260C0B28),
            blurRadius: 30,
            offset: Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFB8B8B4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text(
                  isFinished ? 'Yürüyüş Tamamlandı' : 'Yürüyüş Özeti',
                  style: const TextStyle(
                    color: _FreeWalkMapPageState._ink,
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: onToggleLock,
                    style: IconButton.styleFrom(
                      backgroundColor:
                          controlsLocked
                              ? _FreeWalkMapPageState._pink.withValues(
                                alpha: 0.12,
                              )
                              : const Color(0xFFF5F1ED),
                    ),
                    color:
                        controlsLocked
                            ? _FreeWalkMapPageState._pink
                            : _FreeWalkMapPageState._ink,
                    icon: Icon(
                      controlsLocked
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      size: 21,
                    ),
                    tooltip:
                        controlsLocked
                            ? 'Kontrollerin kilidini aç'
                            : 'Kontrolleri kilitle',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _SummaryMetric(value: duration, label: 'Süre')),
              const _MetricDivider(),
              Expanded(
                child: _SummaryMetric(
                  value: distance,
                  suffix: 'km',
                  label: 'Mesafe',
                ),
              ),
              const _MetricDivider(),
              Expanded(
                child: _SummaryMetric(
                  value: pace,
                  suffix: '/km',
                  label: 'Tempo',
                ),
              ),
            ],
          ),
          const Spacer(),
          if (isIdle)
            _PrimaryRoundAction(
              icon: Icons.play_arrow_rounded,
              label: 'Başlat',
              onPressed: onStart,
            )
          else if (isFinished)
            _PrimaryRoundAction(
              icon: Icons.refresh_rounded,
              label: 'Yeni Yürüyüş',
              onPressed: onReset,
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PrimaryRoundAction(
                  icon:
                      isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  label: isPaused ? 'Devam Et' : 'Duraklat',
                  onPressed:
                      controlsLocked ? null : (isPaused ? onResume : onPause),
                ),
                const SizedBox(width: 42),
                _SecondaryRoundAction(
                  icon: Icons.stop_rounded,
                  label: 'Bitir',
                  onPressed: controlsLocked ? null : onFinish,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.value, required this.label, this.suffix});

  final String value;
  final String label;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: value),
                if (suffix != null)
                  TextSpan(
                    text: ' $suffix',
                    style: const TextStyle(fontSize: 14),
                  ),
              ],
            ),
            maxLines: 1,
            style: const TextStyle(
              color: _FreeWalkMapPageState._ink,
              fontSize: 24,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF77718D),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 52,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: const Color(0xFFE2DDD8),
    );
  }
}

class _PrimaryRoundAction extends StatelessWidget {
  const _PrimaryRoundAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF0B69), Color(0xFF9E13C9)],
              ),
              boxShadow: [
                BoxShadow(
                  color: _FreeWalkMapPageState._pink.withValues(alpha: 0.24),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: IconButton(
              onPressed: onPressed,
              icon: Icon(icon, color: Colors.white, size: 42),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: _FreeWalkMapPageState._ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _SecondaryRoundAction extends StatelessWidget {
  const _SecondaryRoundAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: const Color(0xFFFFFCF8),
              shape: BoxShape.circle,
              border: Border.all(
                color: _FreeWalkMapPageState._orange,
                width: 2,
              ),
            ),
            child: IconButton(
              onPressed: onPressed,
              icon: Icon(icon, color: _FreeWalkMapPageState._orange, size: 37),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: _FreeWalkMapPageState._orange,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _FloatingCircleButton extends StatelessWidget {
  const _FloatingCircleButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: _floatingDecoration(radius: 29),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: _FreeWalkMapPageState._ink, size: 28),
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: _floatingDecoration(radius: 18),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color:
              selected
                  ? _FreeWalkMapPageState._pink
                  : _FreeWalkMapPageState._ink,
          size: 27,
        ),
      ),
    );
  }
}

BoxDecoration _floatingDecoration({required double radius}) {
  return BoxDecoration(
    color: const Color(0xF7FFFCF8),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: Colors.white.withValues(alpha: 0.86)),
    boxShadow: const [
      BoxShadow(color: Color(0x290C0B28), blurRadius: 18, offset: Offset(0, 7)),
    ],
  );
}

class _LocatingView extends StatelessWidget {
  const _LocatingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: 18),
          Text(
            'Konumun bulunuyor…',
            style: TextStyle(
              color: AppColors.textMain,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationErrorView extends StatelessWidget {
  const _LocationErrorView({
    required this.title,
    required this.message,
    required this.showSettings,
    required this.onSettings,
    required this.onRetry,
  });

  final String title;
  final String message;
  final bool showSettings;
  final VoidCallback onSettings;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                color: AppColors.primary,
                size: 36,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            if (showSettings) ...[
              FilledButton.icon(
                onPressed: onSettings,
                icon: const Icon(Icons.settings_rounded),
                label: const Text('Ayarları Aç'),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FinishWalkDialog extends StatelessWidget {
  const _FinishWalkDialog();

  static const _primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFF0B69), Color(0xFF9E13C9)],
  );

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 30),
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 30, 26, 22),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF8),
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x330C0B28),
              blurRadius: 40,
              offset: Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: _primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x40FF176B),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(
                Icons.flag_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Yürüyüşü bitir?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _FreeWalkMapPageState._ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Süre ve rota durdurulacak. Yürüyüş özetin kart olarak hazırlanacak.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF77718D),
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 26),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _FreeWalkMapPageState._ink,
                      side: const BorderSide(color: Color(0xFFE2DDD8)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Devam Et',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        gradient: _primaryGradient,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(context, true),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Center(
                            child: Text(
                              'Bitir',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

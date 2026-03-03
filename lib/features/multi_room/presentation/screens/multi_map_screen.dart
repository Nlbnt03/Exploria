import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/services/map_progress_service.dart';
import '../../../auth/domain/models/campus_map_state.dart';
import '../../../auth/presentation/map/fog_manager.dart';
import '../../../auth/presentation/map/gtu_boundary.dart';
import '../../models/live_location.dart';
import '../../models/member.dart';
import '../../models/room.dart';
import '../../services/multi_room_firestore_service.dart';

class MultiMapScreenArgs {
  const MultiMapScreenArgs({required this.roomId});

  final String roomId;
}

class MultiMapScreen extends StatefulWidget {
  const MultiMapScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<MultiMapScreen> createState() => _MultiMapScreenState();
}

class _MultiMapScreenState extends State<MultiMapScreen> {
  static const String _locationSourceId = 'multi-room-locations-source';
  static const String _circleLayerId = 'multi-room-locations-circle';
  static const String _labelLayerId = 'multi-room-locations-label';
  static const String _fogSourceId = 'multi-room-fog-source';
  static const String _fogLayerId = 'multi-room-fog-layer';

  final MultiRoomFirestoreService _service = MultiRoomFirestoreService();
  final MapProgressService _mapProgressService = MapProgressService();

  MapboxMap? _mapboxMap;
  GeoJsonSource? _locationSource;
  GeoJsonSource? _fogSource;
  FogManager? _fogManager;
  CameraState? _latestCameraState;

  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<List<Member>>? _membersSub;
  StreamSubscription<List<LiveLocation>>? _locationsSub;
  StreamSubscription<Set<String>>? _presenceSub;

  final Map<String, Member> _memberByUid = <String, Member>{};
  final Map<String, LiveLocation> _locationByUid = <String, LiveLocation>{};
  final Set<String> _inMapUids = <String>{};
  final Set<String> _presenceJoinNotifiedUids = <String>{};

  Room? _room;
  Position? _lastInsidePosition;
  Timer? _locationTimer;
  Timer? _fogRefreshDebounce;
  Timer? _fogAnimationTicker;
  Timer? _persistMapStateDebounce;

  bool _styleReady = false;
  bool _isTracking = false;
  bool _routeLocked = false;
  bool _cameraMovedToFirstPoint = false;
  bool _fogRefreshInFlight = false;
  bool _fogRefreshQueued = false;
  bool _historyMarked = false;
  bool _allMembersReadyToExplore = false;

  String? _historyMapId;
  String? _historyAreaId;
  String? _historyMapName;
  String? _lastRenderedFogGeoJson;

  @override
  void initState() {
    super.initState();

    _roomSub = _service
        .listenRoom(widget.roomId)
        .listen(
          _onRoomChanged,
          onError: (Object error) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Oda durumu alinamadi: $error')),
            );
          },
        );

    _membersSub = _service
        .listenMembers(widget.roomId)
        .listen(
          (members) {
            _memberByUid
              ..clear()
              ..addEntries(
                members.map((member) => MapEntry(member.uid, member)),
              );
            _refreshExplorationGate();
            unawaited(_refreshLocationSource());
            if (mounted) {
              setState(() {});
            }
          },
          onError: (Object error) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Uyeler alinamadi: $error')));
          },
        );

    _locationsSub = _service
        .listenLocations(widget.roomId)
        .listen(
          (locations) {
            _locationByUid
              ..clear()
              ..addEntries(
                locations.map((location) => MapEntry(location.uid, location)),
              );
            unawaited(_refreshLocationSource());
          },
          onError: (Object error) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Canli konumlar alinamadi: $error')),
            );
          },
        );

    _presenceSub = _service
        .listenInMapUids(widget.roomId)
        .listen(
          (uids) {
            final previous = Set<String>.from(_inMapUids);
            _inMapUids
              ..clear()
              ..addAll(uids);
            _onPresenceChanged(previous);
          },
          onError: (Object error) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Harita giris durumu alinamadi: $error')),
            );
          },
        );
  }

  CampusAreaConfig _resolveAreaForRoom(Room? room) {
    if (room == null) {
      return resolveCampusArea(defaultCampusAreaId);
    }

    final roomCityId = room.cityId.trim();
    final hasMatch = selectableCampusAreas.any((area) => area.id == roomCityId);
    final areaId = hasMatch ? roomCityId : defaultCampusAreaId;
    return resolveCampusArea(areaId);
  }

  String _resolveAreaIdForRoom(Room room) {
    final roomCityId = room.cityId.trim();
    final hasMatch = selectableCampusAreas.any((area) => area.id == roomCityId);
    return hasMatch ? roomCityId : defaultCampusAreaId;
  }

  String _historyMapIdForRoom(Room room) => 'multi_${room.id}';

  String _historyMapNameForRoom(Room room) {
    final roomName = room.roomName.trim();
    if (roomName.isEmpty) {
      return 'Coklu Oda ${room.id}';
    }
    return '$roomName (Coklu)';
  }

  void _onRoomChanged(Room? room) {
    _room = room;

    if (!mounted) {
      return;
    }

    setState(() {});

    if (room == null) {
      _goHomeWithMessage('Oda bulunamadi.');
      return;
    }

    if (room.isFinished) {
      _stopTracking();
      _goHomeWithMessage('Oda sonlandirildi.');
      return;
    }

    if (room.isActive) {
      unawaited(_service.setMyInMapPresence(widget.roomId, inMap: true));
      _refreshExplorationGate();
      unawaited(_markRoomMapOpenedForHistory(room));
    } else {
      _stopTracking();
      _allMembersReadyToExplore = false;
      unawaited(_service.setMyInMapPresence(widget.roomId, inMap: false));
    }
  }

  void _onPresenceChanged(Set<String> previous) {
    final currentUid = _service.currentUid;
    final newlyJoined = _inMapUids.difference(previous);
    for (final uid in newlyJoined) {
      if (uid == currentUid || _presenceJoinNotifiedUids.contains(uid)) {
        continue;
      }
      _presenceJoinNotifiedUids.add(uid);
      if (!mounted) {
        continue;
      }
      final username = _memberByUid[uid]?.username ?? 'Bir oyuncu';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$username haritaya girdi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    _refreshExplorationGate();
  }

  bool _computeAllMembersReadyToExplore() {
    final room = _room;
    if (room == null || !room.isActive) {
      return false;
    }

    final memberUids = _memberByUid.keys.toSet();
    if (memberUids.isEmpty) {
      return false;
    }

    return _inMapUids.containsAll(memberUids);
  }

  void _refreshExplorationGate() {
    final isReady = _computeAllMembersReadyToExplore();
    final changed = _allMembersReadyToExplore != isReady;
    _allMembersReadyToExplore = isReady;

    if (_room?.isActive == true) {
      if (_allMembersReadyToExplore) {
        unawaited(_startTracking());
      } else {
        _stopTracking();
      }
    } else {
      _stopTracking();
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  Future<void> _markRoomMapOpenedForHistory(Room room) async {
    if (_historyMarked) {
      return;
    }

    final uid = _service.currentUid;
    if (uid == null || uid.isEmpty) {
      return;
    }

    final mapId = _historyMapIdForRoom(room);
    final areaId = _resolveAreaIdForRoom(room);
    final mapName = _historyMapNameForRoom(room);

    try {
      await _mapProgressService.markMapOpened(
        uid: uid,
        mapId: mapId,
        areaId: areaId,
        mapName: mapName,
      );
      _historyMarked = true;
      _historyMapId = mapId;
      _historyAreaId = areaId;
      _historyMapName = mapName;
      _schedulePersistMapState(delay: const Duration(milliseconds: 700));
    } catch (_) {
      // Room map history registration is best-effort.
    }
  }

  Future<void> _startTracking() async {
    if (_isTracking) {
      return;
    }
    if (!_allMembersReadyToExplore || !(_room?.isActive ?? false)) {
      return;
    }

    final permissionOk = await _ensureLocationPermission();
    if (!permissionOk) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Konum izni olmadan canli konum paylasilamaz.'),
          ),
        );
      }
      return;
    }

    _isTracking = true;
    await _pushCurrentLocation();

    _locationTimer?.cancel();
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(_pushCurrentLocation());
    });
  }

  void _stopTracking() {
    _isTracking = false;
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<bool> _ensureLocationPermission() async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    return permission == geo.LocationPermission.always ||
        permission == geo.LocationPermission.whileInUse;
  }

  Future<void> _pushCurrentLocation() async {
    final room = _room;
    if (!_isTracking ||
        room == null ||
        !room.isActive ||
        !_allMembersReadyToExplore) {
      return;
    }

    try {
      final current = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );

      await _service.updateMyLocation(
        widget.roomId,
        current.latitude,
        current.longitude,
      );

      _revealFogForPosition(Position(current.longitude, current.latitude));
    } on Exception {
      // Next 5-second tick retries.
    }
  }

  void _revealFogForPosition(Position position) {
    final fogManager = _fogManager;
    if (fogManager == null) {
      return;
    }

    if (!fogManager.contains(position)) {
      return;
    }

    _lastInsidePosition = position;

    final hasNewReveal = fogManager.revealForPosition(position);
    if (hasNewReveal) {
      _startFogAnimationTicker();
      _scheduleFogRefresh(delay: const Duration(milliseconds: 16));
      _schedulePersistMapState(delay: const Duration(milliseconds: 650));
      if (mounted) {
        setState(() {});
      }
      return;
    }

    if (fogManager.hasPendingRevealAnimation) {
      _startFogAnimationTicker();
    }
  }

  void _goHomeWithMessage(String message) {
    if (_routeLocked || !mounted) {
      return;
    }
    _routeLocked = true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    Navigator.pushNamedAndRemoveUntil(context, AppRouter.home, (_) => false);
  }

  Future<void> _leaveRoom() async {
    try {
      _stopTracking();
      await _service.setMyInMapPresence(widget.roomId, inMap: false);
      await _service.leaveRoom(widget.roomId);
      if (!mounted) {
        return;
      }
      Navigator.pushNamedAndRemoveUntil(context, AppRouter.home, (_) => false);
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Odadan ayrilinamadi: $e')));
    }
  }

  Future<void> _endRoom() async {
    try {
      await _service.endRoom(widget.roomId);
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Oda sonlandirilamadi: $e')));
    }
  }

  Future<void> _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = false;
    await _prepareFogLayer();
    await _prepareLocationLayers();
    _latestCameraState = await _mapboxMap?.getCameraState();
    _styleReady = true;
    await _refreshLocationSource();
    _scheduleFogRefresh(delay: const Duration(milliseconds: 120));
  }

  void _onCameraChanged(CameraChangedEventData data) {
    _latestCameraState = data.cameraState;
    _scheduleFogRefresh();
    _schedulePersistMapState();
  }

  Future<void> _prepareFogLayer() async {
    final map = _mapboxMap;
    if (map == null) {
      return;
    }

    final area = _resolveAreaForRoom(_room);
    final fogManager = FogManager(
      campusBoundary: area.boundary,
      gridSizeMeters: area.gridSizeMeters,
    );
    await fogManager.initialize();
    _fogManager = fogManager;

    await map.setBounds(
      CameraBoundsOptions(
        bounds: fogManager.bounds.toCoordinateBounds(),
        minZoom: 14.8,
        maxZoom: 19.2,
        minPitch: 0,
        maxPitch: 75,
      ),
    );

    final source = GeoJsonSource(
      id: _fogSourceId,
      data: _emptyFeatureCollection(),
    );

    try {
      await map.style.addSource(source);
      _fogSource = source;
    } on PlatformException catch (e) {
      if (_isAlreadyExistsError(e)) {
        final existing = await map.style.getSource(_fogSourceId);
        if (existing is GeoJsonSource) {
          _fogSource = existing;
        }
      } else {
        rethrow;
      }
    }

    await _fogSource?.updateGeoJSON(_emptyFeatureCollection());
    _lastRenderedFogGeoJson = _emptyFeatureCollection();

    try {
      await map.style.addLayer(
        FillLayer(
          id: _fogLayerId,
          sourceId: _fogSourceId,
          fillAntialias: true,
          fillColor: const Color(0xFF0D1117).toARGB32(),
          fillOpacityExpression: <Object>[
            'coalesce',
            <Object>['get', 'opacity'],
            fogManager.baseFogOpacity,
          ],
        ),
      );
    } on PlatformException catch (e) {
      if (!_isAlreadyExistsError(e)) {
        rethrow;
      }
    }
  }

  Future<void> _prepareLocationLayers() async {
    final map = _mapboxMap;
    if (map == null) {
      return;
    }

    final source = GeoJsonSource(
      id: _locationSourceId,
      data: _emptyFeatureCollection(),
    );

    try {
      await map.style.addSource(source);
      _locationSource = source;
    } on Exception {
      final existing = await map.style.getSource(_locationSourceId);
      if (existing is GeoJsonSource) {
        _locationSource = existing;
      }
    }

    try {
      await map.style.addLayer(
        CircleLayer(
          id: _circleLayerId,
          sourceId: _locationSourceId,
          circleRadius: 9,
          circleOpacity: 0.96,
          circleStrokeWidth: 2,
          circleStrokeColor: Colors.white.toARGB32(),
          circleColorExpression: <Object>[
            'to-color',
            <Object>['get', 'color'],
          ],
        ),
      );
    } on Exception {
      // Layer exists.
    }

    try {
      await map.style.addLayer(
        SymbolLayer(
          id: _labelLayerId,
          sourceId: _locationSourceId,
          textFieldExpression: <Object>['get', 'username'],
          textSize: 12,
          textColor: Colors.white.toARGB32(),
          textHaloColor: const Color(0xCC000000).toARGB32(),
          textHaloWidth: 1.4,
          textOffset: <double>[0, -1.7],
          textAllowOverlap: true,
          textIgnorePlacement: true,
        ),
      );
    } on Exception {
      // Layer exists.
    }
  }

  Future<void> _refreshLocationSource() async {
    if (!_styleReady) {
      return;
    }

    final source = _locationSource;
    if (source == null) {
      return;
    }

    final hostId = _room?.hostId ?? '';
    final features = <Map<String, Object?>>[];

    for (final entry in _locationByUid.entries) {
      final location = entry.value;
      final member = _memberByUid[entry.key];
      final username = member?.username ?? location.username ?? entry.key;

      features.add(<String, Object?>{
        'type': 'Feature',
        'geometry': <String, Object?>{
          'type': 'Point',
          'coordinates': <double>[location.lng, location.lat],
        },
        'properties': <String, Object?>{
          'uid': location.uid,
          'username': username,
          'color': _colorForMember(location.uid, hostId),
        },
      });
    }

    final geoJson = jsonEncode(<String, Object?>{
      'type': 'FeatureCollection',
      'features': features,
    });

    await source.updateGeoJSON(geoJson);

    if (!_cameraMovedToFirstPoint &&
        features.isNotEmpty &&
        _mapboxMap != null) {
      _cameraMovedToFirstPoint = true;
      final firstCoords = features.first['geometry'] as Map<String, Object?>;
      final values =
          (firstCoords['coordinates'] as List<Object?>).cast<double>();
      await _mapboxMap!.easeTo(
        CameraOptions(
          center: Point(coordinates: Position(values[0], values[1])),
          zoom: 15,
        ),
        MapAnimationOptions(duration: 900, startDelay: 0),
      );
    }
  }

  void _scheduleFogRefresh({
    Duration delay = const Duration(milliseconds: 100),
  }) {
    _fogRefreshDebounce?.cancel();
    _fogRefreshDebounce = Timer(delay, _refreshFog);
  }

  Future<void> _refreshFog() async {
    if (_fogRefreshInFlight) {
      _fogRefreshQueued = true;
      return;
    }

    _fogRefreshInFlight = true;

    final map = _mapboxMap;
    final fogSource = _fogSource;
    final fogManager = _fogManager;
    final cameraState = _latestCameraState;
    if (!_styleReady ||
        map == null ||
        fogSource == null ||
        fogManager == null ||
        cameraState == null) {
      _fogRefreshInFlight = false;
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
    } finally {
      _fogRefreshInFlight = false;
      if (_fogRefreshQueued) {
        _fogRefreshQueued = false;
        unawaited(_refreshFog());
      }
    }
  }

  void _startFogAnimationTicker() {
    if (_fogAnimationTicker != null) {
      return;
    }

    _fogAnimationTicker = Timer.periodic(const Duration(milliseconds: 180), (
      timer,
    ) {
      final fogManager = _fogManager;
      if (fogManager == null) {
        timer.cancel();
        _fogAnimationTicker = null;
        return;
      }

      final changed = fogManager.advanceRevealAnimationStep();
      if (changed) {
        _scheduleFogRefresh(delay: const Duration(milliseconds: 16));
        _schedulePersistMapState(delay: const Duration(milliseconds: 650));
        if (mounted) {
          setState(() {});
        }
      }

      if (!fogManager.hasPendingRevealAnimation) {
        timer.cancel();
        _fogAnimationTicker = null;
      }
    });
  }

  void _schedulePersistMapState({
    Duration delay = const Duration(milliseconds: 850),
  }) {
    _persistMapStateDebounce?.cancel();
    _persistMapStateDebounce = Timer(delay, () {
      unawaited(_persistMapState());
    });
  }

  Future<void> _persistMapState() async {
    if (!_historyMarked) {
      return;
    }

    final uid = _service.currentUid;
    final mapId = _historyMapId;
    final areaId = _historyAreaId;
    final mapName = _historyMapName;
    final fogManager = _fogManager;

    if (uid == null ||
        uid.isEmpty ||
        mapId == null ||
        areaId == null ||
        mapName == null ||
        fogManager == null) {
      return;
    }

    final cameraState = _latestCameraState;
    final cameraCenter = cameraState?.center.coordinates;
    final zoom = cameraState?.zoom;

    try {
      await _mapProgressService.saveMapState(
        uid: uid,
        mapId: mapId,
        areaId: areaId,
        mapName: mapName,
        state: CampusMapState(
          revealedCellIds: fogManager.snapshotRevealedCellIds(),
          lastInsidePosition: _lastInsidePosition,
          cameraCenter: cameraCenter,
          zoom: zoom,
        ),
      );
    } catch (_) {
      // Persisting map state is best-effort.
    }
  }

  String _emptyFeatureCollection() {
    return '{"type":"FeatureCollection","features":[]}';
  }

  String _colorForMember(String uid, String hostId) {
    if (uid == hostId) {
      return '#1E88E5';
    }

    const palette = <String>['#E53935', '#43A047', '#FB8C00', '#8E24AA'];
    final hash = uid.codeUnits.fold<int>(0, (prev, code) => prev + code);
    return palette[hash % palette.length];
  }

  bool _isAlreadyExistsError(PlatformException error) {
    final message =
        '${error.message ?? ''} ${error.details ?? ''}'.toLowerCase();
    return message.contains('already exists') || message.contains('exists');
  }

  @override
  void dispose() {
    _stopTracking();
    _fogRefreshDebounce?.cancel();
    _fogAnimationTicker?.cancel();
    _persistMapStateDebounce?.cancel();
    unawaited(_persistMapState());
    unawaited(_service.setMyInMapPresence(widget.roomId, inMap: false));
    _roomSub?.cancel();
    _membersSub?.cancel();
    _locationsSub?.cancel();
    _presenceSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final isHost = room?.hostId == _service.currentUid;
    final area = _resolveAreaForRoom(room);
    final shouldLockExploration =
        room?.isActive == true && !_allMembersReadyToExplore;
    final waitingUids =
        _memberByUid.keys.where((uid) => !_inMapUids.contains(uid)).toList();
    final waitingNames = waitingUids
        .map((uid) => _memberByUid[uid]?.username ?? uid)
        .take(3)
        .join(', ');
    final fogManager = _fogManager;
    final fogSummary =
        fogManager == null
            ? 'Sis hazirlaniyor...'
            : 'Sis acilan hucre: ${fogManager.revealedCount}/${fogManager.totalCount}';

    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textMain,
        title: Text(room?.roomName ?? 'Coklu Harita'),
        actions: [
          if (isHost)
            IconButton(
              tooltip: 'End room',
              onPressed: _endRoom,
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          IconButton(
            tooltip: 'Leave room',
            onPressed: _leaveRoom,
            icon: const Icon(Icons.exit_to_app_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          AbsorbPointer(
            absorbing: shouldLockExploration,
            child: MapWidget(
              key: ValueKey('multi-map-${widget.roomId}-${area.id}'),
              styleUri: area.styleUri,
              cameraOptions: CameraOptions(
                center: Point(coordinates: area.center),
                zoom: 14.8,
                bearing: 0,
                pitch: 0,
              ),
              onMapCreated: (mapboxMap) => unawaited(_onMapCreated(mapboxMap)),
              onStyleLoadedListener: (_) => unawaited(_onStyleLoaded()),
              onCameraChangeListener: _onCameraChanged,
            ),
          ),
          if (shouldLockExploration)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: const Color(0x7A120A24),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xEE1A1030),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.inputBorder.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Keşif kilitli',
                            style: TextStyle(
                              color: AppColors.textMain,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            waitingNames.isEmpty
                                ? 'Tüm oyuncular haritaya girene kadar bekleniyor.'
                                : 'Beklenen oyuncu: $waitingNames',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xD9190D2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.inputBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Durum: ${room?.status ?? 'yukleniyor'}',
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Canli uyeler: ${_memberByUid.length} | Haritada: ${_inMapUids.length} | Konum gelen: ${_locationByUid.length}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      fogSummary,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 14,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xD9190D2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.inputBorder.withValues(alpha: 0.45),
                ),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  'Mavi: Host | Diger oyuncular: kirmizi/yesil/turuncu/mor',
                  style: TextStyle(
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

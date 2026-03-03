import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
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
  static const String _sourceId = 'multi-room-locations-source';
  static const String _circleLayerId = 'multi-room-locations-circle';
  static const String _labelLayerId = 'multi-room-locations-label';

  final MultiRoomFirestoreService _service = MultiRoomFirestoreService();

  MapboxMap? _mapboxMap;
  GeoJsonSource? _locationSource;

  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<List<Member>>? _membersSub;
  StreamSubscription<List<LiveLocation>>? _locationsSub;

  final Map<String, Member> _memberByUid = <String, Member>{};
  final Map<String, LiveLocation> _locationByUid = <String, LiveLocation>{};

  Room? _room;
  Timer? _locationTimer;

  bool _styleReady = false;
  bool _isTracking = false;
  bool _routeLocked = false;
  bool _cameraMovedToFirstPoint = false;

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
      _startTracking();
    } else {
      _stopTracking();
    }
  }

  Future<void> _startTracking() async {
    if (_isTracking) {
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
    if (!_isTracking || room == null || !room.isActive) {
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
    } on Exception {
      // Next 5-second tick retries.
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
    await _prepareLocationLayers();
    await _refreshLocationSource();
  }

  Future<void> _prepareLocationLayers() async {
    final map = _mapboxMap;
    if (map == null) {
      return;
    }

    final source = GeoJsonSource(
      id: _sourceId,
      data: _emptyFeatureCollection(),
    );

    try {
      await map.style.addSource(source);
      _locationSource = source;
    } on Exception {
      final existing = await map.style.getSource(_sourceId);
      if (existing is GeoJsonSource) {
        _locationSource = existing;
      }
    }

    try {
      await map.style.addLayer(
        CircleLayer(
          id: _circleLayerId,
          sourceId: _sourceId,
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
          sourceId: _sourceId,
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

    _styleReady = true;
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

  @override
  void dispose() {
    _stopTracking();
    _roomSub?.cancel();
    _membersSub?.cancel();
    _locationsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final isHost = room?.hostId == _service.currentUid;

    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textMain,
        title: Text(room?.roomName ?? 'Multi Room Map'),
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
          MapWidget(
            key: ValueKey('multi-map-${widget.roomId}'),
            styleUri: defaultMapStyleUri,
            cameraOptions: CameraOptions(
              center: Point(coordinates: gtuCampusCenter),
              zoom: 13,
              bearing: 0,
              pitch: 0,
            ),
            onMapCreated: (mapboxMap) => unawaited(_onMapCreated(mapboxMap)),
            onStyleLoadedListener: (_) => unawaited(_onStyleLoaded()),
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
                      'Canli uyeler: ${_memberByUid.length} | Konum gelen: ${_locationByUid.length}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
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

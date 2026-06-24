import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/data/services/map_area_firestore_service.dart';
import '../../../auth/data/services/map_progress_service.dart';
import '../../../auth/domain/models/campus_map_state.dart';
import '../../../auth/presentation/map/fog_manager.dart';
import '../../../auth/presentation/map/map_areas.dart';
import '../../../auth/data/services/poi_service.dart';
import '../../../badges/data/badge_award_service.dart';
import '../../../badges/domain/badge_definitions.dart';
import '../../../badges/presentation/widgets/badge_celebration_dialog.dart';
import '../../../check_in/presentation/widgets/gezdim_button.dart';
import '../../models/live_location.dart';
import '../../models/member.dart';
import '../../models/room.dart';
import '../../services/multi_room_firestore_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/game_provider.dart';
import '../../../../widgets/xp_popup.dart';
import '../../../../widgets/level_up_dialog.dart';

class MultiMapScreenArgs {
  const MultiMapScreenArgs({required this.roomId});

  final String roomId;
}

class MultiMapScreen extends ConsumerStatefulWidget {
  const MultiMapScreen({super.key, required this.roomId});

  final String roomId;

  @override
  ConsumerState<MultiMapScreen> createState() => _MultiMapScreenState();
}

class _MultiMapScreenState extends ConsumerState<MultiMapScreen> {
  static const String _locationSourceId = 'multi-room-locations-source';
  static const String _circleLayerId = 'multi-room-locations-circle';
  static const String _labelLayerId = 'multi-room-locations-label';
  static const String _fogSourceId = 'multi-room-fog-source';
  static const String _fogLayerId = 'multi-room-fog-layer';
  static const String _cloudSourceId = 'multi-room-cloud-source';
  static const String _cloudLayerId = 'multi-room-cloud-layer';

  final MultiRoomFirestoreService _service = MultiRoomFirestoreService();
  final MapProgressService _mapProgressService = MapProgressService();
  final MapAreaFirestoreService _mapAreaService = MapAreaFirestoreService();

  MapboxMap? _mapboxMap;
  GeoJsonSource? _locationSource;
  GeoJsonSource? _fogSource;
  GeoJsonSource? _cloudSource;
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

  Set<String> _visitedPoiIds = {};
  int _totalPoiCount = 0;

  Room? _room;
  MapAreaConfig? _roomArea;
  Position? _lastInsidePosition;
  StreamSubscription<geo.Position>? _locationSub;
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
  double _initialZoom = 16.0;
  double _minZoom = 14.8;
  double _maxZoom = 17.5;

  String? _historyMapId;
  String? _historyAreaId;
  String? _historyMapName;
  String? _lastRenderedFogGeoJson;
  String? _lastRenderedCloudGeoJson;

  // POI & badge state
  final BadgeAwardService _badgeAwardService = BadgeAwardService();
  List<Map<String, dynamic>> _parsedPois = [];
  final Map<String, Map<String, dynamic>> _parsedPoisById = {};
  Set<String> _availableCategories = {};
  Set<String> _activeCategories = {};
  bool _poisInitiallyLoaded = false;
  bool _poiLayerCreated = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid;

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

  MapAreaConfig _resolveAreaForRoom(Room? room) {
    if (room == null) {
      return resolveMapArea(defaultMapAreaId);
    }

    final roomCityId = room.cityId.trim();
    if (_roomArea?.id == roomCityId) {
      return _roomArea!;
    }
    final hasMatch = selectableMapAreas.any((area) => area.id == roomCityId);
    final areaId = hasMatch ? roomCityId : defaultMapAreaId;
    return resolveMapArea(areaId);
  }

  String _resolveAreaIdForRoom(Room room) {
    final roomCityId = room.cityId.trim();
    return roomCityId.isEmpty ? defaultMapAreaId : roomCityId;
  }

  Future<void> _loadRoomArea(Room room) async {
    final area = await _mapAreaService.fetchArea(room.cityId);
    if (!mounted || _room?.cityId != room.cityId) return;
    setState(() => _roomArea = area);
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

    unawaited(_loadRoomArea(room));

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

    CampusMapState? restoredState;
    try {
      restoredState = await _mapProgressService.fetchMapState(
        uid: uid,
        mapId: mapId,
      );
    } catch (_) {
      // Best effort
    }

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

      if (restoredState != null) {
        _lastInsidePosition = restoredState.lastInsidePosition;
        _initialZoom =
            (restoredState.zoom ?? 16.0).clamp(14.8, 17.5).toDouble();
        _visitedPoiIds = Set.from(restoredState.visitedPoiIds);
        _fogManager?.restoreRevealedCells(restoredState.revealedCellIds);
      }

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

    _locationSub = geo.Geolocator.getPositionStream(
      locationSettings: const geo.LocationSettings(
        accuracy: geo.LocationAccuracy.high,
        distanceFilter: 4,
      ),
    ).listen(
      (pos) {
        if (!_isTracking) return;
        final position = Position(pos.longitude, pos.latitude);
        unawaited(
          _service.updateMyLocation(widget.roomId, pos.latitude, pos.longitude),
        );
        _revealFogForPosition(position);
        if (!_cameraMovedToFirstPoint && _styleReady) {
          _cameraMovedToFirstPoint = true;
          unawaited(
            _mapboxMap?.setCamera(
              CameraOptions(
                center: Point(coordinates: position),
                zoom: _initialZoom > _minZoom ? _initialZoom : 16.0,
              ),
            ),
          );
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  void _stopTracking() {
    _isTracking = false;
    _locationSub?.cancel();
    _locationSub = null;
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

  Future<void> _ensurePoisParsed() async {
    if (_parsedPois.isNotEmpty) return;
    final areaId = _historyAreaId ?? _room?.cityId ?? _resolveAreaForRoom(_room).id;
    final rawList = await PoiService().getPoisForCity(areaId);
    final categories = <String>{};
    final parsed = <Map<String, dynamic>>[];
    for (final raw in rawList) {
      try {
        final name = (raw['name'] as String?)?.trim() ?? '';
        final type = (raw['category'] as String?)?.trim() ?? 'unknown';
        final xpValue = (raw['xpValue'] as num?)?.toInt() ?? 0;
        final String rarity;
        if (xpValue >= 100) {
          rarity = 'must-see';
        } else if (xpValue >= 75) {
          rarity = 'önerilen';
        } else if (xpValue >= 50) {
          rarity = 'rare';
        } else {
          rarity = raw['rarity'] as String? ?? 'common';
        }
        final lon = (raw['longitude'] as num?)?.toDouble() ?? 0;
        final lat = (raw['latitude'] as num?)?.toDouble() ?? 0;
        if (lon == 0 && lat == 0) continue;
        final featureId = raw['id']?.toString() ?? name;
        categories.add(type);
        final entry = <String, dynamic>{
          'featureId': featureId,
          'name': name,
          'type': type,
          'rarity': rarity,
          'category': type,
          'xp': xpValue,
          'description': raw['description'] as String? ?? '',
          'photo_url': raw['imageUrl'] as String? ?? '',
          'lon': lon,
          'lat': lat,
        };
        parsed.add(entry);
        _parsedPoisById[featureId] = entry;
      } catch (_) {}
    }
    _parsedPois = parsed;
    _availableCategories = categories;
    if (!_poisInitiallyLoaded) {
      _activeCategories = Set.from(categories);
      _poisInitiallyLoaded = true;
    }
  }

  void _toggleCategory(String category) {
    setState(() {
      if (_activeCategories.contains(category)) {
        _activeCategories.remove(category);
      } else {
        _activeCategories.add(category);
      }
    });
    _loadAndShowPois();
  }

  void _toggleAllCategories() {
    setState(() {
      if (_activeCategories.length == _availableCategories.length) {
        _activeCategories.clear();
      } else {
        _activeCategories = Set.from(_availableCategories);
      }
    });
    _loadAndShowPois();
  }

  Future<void> _checkBadgesBeforeExit() async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final bContext = BadgeCheckContext(
        totalVisited: _visitedPoiIds.length,
        historicBuildingVisited: _parsedPois
            .where((p) =>
                _visitedPoiIds.contains(p['featureId']) &&
                (p['category'].toString().toLowerCase().contains('tarih') ||
                    p['type'].toString().toLowerCase().contains('tarih')))
            .length,
        mosqueVisited: _parsedPois
            .where((p) =>
                _visitedPoiIds.contains(p['featureId']) &&
                (p['category'].toString().toLowerCase().contains('cami') ||
                    p['type'].toString().toLowerCase().contains('cami')))
            .length,
        distinctCitiesVisited: 1,
        coopSessionsCompleted: 1,
        distinctCoopPartners: (_memberByUid.length - 1).clamp(0, 99),
        coopMapJustCompleted:
            _totalPoiCount > 0 && _visitedPoiIds.length >= _totalPoiCount,
        currentStreak:
            ref
                .read(gameProvider)
                .valueOrNull
                ?.weeklyQuests
                .duzenliGezgin
                .current ??
            0,
        allWeeklyQuestsJustCompleted: false,
        visitTime: DateTime.now(),
        recentVisitTimes: [DateTime.now()],
        lastVisitedMapId: _historyAreaId,
        lastVisitedMapCompletion:
            _totalPoiCount > 0 ? _visitedPoiIds.length / _totalPoiCount : 0.0,
        weeklyLeaderboardRank: 999,
      );
      final newBadgeDefs = await _badgeAwardService.checkNewBadges(
        uid: uid,
        context: bContext,
      );
      if (newBadgeDefs.isNotEmpty && mounted) {
        unawaited(_badgeAwardService.awardBadges(
          uid: uid,
          badges: newBadgeDefs,
          gameNotifier: ref.read(gameProvider.notifier),
        ));
        await BadgeCelebrationDialog.show(
          context,
          newBadgeDefs.map((d) => d.id).toList(),
          showAsPill: true,
        );
      }
    } catch (e) {
      debugPrint('[Co Badge] Hata: $e');
    }
  }

  Future<void> _leaveRoom() async {
    try {
      _stopTracking();
      await _checkBadgesBeforeExit();
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

  // 80m base + 40m max accuracy allowance — mirrors VenueCheckInService thresholds.
  static const double _coopProximityThreshold = 120.0;

  /// Returns member UIDs whose last known location is beyond [_coopProximityThreshold]
  /// from the given POI. Members with no location data are excluded (benefit of doubt).
  List<String> _outOfRangeMembers(double venueLat, double venueLng) {
    final out = <String>[];
    for (final entry in _locationByUid.entries) {
      final loc = entry.value;
      final dist = haversineDistanceMeters(
        Position(loc.lng, loc.lat),
        Position(venueLng, venueLat),
      );
      if (dist > _coopProximityThreshold) out.add(entry.key);
    }
    return out;
  }

  void _onPoiTapped(Map<String, dynamic> payload) {
    if (!mounted) return;

    final id =
        payload['_feature_id']?.toString() ?? payload['name']?.toString() ?? '';
    if (id.isEmpty) return;

    final poi = _parsedPoisById[id];
    final name =
        poi?['name'] as String? ??
        payload['name']?.toString() ??
        'Bilinmeyen Mekan';
    final category =
        poi?['category'] as String? ?? payload['category']?.toString() ?? '';
    final description = poi?['description'] as String? ?? '';
    final photoUrl = poi?['photo_url'] as String? ?? '';
    final lat = poi?['lat'] as double? ?? 0.0;
    final lon = poi?['lon'] as double? ?? 0.0;
    final xpValue = poi?['xp'] as int? ?? 50;
    final mapId = _historyMapId ?? 'multi_${widget.roomId}';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        int? xpAnimAmount;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final currentVisited = _visitedPoiIds.contains(id);
            return SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: AppColors.bgBottom,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.textMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    if (photoUrl.isNotEmpty)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: AppColors.card,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: CachedNetworkImage(
                            imageUrl: photoUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, _, _) => const Icon(
                              Icons.image_not_supported_rounded,
                              color: AppColors.textMuted,
                              size: 40,
                            ),
                            placeholder: (_, _) => const Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      color: AppColors.textMain,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (currentVisited)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.check_circle,
                                            color: AppColors.primary, size: 14),
                                        SizedBox(width: 4),
                                        Text(
                                          'Gezildi',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            if (category.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                category,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                            if (description.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Text(
                                description,
                                style: TextStyle(
                                  color: AppColors.textMain
                                      .withValues(alpha: 0.85),
                                  fontSize: 14,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final outOfRange = _outOfRangeMembers(lat, lon);
                        final allInRange = outOfRange.isEmpty;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 8, 20, 16),
                              child: SafeArea(
                                top: false,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Team proximity status
                                    if (_memberByUid.length > 1) ...[
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: allInRange
                                              ? const Color(0xFF10B981)
                                                  .withValues(alpha: 0.12)
                                              : Colors.orange
                                                  .withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: allInRange
                                                ? const Color(0xFF10B981)
                                                    .withValues(alpha: 0.4)
                                                : Colors.orange
                                                    .withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (final entry
                                                in _memberByUid.entries)
                                              () {
                                                final loc = _locationByUid[
                                                    entry.key];
                                                if (loc == null) {
                                                  return _ProximityRow(
                                                    name:
                                                        entry.value.username,
                                                    status:
                                                        _ProximityStatus.unknown,
                                                  );
                                                }
                                                final inRange = !outOfRange
                                                    .contains(entry.key);
                                                return _ProximityRow(
                                                  name:
                                                      entry.value.username,
                                                  status: inRange
                                                      ? _ProximityStatus.inRange
                                                      : _ProximityStatus
                                                          .outOfRange,
                                                );
                                              }(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                    // Gezdim button — blocked when any member is out of range
                                    IgnorePointer(
                                      ignoring: !allInRange,
                                      child: Opacity(
                                        opacity: allInRange ? 1.0 : 0.45,
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: GezdimButton(
                                            venueId: id,
                                            mapId: mapId,
                                            venueLat: lat,
                                            venueLng: lon,
                                            currentVisited: currentVisited,
                                            userLat: _lastInsidePosition
                                                ?.lat
                                                .toDouble(),
                                            userLng: _lastInsidePosition
                                                ?.lng
                                                .toDouble(),
                                            onCheckInSuccess: () async {
                                              _visitedPoiIds.add(id);
                                              xpAnimAmount = xpValue;
                                              setSheetState(() {});
                                              setState(() {});
                                              _loadAndShowPois();

                                              // Award XP + visited to all other members
                                              unawaited(
                                                _service.awardCoopCheckIn(
                                                  mapId: mapId,
                                                  venueId: id,
                                                  xpValue: xpValue,
                                                  memberUids: _memberByUid
                                                      .keys
                                                      .toList(),
                                                ),
                                              );

                                              if (!context.mounted) return;
                                              try {
                                                final isLevelUp = await ref
                                                    .read(gameProvider.notifier)
                                                    .onPlaceVisited(
                                                      id,
                                                      category,
                                                      true,
                                                      xpValue: xpValue,
                                                    );
                                                if (context.mounted &&
                                                    isLevelUp) {
                                                  final userXP = ref
                                                      .read(gameProvider)
                                                      .valueOrNull;
                                                  if (userXP != null) {
                                                    LevelUpDialog.show(
                                                      context,
                                                      userXP.currentTitle,
                                                    );
                                                  }
                                                }
                                              } catch (e) {
                                                debugPrint(
                                                    '[Co] onPlaceVisited: $e');
                                              }
                                              unawaited(_persistMapState());
                                            },
                                            onCancelVisit: () async {
                                              _visitedPoiIds.remove(id);
                                              xpAnimAmount = -xpValue;
                                              setSheetState(() {});
                                              setState(() {});
                                              _loadAndShowPois();
                                              try {
                                                await ref
                                                    .read(gameProvider.notifier)
                                                    .removeXP(xpValue);
                                              } catch (e) {
                                                debugPrint('[Co] removeXP: $e');
                                              }
                                              unawaited(_persistMapState());
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (!allInRange)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(top: 8),
                                        child: Text(
                                          'Tüm takım arkadaşları mekana yakın olmalı (${_coopProximityThreshold.toInt()}m).',
                                          style: const TextStyle(
                                            color: Colors.orange,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            if (xpAnimAmount != null)
                              Positioned(
                                top: -30,
                                left: 0,
                                right: 0,
                                child: Center(
                                  child: XPPopup(
                                    key: UniqueKey(),
                                    xpAmount: xpAnimAmount!,
                                    onComplete: () {},
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _loadAndShowPois() async {
    final map = _mapboxMap;
    if (map == null) return;

    try {
      await _ensurePoisParsed();

      final features = <Map<String, Object?>>[];
      for (final poi in _parsedPois) {
        final type = poi['type'] as String;
        if (!_activeCategories.contains(type)) continue;
        final featureId = poi['featureId'] as String;
        features.add(<String, Object?>{
          'type': 'Feature',
          'id': featureId,
          'properties': <String, Object?>{
            'name': poi['name'],
            'poi_type': type,
            'rarity': poi['rarity'],
            'category': poi['category'],
            'xp': poi['xp'],
            'visited': _visitedPoiIds.contains(featureId),
          },
          'geometry': <String, Object?>{
            'type': 'Point',
            'coordinates': <double>[poi['lon'] as double, poi['lat'] as double],
          },
        });
      }

      final geoJson = jsonEncode(<String, Object?>{
        'type': 'FeatureCollection',
        'features': features,
      });

      if (mounted) setState(() => _totalPoiCount = _parsedPois.length);

      const sourceId = 'poi-source';
      const circleLayerId = 'poi-circle-layer';
      const labelLayerId = 'poi-label-layer';

      if (!_poiLayerCreated) {
        _poiLayerCreated = true;
        try {
          await map.style.addSource(GeoJsonSource(id: sourceId, data: geoJson));
        } on PlatformException catch (e) {
          if (_isAlreadyExistsError(e)) {
            final existing = await map.style.getSource(sourceId);
            if (existing is GeoJsonSource) await existing.updateGeoJSON(geoJson);
          } else {
            rethrow;
          }
        }
        try {
          await map.style.addLayer(
            CircleLayer(
              id: circleLayerId,
              sourceId: sourceId,
              circleRadiusExpression: <Object>[
                'match', <Object>['get', 'rarity'],
                'must-see', 14.0, 'önerilen', 10.0,
                'legendary', 14.0, 'epic', 11.0, 'rare', 8.0, 6.0,
              ],
              circleColorExpression: <Object>[
                'match', <Object>['get', 'poi_type'],
                'Cami', '#10B981', 'Saray', '#F59E0B', 'Müze', '#3B82F6',
                'Tarihi Yapı', '#6B7280', 'Meydan', '#F43F5E',
                'Hamam', '#06B6D4', 'Çarşı & Pazar', '#8B5CF6',
                'Çarşı', '#8B5CF6', 'Park & Bahçe', '#84CC16',
                'Semt & Cadde', '#F97316', 'Kule & Tepe', '#EF4444',
                'Sinagog & Kilise', '#A855F7', 'Eğitim Binası', '#3B82F6',
                'Araştırma Merkezi', '#F59E0B', 'Spor Tesisleri', '#10B981',
                'Yeme & İçme', '#F43F5E', '#E0E0E0',
              ],
              circleStrokeWidth: 1.5,
              circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
              circleOpacityExpression: <Object>[
                'case',
                <Object>['==', <Object>['get', 'visited'], true],
                0.4, 0.92,
              ],
            ),
          );
        } on PlatformException catch (e) {
          if (!_isAlreadyExistsError(e)) rethrow;
        }
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
                0.5, 1.0,
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
      } else {
        final existing = await map.style.getSource(sourceId);
        if (existing is GeoJsonSource) await existing.updateGeoJSON(geoJson);
      }
    } catch (e, st) {
      debugPrint('Error loading POIs: $e\n$st');
    }
  }

  void _handleMapTap(MapContentGestureContext context) {
    if (_mapboxMap == null) return;

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
          _onPoiTapped(payload);
        }
      }
    } catch (_) {
      // Ignore query errors
    }
  }

  Future<void> _onStyleLoaded() async {
    _styleReady = false;
    await _prepareFogLayer();
    await _prepareLocationLayers();
    _latestCameraState = await _mapboxMap?.getCameraState();
    _styleReady = true;
    try {
      await _mapboxMap?.scaleBar.updateSettings(
        ScaleBarSettings(
          position: OrnamentPosition.BOTTOM_LEFT,
          marginLeft: 16,
          marginBottom: 72,
        ),
      );
      await _mapboxMap?.compass.updateSettings(CompassSettings(enabled: false));
    } on PlatformException {
      // Best-effort
    }
    await _refreshLocationSource();
    await _loadAndShowPois();
    _scheduleFogRefresh(delay: const Duration(milliseconds: 120));
  }

  void _onCameraChanged(CameraChangedEventData data) {
    _latestCameraState = data.cameraState;
    final zoom = data.cameraState.zoom;
    final map = _mapboxMap;
    if (map != null && (zoom < _minZoom - 0.05 || zoom > _maxZoom + 0.05)) {
      final corrected = zoom.clamp(_minZoom, _maxZoom);
      unawaited(
        map.easeTo(
          CameraOptions(zoom: corrected),
          MapAnimationOptions(duration: 150, startDelay: 0),
        ),
      );
    }
    _scheduleFogRefresh();
    _schedulePersistMapState();
  }

  Future<void> _prepareFogLayer() async {
    final map = _mapboxMap;
    if (map == null) {
      return;
    }

    final room = _room;
    if (room != null && _roomArea?.id != room.cityId) {
      _roomArea = await _mapAreaService.fetchArea(room.cityId);
    }
    final area = _resolveAreaForRoom(room);
    final fogManager = FogManager(
      campusBoundary: area.boundary,
      gridSizeMeters: area.gridSizeMeters,
      revealRadiusMeters: area.gridSizeMeters * 1.3,
    );
    await fogManager.initialize();
    _fogManager = fogManager;

    _minZoom = area.minZoom;
    _maxZoom = 17.5;
    await map.setBounds(
      CameraBoundsOptions(
        bounds: fogManager.bounds.toCoordinateBounds(),
        minZoom: _minZoom,
        maxZoom: _maxZoom,
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

    final cloudSource = GeoJsonSource(
      id: _cloudSourceId,
      data: _emptyFeatureCollection(),
    );

    try {
      await map.style.addSource(cloudSource);
      _cloudSource = cloudSource;
    } on PlatformException catch (e) {
      if (_isAlreadyExistsError(e)) {
        final existing = await map.style.getSource(_cloudSourceId);
        if (existing is GeoJsonSource) {
          _cloudSource = existing;
        }
      } else {
        rethrow;
      }
    }

    await _cloudSource?.updateGeoJSON(_emptyFeatureCollection());
    _lastRenderedCloudGeoJson = _emptyFeatureCollection();

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
      await _mapboxMap!.setCamera(
        CameraOptions(
          center: Point(coordinates: Position(values[0], values[1])),
          zoom: _initialZoom > 14.8 ? _initialZoom : 16.0,
        ),
      );
    }
  }

  void _scheduleFogRefresh({
    Duration delay = const Duration(milliseconds: 250),
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
    final cloudSource = _cloudSource;
    final fogManager = _fogManager;
    final cameraState = _latestCameraState;
    if (!_styleReady ||
        map == null ||
        fogSource == null ||
        cloudSource == null ||
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

      final cloudGeoJson = fogManager.cloudGeoJsonForViewport(
        southwest: bounds.southwest.coordinates,
        northeast: bounds.northeast.coordinates,
      );
      if (cloudGeoJson != _lastRenderedCloudGeoJson) {
        await cloudSource.updateGeoJSON(cloudGeoJson);
        _lastRenderedCloudGeoJson = cloudGeoJson;
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
          visitedPoiIds: _visitedPoiIds.toList(),
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
    _locationSub?.cancel();
    _isTracking = false;
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
    final String fogSummary;
    if (fogManager == null) {
      fogSummary = 'Sis hazirlaniyor...';
    } else {
      fogSummary =
          'Gezilen: ${_visitedPoiIds.length} / $_totalPoiCount  |  ${fogManager.revealedCount}/${fogManager.totalCount} hücre';
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.bgBottom,
            title: const Text(
              'Odadan Ayrıl',
              style: TextStyle(color: AppColors.textMain),
            ),
            content: const Text(
              'Odadan ayrılmak istediğinize emin misiniz?',
              style: TextStyle(color: AppColors.textMuted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(
                  'İptal',
                  style: TextStyle(color: AppColors.textMuted),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(
                  'Ayrıl',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
        );
        if (confirm == true && context.mounted) unawaited(_leaveRoom());
      },
      child: Scaffold(
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
                center: Point(coordinates: _lastInsidePosition ?? area.center),
                zoom: _initialZoom,
                bearing: 0,
                pitch: 0,
              ),
              onMapCreated: (mapboxMap) => unawaited(_onMapCreated(mapboxMap)),
              onTapListener: _handleMapTap,
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
          // Category filter chips
          if (_availableCategories.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 118,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 10),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xCC12091F),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.inputBorder.withValues(alpha: 0.35),
                  ),
                ),
                child: SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    children: [
                      _MultiCategoryChip(
                        label: 'Tümü',
                        isActive: _activeCategories.length ==
                            _availableCategories.length,
                        onTap: _toggleAllCategories,
                        showAllIcon: true,
                      ),
                      const SizedBox(width: 6),
                      for (final cat in _availableCategories) ...[
                        _MultiCategoryChip(
                          label: cat,
                          isActive: _activeCategories.contains(cat),
                          onTap: () => _toggleCategory(cat),
                          categoryColor: _coopCategoryColorMap[cat],
                        ),
                        const SizedBox(width: 6),
                      ],
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  'Gezilen: ${_visitedPoiIds.length} / $_totalPoiCount',
                  style: const TextStyle(
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
      ),
    );
  }
}

class _MultiCategoryChip extends StatelessWidget {
  const _MultiCategoryChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.categoryColor,
    this.showAllIcon = false,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final Color? categoryColor;
  final bool showAllIcon;

  @override
  Widget build(BuildContext context) {
    final dotColor = categoryColor ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isActive ? dotColor.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? dotColor.withValues(alpha: 0.7)
                : AppColors.textMuted.withValues(alpha: 0.3),
            width: isActive ? 1.4 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showAllIcon)
              Icon(Icons.grid_view_rounded,
                  size: 14,
                  color: isActive ? AppColors.primary : AppColors.textMuted)
            else
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? dotColor : dotColor.withValues(alpha: 0.3),
                ),
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? AppColors.textMain
                    : AppColors.textMuted.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ProximityStatus { inRange, outOfRange, unknown }

class _ProximityRow extends StatelessWidget {
  const _ProximityRow({required this.name, required this.status});

  final String name;
  final _ProximityStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (status) {
      _ProximityStatus.inRange => (Icons.check_circle_rounded, const Color(0xFF10B981), 'Yakın'),
      _ProximityStatus.outOfRange => (Icons.location_off_rounded, Colors.orange, 'Uzakta'),
      _ProximityStatus.unknown => (Icons.help_outline_rounded, AppColors.textMuted, 'Konum yok'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              style: const TextStyle(color: AppColors.textMain, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

const Map<String, Color> _coopCategoryColorMap = {
  'Cami': Color(0xFF10B981),
  'Saray': Color(0xFFF59E0B),
  'Müze': Color(0xFF3B82F6),
  'Tarihi Yapı': Color(0xFF6B7280),
  'Meydan': Color(0xFFF43F5E),
  'Hamam': Color(0xFF06B6D4),
  'Çarşı & Pazar': Color(0xFF8B5CF6),
  'Çarşı': Color(0xFF8B5CF6),
  'Park & Bahçe': Color(0xFF84CC16),
  'Semt & Cadde': Color(0xFFF97316),
  'Kule & Tepe': Color(0xFFEF4444),
  'Sinagog & Kilise': Color(0xFFA855F7),
  'Eğitim Binası': Color(0xFF3B82F6),
  'Araştırma Merkezi': Color(0xFFF59E0B),
  'Spor Tesisleri': Color(0xFF10B981),
  'Yeme & İçme': Color(0xFFF43F5E),
};

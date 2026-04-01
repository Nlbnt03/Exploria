import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../data/services/poi_service.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/services/map_progress_service.dart';
import '../../domain/models/campus_map_state.dart';
import '../map/fog_manager.dart';
import '../map/map_areas.dart';
import '../map/location_service.dart';
import '../map/map_controller.dart';
import '../../../check_in/presentation/widgets/gezdim_button.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/game_provider.dart';
import '../../../../widgets/xp_popup.dart';
import '../../../../widgets/level_up_dialog.dart';
import '../../../../widgets/map_completed_dialog.dart';
import '../../../badges/data/badge_award_service.dart';
import '../../../badges/domain/badge_definitions.dart';
import '../../../badges/presentation/widgets/badge_celebration_dialog.dart';
class CityMapPageArgs {
  const CityMapPageArgs({
    required this.areaId,
    required this.mapId,
    required this.mapName,
    this.initialUserPosition,
  });

  final String areaId;
  final String mapId;
  final String mapName;
  final Position? initialUserPosition;
}

class CityMapPage extends ConsumerStatefulWidget {
  const CityMapPage({
    super.key,
    required this.areaId,
    required this.mapId,
    required this.mapName,
    this.initialUserPosition,
  });

  final String areaId;
  final String mapId;
  final String mapName;
  final Position? initialUserPosition;

  @override
  ConsumerState<CityMapPage> createState() => _CityMapPageState();
}

class _CityMapPageState extends ConsumerState<CityMapPage>
    with WidgetsBindingObserver {
  final MapProgressService _mapProgressService = MapProgressService();
  final BadgeAwardService _badgeAwardService = BadgeAwardService();

  CampusMapController? _mapController;
  late final MapAreaConfig _selectedArea;
  late final String _mapId;
  late final String _mapName;
  late Position _initialCenter;
  double _initialZoom = 16.0;
  bool _isLoadingSession = true;
  bool _warningShown = false;
  String? _uid;
  Set<String> _visitedPoiIds = {};
  int _totalPoiCount = 0;
  StreamSubscription<Map<String, dynamic>>? _poiTapSub;

  // Category filtering
  List<Map<String, dynamic>> _parsedPois = [];
  Set<String> _availableCategories = {};
  Set<String> _activeCategories = {};
  bool _poisInitiallyLoaded = false;

  bool get _isTestArea =>
      widget.areaId == mapAreaFatih ||
      widget.areaId == mapAreaBeyoglu ||
      widget.areaId == mapAreaUskudar ||
      widget.areaId == mapAreaKadikoy ||
      widget.areaId == mapAreaAnkara;

  bool get _hasPoiData =>
      widget.areaId == mapAreaGtu ||
      widget.areaId == mapAreaFatih ||
      widget.areaId == mapAreaBeyoglu ||
      widget.areaId == mapAreaUskudar ||
      widget.areaId == mapAreaKadikoy ||
      widget.areaId == mapAreaAnkara;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedArea = resolveMapArea(widget.areaId);
    _mapId = widget.mapId.trim().isEmpty ? widget.areaId : widget.mapId.trim();
    _mapName =
        widget.mapName.trim().isEmpty
            ? _selectedArea.title
            : widget.mapName.trim();
    _initialCenter = widget.initialUserPosition ?? _selectedArea.center;
    _uid = FirebaseAuth.instance.currentUser?.uid;
    unawaited(_prepareMapSession());
  }

  Future<void> _prepareMapSession() async {
    CampusMapState? restoredState;
    final uid = _uid;

    if (uid != null) {
      try {
        restoredState = await _mapProgressService.fetchMapState(
          uid: uid,
          mapId: _mapId,
        );
        debugPrint('[Restore] uid=$uid, mapId=$_mapId, visitedPois=${restoredState?.visitedPoiIds.length ?? 0}, revealedCells=${restoredState?.revealedCellIds.length ?? 0}');
      } catch (e) {
        debugPrint('[Restore] Hata: $e');
      }

      try {
        await _mapProgressService.markMapOpened(
          uid: uid,
          mapId: _mapId,
          areaId: _selectedArea.id,
          mapName: _mapName,
        );
      } catch (_) {
        // Opening registration should not block map launch.
      }
    }

    final restoredCenter =
        restoredState?.cameraCenter ??
        restoredState?.lastInsidePosition ??
        widget.initialUserPosition ??
        _selectedArea.center;
    final restoredZoom =
        (restoredState?.zoom ?? 16.0).clamp(14.8, 19.2).toDouble();

    final mapController = CampusMapController(
      fogManager: FogManager(
        campusBoundary: _selectedArea.boundary,
        gridSizeMeters: _selectedArea.gridSizeMeters,
      ),
      locationService: LocationService(
        pollingInterval: const Duration(seconds: 4),
      ),
      defaultCenter: restoredCenter,
      initialUserPosition:
          restoredState?.lastInsidePosition ?? widget.initialUserPosition,
      restoredState: restoredState,
      onPersistStateRequested:
          (state) => _persistMapState(uid: uid, mapState: state),
      testMode: _isTestArea,
    );
    mapController.addListener(_onControllerChanged);

    if (!mounted) {
      mapController.removeListener(_onControllerChanged);
      await mapController.disposeController();
      return;
    }

    setState(() {
      _initialCenter = restoredCenter;
      _initialZoom = restoredZoom;
      _mapController = mapController;
      _visitedPoiIds = Set.from(restoredState?.visitedPoiIds ?? []);
      _isLoadingSession = false;
    });

    _poiTapSub = mapController.onPoiTapped.listen(_onPoiTapped);
  }

  void _onPoiTapped(Map<String, dynamic> payload) {
    if (!mounted) return;
    
    final id = payload['_feature_id']?.toString() ?? payload['name']?.toString() ?? '';
    if (id.isEmpty) return;
    
    final name = payload['name']?.toString() ?? 'Bilinmeyen Mekan';
    final category = payload['category']?.toString() ?? '';
    final poiType = payload['poi_type']?.toString() ?? '';
    final description = payload['description']?.toString() ?? '';
    final photoUrl = payload['photo_url']?.toString() ?? '';
    final lat = (payload['lat'] as num?)?.toDouble() ?? 0.0;
    final lon = (payload['lon'] as num?)?.toDouble() ?? 0.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        int? xpAnimAmount; // Closure scope — survives setSheetState rebuilds
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final currentVisited = _visitedPoiIds.contains(id);

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              decoration: const BoxDecoration(
                color: AppColors.bgBottom,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Photo header
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
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.network(
                              photoUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.card,
                                child: const Icon(
                                  Icons.image_not_supported_rounded,
                                  color: AppColors.textMuted,
                                  size: 40,
                                ),
                              ),
                              loadingBuilder: (_, child, progress) {
                                if (progress == null) return child;
                                return Container(
                                  color: AppColors.card,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                );
                              },
                            ),
                            // Bottom gradient for text readability
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              height: 60,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      Colors.black.withValues(alpha: 0.6),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Category badge on photo
                            if (poiType.isNotEmpty)
                              Positioned(
                                top: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    poiType,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                  // Content section
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
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.check_circle, color: AppColors.primary, size: 14),
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
                                color: AppColors.textMain.withValues(alpha: 0.85),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Bottom button area wrapped in a Stack to allow XPPopup to overflow without clipping
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                        child: SafeArea(
                          top: false,
                          child: SizedBox(
                            width: double.infinity,
                            child: GezdimButton(
                              venueId: id,
                              mapId: _mapId,
                              venueLat: lat,
                              venueLng: lon,
                              currentVisited: currentVisited,
                              onCheckInSuccess: () async {
                                _visitedPoiIds.add(id);
                                _mapController?.visitedPoiIds = _visitedPoiIds.toList();
                                xpAnimAmount = 50;
                                debugPrint('[Gezdim] CheckIn başarılı: poi=$id, visited=${_visitedPoiIds.length}/$_totalPoiCount, uid=$_uid');
                                setSheetState(() {});
                                setState(() {});
                                
                                if (!context.mounted) return;
                                debugPrint('[Gezdim] onPlaceVisited çağrılıyor...');
                                try {
                                  final isLevelUp = await ref.read(gameProvider.notifier).onPlaceVisited(id, category, false);
                                  debugPrint('[Gezdim] onPlaceVisited tamamlandı, isLevelUp=$isLevelUp');
                                  if (context.mounted && isLevelUp) {
                                    final userXP = ref.read(gameProvider).valueOrNull;
                                    if (userXP != null) {
                                      LevelUpDialog.show(context, userXP.currentTitle);
                                    }
                                  }
                                } catch (e) {
                                  debugPrint('[Gezdim] onPlaceVisited HATA: $e');
                                }
                                _loadAndShowPois();
                                
                                // Harita tamamlandı mı kontrol et
                                if (_totalPoiCount > 0 && _visitedPoiIds.length >= _totalPoiCount) {
                                  if (context.mounted) {
                                    MapCompletedDialog.show(
                                      context, 
                                      _mapName,
                                      uid: _uid,
                                      mapId: _mapId,
                                      gameNotifier: ref.read(gameProvider.notifier),
                                    );
                                  }
                                }

                                unawaited(_persistMapState(
                                  uid: _uid, 
                                  mapState: CampusMapState(
                                    revealedCellIds: _mapController?.fogManager.snapshotRevealedCellIds() ?? [],
                                    visitedPoiIds: _visitedPoiIds.toList(),
                                    lastInsidePosition: _mapController?.restoredState?.lastInsidePosition,
                                    cameraCenter: _initialCenter,
                                    zoom: _initialZoom,
                                  )
                                ));
                              },
                              onCancelVisit: () async {
                                _visitedPoiIds.remove(id);
                                _mapController?.visitedPoiIds = _visitedPoiIds.toList();
                                xpAnimAmount = -50;
                                debugPrint('[Gezdim] İptal: poi=$id, visited=${_visitedPoiIds.length}/$_totalPoiCount, uid=$_uid');
                                setSheetState(() {});
                                setState(() {});
                                _loadAndShowPois();
                                
                                // XP düşür
                                debugPrint('[Gezdim] removeXP çağrılıyor...');
                                try {
                                  await ref.read(gameProvider.notifier).removeXP(50);
                                  debugPrint('[Gezdim] removeXP tamamlandı');
                                } catch (e) {
                                  debugPrint('[Gezdim] removeXP HATA: $e');
                                }
                                
                                unawaited(_persistMapState(
                                  uid: _uid, 
                                  mapState: CampusMapState(
                                    revealedCellIds: _mapController?.fogManager.snapshotRevealedCellIds() ?? [],
                                    visitedPoiIds: _visitedPoiIds.toList(),
                                    lastInsidePosition: _mapController?.restoredState?.lastInsidePosition,
                                    cameraCenter: _initialCenter,
                                    zoom: _initialZoom,
                                  )
                                ));
                              },
                            ),
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
                  ),
                ],
              ),
            );
          }
        );
      },
    );
  }

  /// Parses POI JSON from Firestore once and caches in [_parsedPois].
  Future<void> _ensurePoisParsed() async {
    if (_parsedPois.isNotEmpty) return;

    final rawList = await PoiService().getPoisForCity(widget.areaId);

    final categories = <String>{};
    final parsed = <Map<String, dynamic>>[];

    for (final map in rawList) {
      final name = map['isim'] as String? ?? map['name'] as String? ?? '';
      final type = map['kategori'] as String? ?? map['type'] as String? ?? 'unknown';
      final rarity = map['oncelik'] as String? ?? map['rarity'] as String? ?? 'common';
      final category = map['alt_kategori'] as String? ?? map['category'] as String? ?? '';
      final xp = (map['xp'] as num?)?.toInt() ?? 0;
      final description = map['aciklama'] as String? ?? '';
      final photoUrl = map['foto_url'] as String? ?? '';

      double lon = 0;
      double lat = 0;
      if (map.containsKey('koordinatlar')) {
        final coords = map['koordinatlar'] as Map<String, dynamic>;
        lon = (coords['longitude'] as num).toDouble();
        lat = (coords['latitude'] as num).toDouble();
      } else {
        lon = (map['lon'] as num).toDouble();
        lat = (map['lat'] as num).toDouble();
      }

      final featureId = map['id']?.toString() ?? name;
      categories.add(type);

      parsed.add(<String, dynamic>{
        'featureId': featureId,
        'name': name,
        'type': type,
        'rarity': rarity,
        'category': category,
        'xp': xp,
        'description': description,
        'photo_url': photoUrl,
        'lon': lon,
        'lat': lat,
      });
    }

    _parsedPois = parsed;
    _availableCategories = categories;
    if (!_poisInitiallyLoaded) {
      _activeCategories = Set.from(categories);
      _poisInitiallyLoaded = true;
    }
  }

  Future<void> _loadAndShowPois() async {
    final controller = _mapController;
    if (controller == null || !_hasPoiData) return;

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
            'description': poi['description'],
            'photo_url': poi['photo_url'],
            'visited': _visitedPoiIds.contains(featureId),
            'lat': poi['lat'],
            'lon': poi['lon'],
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

      if (mounted) {
        setState(() {
          _totalPoiCount = _parsedPois.length;
        });
      }

      // First load uses addPoiGeoJsonLayer (creates source + layers).
      // Subsequent calls update existing source.
      if (!_poisInitiallyLoaded || !controller.styleReady) {
        await controller.addPoiGeoJsonLayer(geoJson);
      } else {
        await controller.updatePoiGeoJson(geoJson);
      }
    } catch (e, st) {
      debugPrint('Error loading POIs: $e\n$st');
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

  Future<void> _persistMapState({
    required String? uid,
    required CampusMapState mapState,
  }) async {
    if (uid == null) {
      debugPrint('[Persist] uid null — kaydetme atlandı!');
      return;
    }

    debugPrint('[Persist] Kaydediliyor: uid=$uid, mapId=$_mapId, visited=${mapState.visitedPoiIds.length}');
    await _mapProgressService.saveMapState(
      uid: uid,
      mapId: _mapId,
      areaId: _selectedArea.id,
      mapName: _mapName,
      state: mapState,
    );
    debugPrint('[Persist] Kayıt tamamlandı.');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _mapController?.flushPersist();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poiTapSub?.cancel();
    final mapController = _mapController;
    if (mapController != null) {
      mapController.removeListener(_onControllerChanged);
      unawaited(mapController.disposeController());
    }
    super.dispose();
  }

  Future<bool> _showExitConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.bgBottom,
          title: const Text('Çıkış', style: TextStyle(color: AppColors.textMain)),
          content: const Text(
            'Haritadan çıkmak istediğinize emin misiniz? İlerlemeniz kaydedildi.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal', style: TextStyle(color: AppColors.textMuted)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Çıkış', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  void _onControllerChanged() {
    if (!mounted) return;

    final mapController = _mapController;
    if (mapController == null) return;

    if (mapController.isOutOfCampus && !_warningShown) {
      _warningShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kampüs dışındasın'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!mapController.isOutOfCampus) {
      _warningShown = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapController = _mapController;
    if (_isLoadingSession || mapController == null) {
      return Scaffold(
        backgroundColor: AppColors.bgBottom,
        appBar: AppBar(
          backgroundColor: AppColors.bgTop,
          foregroundColor: AppColors.textMain,
          title: Text(_mapName),
        ),
        body: _MapLoadingSplash(
          mapName: _mapName,
          areaTitle: _selectedArea.title,
        ),
      );
    }

    return AnimatedBuilder(
      animation: mapController,
      builder: (context, _) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final shouldPop = await _showExitConfirmation();
            if (shouldPop && context.mounted) {
              // BÖLÜM 2 — Rozet Kontrolü (Haritadan Çıkarken)
              final bContext = BadgeCheckContext(
                totalVisited: _visitedPoiIds.length,
                historicBuildingVisited: _parsedPois.where((p) => _visitedPoiIds.contains(p['featureId']) && (p['category'].toString().toLowerCase().contains('tarih') || p['type'].toString().toLowerCase().contains('tarih'))).length,
                mosqueVisited: _parsedPois.where((p) => _visitedPoiIds.contains(p['featureId']) && (p['category'].toString().toLowerCase().contains('cami') || p['type'].toString().toLowerCase().contains('cami'))).length,
                distinctCitiesVisited: 1, // Mevcut scope içinde tek şehir
                coopSessionsCompleted: 0,
                distinctCoopPartners: 0,
                coopMapJustCompleted: false,
                currentStreak: ref.read(gameProvider).valueOrNull?.weeklyQuests.duzenliGezgin.current ?? 0,
                allWeeklyQuestsJustCompleted: false,
                visitTime: DateTime.now(),
                recentVisitTimes: [DateTime.now()],
                lastVisitedMapId: _mapId,
                lastVisitedMapCompletion: _totalPoiCount > 0 ? _visitedPoiIds.length / _totalPoiCount : 0.0,
                weeklyLeaderboardRank: 999,
              );

              final newBadges = await _badgeAwardService.checkAndAwardBadges(
                uid: _uid!,
                context: bContext,
                gameNotifier: ref.read(gameProvider.notifier),
              );

              if (newBadges.isNotEmpty && context.mounted) {
                await BadgeCelebrationDialog.show(context, newBadges);
              }

              if (context.mounted) {
                Navigator.of(context).popUntil(
                  (route) => route.settings.name == AppRouter.home,
                );
              }
            }
          },
          child: Scaffold(
            backgroundColor: AppColors.bgBottom,
          appBar: AppBar(
            backgroundColor: AppColors.bgTop,
            foregroundColor: AppColors.textMain,
            title: Text(_mapName),
          ),
          body: Stack(
            children: [
              MapWidget(
                key: ValueKey('$_mapId-map'),
                styleUri: _selectedArea.styleUri,
                cameraOptions: CameraOptions(
                  center: Point(coordinates: _initialCenter),
                  zoom: _initialZoom,
                  bearing: 0,
                  pitch: 0,
                ),
                onMapCreated:
                    (mapboxMap) =>
                        unawaited(mapController.onMapCreated(mapboxMap)),
                onTapListener: mapController.handleMapTap,
                onStyleLoadedListener:
                    (_) => unawaited(
                      mapController.onStyleLoaded().then((_) => _loadAndShowPois()),
                    ),
                onCameraChangeListener: mapController.onCameraChanged,
              ),
              if (mapController.isOutOfCampus)
                Positioned(
                  top: 14,
                  left: 14,
                  right: 14,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xE6B3261E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Text(
                        'Kampüs dışındasın. Harita ve sis sistemi durduruldu.',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              // ── Category filter chips ──
              if (_hasPoiData && _availableCategories.isNotEmpty)
                Positioned(
                  left: 0,
                  right: 0,
                  top: mapController.isOutOfCampus ? 70 : 10,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xCC12091F),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.inputBorder.withValues(alpha: 0.35),
                      ),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          _CategoryChip(
                            label: 'Tümü',
                            isActive: _activeCategories.length == _availableCategories.length,
                            onTap: _toggleAllCategories,
                            showAllIcon: true,
                          ),
                          const SizedBox(width: 6),
                          for (final category in _availableCategories) ...[
                            _CategoryChip(
                              label: category,
                              isActive: _activeCategories.contains(category),
                              onTap: () => _toggleCategory(category),
                              categoryColor: _categoryColorMap[category],
                            ),
                            const SizedBox(width: 6),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 18,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xCC190D2A),
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
                    child: Text(
                      _hasPoiData
                          ? 'Gezilen: ${_visitedPoiIds.length} / $_totalPoiCount  |  ${mapController.revealedCellCount}/${mapController.totalCellCount} hücre'
                          : mapController.statusMessage ??
                              '${_selectedArea.title} fog modu: ${mapController.revealedCellCount}/${mapController.totalCellCount} hücre açıldı',
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 18,
                bottom: 94,
                child: _ZoomControls(
                  canZoomIn:
                      !mapController.isOutOfCampus &&
                      mapController.currentZoom < mapController.maxZoom - 0.02,
                  canZoomOut:
                      !mapController.isOutOfCampus &&
                      mapController.currentZoom > mapController.minZoom + 0.02,
                  onZoomIn: () => unawaited(mapController.zoomBy(0.8)),
                  onZoomOut: () => unawaited(mapController.zoomBy(-0.8)),
                ),
              ),
            ],
          ),
        ));
      },
    );
  }
}

class _ZoomControls extends StatelessWidget {
  const _ZoomControls({
    required this.canZoomIn,
    required this.canZoomOut,
    required this.onZoomIn,
    required this.onZoomOut,
  });

  final bool canZoomIn;
  final bool canZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xE6211634), Color(0xE6150E26)],
        ),
        border: Border.all(
          color: AppColors.inputBorder.withValues(alpha: 0.65),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ZoomButton(
              icon: Icons.add_rounded,
              enabled: canZoomIn,
              onTap: onZoomIn,
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 10),
              height: 1,
              color: AppColors.inputBorder.withValues(alpha: 0.45),
            ),
            _ZoomButton(
              icon: Icons.remove_rounded,
              enabled: canZoomOut,
              onTap: onZoomOut,
            ),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      splashRadius: 22,
      icon: Icon(
        icon,
        size: 26,
        color:
            enabled
                ? AppColors.textMain
                : AppColors.textMuted.withValues(alpha: 0.5),
      ),
    );
  }
}

class _MapLoadingSplash extends StatefulWidget {
  const _MapLoadingSplash({required this.mapName, required this.areaTitle});

  final String mapName;
  final String areaTitle;

  @override
  State<_MapLoadingSplash> createState() => _MapLoadingSplashState();
}

class _MapLoadingSplashState extends State<_MapLoadingSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final dots = '. ' * (_controller.value * 3).floor().clamp(1, 3);
        final compactDots = dots.replaceAll(' ', '');
        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.bgTop, AppColors.bgBottom],
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 126,
                    height: 126,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.rotate(
                          angle: _controller.value * math.pi * 2,
                          child: Container(
                            width: 110 + (10 * _pulse.value),
                            height: 110 + (10 * _pulse.value),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.primary.withValues(
                                  alpha: 0.35 + (_pulse.value * 0.4),
                                ),
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppColors.primary, AppColors.secondary],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.35,
                                ),
                                blurRadius: 22,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.explore_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.mapName,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.areaTitle} haritası hazırlanıyor$compactDots',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
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
          color: isActive
              ? dotColor.withValues(alpha: 0.18)
              : Colors.transparent,
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
            if (showAllIcon) ...[
              Icon(
                isActive
                    ? Icons.grid_view_rounded
                    : Icons.grid_view_rounded,
                size: 14,
                color: isActive ? AppColors.primary : AppColors.textMuted,
              ),
            ] else ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? dotColor
                      : dotColor.withValues(alpha: 0.3),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: dotColor.withValues(alpha: 0.4),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? AppColors.textMain
                    : AppColors.textMuted.withValues(alpha: 0.7),
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Map of category names to their marker colors (matching map_controller.dart).
const Map<String, Color> _categoryColorMap = {
  'Cami': Color(0xFF10B981),
  'Saray': Color(0xFFF59E0B),
  'Müze': Color(0xFF3B82F6),
  'Tarihi Yapı': Color(0xFF6B7280),
  'Meydan': Color(0xFFF43F5E),
  'Hamam': Color(0xFF06B6D4),
  'Çarşı & Pazar': Color(0xFF8B5CF6),
  'Park & Bahçe': Color(0xFF84CC16),
  'Semt & Cadde': Color(0xFFF97316),
  'Kule & Tepe': Color(0xFFEF4444),
  'Sinagog & Kilise': Color(0xFFA855F7),
  'Eğitim Binası': Color(0xFF3B82F6),
  'Araştırma Merkezi': Color(0xFFF59E0B),
  'Spor Tesisleri': Color(0xFF10B981),
  'Yeme & İçme': Color(0xFFF43F5E),
};

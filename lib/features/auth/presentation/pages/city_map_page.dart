import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../data/services/poi_service.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/services/map_progress_service.dart';
import '../../data/services/map_area_firestore_service.dart';
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
import '../../../../widgets/location_disclosure_dialog.dart';
import '../../../badges/data/badge_award_service.dart';
import '../../../badges/domain/badge_definitions.dart';
import '../../../badges/presentation/widgets/badge_celebration_dialog.dart';
import '../../../../widgets/quest_completed_dialog.dart';
import '../../../../core/services/interstitial_ad_manager.dart';
import '../../../place_suggestion/presentation/suggest_place_button.dart';
import '../../../place_suggestion/presentation/place_suggestion_form_sheet.dart';
import '../../../place_suggestion/presentation/animated_map_pin.dart';
import '../../../daily_exploration/data/services/daily_exploration_analytics.dart';
import '../../../daily_exploration/data/services/daily_exploration_service.dart';
import '../../../daily_exploration/data/services/share_map_snapshot_service.dart';
import '../../../daily_exploration/domain/models/daily_exploration.dart';
import '../../../daily_exploration/domain/models/debug_sample_exploration.dart';
import '../../../daily_exploration/domain/models/route_point.dart';
import '../../../daily_exploration/domain/models/share_map_scene.dart';
import '../../../daily_exploration/presentation/pages/exploration_share_preview_page.dart';
import '../../../daily_exploration/presentation/widgets/daily_exploration_summary_sheet.dart';

class CityMapPageArgs {
  const CityMapPageArgs({
    required this.areaId,
    required this.mapId,
    required this.mapName,
    this.initialUserPosition,
    this.mapAreaConfig,
    this.fogEnabled = true,
  });

  final String areaId;
  final String mapId;
  final String mapName;
  final Position? initialUserPosition;
  final MapAreaConfig? mapAreaConfig;
  final bool fogEnabled;
}

class CityMapPage extends ConsumerStatefulWidget {
  const CityMapPage({
    super.key,
    required this.areaId,
    required this.mapId,
    required this.mapName,
    this.initialUserPosition,
    this.mapAreaConfig,
    this.fogEnabled = true,
  });

  final String areaId;
  final String mapId;
  final String mapName;
  final Position? initialUserPosition;
  final MapAreaConfig? mapAreaConfig;
  final bool fogEnabled;

  @override
  ConsumerState<CityMapPage> createState() => _CityMapPageState();
}

class _CityMapPageState extends ConsumerState<CityMapPage>
    with WidgetsBindingObserver {
  final MapProgressService _mapProgressService = MapProgressService();
  final MapAreaFirestoreService _mapAreaService = MapAreaFirestoreService();
  final BadgeAwardService _badgeAwardService = BadgeAwardService();
  final DailyExplorationService _dailyExplorationService =
      DailyExplorationService();
  final DailyExplorationAnalytics _dailyExplorationAnalytics =
      const DailyExplorationAnalytics();
  final ShareMapSnapshotService _shareMapSnapshotService =
      const ShareMapSnapshotService();

  CampusMapController? _mapController;
  late MapAreaConfig _selectedArea;
  late final String _mapId;
  late final String _mapName;
  late bool _fogEnabled;
  late Position _initialCenter;
  double _initialZoom = 16.0;
  bool _isLoadingSession = true;
  String? _sessionErrorMessage;
  bool _warningShown = false;
  String? _uid;
  Set<String> _visitedPoiIds = {};
  int _totalPoiCount = 0;
  bool _isReadOnlyCompletedMap = false;
  StreamSubscription<Map<String, dynamic>>? _poiTapSub;
  bool _dailySessionStartInFlight = false;
  bool _dailySessionEnded = false;
  bool _exitFlowInProgress = false;

  // Category filtering
  List<Map<String, dynamic>> _parsedPois = [];
  Set<String> _availableCategories = {};
  Set<String> _activeCategories = {};
  bool _poisInitiallyLoaded = false;
  bool _poiLayerCreated = false;

  // Yer Öner — suggest mode state
  bool _isSuggestMode = false;
  Position? _suggestPin;
  double? _suggestScreenX;
  double? _suggestScreenY;
  Key _pinKey = UniqueKey();

  bool get _hasPoiData => true;

  static const bool _kTestMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _selectedArea = widget.mapAreaConfig ?? resolveMapArea(widget.areaId);
    _mapId = widget.mapId.trim().isEmpty ? widget.areaId : widget.mapId.trim();
    _fogEnabled = widget.fogEnabled;
    _mapName =
        widget.mapName.trim().isEmpty
            ? _selectedArea.title
            : widget.mapName.trim();
    _initialCenter = widget.initialUserPosition ?? _selectedArea.center;
    _uid = FirebaseAuth.instance.currentUser?.uid;
    unawaited(_prepareMapSession());
  }

  Future<void> _prepareMapSession() async {
    final uid = _uid;

    try {
      await Future.wait([
        _loadAreaConfig(),
        _loadMapState(uid),
      ]).timeout(const Duration(seconds: 25));
    } on TimeoutException {
      debugPrint(
        '[Session] Timeout aşıldı, varsayılan değerlerle devam ediliyor.',
      );
    } catch (e) {
      debugPrint('[Session] Hazırlık hatası: $e');
    }

    if (!mounted) return;

    final restoredState = _cachedRestoredState;

    // For real areas, GPS position (passed from selection screen) takes
    // priority over saved camera state so the map always opens on the user.
    final restoredCenter =
        widget.initialUserPosition ??
        restoredState?.lastInsidePosition ??
        _selectedArea.center;

    final restoredZoom =
        (restoredState?.zoom ?? 16.0).clamp(14.8, 19.2).toDouble();

    final canStartLocation = await _requestBackgroundPermissionIfNeeded();
    if (!canStartLocation || !mounted) {
      if (mounted) {
        setState(() {
          _isLoadingSession = false;
          _sessionErrorMessage =
              'Haritayı açmak için konum ve arka plan konum izni gerekiyor.';
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).maybePop();
          }
        });
      }
      return;
    }

    final mapController = CampusMapController(
      fogManager: FogManager(
        campusBoundary: _selectedArea.boundary,
        gridSizeMeters: _selectedArea.gridSizeMeters,
        revealRadiusMeters: _selectedArea.gridSizeMeters * 1.3,
      ),
      fogEnabled: _fogEnabled,
      locationService: LocationService(
        pollingInterval: const Duration(seconds: 4),
        requestDisclosureConsent: _showLocationDisclosure,
      ),
      defaultCenter: restoredCenter,
      initialUserPosition:
          widget.initialUserPosition ?? restoredState?.lastInsidePosition,
      restoredState: restoredState,
      onPersistStateRequested:
          (state) => _persistMapState(uid: uid, mapState: state),
      areaMinZoom: _selectedArea.minZoom,
      skipLocationVerification:
          _kTestMode || _selectedArea.skipLocationVerification,
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

  Future<bool> _requestBackgroundPermissionIfNeeded() async {
    if (_kTestMode || _selectedArea.skipLocationVerification) return true;
    if (!mounted) return false;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final hasBackground = await LocationService.hasBackgroundPermission();
    if (hasBackground) return true;

    var permission = await geo.Geolocator.checkPermission();
    if (permission != geo.LocationPermission.whileInUse &&
        permission != geo.LocationPermission.always) {
      final accessResult = await LocationService.requestSinglePosition(
        requestDisclosureConsent: _showLocationDisclosure,
      );
      if (!mounted) return false;
      if (!accessResult.isGranted) {
        _showLocationGateMessage(accessResult.status);
        await navigator.maybePop();
        return false;
      }

      permission = await geo.Geolocator.checkPermission();
      if (permission != geo.LocationPermission.whileInUse &&
          permission != geo.LocationPermission.always) {
        _showLocationGateMessage(LocationAccessStatus.permissionDenied);
        await navigator.maybePop();
        return false;
      }
    }

    if (!mounted) return false;

    final agree = await _showLocationDisclosure();

    geo.LocationPermission? result;
    if (agree == true && mounted) {
      result = await LocationService.requestAlwaysPermission();
    }

    if (!mounted) return false;

    if (result == geo.LocationPermission.deniedForever) {
      await _showBackgroundPermissionSettingsDialog();
      return false;
    }

    final hasBackgroundAfterRequest =
        result == geo.LocationPermission.always ||
        await LocationService.hasBackgroundPermission();
    if (!hasBackgroundAfterRequest) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Haritayı kullanmak için arka plan konum iznini de vermen gerekiyor.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await navigator.maybePop();
      return false;
    }

    if (mounted) {
      unawaited(_requestIgnoreBatteryOptimizations());
    }
    return true;
  }

  Future<void> _showBackgroundPermissionSettingsDialog() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const Text('Arka Plan Konum İzni Gerekli'),
            content: const Text(
              'Haritayı kullanmak için "Her Zaman" konum izni gerekiyor. Bu izin '
              'daha önce reddedildiği için uygulama üzerinden tekrar sorulamıyor '
              '— izni açmak için Ayarlar\'a gitmen gerekiyor.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  LocationService.openSettings();
                },
                child: const Text('Ayarları Aç'),
              ),
            ],
          ),
    );
    if (!mounted) return;
    await navigator.maybePop();
  }

  void _showLocationGateMessage(LocationAccessStatus status) {
    final message = switch (status) {
      LocationAccessStatus.serviceDisabled =>
        'Konum servisleri kapalı. Haritayı kullanmak için konumu etkinleştir.',
      LocationAccessStatus.permissionDenied =>
        'Konum izni gerekli. Lütfen izin verip tekrar dene.',
      LocationAccessStatus.permissionDeniedForever =>
        'Konum izni kalıcı olarak reddedildi. Ayarlardan izin vermen gerekiyor.',
      LocationAccessStatus.unavailable =>
        'Konum bilgisi alınamadı. Uygulamayı yeniden başlatıp tekrar dene.',
      LocationAccessStatus.granted => '',
    };
    if (message.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<bool> _showLocationDisclosure() async {
    if (!mounted) return false;
    if (Platform.isIOS) return true;
    return showLocationDisclosureDialog(context);
  }

  Future<void> _requestIgnoreBatteryOptimizations() async {
    if (_kTestMode) return;
    if (!mounted || !Platform.isAndroid) return;

    try {
      final status = await geo.Geolocator.isLocationServiceEnabled();
      if (!status) return;

      final alreadyGranted = await Permission.ignoreBatteryOptimizations.status;
      if (alreadyGranted.isGranted) return;

      if (!mounted) return;
      final agree = await showDialog<bool>(
        context: context,
        builder:
            (ctx) => AlertDialog(
              backgroundColor: AppColors.bgBottom,
              title: const Text(
                'Pil Tasarrufu İstisnası',
                style: TextStyle(color: AppColors.textMain),
              ),
              content: const Text(
                'Bazı telefonlar (Xiaomi, Huawei, Samsung vb.) uygulamaları '
                'arka planda kısıtlayarak konum takibini durdurabilir. '
                'Kesintisiz takip için pil optimizasyonu istisnası eklemek '
                'ister misiniz?',
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
                    'İzin Ver',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
              ],
            ),
      );

      if (agree == true && mounted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (_) {
      // Battery optimization request is best-effort.
    }
  }

  CampusMapState? _cachedRestoredState;

  Future<void> _loadAreaConfig() async {
    if (widget.mapAreaConfig != null) return;
    try {
      final firestoreArea = await _mapAreaService.fetchArea(widget.areaId);
      if (firestoreArea != null) {
        _selectedArea = firestoreArea;
        if (widget.initialUserPosition == null) {
          _initialCenter = firestoreArea.center;
        }
      }
    } catch (e) {
      debugPrint('[Session] Area config yüklenemedi: $e');
    }
  }

  Future<void> _loadMapState(String? uid) async {
    if (uid == null) return;
    try {
      final record = await _mapProgressService.fetchMapById(
        uid: uid,
        mapId: _mapId,
      );
      _cachedRestoredState = record?.state;
      _isReadOnlyCompletedMap = record?.isCompleted ?? false;
      if (record != null) _fogEnabled = record.fogEnabled;
      debugPrint(
        '[Restore] uid=$uid, mapId=$_mapId, visitedPois=${_cachedRestoredState?.visitedPoiIds.length ?? 0}, revealedCells=${_cachedRestoredState?.revealedCellIds.length ?? 0}',
      );
    } catch (e) {
      debugPrint('[Restore] Hata: $e');
    }

    try {
      unawaited(
        _mapProgressService.markMapOpened(
          uid: uid,
          mapId: _mapId,
          areaId: _selectedArea.id,
          mapName: _mapName,
        ),
      );
    } catch (_) {
      // Opening registration should not block map launch.
    }
  }

  void _onPoiTapped(Map<String, dynamic> payload) {
    if (!mounted) return;

    final id =
        payload['_feature_id']?.toString() ?? payload['name']?.toString() ?? '';
    if (id.isEmpty) return;

    final name = payload['name']?.toString() ?? 'Bilinmeyen Mekan';
    final category = payload['category']?.toString() ?? '';
    final poiType = payload['poi_type']?.toString() ?? '';
    final description = payload['description']?.toString() ?? '';
    final photoUrl = payload['photo_url']?.toString() ?? '';
    final lat = (payload['lat'] as num?)?.toDouble() ?? 0.0;
    final lon = (payload['lon'] as num?)?.toDouble() ?? 0.0;
    final xpValue = (payload['xp'] as num?)?.toInt() ?? 50;

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
                            CachedNetworkImage(
                              imageUrl: photoUrl,
                              fit: BoxFit.cover,
                              errorWidget:
                                  (context, url, error) => Container(
                                    color: AppColors.card,
                                    child: const Icon(
                                      Icons.image_not_supported_rounded,
                                      color: AppColors.textMuted,
                                      size: 40,
                                    ),
                                  ),
                              placeholder:
                                  (context, url) => Container(
                                    color: AppColors.card,
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: AppColors.primary,
                                        size: 14,
                                      ),
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
                                color: AppColors.textMain.withValues(
                                  alpha: 0.85,
                                ),
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
                  if (_isReadOnlyCompletedMap)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: SafeArea(
                        top: false,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.greenAccept.withValues(
                              alpha: 0.13,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: AppColors.greenAccept.withValues(
                                alpha: 0.36,
                              ),
                            ),
                          ),
                          child: Text(
                            _fogEnabled
                                ? 'Tamamlanan harita salt okunur. Gezilen mekanları ve açılan sisi görüntüleyebilirsin.'
                                : 'Tamamlanan harita salt okunur. Rotanı ve gezilen mekanları görüntüleyebilirsin.',
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    )
                  else
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
                                xpValue: xpValue,
                                userLat:
                                    _mapController?.lastInsidePosition?.lat
                                        .toDouble(),
                                userLng:
                                    _mapController?.lastInsidePosition?.lng
                                        .toDouble(),
                                onCheckInSuccess: (checkInResult) async {
                                  _visitedPoiIds.add(id);
                                  _mapController?.visitedPoiIds =
                                      _visitedPoiIds.toList();
                                  xpAnimAmount =
                                      checkInResult.xpEligible ? xpValue : null;
                                  debugPrint(
                                    '[Gezdim] CheckIn başarılı: poi=$id, visited=${_visitedPoiIds.length}/$_totalPoiCount, uid=$_uid',
                                  );
                                  setSheetState(() {});
                                  setState(() {});

                                  if (!context.mounted) return;
                                  debugPrint(
                                    '[Gezdim] onPlaceVisited çağrılıyor...',
                                  );
                                  if (checkInResult.xpEligible) {
                                    try {
                                      final isLevelUp = await ref
                                          .read(gameProvider.notifier)
                                          .onPlaceVisited(
                                            id,
                                            category,
                                            false,
                                            xpValue: xpValue,
                                          );
                                      debugPrint(
                                        '[Gezdim] onPlaceVisited tamamlandı, isLevelUp=$isLevelUp',
                                      );
                                      if (context.mounted && isLevelUp) {
                                        final userXP =
                                            ref.read(gameProvider).valueOrNull;
                                        if (userXP != null) {
                                          LevelUpDialog.show(
                                            context,
                                            userXP.currentTitle,
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      debugPrint(
                                        '[Gezdim] onPlaceVisited HATA: $e',
                                      );
                                    }
                                    await _recordDailyPoi(
                                      poiId: id,
                                      xp: xpValue,
                                    );
                                  } else {
                                    debugPrint(
                                      '[Gezdim] XP atlandı: completed/duplicate check-in',
                                    );
                                  }
                                  await _loadAndShowPois();

                                  if (checkInResult.mapCompleted) {
                                    if (context.mounted) {
                                      MapCompletedDialog.show(
                                        context,
                                        _mapName,
                                        subtitle:
                                            '1 harita slotun açıldı. Yeni bir harita oluşturabilirsin.',
                                        uid: _uid,
                                        mapId: _mapId,
                                        gameNotifier: ref.read(
                                          gameProvider.notifier,
                                        ),
                                      );
                                    }
                                  }

                                  unawaited(
                                    _persistMapState(
                                      uid: _uid,
                                      mapState: CampusMapState(
                                        revealedCellIds:
                                            _mapController?.fogManager
                                                .snapshotRevealedCellIds() ??
                                            [],
                                        visitedPoiIds: _visitedPoiIds.toList(),
                                        lastInsidePosition:
                                            _mapController
                                                ?.restoredState
                                                ?.lastInsidePosition,
                                        cameraCenter: _initialCenter,
                                        zoom: _initialZoom,
                                      ),
                                    ),
                                  );
                                },
                                onCancelVisit: () async {
                                  _visitedPoiIds.remove(id);
                                  _mapController?.visitedPoiIds =
                                      _visitedPoiIds.toList();
                                  xpAnimAmount = -xpValue;
                                  debugPrint(
                                    '[Gezdim] İptal: poi=$id, visited=${_visitedPoiIds.length}/$_totalPoiCount, uid=$_uid',
                                  );
                                  setSheetState(() {});
                                  setState(() {});
                                  await _loadAndShowPois();

                                  // XP düşür
                                  debugPrint('[Gezdim] removeXP çağrılıyor...');
                                  try {
                                    await ref
                                        .read(gameProvider.notifier)
                                        .removeXP(xpValue);
                                    debugPrint('[Gezdim] removeXP tamamlandı');
                                  } catch (e) {
                                    debugPrint('[Gezdim] removeXP HATA: $e');
                                  }
                                  await _removeDailyPoi(poiId: id, xp: xpValue);

                                  unawaited(
                                    _persistMapState(
                                      uid: _uid,
                                      mapState: CampusMapState(
                                        revealedCellIds:
                                            _mapController?.fogManager
                                                .snapshotRevealedCellIds() ??
                                            [],
                                        visitedPoiIds: _visitedPoiIds.toList(),
                                        lastInsidePosition:
                                            _mapController
                                                ?.restoredState
                                                ?.lastInsidePosition,
                                        cameraCenter: _initialCenter,
                                        zoom: _initialZoom,
                                      ),
                                    ),
                                  );
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
          },
        );
      },
    );
  }

  /// Parses POI JSON from Firestore once and caches in [_parsedPois].
  Future<void> _ensurePoisParsed() async {
    if (_parsedPois.isNotEmpty) return;

    try {
      final rawList = await PoiService().getPoisForCity(widget.areaId);
      debugPrint('[Map] ${widget.areaId} için ${rawList.length} POI alındı.');

      if (!mounted) return;
      final categories = <String>{};
      final parsed = <Map<String, dynamic>>[];

      for (final map in rawList) {
        try {
          final name = (map['name'] as String?)?.trim() ?? '';
          final type = (map['category'] as String?)?.trim() ?? 'unknown';
          final xpValue = (map['xpValue'] as num?)?.toInt() ?? 0;
          final String rarity;
          if (xpValue >= 100) {
            rarity = 'must-see';
          } else if (xpValue >= 75) {
            rarity = 'önerilen';
          } else if (xpValue >= 50) {
            rarity = 'rare';
          } else {
            rarity = map['rarity'] as String? ?? 'common';
          }
          final category = type;
          final description = map['description'] as String? ?? '';
          final photoUrl = map['imageUrl'] as String? ?? '';
          // Support both 'longitude'/'latitude' and 'lon'/'lat' field names
          final lon =
              (map['longitude'] as num?)?.toDouble() ??
              (map['lon'] as num?)?.toDouble() ??
              0;
          final lat =
              (map['latitude'] as num?)?.toDouble() ??
              (map['lat'] as num?)?.toDouble() ??
              0;

          if (lon == 0 && lat == 0) {
            debugPrint('[Map] Koordinat bulunamadı, POI atlanıyor: $name');
            continue;
          }

          final featureId = map['id']?.toString() ?? name;
          categories.add(type);

          parsed.add(<String, dynamic>{
            'featureId': featureId,
            'name': name,
            'type': type,
            'rarity': rarity,
            'category': category,
            'xp': xpValue,
            'description': description,
            'photo_url': photoUrl,
            'lon': lon,
            'lat': lat,
          });
        } catch (e) {
          debugPrint('[Map] POI parse hatası (atlanıyor): $e — veri: $map');
        }
      }

      debugPrint(
        '[Map] ${widget.areaId}: ${parsed.length} geçerli POI parse edildi.',
      );
      _parsedPois = parsed;
      _availableCategories = categories;
      if (!_poisInitiallyLoaded) {
        _activeCategories = Set.from(categories);
        _poisInitiallyLoaded = true;
      }
    } catch (e) {
      debugPrint('[Map] POI verisi alınamadı: $e');
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
      if (!_poiLayerCreated) {
        _poiLayerCreated = true;
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

    debugPrint(
      '[Persist] Kaydediliyor: uid=$uid, mapId=$_mapId, visited=${mapState.visitedPoiIds.length}',
    );
    await _mapProgressService.saveMapState(
      uid: uid,
      mapId: _mapId,
      areaId: _selectedArea.id,
      mapName: _mapName,
      state: mapState,
      totalPois: _totalPoiCount,
    );
    debugPrint('[Persist] Kayıt tamamlandı.');
  }

  void _startDailySessionIfReady() {
    final controller = _mapController;
    final uid = _uid;
    if (controller == null ||
        uid == null ||
        !controller.trackingReady ||
        _dailySessionStartInFlight ||
        _dailySessionEnded ||
        _dailyExplorationService.hasActiveSession) {
      return;
    }
    _dailySessionStartInFlight = true;
    unawaited(
      _dailyExplorationService
          .startSession(
            uid: uid,
            mapId: _mapId,
            areaId: _selectedArea.id,
            mapName: _mapName,
            trackingStream: controller.locationService.trackingStream,
            isInsideBoundary:
                (point) => controller.fogManager.contains(
                  Position(point.longitude, point.latitude),
                ),
          )
          .catchError((Object error) {
            debugPrint('[DailyExploration] Oturum başlatılamadı: $error');
          })
          .whenComplete(() => _dailySessionStartInFlight = false),
    );
  }

  Future<void> _recordDailyPoi({required String poiId, required int xp}) async {
    try {
      await _dailyExplorationService.addPoi(poiId: poiId, xp: xp);
    } catch (error) {
      debugPrint('[DailyExploration] POI kaydedilemedi: $error');
    }
  }

  Future<void> _removeDailyPoi({required String poiId, required int xp}) async {
    try {
      await _dailyExplorationService.removePoi(poiId: poiId, xp: xp);
    } catch (error) {
      debugPrint('[DailyExploration] POI iptali kaydedilemedi: $error');
    }
  }

  ShareMapScene _shareMapScene(DailyExploration exploration) {
    return ShareMapScene.fromDailyExploration(
      exploration: exploration,
      boundaryGeoJson: _selectedArea.boundaryGeoJson,
    );
  }

  /// Debug-only preview deliberately shows just the 1080×820 map panel.
  Future<void> _openDebugShareMapPreview() async {
    if (!kDebugMode) return;
    final center = _selectedArea.center;
    final sample = buildDebugSampleExploration(
      anchorLat: center.lat.toDouble(),
      anchorLng: center.lng.toDouble(),
      mapId: _mapId,
      areaId: _selectedArea.id,
      mapName: _mapName,
    );
    final scene = _shareMapScene(sample);
    try {
      final mapSnapshot = await _shareMapSnapshotService.createSnapshot(
        scene,
      );
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder:
              (_) => ExplorationSharePreviewPage(
                exploration: sample,
                initialMapSnapshot: mapSnapshot,
                createMapSnapshot:
                    () => _shareMapSnapshotService.createSnapshot(scene),
              ),
        ),
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[ShareMapSnapshot] Debug önizleme hatası: $error\n$stackTrace',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Harita paneli oluşturulamadı: $error')),
      );
    }
  }

  Future<DailyExploration?> _finishDailySession() async {
    _dailySessionEnded = true;
    try {
      final exploration = await _dailyExplorationService.finishSession();
      if (exploration == null) return null;
      await _ensurePoisParsed();
      final poiLocations = <String, RoutePoint>{};
      final poiNames = <String, String>{};
      for (final poi in _parsedPois) {
        final id = poi['featureId']?.toString();
        if (id == null || !exploration.newPoiIds.contains(id)) continue;
        final lat = (poi['lat'] as num?)?.toDouble();
        final lng = (poi['lon'] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        poiLocations[id] = RoutePoint(
          latitude: lat,
          longitude: lng,
          accuracy: 0,
          timestamp: exploration.date,
        );
        final name = poi['name']?.toString();
        if (name != null && name.isNotEmpty) poiNames[id] = name;
      }
      return exploration.copyWith(
        poiLocations: poiLocations,
        poiNames: poiNames,
      );
    } catch (error) {
      debugPrint('[DailyExploration] Oturum kapatılamadı: $error');
      return null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _mapController?.flushPersist();
      unawaited(_dailyExplorationService.flushSession());
      if (state == AppLifecycleState.paused) {
        _mapController?.setBackgroundMode(true);
      }
    } else if (state == AppLifecycleState.resumed) {
      _mapController?.setBackgroundMode(false);
      _mapController?.snapToLastInsidePosition();
    }
  }

  @override
  void deactivate() {
    _mapController?.flushPersist();
    unawaited(_dailyExplorationService.flushSession());
    super.deactivate();
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
    if (_dailyExplorationService.hasActiveSession) {
      unawaited(
        _dailyExplorationService.finishSession().whenComplete(
          _dailyExplorationService.dispose,
        ),
      );
    } else {
      unawaited(_dailyExplorationService.dispose());
    }
    super.dispose();
  }

  Future<bool> _showExitConfirmation() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.bgBottom,
          title: const Text(
            'Çıkış',
            style: TextStyle(color: AppColors.textMain),
          ),
          content: const Text(
            'Haritadan çıkmak istediğinize emin misiniz? İlerlemeniz kaydedildi.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'İptal',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Çıkış',
                style: TextStyle(color: AppColors.primary),
              ),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _handleExit() async {
    if (_exitFlowInProgress || !mounted) return;
    final shouldExit = await _showExitConfirmation();
    if (!shouldExit || !mounted) return;
    _exitFlowInProgress = true;

    final navigator = Navigator.of(context);
    final uid = _uid;
    var navigatedHome = false;
    var newBadgeDefs = <BadgeDefinition>[];

    try {
      final dailyExploration = await _finishDailySession();
      try {
        await _mapController?.flushPersist();
      } catch (error) {
        debugPrint('[Exit] Flush hatası: $error');
      }

      final badgeContext = BadgeCheckContext(
        totalVisited: _visitedPoiIds.length,
        historicBuildingVisited:
            _parsedPois
                .where(
                  (poi) =>
                      _visitedPoiIds.contains(poi['featureId']) &&
                      (poi['category'].toString().toLowerCase().contains(
                            'tarih',
                          ) ||
                          poi['type'].toString().toLowerCase().contains(
                            'tarih',
                          )),
                )
                .length,
        mosqueVisited:
            _parsedPois
                .where(
                  (poi) =>
                      _visitedPoiIds.contains(poi['featureId']) &&
                      (poi['category'].toString().toLowerCase().contains(
                            'cami',
                          ) ||
                          poi['type'].toString().toLowerCase().contains(
                            'cami',
                          )),
                )
                .length,
        distinctCitiesVisited: 1,
        coopSessionsCompleted: 0,
        distinctCoopPartners: 0,
        coopMapJustCompleted: false,
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
        recentVisitTimes: <DateTime>[DateTime.now()],
        lastVisitedMapId: _mapId,
        lastVisitedMapCompletion:
            _totalPoiCount > 0 ? _visitedPoiIds.length / _totalPoiCount : 0,
      );
      final badgeFuture =
          uid == null
              ? Future<List<BadgeDefinition>>.value(const <BadgeDefinition>[])
              : _badgeAwardService.checkNewBadges(
                uid: uid,
                context: badgeContext,
              );

      if (dailyExploration != null && mounted) {
        _dailyExplorationAnalytics.promptShown(dailyExploration);
        final action = await DailyExplorationSummarySheet.show(
          context,
          dailyExploration,
        );
        if (!mounted) return;
        if (action == DailyExplorationSummaryAction.share) {
          _dailyExplorationAnalytics.previewOpened(dailyExploration);
          try {
            final scene = _shareMapScene(dailyExploration);
            // The card page is opened only after Snapshotter has finished.
            final mapSnapshot = await _shareMapSnapshotService.createSnapshot(
              scene,
            );
            if (!navigator.mounted) return;
            await navigator.push<bool>(
              MaterialPageRoute<bool>(
                builder:
                    (_) => ExplorationSharePreviewPage(
                      exploration: dailyExploration,
                      initialMapSnapshot: mapSnapshot,
                      createMapSnapshot:
                          () => _shareMapSnapshotService.createSnapshot(scene),
                    ),
              ),
            );
          } catch (error, stackTrace) {
            debugPrint(
              '[ShareMapSnapshot] Harita paneli oluşturulamadı: '
              '$error\n$stackTrace',
            );
            _dailyExplorationAnalytics.failed(dailyExploration);
            if (navigator.mounted) {
              ScaffoldMessenger.of(navigator.context).showSnackBar(
                SnackBar(content: Text('Harita oluşturulamadı: $error')),
              );
            }
          }
        } else {
          _dailyExplorationAnalytics.dismissed(dailyExploration);
        }
      }

      await InterstitialAdManager.instance.show();
      if (navigator.mounted) {
        navigatedHome = true;
        navigator.pushNamedAndRemoveUntil(AppRouter.home, (route) => false);
      }

      try {
        newBadgeDefs = await badgeFuture;
      } catch (error) {
        debugPrint('[Exit] Rozet kontrolü hatası: $error');
      }
      if (newBadgeDefs.isNotEmpty && uid != null && navigator.mounted) {
        unawaited(
          _badgeAwardService.awardBadges(
            uid: uid,
            badges: newBadgeDefs,
            gameNotifier: ref.read(gameProvider.notifier),
          ),
        );
        await BadgeCelebrationDialog.show(
          navigator.context,
          newBadgeDefs.map((definition) => definition.id).toList(),
          showAsPill: true,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('[Exit] Beklenmeyen hata: $error\n$stackTrace');
    } finally {
      if (!navigatedHome && navigator.mounted) {
        navigatedHome = true;
        navigator.pushNamedAndRemoveUntil(AppRouter.home, (route) => false);
      }
      if (navigator.mounted) {
        final notifier = ref.read(gameProvider.notifier);
        final completions = notifier.consumePendingQuestCompletions();
        final earnedXp =
            ref.read(gameProvider).valueOrNull?.weeklyQuests.earnedWeeklyXP ??
            0;
        for (final info in completions) {
          if (!navigator.mounted) break;
          await QuestCompletedDialog.show(
            navigator.context,
            info,
            currentWeeklyXP: earnedXp,
          );
        }
      }
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;

    final mapController = _mapController;
    if (mapController == null) return;
    _startDailySessionIfReady();

    if (mapController.isOutOfCampus && !_warningShown) {
      _warningShown = true;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Harita alanı dışındasın'),
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
    if (_isLoadingSession) {
      return Scaffold(
        backgroundColor: AppColors.bgBottom,
        appBar: AppBar(
          backgroundColor: AppColors.bgTop,
          foregroundColor: AppColors.textMain,
          title: Text(_mapName),
        ),
        body: _MapLoadingSplash(mapName: _mapName),
      );
    }

    if (mapController == null) {
      return Scaffold(
        backgroundColor: AppColors.bgBottom,
        appBar: AppBar(
          backgroundColor: AppColors.bgTop,
          foregroundColor: AppColors.textMain,
          title: Text(_mapName),
        ),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_off_rounded,
                    color: AppColors.textMuted,
                    size: 42,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _sessionErrorMessage ?? 'Harita başlatılamadı.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 15,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Geri Dön'),
                  ),
                ],
              ),
            ),
          ),
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
            await _handleExit();
          },
          child: Scaffold(
            backgroundColor: AppColors.bgBottom,
            appBar: AppBar(
              backgroundColor: AppColors.bgTop,
              foregroundColor: AppColors.textMain,
              title: Text(_mapName),
              actions: [
                if (kDebugMode)
                  IconButton(
                    onPressed: _openDebugShareMapPreview,
                    icon: const Icon(Icons.image_outlined),
                    tooltip: 'Paylaşım haritası önizlemesi (debug)',
                  ),
              ],
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
                  onTapListener: (ctx) {
                    if (_isSuggestMode) {
                      final coord = ctx.point.coordinates;
                      final tp = ctx.touchPosition;
                      setState(() {
                        _suggestPin = coord;
                        _suggestScreenX = tp.x;
                        _suggestScreenY = tp.y;
                        _pinKey = UniqueKey();
                      });
                    } else {
                      mapController.handleMapTap(ctx);
                    }
                  },
                  onStyleLoadedListener:
                      (_) => unawaited(
                        mapController.onStyleLoaded().then(
                          (_) => _loadAndShowPois(),
                          onError:
                              (e) => debugPrint('[Map] POI yükleme hatası: $e'),
                        ),
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
                          'Harita alanı dışındasın. Harita ve sis sistemi durduruldu.',
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
                              isActive:
                                  _activeCategories.length ==
                                  _availableCategories.length,
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
                        (!mapController.trackingReady &&
                                mapController.statusMessage != null)
                            ? mapController.statusMessage!
                            : (_hasPoiData
                                ? 'Gezilen: ${_visitedPoiIds.length} / $_totalPoiCount'
                                : mapController.statusMessage ??
                                    _selectedArea.title),
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
                        mapController.currentZoom <
                            mapController.maxZoom - 0.02,
                    canZoomOut:
                        !mapController.isOutOfCampus &&
                        mapController.currentZoom >
                            mapController.minZoom + 0.02,
                    onZoomIn: () => unawaited(mapController.zoomBy(0.8)),
                    onZoomOut: () => unawaited(mapController.zoomBy(-0.8)),
                  ),
                ),
                // ── Yer Öner button (shown when NOT in suggest mode) ────
                if (!_isSuggestMode)
                  Positioned(
                    left: 16,
                    bottom: 94,
                    child: SuggestPlaceButton(
                      onTap:
                          () => setState(() {
                            _isSuggestMode = true;
                            _suggestPin = null;
                            _suggestScreenX = null;
                            _suggestScreenY = null;
                          }),
                    ),
                  ),
                // ── Suggest mode overlay ──────────────────────────────
                if (_isSuggestMode) ...[
                  // Tooltip card at the top
                  Positioned(
                    top: (_availableCategories.isNotEmpty) ? 64 : 14,
                    left: 14,
                    right: 14,
                    child: _SuggestTooltipCard(),
                  ),
                  // Animated pin at the tapped screen position
                  if (_suggestScreenX != null && _suggestScreenY != null)
                    Positioned(
                      left: _suggestScreenX! - 28,
                      top: _suggestScreenY! - 56,
                      child: AnimatedMapPin(key: _pinKey),
                    ),
                  // Close (X) button top-right
                  Positioned(
                    top: 8,
                    right: 8,
                    child: SafeArea(
                      child: Material(
                        color: const Color(0xCC12091F),
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap:
                              () => setState(() {
                                _isSuggestMode = false;
                                _suggestPin = null;
                                _suggestScreenX = null;
                                _suggestScreenY = null;
                              }),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Icon(
                              Icons.close_rounded,
                              color: AppColors.textMain,
                              size: 22,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bottom action bar
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _SuggestBottomBar(
                      pinSelected: _suggestPin != null,
                      onCancel:
                          () => setState(() {
                            _isSuggestMode = false;
                            _suggestPin = null;
                            _suggestScreenX = null;
                            _suggestScreenY = null;
                          }),
                      onConfirm: () {
                        final pin = _suggestPin;
                        if (pin == null) return;
                        final lat = pin.lat.toDouble();
                        final lng = pin.lng.toDouble();
                        setState(() {
                          _isSuggestMode = false;
                          _suggestScreenX = null;
                          _suggestScreenY = null;
                        });
                        showModalBottomSheet<bool>(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder:
                              (_) => PlaceSuggestionFormSheet(
                                latitude: lat,
                                longitude: lng,
                                mapAreaId: _selectedArea.id,
                                onChangeLocation:
                                    () => setState(() {
                                      _isSuggestMode = true;
                                      _suggestPin = null;
                                      _suggestScreenX = null;
                                      _suggestScreenY = null;
                                    }),
                              ),
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
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
  const _MapLoadingSplash({required this.mapName});

  final String mapName;

  @override
  State<_MapLoadingSplash> createState() => _MapLoadingSplashState();
}

class _MapLoadingSplashState extends State<_MapLoadingSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;
  bool _timedOut = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) setState(() => _timedOut = true);
    });
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
                    _timedOut
                        ? 'Bağlantı sorunu oluştu.'
                        : '${widget.mapName} hazırlanıyor${'.' * (_controller.value * 3).floor().clamp(1, 3)}',
                    style: TextStyle(
                      color:
                          _timedOut
                              ? const Color(0xFFE57373)
                              : AppColors.textMuted,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_timedOut) ...[
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Geri dön'),
                    ),
                  ],
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
          color:
              isActive ? dotColor.withValues(alpha: 0.18) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isActive
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
                isActive ? Icons.grid_view_rounded : Icons.grid_view_rounded,
                size: 14,
                color: isActive ? AppColors.primary : AppColors.textMuted,
              ),
            ] else ...[
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? dotColor : dotColor.withValues(alpha: 0.3),
                  boxShadow:
                      isActive
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
                color:
                    isActive
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

// ─── Suggest mode helpers ──────────────────────────────────────────────────────

class _SuggestTooltipCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xF0130826),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.inputBorder.withValues(alpha: 0.5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(
              child: Icon(
                Icons.location_on_rounded,
                color: AppColors.primary,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Önerdiğin yeri işaretle',
                  style: TextStyle(
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    text: 'Haritada eksik olan mekana ',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                    children: [
                      TextSpan(
                        text: 'dokunarak',
                        style: TextStyle(
                          color: AppColors.textMain,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(text: '\niğne bırak.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestBottomBar extends StatelessWidget {
  const _SuggestBottomBar({
    required this.pinSelected,
    required this.onCancel,
    required this.onConfirm,
  });

  final bool pinSelected;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xF0130826),
          border: Border(
            top: BorderSide(
              color: AppColors.inputBorder.withValues(alpha: 0.4),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            // Vazgeç
            Expanded(
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  side: BorderSide(
                    color: AppColors.textMuted.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Vazgeç',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Burayı işaretle
            Expanded(
              flex: 2,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient:
                      pinSelected
                          ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [AppColors.primary, AppColors.secondary],
                          )
                          : null,
                  color:
                      pinSelected
                          ? null
                          : AppColors.textMuted.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ElevatedButton(
                  onPressed: pinSelected ? onConfirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(
                    'Burayı işaretle',
                    style: TextStyle(
                      color: pinSelected ? Colors.white : AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/map/fog_manager.dart';
import '../../../auth/presentation/map/location_service.dart';
import '../../../auth/presentation/map/map_areas.dart';
import '../../../auth/presentation/map/map_controller.dart';

/// Onboarding slaytları bitince açılan, tamamen kurgulanmış (scripted)
/// bir keşif demosu. Gerçek konum, izin veya Firestore yazımı YOKTUR —
/// [CampusMapController] gerçek harita render pipeline'ını aynen kullanır,
/// sadece konum kaynağı [feedSimulatedPosition] ile beslenen sahte bir
/// rotadır. Ödül/XP/rozet verilmez, sadece mekaniği gösterir.
class OnboardingDemoPage extends StatefulWidget {
  const OnboardingDemoPage({super.key});

  @override
  State<OnboardingDemoPage> createState() => _OnboardingDemoPageState();
}

class _DemoPoi {
  _DemoPoi({required this.name, required this.position});

  final String name;
  final Position position;
  bool visited = false;
}

enum OnboardingDemoCheckInStage { approaching, ready, completed, dismissed }

/// Demo haritasının üzerinde gösterilen, check-in akışını adım adım anlatan
/// rehber kart. Haritadan bağımsız tutulduğu için widget testinde de gerçek
/// Mapbox/GPS bağımlılıklarına ihtiyaç duymaz.
class OnboardingDemoCheckInCard extends StatelessWidget {
  const OnboardingDemoCheckInCard({
    super.key,
    required this.stage,
    required this.venueName,
    required this.onOpenCheckIn,
    required this.onContinue,
  });

  final OnboardingDemoCheckInStage stage;
  final String venueName;
  final VoidCallback onOpenCheckIn;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final completed = stage == OnboardingDemoCheckInStage.completed;
    return Container(
      key: ValueKey(
        completed ? 'demo-check-in-success' : 'demo-check-in-guide',
      ),
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bgBottom.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (completed ? Colors.greenAccent : AppColors.primary)
              .withValues(alpha: 0.55),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (completed ? Colors.greenAccent : AppColors.primary)
                      .withValues(alpha: 0.18),
                ),
                child: Icon(
                  completed ? Icons.check_rounded : Icons.location_on_rounded,
                  color: completed ? Colors.greenAccent : AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      completed ? 'Check-in tamamlandı!' : 'Mekana ulaştın',
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      venueName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            completed
                ? 'Mekan keşfedildi olarak işaretlendi. Gerçek gezilerinde yakınlık doğrulandıktan sonra XP ve harita ilerlemen güncellenir.'
                : 'Yakındaki mekan işaretine dokunup “Gezdim” butonuyla check-in yapabilirsin.',
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: ValueKey(
                completed ? 'demo-check-in-continue' : 'demo-check-in-open',
              ),
              onPressed: completed ? onContinue : onOpenCheckIn,
              style: FilledButton.styleFrom(
                backgroundColor:
                    completed ? Colors.green.shade700 : AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: Icon(
                completed ? Icons.directions_walk_rounded : Icons.touch_app,
              ),
              label: Text(completed ? 'Demoya Devam Et' : 'Check-in’i Dene'),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingDemoPageState extends State<OnboardingDemoPage> {
  static const Duration _stepInterval = Duration(milliseconds: 1300);
  static const Duration _checkInSimulationDuration = Duration(
    milliseconds: 700,
  );
  static const int _stepsPerSegment = 5;
  static const double _poiVisitRadiusMeters = 25;

  static const String _walkerSourceId = 'onboarding-demo-walker-source';
  static const String _walkerLayerId = 'onboarding-demo-walker-layer';

  late final List<Position> _route = _buildRoute();
  late final List<_DemoPoi> _pois = _buildPois();

  CampusMapController? _mapController;
  MapboxMap? _mapboxMap;
  StreamSubscription<Map<String, dynamic>>? _poiTapSub;
  Timer? _routeTimer;
  int _stepIndex = 0;
  bool _finished = false;
  bool _checkInSheetOpen = false;
  int _visitedCount = 0;
  OnboardingDemoCheckInStage _checkInStage =
      OnboardingDemoCheckInStage.approaching;

  @override
  void initState() {
    super.initState();
    final controller = CampusMapController(
      fogManager: FogManager(
        campusBoundary: beyogluBoundary,
        gridSizeMeters: 35,
        revealRadiusMeters: 45,
      ),
      locationService: LocationService(),
      defaultCenter: beyogluCenter,
      initialUserPosition: _route.first,
      skipLocationVerification: true,
    );
    controller.addListener(_onControllerChanged);
    _poiTapSub = controller.onPoiTapped.listen(_onPoiTapped);
    _mapController = controller;
  }

  @override
  void dispose() {
    _routeTimer?.cancel();
    unawaited(_poiTapSub?.cancel());
    _mapController?.removeListener(_onControllerChanged);
    unawaited(_mapController?.disposeController());
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  List<Position> _buildRoute() {
    final center = beyogluCenter;
    Position offset(double dLng, double dLat) =>
        Position(center.lng + dLng, center.lat + dLat);

    final checkpoints = <Position>[
      center,
      offset(0.0000, 0.0007),
      offset(0.0008, 0.0009),
      offset(0.0012, 0.0002),
      offset(0.0008, -0.0006),
      offset(0.0000, -0.0008),
      offset(-0.0008, -0.0005),
      offset(-0.0010, 0.0003),
      offset(-0.0004, 0.0008),
      center,
    ];

    final route = <Position>[];
    for (var i = 0; i < checkpoints.length - 1; i++) {
      final start = checkpoints[i];
      final end = checkpoints[i + 1];
      for (var step = 0; step < _stepsPerSegment; step++) {
        final t = step / _stepsPerSegment;
        route.add(
          Position(
            start.lng + (end.lng - start.lng) * t,
            start.lat + (end.lat - start.lat) * t,
          ),
        );
      }
    }
    route.add(checkpoints.last);
    return route;
  }

  List<_DemoPoi> _buildPois() {
    // Rotanın 2, 4 ve 7. checkpoint'lerinden geçtiği noktalar. İlk noktada
    // rehberli check-in aşaması tetiklenir; diğerleri rotayı görselleştirir.
    final center = beyogluCenter;
    return [
      _DemoPoi(
        name: 'Galatasaray Lisesi',
        position: Position(center.lng + 0.0008, center.lat + 0.0009),
      ),
      _DemoPoi(
        name: 'Çiçek Pasajı',
        position: Position(center.lng + 0.0008, center.lat - 0.0006),
      ),
      _DemoPoi(
        name: 'Tünel Meydanı',
        position: Position(center.lng - 0.0010, center.lat + 0.0003),
      ),
    ];
  }

  Future<void> _onStyleLoaded() async {
    final controller = _mapController;
    if (controller == null) return;
    await controller.onStyleLoaded();
    await controller.addPoiGeoJsonLayer(_poiGeoJson());
    await _addWalkerMarker(_route.first);
    _startRoute();
  }

  void _startRoute() {
    _routeTimer?.cancel();
    _routeTimer = Timer.periodic(_stepInterval, (_) => _advanceRoute());
  }

  void _advanceRoute() {
    final controller = _mapController;
    if (controller == null || _finished) return;
    if (_stepIndex >= _route.length) {
      _finishDemo();
      return;
    }
    final position = _route[_stepIndex];
    unawaited(controller.feedSimulatedPosition(position));
    unawaited(_updateWalkerMarker(position));
    _checkForGuidedCheckIn(position);
    _stepIndex++;
    if (mounted) setState(() {});
  }

  void _checkForGuidedCheckIn(Position current) {
    if (_checkInStage != OnboardingDemoCheckInStage.approaching) return;
    final poi = _pois.first;
    if (haversineDistanceMeters(current, poi.position) >=
        _poiVisitRadiusMeters) {
      return;
    }

    // Gerçek check-in gibi kullanıcının eylemini beklemek için yürüyüş burada
    // durur. Mekan yalnızca "Gezdim" onayından sonra ziyaret edilmiş sayılır.
    _routeTimer?.cancel();
    _checkInStage = OnboardingDemoCheckInStage.ready;
  }

  String _poiGeoJson() {
    final features = _pois
        .map(
          (poi) =>
              '{'
              '"type":"Feature",'
              '"geometry":{"type":"Point","coordinates":[${poi.position.lng},${poi.position.lat}]},'
              '"properties":{'
              '"name":"${poi.name}",'
              '"poi_type":"Tarihi Yapı",'
              '"rarity":"önerilen",'
              '"visited":${poi.visited}'
              '}'
              '}',
        )
        .join(',');
    return '{"type":"FeatureCollection","features":[$features]}';
  }

  String _walkerGeoJson(Position position) =>
      '{"type":"Feature","geometry":{"type":"Point","coordinates":[${position.lng},${position.lat}]},"properties":{}}';

  /// Demo yürüyüşçüsünü temsil eden özel bir işaretçi ekler. Native konum
  /// puck'ı [CampusMapController] içinde demo modunda devre dışı
  /// bırakıldığı için (gerçek GPS'e bağlı olduğundan), sahte rotayı gösteren
  /// bu ayrı katman kullanılır.
  Future<void> _addWalkerMarker(Position position) async {
    final map = _mapboxMap;
    if (map == null) return;
    try {
      await map.style.addSource(
        GeoJsonSource(id: _walkerSourceId, data: _walkerGeoJson(position)),
      );
      await map.style.addLayer(
        CircleLayer(
          id: _walkerLayerId,
          sourceId: _walkerSourceId,
          circleRadius: 9.0,
          circleColor: const Color(0xFF2F80ED).toARGB32(),
          circleStrokeWidth: 3.0,
          circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
        ),
      );
    } on PlatformException {
      await _updateWalkerMarker(position);
    }
  }

  Future<void> _updateWalkerMarker(Position position) async {
    final map = _mapboxMap;
    if (map == null) return;
    try {
      final existing = await map.style.getSource(_walkerSourceId);
      if (existing is GeoJsonSource) {
        await existing.updateGeoJSON(_walkerGeoJson(position));
      } else {
        await _addWalkerMarker(position);
      }
    } catch (_) {
      // Kaynak henüz hazır değilse sessizce yok say — bir sonraki adımda
      // tekrar denenecek.
    }
  }

  void _onPoiTapped(Map<String, dynamic> payload) {
    final name = payload['name'] as String?;
    if (name == null) return;
    final target = _pois.first;
    if (name == target.name &&
        _checkInStage == OnboardingDemoCheckInStage.ready) {
      unawaited(_showGezdimSheet(target));
    }
  }

  Future<void> _showGezdimSheet(_DemoPoi poi) async {
    if (!mounted ||
        _checkInSheetOpen ||
        _checkInStage != OnboardingDemoCheckInStage.ready) {
      return;
    }
    _checkInSheetOpen = true;
    var isLoading = false;
    try {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: AppColors.bgBottom,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (sheetContext, setSheetState) {
              Future<void> checkIn() async {
                if (isLoading) return;
                setSheetState(() => isLoading = true);
                await Future<void>.delayed(_checkInSimulationDuration);
                if (!mounted) return;

                if (!poi.visited) {
                  poi.visited = true;
                  _visitedCount++;
                }
                _checkInStage = OnboardingDemoCheckInStage.completed;
                setState(() {});
                unawaited(_mapController?.updatePoiGeoJson(_poiGeoJson()));
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              }

              return SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.place_rounded, color: AppColors.primary),
                          SizedBox(width: 8),
                          Text(
                            'Yakındaki mekan',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        poi.name,
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Yeterince yakınsın. Ziyaretini doğrulamak için check-in yap.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 18),
                      ElevatedButton(
                        key: const ValueKey('demo-gezdim-button'),
                        onPressed:
                            isLoading ? null : () => unawaited(checkIn()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: AppColors.primary.withValues(
                            alpha: 0.55,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child:
                            isLoading
                                ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                                : const Text(
                                  'Gezdim ✓',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Demo işlemi — hesabına XP veya ziyaret kaydı eklenmez.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _checkInSheetOpen = false;
    }
  }

  void _continueAfterCheckIn() {
    if (_checkInStage != OnboardingDemoCheckInStage.completed) return;
    setState(() {
      _checkInStage = OnboardingDemoCheckInStage.dismissed;
    });
    _startRoute();
  }

  void _finishDemo() {
    if (_finished) return;
    _finished = true;
    _routeTimer?.cancel();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRouter.home);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _mapController;
    if (controller == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    final progress = (_stepIndex / _route.length).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: Stack(
        children: [
          MapWidget(
            key: const ValueKey('onboarding-demo-map'),
            styleUri: defaultMapStyleUri,
            cameraOptions: CameraOptions(
              center: Point(coordinates: _route.first),
              zoom: 16.4,
              bearing: 0,
              pitch: 0,
            ),
            onMapCreated: (mapboxMap) {
              _mapboxMap = mapboxMap;
              unawaited(controller.onMapCreated(mapboxMap));
            },
            onTapListener: controller.handleMapTap,
            onStyleLoadedListener: (_) => unawaited(_onStyleLoaded()),
            onCameraChangeListener: controller.onCameraChanged,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Demo modu — gerçek konumun kullanılmıyor',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (_visitedCount > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$_visitedCount/${_pois.length} mekan keşfedildi',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const Spacer(),
                  if (_checkInStage == OnboardingDemoCheckInStage.ready ||
                      _checkInStage ==
                          OnboardingDemoCheckInStage.completed) ...[
                    OnboardingDemoCheckInCard(
                      stage: _checkInStage,
                      venueName: _pois.first.name,
                      onOpenCheckIn:
                          () => unawaited(_showGezdimSheet(_pois.first)),
                      onContinue: _continueAfterCheckIn,
                    ),
                    const SizedBox(height: 12),
                  ],
                  Align(
                    alignment: Alignment.bottomRight,
                    child: FilledButton(
                      onPressed: _finishDemo,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Demoyu Geç'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

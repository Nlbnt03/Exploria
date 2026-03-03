import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/services/map_progress_service.dart';
import '../../domain/models/campus_map_state.dart';
import '../map/fog_manager.dart';
import '../map/gtu_boundary.dart';
import '../map/location_service.dart';
import '../map/map_controller.dart';

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

class CityMapPage extends StatefulWidget {
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
  State<CityMapPage> createState() => _CityMapPageState();
}

class _CityMapPageState extends State<CityMapPage> {
  final MapProgressService _mapProgressService = MapProgressService();

  CampusMapController? _mapController;
  late final CampusAreaConfig _selectedArea;
  late final String _mapId;
  late final String _mapName;
  late Position _initialCenter;
  double _initialZoom = 16.0;
  bool _isLoadingSession = true;
  bool _warningShown = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _selectedArea = resolveCampusArea(widget.areaId);
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
      } catch (_) {
        // Loading persisted state is best-effort.
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
      _isLoadingSession = false;
    });
  }

  Future<void> _persistMapState({
    required String? uid,
    required CampusMapState mapState,
  }) async {
    if (uid == null) return;

    await _mapProgressService.saveMapState(
      uid: uid,
      mapId: _mapId,
      areaId: _selectedArea.id,
      mapName: _mapName,
      state: mapState,
    );
  }

  @override
  void dispose() {
    final mapController = _mapController;
    if (mapController != null) {
      mapController.removeListener(_onControllerChanged);
      unawaited(mapController.disposeController());
    }
    super.dispose();
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
        return Scaffold(
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
                onStyleLoadedListener:
                    (_) => unawaited(mapController.onStyleLoaded()),
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
                      mapController.statusMessage ??
                          '${_selectedArea.title} fog modu: ${mapController.revealedCellCount}/${mapController.totalCellCount} hucre acildi',
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

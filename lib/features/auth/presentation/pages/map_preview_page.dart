import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/services/poi_service.dart';
import '../map/map_areas.dart';

class MapPreviewPageArgs {
  const MapPreviewPageArgs({
    required this.areaId,
    required this.mode,
    this.mapAreaConfig,
  });

  final String areaId;
  final String mode;
  final MapAreaConfig? mapAreaConfig;
}

class MapPreviewPage extends StatefulWidget {
  const MapPreviewPage({
    super.key,
    required this.areaId,
    required this.mode,
    this.mapAreaConfig,
  });

  final String areaId;
  final String mode;
  final MapAreaConfig? mapAreaConfig;

  @override
  State<MapPreviewPage> createState() => _MapPreviewPageState();
}

class _MapPreviewPageState extends State<MapPreviewPage> {
  late final MapAreaConfig _area;
  MapboxMap? _mapboxMap;
  bool _styleLoaded = false;

  bool get _hasPoiData => true;

  @override
  void initState() {
    super.initState();
    _area = widget.mapAreaConfig ?? resolveMapArea(widget.areaId);
  }

  Future<void> _onStyleLoaded(StyleLoadedEventData _) async {
    if (_styleLoaded) return;
    _styleLoaded = true;
    final map = _mapboxMap;
    if (map == null) return;

    await _addBoundaryPolygon();
    await _loadPreviewPois();
  }

  Future<void> _fitPreviewCamera(List<Position> poiPositions) async {
    final map = _mapboxMap;
    if (map == null) return;

    final allPositions = <Position>[..._area.boundary, ...poiPositions];
    if (allPositions.isEmpty) return;

    final bounds = calculatePolygonBounds(allPositions);
    await map.setBounds(
      CameraBoundsOptions(
        bounds: bounds.toCoordinateBounds(),
        minZoom: 0,
        maxZoom: 17.5,
        minPitch: 0,
        maxPitch: 75,
      ),
    );
    final camera = await map.cameraForCoordinateBounds(
      bounds.toCoordinateBounds(),
      MbxEdgeInsets(top: 125, left: 28, bottom: 135, right: 28),
      0,
      0,
      14.5,
      null,
    );
    await map.setCamera(camera);
  }

  Future<void> _addBoundaryPolygon() async {
    final map = _mapboxMap;
    if (map == null) return;

    final coordinates =
        _area.boundary
            .map((p) => [p.lng.toDouble(), p.lat.toDouble()])
            .toList();

    // Close the polygon ring
    if (coordinates.isNotEmpty &&
        (coordinates.first[0] != coordinates.last[0] ||
            coordinates.first[1] != coordinates.last[1])) {
      coordinates.add(coordinates.first);
    }

    final geoJson = jsonEncode(<String, Object?>{
      'type': 'FeatureCollection',
      'features': [
        <String, Object?>{
          'type': 'Feature',
          'properties': <String, Object?>{},
          'geometry': <String, Object?>{
            'type': 'Polygon',
            'coordinates': [coordinates],
          },
        },
      ],
    });

    try {
      await map.style.addSource(
        GeoJsonSource(id: 'preview-boundary', data: geoJson),
      );

      // Fill with semi-transparent purple
      await map.style.addLayer(
        FillLayer(
          id: 'preview-boundary-fill',
          sourceId: 'preview-boundary',
          fillColor: AppColors.primary.toARGB32(),
          fillOpacity: 0.12,
        ),
      );

      // Solid border line
      await map.style.addLayer(
        LineLayer(
          id: 'preview-boundary-line',
          sourceId: 'preview-boundary',
          lineColor: AppColors.primary.toARGB32(),
          lineWidth: 2.5,
          lineOpacity: 0.85,
        ),
      );
    } catch (e) {
      debugPrint('Error adding boundary polygon: $e');
    }
  }

  void _onConfirm() {
    Navigator.pop(context, true);
  }

  /// Loads POIs from Firestore and renders them as read-only circle + label layers.
  Future<void> _loadPreviewPois() async {
    final map = _mapboxMap;
    if (map == null || !_hasPoiData) return;

    try {
      final rawList = await PoiService().getPoisForCity(widget.areaId);
      debugPrint(
        '[Preview] ${widget.areaId} için ${rawList.length} POI yüklendi.',
      );

      final features = <Map<String, Object?>>[];
      final poiPositions = <Position>[];
      for (final poi in rawList) {
        try {
          final name = (poi['name'] as String?)?.trim() ?? '';
          final type = (poi['category'] as String?)?.trim() ?? 'unknown';
          final rarity = poi['rarity'] as String? ?? 'common';
          final lon = (poi['longitude'] as num?)?.toDouble() ?? 0;
          final lat = (poi['latitude'] as num?)?.toDouble() ?? 0;

          if (lon == 0 && lat == 0) {
            debugPrint('[Preview] Koordinat bulunamadı, POI atlanıyor: $name');
            continue;
          }

          poiPositions.add(Position(lon, lat));
          features.add(<String, Object?>{
            'type': 'Feature',
            'id': poi['id']?.toString() ?? name,
            'properties': <String, Object?>{
              'name': name,
              'poi_type': type,
              'rarity': rarity,
              'marker_color': _markerColorForCategory(type),
              'marker_radius': _markerRadiusForRarity(rarity),
            },
            'geometry': <String, Object?>{
              'type': 'Point',
              'coordinates': <double>[lon, lat],
            },
          });
        } catch (e) {
          debugPrint('[Preview] POI parse hatası (atlanıyor): $e — veri: $poi');
        }
      }

      debugPrint(
        '[Preview] ${features.length} geçerli POI feature oluşturuldu.',
      );
      final geoJson = jsonEncode(<String, Object?>{
        'type': 'FeatureCollection',
        'features': features,
      });

      const sourceId = 'preview-poi-source';
      const circleLayerId = 'preview-poi-circle';
      const labelLayerId = 'preview-poi-label';

      try {
        await map.style.addSource(GeoJsonSource(id: sourceId, data: geoJson));
      } on PlatformException catch (e) {
        if (!e.toString().toLowerCase().contains('exists')) rethrow;
      }

      try {
        await map.style.addLayer(
          CircleLayer(
            id: circleLayerId,
            sourceId: sourceId,
            circleRadiusExpression: <Object>['get', 'marker_radius'],
            circleColorExpression: <Object>['get', 'marker_color'],
            circleStrokeWidth: 2.0,
            circleStrokeColor: const Color(0xFFFFFFFF).toARGB32(),
            circleOpacity: 0.95,
          ),
        );
      } on PlatformException catch (e) {
        if (!e.toString().toLowerCase().contains('exists')) rethrow;
      }

      try {
        await map.style.addLayer(
          SymbolLayer(
            id: labelLayerId,
            sourceId: sourceId,
            textFieldExpression: <Object>['get', 'name'],
            textSize: 11.0,
            textColor: const Color(0xFFFFFFFF).toARGB32(),
            textHaloColor: const Color(0xFF000000).toARGB32(),
            textHaloWidth: 1.5,
            textOffset: <double>[0, 1.6],
            textMaxWidth: 12.0,
            textAllowOverlap: true,
            iconAllowOverlap: false,
          ),
        );
      } on PlatformException catch (e) {
        if (!e.toString().toLowerCase().contains('exists')) rethrow;
      }

      await _fitPreviewCamera(poiPositions);
    } catch (e) {
      debugPrint('Error loading preview POIs: $e');
    }
  }

  String _markerColorForCategory(String category) {
    switch (category.trim().toLowerCase()) {
      case 'cami':
      case 'park':
      case 'park & bahçe':
      case 'spor tesisleri':
        return '#22C55E';
      case 'saray':
      case 'araştırma merkezi':
        return '#F59E0B';
      case 'müze':
      case 'eğitim binası':
        return '#3B82F6';
      case 'meydan':
      case 'yeme & içme':
        return '#F43F5E';
      case 'hamam':
        return '#06B6D4';
      case 'çarşı':
      case 'çarşı & pazar':
      case 'sinagog & kilise':
        return '#A855F7';
      case 'semt & cadde':
        return '#F97316';
      case 'kule & tepe':
        return '#EF4444';
      default:
        return '#8B5CF6';
    }
  }

  double _markerRadiusForRarity(String rarity) {
    switch (rarity.trim().toLowerCase()) {
      case 'must-see':
      case 'legendary':
        return 13;
      case 'epic':
      case 'önerilen':
        return 11;
      case 'rare':
        return 9;
      default:
        return 8;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Mapbox Map ──
          MapWidget(
            key: ValueKey('preview-${_area.id}'),
            styleUri: _area.styleUri,
            cameraOptions: CameraOptions(
              center: Point(coordinates: _area.center),
              zoom: 10,
              bearing: 0,
              pitch: 0,
            ),
            onMapCreated: (mapboxMap) {
              _mapboxMap = mapboxMap;
              // Disable user location puck – preview only
              mapboxMap.location.updateSettings(
                LocationComponentSettings(enabled: false),
              );
            },
            onStyleLoadedListener: _onStyleLoaded,
          ),

          // ── Top gradient overlay for legibility ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 160,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.bgBottom.withValues(alpha: 0.92),
                      AppColors.bgBottom.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Top bar ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _area.title,
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _area.subtitle,
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Bottom gradient overlay ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 140,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.bgBottom.withValues(alpha: 0.95),
                      AppColors.bgBottom.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── "Haritayı Oluştur" button ──
          Positioned(
            left: 20,
            right: 20,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.45),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _onConfirm,
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        widget.mode == 'multi'
                            ? 'Çoklu Oda Oluştur'
                            : 'Haritayı Oluştur',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Info chip ──
          Positioned(
            left: 16,
            bottom: 80,
            child: SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: AppColors.bgBottom.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppColors.inputBorder.withValues(alpha: 0.5),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.visibility_rounded,
                      color: AppColors.primary,
                      size: 18,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'Ön İzleme',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

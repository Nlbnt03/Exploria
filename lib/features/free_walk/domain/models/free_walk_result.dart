import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../../daily_exploration/domain/models/share_map_scene.dart';
import '../free_walk_tracker.dart';

/// A completed free walk, as it is persisted and re-read from history. Unlike
/// [DailyExploration], a free walk has no map/area — the user cannot resume
/// it — so it is represented and browsed as a standalone record instead of a
/// reopenable map.
class FreeWalkResult {
  const FreeWalkResult({
    required this.id,
    required this.userId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.segments,
  });

  final String id;
  final String userId;
  final DateTime startedAt;
  final DateTime endedAt;
  final double distanceMeters;
  final int durationSeconds;
  final List<List<FreeWalkPoint>> segments;

  List<FreeWalkPoint> get allPoints => <FreeWalkPoint>[
    for (final segment in segments) ...segment,
  ];

  bool get hasRoute => allPoints.length >= 2;

  int get segmentCount =>
      segments.where((segment) => segment.length >= 2).length;

  /// Builds the generic Mapbox scene used to render this walk's share-card
  /// snapshot. Free walks have no boundary or discovered POIs, only a route.
  ShareMapScene toShareScene() {
    final routeSessions = <RouteSession>[];
    for (final entry in segments.indexed) {
      final segment = entry.$2;
      if (segment.length < 2) continue;
      routeSessions.add(
        RouteSession(
          id: 'segment-${entry.$1}',
          startedAt: segment.first.timestamp,
          endedAt: segment.last.timestamp,
          points: <Position>[
            for (final point in segment) Position(point.longitude, point.latitude),
          ],
        ),
      );
    }
    final routePoints = <Position>[
      for (final session in routeSessions) ...session.points,
    ];
    if (routePoints.length < 2) {
      throw ArgumentError.value(
        segments,
        'segments',
        'Paylaşım haritası için en az iki geçerli rota noktası gerekli.',
      );
    }
    return ShareMapScene(
      sessions: routeSessions,
      discoveredPois: const <DiscoveredPoi>[],
      boundaryGeoJson: null,
      startPoint: routePoints.first,
      endPoint: routePoints.last,
      mapName: 'Serbest Yürüyüş',
    );
  }
}

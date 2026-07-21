import 'dart:math' as math;

import 'daily_exploration.dart';
import 'exploration_session.dart';
import 'route_point.dart';

/// Design-preview-only fixture for the "Keşif Kartın" share card: fixed
/// stats (5,4 km · 7 yeni yer · +340 XP · 1 sa 48 dk) over a plausible
/// ~30-point wandering path near [anchorLat]/[anchorLng]. Callers must gate
/// this behind `kDebugMode` — it must never reach a real user's share card.
DailyExploration buildDebugSampleExploration({
  required double anchorLat,
  required double anchorLng,
  required String mapId,
  required String areaId,
  required String mapName,
}) {
  final now = DateTime.now();
  final startedAt = now.subtract(const Duration(hours: 2, minutes: 10));
  final points = _sampleRoutePoints(
    anchorLat: anchorLat,
    anchorLng: anchorLng,
    startedAt: startedAt,
  );
  final session = ExplorationSession(
    sessionId: 'debug-preview-session',
    startedAt: startedAt,
    endedAt: points.last.timestamp,
    distanceMeters: 5400,
    activeDurationSeconds: 6480,
    points: points,
  );

  const poiNames = <String, String>{
    'debug-poi-1': 'Tarihi Çeşme',
    'debug-poi-2': 'Kale Burcu',
    'debug-poi-3': 'Sahil Meydanı',
  };
  final poiLocations = <String, RoutePoint>{
    for (final entry in poiNames.keys.toList().asMap().entries)
      entry.value: points[(points.length ~/ 4) * (entry.key + 1)],
  };

  return DailyExploration(
    userId: 'debug-preview',
    mapId: mapId,
    areaId: areaId,
    mapName: mapName,
    dayKey: DateTime(now.year, now.month, now.day).toIso8601String().substring(
      0,
      10,
    ).replaceAll('-', ''),
    date: now,
    sessionCount: 1,
    totalDistanceMeters: 5400,
    totalDurationSeconds: 6480,
    earnedXp: 340,
    newPoiIds: <String>[
      ...poiNames.keys,
      'debug-poi-4',
      'debug-poi-5',
      'debug-poi-6',
      'debug-poi-7',
    ],
    sessions: <ExplorationSession>[session],
    poiLocations: poiLocations,
    poiNames: poiNames,
  );
}

List<RoutePoint> _sampleRoutePoints({
  required double anchorLat,
  required double anchorLng,
  required DateTime startedAt,
}) {
  const pointCount = 32;
  final rand = math.Random(7);
  final points = <RoutePoint>[];
  for (var i = 0; i < pointCount; i++) {
    final progress = i / (pointCount - 1);
    final angle = progress * 2 * math.pi * 1.6;
    final radius = 0.0022 * (0.35 + 0.65 * progress);
    final jitterLat = (rand.nextDouble() - 0.5) * 0.00025;
    final jitterLng = (rand.nextDouble() - 0.5) * 0.00025;
    points.add(
      RoutePoint(
        latitude: anchorLat + math.sin(angle) * radius + jitterLat,
        longitude: anchorLng + math.cos(angle) * radius * 1.3 + jitterLng,
        accuracy: 6,
        // Kept well under ExplorationSession.maxConnectedGap (2 dk) so every
        // point lands in one continuous walked segment.
        timestamp: startedAt.add(Duration(seconds: i * 15)),
      ),
    );
  }
  return points;
}

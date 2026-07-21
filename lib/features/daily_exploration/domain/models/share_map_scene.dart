import 'dart:convert';

import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import 'daily_exploration.dart';

class ShareMapScene {
  const ShareMapScene({
    required this.sessions,
    required this.discoveredPois,
    required this.boundaryGeoJson,
    required this.startPoint,
    required this.endPoint,
    required this.mapName,
  });

  final List<RouteSession> sessions;
  final List<DiscoveredPoi> discoveredPois;
  final String? boundaryGeoJson;
  final Position startPoint;
  final Position endPoint;
  final String mapName;

  List<Position> get routePoints => <Position>[
    for (final session in sessions) ...session.points,
  ];

  factory ShareMapScene.fromDailyExploration({
    required DailyExploration exploration,
    String? boundaryGeoJson,
  }) {
    final orderedSessions = exploration.sessions.toList(growable: false)
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final routeSessions = <RouteSession>[];
    for (final session in orderedSessions) {
      for (final segmentEntry in session.walkedSegments.indexed) {
        final segment = segmentEntry.$2;
        routeSessions.add(
          RouteSession(
            id: '${session.sessionId}-${segmentEntry.$1}',
            startedAt: segment.first.timestamp,
            endedAt: segment.last.timestamp,
            points: <Position>[
              for (final point in segment)
                Position(point.longitude, point.latitude),
            ],
          ),
        );
      }
    }

    final routePoints = <Position>[
      for (final session in routeSessions) ...session.points,
    ];
    if (routePoints.length < 2) {
      throw ArgumentError.value(
        exploration.sessions,
        'exploration.sessions',
        'Paylaşım haritası için en az iki geçerli rota noktası gerekli.',
      );
    }

    final rawPois = <DiscoveredPoi>[];
    for (final entry in exploration.newPoiIds.indexed) {
      final poiId = entry.$2;
      final point = exploration.poiLocations[poiId];
      if (point == null) continue;
      rawPois.add(
        DiscoveredPoi(
          id: poiId,
          position: Position(point.longitude, point.latitude),
          // Existing daily records preserve discovery order in newPoiIds.
          // The tiny tie-break keeps that order when older records have no
          // per-POI timestamp and all enriched points share the same time.
          visitedAt: point.timestamp.add(Duration(microseconds: entry.$1)),
          name: exploration.poiNames[poiId],
        ),
      );
    }

    final middleNamedIndex = rawPois.isEmpty ? -1 : rawPois.length ~/ 2;
    final pois = <DiscoveredPoi>[
      for (final entry in rawPois.indexed)
        entry.$2.copyWith(isImportant: entry.$1 == middleNamedIndex),
    ];

    return ShareMapScene(
      sessions: routeSessions,
      discoveredPois: pois,
      boundaryGeoJson: boundaryGeoJson,
      startPoint: routePoints.first,
      endPoint: routePoints.last,
      mapName: exploration.mapName,
    );
  }
}

class RouteSession {
  const RouteSession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.points,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final List<Position> points;
}

class DiscoveredPoi {
  const DiscoveredPoi({
    required this.id,
    required this.position,
    required this.visitedAt,
    this.name,
    this.isImportant = false,
  });

  final String id;
  final Position position;
  final DateTime visitedAt;
  final String? name;
  final bool isImportant;

  DiscoveredPoi copyWith({bool? isImportant}) {
    return DiscoveredPoi(
      id: id,
      position: position,
      visitedAt: visitedAt,
      name: name,
      isImportant: isImportant ?? this.isImportant,
    );
  }
}

String? boundaryGeoJsonFromPositions(List<Position> positions) {
  if (positions.length < 3) return null;
  final ring = <List<double>>[
    for (final position in positions)
      <double>[position.lng.toDouble(), position.lat.toDouble()],
  ];
  if (ring.first[0] != ring.last[0] || ring.first[1] != ring.last[1]) {
    ring.add(List<double>.from(ring.first));
  }
  return jsonEncode(<String, Object?>{
    'type': 'Feature',
    'properties': const <String, Object?>{},
    'geometry': <String, Object?>{
      'type': 'Polygon',
      'coordinates': <Object?>[ring],
    },
  });
}

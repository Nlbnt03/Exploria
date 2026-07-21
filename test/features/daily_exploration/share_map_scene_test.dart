import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kesfedio/features/daily_exploration/domain/models/daily_exploration.dart';
import 'package:kesfedio/features/daily_exploration/domain/models/exploration_session.dart';
import 'package:kesfedio/features/daily_exploration/domain/models/route_point.dart';
import 'package:kesfedio/features/daily_exploration/domain/models/share_map_scene.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() {
  RoutePoint point(double lat, double lng, DateTime timestamp) {
    return RoutePoint(
      latitude: lat,
      longitude: lng,
      accuracy: 5,
      timestamp: timestamp,
    );
  }

  test('daily exploration becomes ordered sessions and sequential POIs', () {
    final start = DateTime.utc(2026, 7, 19, 8);
    final firstSession = ExplorationSession(
      sessionId: 'first',
      startedAt: start,
      endedAt: start.add(const Duration(minutes: 8)),
      distanceMeters: 800,
      activeDurationSeconds: 480,
      points: <RoutePoint>[
        point(41.000, 29.000, start),
        point(41.001, 29.001, start.add(const Duration(minutes: 1))),
      ],
    );
    final secondSession = ExplorationSession(
      sessionId: 'second',
      startedAt: start.add(const Duration(hours: 1)),
      endedAt: start.add(const Duration(hours: 1, minutes: 8)),
      distanceMeters: 900,
      activeDurationSeconds: 480,
      points: <RoutePoint>[
        point(41.002, 29.002, start.add(const Duration(hours: 1))),
        point(41.003, 29.003, start.add(const Duration(hours: 1, minutes: 1))),
      ],
    );
    final exploration = DailyExploration(
      userId: 'u1',
      mapId: 'm1',
      areaId: 'a1',
      mapName: 'Test Haritası',
      dayKey: '20260719',
      date: start,
      sessionCount: 2,
      totalDistanceMeters: 1700,
      totalDurationSeconds: 960,
      earnedXp: 100,
      newPoiIds: const <String>['poi-b', 'poi-a', 'poi-c'],
      sessions: <ExplorationSession>[secondSession, firstSession],
      poiLocations: <String, RoutePoint>{
        'poi-a': point(41.002, 29.002, start),
        'poi-b': point(41.001, 29.001, start),
        'poi-c': point(41.003, 29.003, start),
      },
      poiNames: const <String, String>{
        'poi-a': 'İkinci',
        'poi-b': 'Birinci',
        'poi-c': 'Üçüncü',
      },
    );

    final scene = ShareMapScene.fromDailyExploration(exploration: exploration);

    expect(scene.sessions.map((session) => session.id), <String>[
      'first-0',
      'second-0',
    ]);
    expect(scene.startPoint, Position(29.000, 41.000));
    expect(scene.endPoint, Position(29.003, 41.003));
    expect(scene.discoveredPois.map((poi) => poi.id), <String>[
      'poi-b',
      'poi-a',
      'poi-c',
    ]);
    expect(
      scene.discoveredPois.map((poi) => poi.visitedAt).toList(),
      orderedEquals(
        scene.discoveredPois.map((poi) => poi.visitedAt).toList(growable: false)
          ..sort(),
      ),
    );
  });

  test('GPS gaps become separate route sessions for dashed transitions', () {
    final start = DateTime.utc(2026, 7, 19, 8);
    final exploration = DailyExploration(
      userId: 'u1',
      mapId: 'm1',
      areaId: 'a1',
      mapName: 'Test Haritası',
      dayKey: '20260719',
      date: start,
      sessionCount: 1,
      totalDistanceMeters: 500,
      totalDurationSeconds: 300,
      earnedXp: 20,
      newPoiIds: const <String>[],
      sessions: <ExplorationSession>[
        ExplorationSession(
          sessionId: 'session',
          startedAt: start,
          endedAt: start.add(const Duration(minutes: 8)),
          distanceMeters: 500,
          activeDurationSeconds: 300,
          points: <RoutePoint>[
            point(41.000, 29.000, start),
            point(41.001, 29.001, start.add(const Duration(minutes: 1))),
            point(41.002, 29.002, start.add(const Duration(minutes: 5))),
            point(41.003, 29.003, start.add(const Duration(minutes: 6))),
          ],
        ),
      ],
    );

    final scene = ShareMapScene.fromDailyExploration(exploration: exploration);

    expect(scene.sessions, hasLength(2));
    expect(scene.sessions[0].points, hasLength(2));
    expect(scene.sessions[1].points, hasLength(2));
  });

  test('boundary helper emits a closed GeoJSON polygon', () {
    final geoJson = boundaryGeoJsonFromPositions(<Position>[
      Position(29.0, 41.0),
      Position(29.1, 41.0),
      Position(29.1, 41.1),
      Position(29.0, 41.1),
    ]);

    final decoded = jsonDecode(geoJson!) as Map<String, dynamic>;
    final geometry = decoded['geometry'] as Map<String, dynamic>;
    final rings = geometry['coordinates'] as List<dynamic>;
    final ring = rings.single as List<dynamic>;
    expect(ring.first, ring.last);
    expect(ring, hasLength(5));
  });
}

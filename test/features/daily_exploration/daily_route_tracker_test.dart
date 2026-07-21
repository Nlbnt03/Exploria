import 'package:flutter_test/flutter_test.dart';
import 'package:kesfedio/features/daily_exploration/data/services/daily_exploration_service.dart';
import 'package:kesfedio/features/daily_exploration/data/services/daily_route_tracker.dart';
import 'package:kesfedio/features/daily_exploration/domain/models/daily_exploration.dart';
import 'package:kesfedio/features/daily_exploration/domain/models/exploration_session.dart';
import 'package:kesfedio/features/daily_exploration/domain/models/route_point.dart';

void main() {
  final start = DateTime(2026, 7, 19, 9);

  RoutePoint point({
    required double x,
    required int seconds,
    double accuracy = 5,
  }) {
    return RoutePoint(
      latitude: 40,
      longitude: x,
      accuracy: accuracy,
      timestamp: start.add(Duration(seconds: seconds)),
    );
  }

  DailyRouteTracker tracker() {
    return DailyRouteTracker(
      sessionId: 'session',
      startedAt: start,
      isInsideBoundary: (_) => true,
      distanceCalculator: (startLat, startLng, endLat, endLng) {
        return (endLng - startLng).abs();
      },
    );
  }

  ExplorationSession session(String id, double distance, int offset) {
    return ExplorationSession(
      sessionId: id,
      startedAt: start.add(Duration(hours: offset)),
      endedAt: start.add(Duration(hours: offset, minutes: 10)),
      distanceMeters: distance,
      activeDurationSeconds: 600,
      points: <RoutePoint>[
        point(x: offset * 100, seconds: offset * 3600),
        point(x: offset * 100 + distance, seconds: offset * 3600 + 600),
      ],
    );
  }

  DailyExploration exploration({
    required String dayKey,
    List<ExplorationSession> sessions = const <ExplorationSession>[],
  }) {
    return DailyExploration(
      userId: 'user',
      mapId: 'map',
      areaId: 'area',
      mapName: 'Büyükada',
      dayKey: dayKey,
      date: start,
      sessionCount: sessions.length,
      totalDistanceMeters: sessions.fold<double>(
        0,
        (sum, item) => sum + item.distanceMeters,
      ),
      totalDurationSeconds: sessions.fold<int>(
        0,
        (sum, item) => sum + item.activeDurationSeconds,
      ),
      earnedXp: 0,
      newPoiIds: const <String>[],
      sessions: sessions,
    );
  }

  test('aynı session içindeki mesafe doğru hesaplanıyor', () {
    final route = tracker();
    expect(route.add(point(x: 0, seconds: 0)), RoutePointDecision.accepted);
    expect(route.add(point(x: 10, seconds: 10)), RoutePointDecision.accepted);
    expect(route.add(point(x: 25, seconds: 20)), RoutePointDecision.accepted);

    expect(route.distanceMeters, 25);
    expect(route.activeDurationSeconds, 20);
  });

  test('iki session arasındaki mesafe toplama eklenmiyor', () {
    final merged = DailyExploration.merge(<DailyExploration>[
      exploration(
        dayKey: '20260719',
        sessions: <ExplorationSession>[session('a', 2000, 0)],
      ),
      exploration(
        dayKey: '20260719',
        sessions: <ExplorationSession>[session('b', 4000, 3)],
      ),
    ]);

    expect(merged.totalDistanceMeters, 6000);
  });

  test('düşük doğruluklu GPS noktası reddediliyor', () {
    final route = tracker();
    expect(
      route.add(point(x: 0, seconds: 0, accuracy: 25.1)),
      RoutePointDecision.inaccurate,
    );
    expect(route.points, isEmpty);
  });

  test('3 metreden küçük GPS hareketi reddediliyor', () {
    final route = tracker();
    route.add(point(x: 0, seconds: 0));

    expect(route.add(point(x: 2.9, seconds: 10)), RoutePointDecision.tooClose);
    expect(route.points, hasLength(1));
  });

  test('aşırı hızlı GPS sıçraması reddediliyor', () {
    final route = tracker();
    route.add(point(x: 0, seconds: 0));

    expect(route.add(point(x: 80, seconds: 10)), RoutePointDecision.tooFast);
    expect(route.distanceMeters, 0);
  });

  test('aynı güne ait üç session doğru birleştiriliyor', () {
    final merged = DailyExploration.merge(<DailyExploration>[
      exploration(
        dayKey: '20260719',
        sessions: <ExplorationSession>[session('a', 2000, 0)],
      ),
      exploration(
        dayKey: '20260719',
        sessions: <ExplorationSession>[session('b', 4000, 3)],
      ),
      exploration(
        dayKey: '20260719',
        sessions: <ExplorationSession>[session('c', 3000, 6)],
      ),
    ]);

    expect(merged.sessionCount, 3);
    expect(merged.totalDistanceMeters, 9000);
    expect(merged.totalDurationSeconds, 1800);
  });

  test('farklı günler birleştirilmiyor', () {
    expect(
      () => DailyExploration.merge(<DailyExploration>[
        exploration(dayKey: '20260719'),
        exploration(dayKey: '20260720'),
      ]),
      throwsArgumentError,
    );
  });

  test('aynı POI iki kez sayılmıyor', () {
    final daily = exploration(dayKey: '20260719').addPoi('poi-1', 50);
    final duplicate = daily.addPoi('poi-1', 50);

    expect(duplicate.newPoiIds, <String>['poi-1']);
    expect(duplicate.earnedXp, 50);
  });

  test('POI iptal edilince XP ve yeni yer sayısı düzeliyor', () {
    final daily = exploration(
      dayKey: '20260719',
    ).addPoi('poi-1', 50).addPoi('poi-2', 75).removePoi('poi-1', 50);

    expect(daily.newPoiIds, <String>['poi-2']);
    expect(daily.earnedXp, 75);
  });

  test('aktif süre uzun GPS boşluklarını saymıyor', () {
    final route = tracker();
    route.add(point(x: 0, seconds: 0));
    route.add(point(x: 10, seconds: 121));
    route.add(point(x: 20, seconds: 131));

    expect(route.distanceMeters, 10);
    expect(route.activeDurationSeconds, 10);
    expect(
      route.finish(start.add(const Duration(minutes: 5))).walkedSegments,
      hasLength(1),
    );
  });

  test('dayKey cihazın yerel tarihinden yyyyMMdd üretiliyor', () {
    expect(
      DailyExplorationService.dayKeyFor(DateTime(2026, 2, 3, 23, 59)),
      '20260203',
    );
  });
}

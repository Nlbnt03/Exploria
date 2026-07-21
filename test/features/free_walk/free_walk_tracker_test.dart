import 'package:flutter_test/flutter_test.dart';
import 'package:kesfedio/features/free_walk/domain/free_walk_tracker.dart';

void main() {
  final startedAt = DateTime(2026, 7, 20, 9);

  FreeWalkPoint point({
    required double x,
    required int seconds,
    double accuracy = 5,
  }) {
    return FreeWalkPoint(
      latitude: 40,
      longitude: x,
      accuracy: accuracy,
      timestamp: startedAt.add(Duration(seconds: seconds)),
    );
  }

  FreeWalkTracker tracker() => FreeWalkTracker(
    distanceCalculator: (startLat, startLng, endLat, endLng) {
      return (endLng - startLng).abs();
    },
  );

  test('mesafe yalnızca geçerli GPS noktalarından hesaplanır', () {
    final route = tracker()..start();

    expect(route.add(point(x: 0, seconds: 0)), FreeWalkPointDecision.accepted);
    expect(
      route.add(point(x: 10, seconds: 10)),
      FreeWalkPointDecision.accepted,
    );
    expect(route.add(point(x: 90, seconds: 20)), FreeWalkPointDecision.tooFast);

    expect(route.distanceMeters, 10);
    expect(route.acceptedPointCount, 2);
  });

  test('düşük doğruluklu GPS noktası rotaya eklenmez', () {
    final route = tracker()..start();

    expect(
      route.add(point(x: 0, seconds: 0, accuracy: 25.1)),
      FreeWalkPointDecision.inaccurate,
    );
    expect(route.acceptedPointCount, 0);
  });

  test('duraklatılan aralık mesafeye ve çizgiye bağlanmaz', () {
    final route = tracker()..start();
    route.add(point(x: 0, seconds: 0));
    route.add(point(x: 10, seconds: 10));
    route.pause();

    expect(route.add(point(x: 100, seconds: 20)), FreeWalkPointDecision.paused);

    route.resume();
    route.add(point(x: 100, seconds: 30));
    route.add(point(x: 110, seconds: 40));

    expect(route.distanceMeters, 20);
    expect(
      route.segments.where((segment) => segment.length >= 2),
      hasLength(2),
    );
  });

  test('uzun GPS boşluğu yeni rota parçası başlatır', () {
    final route = tracker()..start();
    route.add(point(x: 0, seconds: 0));
    route.add(point(x: 10, seconds: 10));
    route.add(point(x: 100, seconds: 131));
    route.add(point(x: 110, seconds: 141));

    expect(route.distanceMeters, 20);
    expect(
      route.segments.where((segment) => segment.length >= 2),
      hasLength(2),
    );
  });
}

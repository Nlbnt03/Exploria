import 'package:geolocator/geolocator.dart';

import '../../domain/models/exploration_session.dart';
import '../../domain/models/route_point.dart';

enum RoutePointDecision {
  accepted,
  outsideBoundary,
  inaccurate,
  tooClose,
  invalidTimestamp,
  tooFast,
}

typedef RouteDistanceCalculator =
    double Function(
      double startLat,
      double startLng,
      double endLat,
      double endLng,
    );

class DailyRouteTracker {
  DailyRouteTracker({
    required this.sessionId,
    required this.startedAt,
    required this.isInsideBoundary,
    RouteDistanceCalculator? distanceCalculator,
  }) : _distanceCalculator = distanceCalculator ?? Geolocator.distanceBetween;

  static const double maxAccuracyMeters = 25;
  static const double minimumMovementMeters = 3;
  static const double maxWalkingSpeedMetersPerSecond = 7;
  static const Duration maxActiveGap = Duration(minutes: 2);

  final String sessionId;
  final DateTime startedAt;
  final bool Function(RoutePoint point) isInsideBoundary;
  final RouteDistanceCalculator _distanceCalculator;
  final List<RoutePoint> _points = <RoutePoint>[];

  double _distanceMeters = 0;
  int _activeDurationSeconds = 0;

  List<RoutePoint> get points => List<RoutePoint>.unmodifiable(_points);
  double get distanceMeters => _distanceMeters;
  int get activeDurationSeconds => _activeDurationSeconds;

  RoutePointDecision add(RoutePoint point) {
    if (!isInsideBoundary(point)) return RoutePointDecision.outsideBoundary;
    if (point.accuracy > maxAccuracyMeters) {
      return RoutePointDecision.inaccurate;
    }
    if (_points.isEmpty) {
      _points.add(point);
      return RoutePointDecision.accepted;
    }

    final previous = _points.last;
    final elapsed = point.timestamp.difference(previous.timestamp);
    if (elapsed <= Duration.zero) return RoutePointDecision.invalidTimestamp;

    final distance = _distanceCalculator(
      previous.latitude,
      previous.longitude,
      point.latitude,
      point.longitude,
    );
    if (distance < minimumMovementMeters) return RoutePointDecision.tooClose;

    final speed = distance / (elapsed.inMilliseconds / 1000);
    if (speed > maxWalkingSpeedMetersPerSecond) {
      return RoutePointDecision.tooFast;
    }

    _points.add(point);
    if (elapsed <= maxActiveGap) {
      _distanceMeters += distance;
      _activeDurationSeconds += elapsed.inSeconds;
    }
    return RoutePointDecision.accepted;
  }

  ExplorationSession finish(DateTime endedAt) {
    return ExplorationSession(
      sessionId: sessionId,
      startedAt: startedAt,
      endedAt: endedAt,
      distanceMeters: _distanceMeters,
      activeDurationSeconds: _activeDurationSeconds,
      points: points,
    );
  }
}

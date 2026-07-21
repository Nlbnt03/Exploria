import 'route_point.dart';

class ExplorationSession {
  const ExplorationSession({
    required this.sessionId,
    required this.startedAt,
    required this.endedAt,
    required this.distanceMeters,
    required this.activeDurationSeconds,
    required this.points,
  });

  final String sessionId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double distanceMeters;
  final int activeDurationSeconds;
  final List<RoutePoint> points;

  /// A GPS gap longer than this starts another visible walking segment. The
  /// point remains in the original recording, but no artificial straight line
  /// is drawn across the gap.
  static const Duration maxConnectedGap = Duration(minutes: 2);

  List<List<RoutePoint>> get walkedSegments {
    if (points.isEmpty) return const <List<RoutePoint>>[];
    final segments = <List<RoutePoint>>[];
    var current = <RoutePoint>[points.first];
    for (var index = 1; index < points.length; index++) {
      final point = points[index];
      final gap = point.timestamp.difference(points[index - 1].timestamp);
      if (gap > maxConnectedGap) {
        if (current.length >= 2) segments.add(current);
        current = <RoutePoint>[point];
      } else {
        current.add(point);
      }
    }
    if (current.length >= 2) segments.add(current);
    return segments;
  }
}

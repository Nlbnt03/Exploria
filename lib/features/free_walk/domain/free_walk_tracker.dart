import 'package:geolocator/geolocator.dart';

enum FreeWalkPointDecision {
  accepted,
  paused,
  inaccurate,
  tooClose,
  invalidTimestamp,
  tooFast,
}

typedef FreeWalkDistanceCalculator =
    double Function(
      double startLat,
      double startLng,
      double endLat,
      double endLng,
    );

class FreeWalkPoint {
  const FreeWalkPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final DateTime timestamp;

  Map<String, Object> toMap() => <String, Object>{
    'lat': latitude,
    'lng': longitude,
    'accuracy': accuracy,
    'timestampMs': timestamp.millisecondsSinceEpoch,
  };

  factory FreeWalkPoint.fromMap(Map<String, dynamic> map) {
    return FreeWalkPoint(
      latitude: (map['lat'] as num?)?.toDouble() ?? 0,
      longitude: (map['lng'] as num?)?.toDouble() ?? 0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestampMs'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

class FreeWalkTracker {
  FreeWalkTracker({FreeWalkDistanceCalculator? distanceCalculator})
    : _distanceCalculator = distanceCalculator ?? Geolocator.distanceBetween;

  static const double maxAccuracyMeters = 25;
  static const double minimumMovementMeters = 3;
  static const double maxWalkingSpeedMetersPerSecond = 7;
  static const Duration maxConnectedGap = Duration(minutes: 2);

  final FreeWalkDistanceCalculator _distanceCalculator;
  final List<List<FreeWalkPoint>> _segments = <List<FreeWalkPoint>>[];

  bool _recording = false;
  double _distanceMeters = 0;

  bool get isRecording => _recording;
  double get distanceMeters => _distanceMeters;
  int get acceptedPointCount =>
      _segments.fold<int>(0, (total, segment) => total + segment.length);

  List<List<FreeWalkPoint>> get segments => <List<FreeWalkPoint>>[
    for (final segment in _segments) List<FreeWalkPoint>.unmodifiable(segment),
  ];

  void start() {
    reset();
    _recording = true;
    _segments.add(<FreeWalkPoint>[]);
  }

  void pause() {
    _recording = false;
  }

  void resume() {
    if (_recording) return;
    _recording = true;
    if (_segments.isEmpty || _segments.last.isNotEmpty) {
      _segments.add(<FreeWalkPoint>[]);
    }
  }

  void reset() {
    _recording = false;
    _distanceMeters = 0;
    _segments.clear();
  }

  FreeWalkPointDecision add(FreeWalkPoint point) {
    if (!_recording) return FreeWalkPointDecision.paused;
    if (point.accuracy > maxAccuracyMeters) {
      return FreeWalkPointDecision.inaccurate;
    }

    if (_segments.isEmpty) _segments.add(<FreeWalkPoint>[]);
    var current = _segments.last;
    if (current.isEmpty) {
      current.add(point);
      return FreeWalkPointDecision.accepted;
    }

    final previous = current.last;
    final elapsed = point.timestamp.difference(previous.timestamp);
    if (elapsed <= Duration.zero) {
      return FreeWalkPointDecision.invalidTimestamp;
    }

    if (elapsed > maxConnectedGap) {
      current = <FreeWalkPoint>[point];
      _segments.add(current);
      return FreeWalkPointDecision.accepted;
    }

    final distance = _distanceCalculator(
      previous.latitude,
      previous.longitude,
      point.latitude,
      point.longitude,
    );
    if (distance < minimumMovementMeters) {
      return FreeWalkPointDecision.tooClose;
    }

    final speed = distance / (elapsed.inMilliseconds / 1000);
    if (speed > maxWalkingSpeedMetersPerSecond) {
      return FreeWalkPointDecision.tooFast;
    }

    current.add(point);
    _distanceMeters += distance;
    return FreeWalkPointDecision.accepted;
  }
}

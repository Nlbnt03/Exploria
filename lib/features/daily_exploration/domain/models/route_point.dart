class RoutePoint {
  const RoutePoint({
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

  factory RoutePoint.fromMap(Map<String, dynamic> map) {
    return RoutePoint(
      latitude: (map['lat'] as num?)?.toDouble() ?? 0,
      longitude: (map['lng'] as num?)?.toDouble() ?? 0,
      accuracy: (map['accuracy'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (map['timestampMs'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

import 'exploration_session.dart';
import 'route_point.dart';

class DailyExploration {
  const DailyExploration({
    required this.userId,
    required this.mapId,
    required this.areaId,
    required this.mapName,
    required this.dayKey,
    required this.date,
    required this.sessionCount,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.earnedXp,
    required this.newPoiIds,
    required this.sessions,
    this.poiLocations = const <String, RoutePoint>{},
    this.poiNames = const <String, String>{},
  });

  final String userId;
  final String mapId;
  final String areaId;
  final String mapName;
  final String dayKey;
  final DateTime date;
  final int sessionCount;
  final double totalDistanceMeters;
  final int totalDurationSeconds;
  final int earnedXp;
  final List<String> newPoiIds;
  final List<ExplorationSession> sessions;

  /// Coordinates and names are enriched from the already loaded POI catalog
  /// before a snapshot is created; they are deliberately not duplicated in
  /// Firestore.
  final Map<String, RoutePoint> poiLocations;
  final Map<String, String> poiNames;

  int get newPlaceCount => newPoiIds.length;

  List<RoutePoint> get allPoints => <RoutePoint>[
    for (final session in sessions) ...session.points,
  ];

  RoutePoint? get firstPoint => allPoints.isEmpty ? null : allPoints.first;
  RoutePoint? get lastPoint => allPoints.isEmpty ? null : allPoints.last;

  DailyExploration copyWith({
    int? sessionCount,
    double? totalDistanceMeters,
    int? totalDurationSeconds,
    int? earnedXp,
    List<String>? newPoiIds,
    List<ExplorationSession>? sessions,
    Map<String, RoutePoint>? poiLocations,
    Map<String, String>? poiNames,
  }) {
    return DailyExploration(
      userId: userId,
      mapId: mapId,
      areaId: areaId,
      mapName: mapName,
      dayKey: dayKey,
      date: date,
      sessionCount: sessionCount ?? this.sessionCount,
      totalDistanceMeters: totalDistanceMeters ?? this.totalDistanceMeters,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      earnedXp: earnedXp ?? this.earnedXp,
      newPoiIds: newPoiIds ?? this.newPoiIds,
      sessions: sessions ?? this.sessions,
      poiLocations: poiLocations ?? this.poiLocations,
      poiNames: poiNames ?? this.poiNames,
    );
  }

  DailyExploration addPoi(String poiId, int xp) {
    if (newPoiIds.contains(poiId)) return this;
    return copyWith(
      newPoiIds: <String>[...newPoiIds, poiId],
      earnedXp: earnedXp + xp.clamp(0, 1 << 30),
    );
  }

  DailyExploration removePoi(String poiId, int xp) {
    if (!newPoiIds.contains(poiId)) return this;
    return copyWith(
      newPoiIds: newPoiIds.where((id) => id != poiId).toList(growable: false),
      earnedXp: (earnedXp - xp).clamp(0, 1 << 30),
    );
  }

  static DailyExploration merge(Iterable<DailyExploration> values) {
    final items = values.toList(growable: false);
    if (items.isEmpty) {
      throw ArgumentError.value(values, 'values', 'En az bir kayıt gerekli.');
    }
    final first = items.first;
    if (items.any(
      (item) =>
          item.userId != first.userId ||
          item.mapId != first.mapId ||
          item.dayKey != first.dayKey,
    )) {
      throw ArgumentError(
        'Farklı gün veya haritalardaki keşifler birleştirilemez.',
      );
    }

    final sessions = <String, ExplorationSession>{};
    final poiIds = <String>{};
    final poiLocations = <String, RoutePoint>{};
    final poiNames = <String, String>{};
    for (final item in items) {
      for (final session in item.sessions) {
        sessions[session.sessionId] = session;
      }
      poiIds.addAll(item.newPoiIds);
      poiLocations.addAll(item.poiLocations);
      poiNames.addAll(item.poiNames);
    }
    final orderedSessions = sessions.values.toList(growable: false)
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));

    return first.copyWith(
      sessionCount: orderedSessions.length,
      totalDistanceMeters: orderedSessions.fold<double>(
        0,
        (total, session) => total + session.distanceMeters,
      ),
      totalDurationSeconds: orderedSessions.fold<int>(
        0,
        (total, session) => total + session.activeDurationSeconds,
      ),
      earnedXp: items.fold<int>(0, (total, item) => total + item.earnedXp),
      newPoiIds: poiIds.toList(growable: false),
      sessions: orderedSessions,
      poiLocations: poiLocations,
      poiNames: poiNames,
    );
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../../domain/models/daily_exploration.dart';
import '../../domain/models/exploration_session.dart';
import '../../domain/models/route_point.dart';
import 'daily_route_tracker.dart';

class DailyExplorationService {
  DailyExplorationService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static const int _pointBufferLimit = 200;

  final FirebaseFirestore _firestore;
  StreamSubscription<geo.Position>? _trackingSubscription;
  DailyRouteTracker? _tracker;
  DocumentReference<Map<String, dynamic>>? _dailyRef;
  DocumentReference<Map<String, dynamic>>? _sessionRef;
  Future<void>? _flushInFlight;
  final List<RoutePoint> _pendingPoints = <RoutePoint>[];

  String? _uid;
  String? _mapId;
  String? _areaId;
  String? _mapName;
  String? _dayKey;
  DateTime? _date;
  bool _finishing = false;

  bool get hasActiveSession => _tracker != null && !_finishing;

  static String dayKeyFor(DateTime date) {
    final local = date.toLocal();
    return '${local.year.toString().padLeft(4, '0')}'
        '${local.month.toString().padLeft(2, '0')}'
        '${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> startSession({
    required String uid,
    required String mapId,
    required String areaId,
    required String mapName,
    required Stream<geo.Position> trackingStream,
    required bool Function(RoutePoint point) isInsideBoundary,
    DateTime? now,
  }) async {
    if (hasActiveSession) return;

    final startedAt = (now ?? DateTime.now()).toLocal();
    final dayKey = dayKeyFor(startedAt);
    final sessionId =
        '${startedAt.microsecondsSinceEpoch}_${mapId.hashCode.abs()}';
    final dailyId = '${dayKey}_$mapId';

    _uid = uid;
    _mapId = mapId;
    _areaId = areaId;
    _mapName = mapName;
    _dayKey = dayKey;
    _date = DateTime(startedAt.year, startedAt.month, startedAt.day);
    _finishing = false;
    _pendingPoints.clear();
    _tracker = DailyRouteTracker(
      sessionId: sessionId,
      startedAt: startedAt,
      isInsideBoundary: isInsideBoundary,
    );
    _dailyRef = _firestore
        .collection('userMapStates')
        .doc(uid)
        .collection('dailyExplorations')
        .doc(dailyId);
    _sessionRef = _dailyRef!.collection('sessions').doc(sessionId);

    _trackingSubscription = trackingStream.listen(
      _onPosition,
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('[DailyExploration] GPS stream hatası: $error');
      },
      cancelOnError: false,
    );

    try {
      final batch = _firestore.batch();
      batch.set(_dailyRef!, <String, Object?>{
        'mapId': mapId,
        'areaId': areaId,
        'mapName': mapName,
        'dayKey': dayKey,
        'date': Timestamp.fromDate(_date!),
        'totalDistanceMeters': FieldValue.increment(0),
        'totalDurationSeconds': FieldValue.increment(0),
        'earnedXp': FieldValue.increment(0),
        'newPoiIds': FieldValue.arrayUnion(const <String>[]),
        'sessionCount': FieldValue.increment(0),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(_sessionRef!, <String, Object?>{
        'startedAt': Timestamp.fromDate(startedAt),
        'endedAt': null,
        'distanceMeters': 0.0,
        'activeDurationSeconds': 0,
        'points': const <Map<String, Object>>[],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (error) {
      // Firestore's offline queue normally accepts this write. Even if the
      // platform rejects it, tracking stays active and finalization retries the
      // complete session without affecting map progress.
      debugPrint('[DailyExploration] Oturum başlangıcı yazılamadı: $error');
    }
  }

  void _onPosition(geo.Position position) {
    final tracker = _tracker;
    if (tracker == null || _finishing) return;
    final point = RoutePoint(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      timestamp: position.timestamp.toLocal(),
    );
    if (tracker.add(point) != RoutePointDecision.accepted) return;
    _pendingPoints.add(point);
    if (_pendingPoints.length >= _pointBufferLimit) {
      unawaited(flushSession());
    }
  }

  Future<void> flushSession() {
    final running = _flushInFlight;
    if (running != null) return running;
    final future = _flushPendingPoints();
    _flushInFlight = future;
    return future.whenComplete(() {
      if (identical(_flushInFlight, future)) _flushInFlight = null;
    });
  }

  Future<void> _flushPendingPoints() async {
    final tracker = _tracker;
    final sessionRef = _sessionRef;
    final dailyRef = _dailyRef;
    if (tracker == null || sessionRef == null || dailyRef == null) return;
    if (_pendingPoints.isEmpty) {
      try {
        await dailyRef.set(<String, Object?>{
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (_) {}
      return;
    }

    final pending = List<RoutePoint>.from(_pendingPoints);
    _pendingPoints.clear();
    try {
      await sessionRef.set(<String, Object?>{
        'points': FieldValue.arrayUnion(
          pending.map((point) => point.toMap()).toList(growable: false),
        ),
        'distanceMeters': tracker.distanceMeters,
        'activeDurationSeconds': tracker.activeDurationSeconds,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await dailyRef.set(<String, Object?>{
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      _pendingPoints.insertAll(0, pending);
      debugPrint('[DailyExploration] Rota tamponu yazılamadı: $error');
    }
  }

  Future<void> addPoi({required String poiId, required int xp}) async {
    final dailyRef = _dailyRef;
    if (dailyRef == null || poiId.isEmpty || xp < 0) return;
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(dailyRef);
      final ids = _stringList(snapshot.data()?['newPoiIds']);
      if (ids.contains(poiId)) return;
      transaction.set(dailyRef, <String, Object?>{
        'newPoiIds': FieldValue.arrayUnion(<String>[poiId]),
        'earnedXp': FieldValue.increment(xp),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> removePoi({required String poiId, required int xp}) async {
    final dailyRef = _dailyRef;
    if (dailyRef == null || poiId.isEmpty || xp < 0) return;
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(dailyRef);
      final data = snapshot.data();
      final ids = _stringList(data?['newPoiIds']);
      if (!ids.contains(poiId)) return;
      final currentXp = (data?['earnedXp'] as num?)?.toInt() ?? 0;
      transaction.set(dailyRef, <String, Object?>{
        'newPoiIds': FieldValue.arrayRemove(<String>[poiId]),
        'earnedXp': (currentXp - xp).clamp(0, 1 << 30),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<DailyExploration?> finishSession({DateTime? now}) async {
    final tracker = _tracker;
    final dailyRef = _dailyRef;
    final sessionRef = _sessionRef;
    if (tracker == null ||
        dailyRef == null ||
        sessionRef == null ||
        _finishing) {
      return null;
    }
    _finishing = true;
    await _trackingSubscription?.cancel();
    _trackingSubscription = null;
    final endedAt = (now ?? DateTime.now()).toLocal();
    final session = tracker.finish(endedAt);

    final runningFlush = _flushInFlight;
    if (runningFlush != null) await runningFlush;

    try {
      final batch = _firestore.batch();
      batch.set(sessionRef, <String, Object?>{
        'startedAt': Timestamp.fromDate(session.startedAt),
        'endedAt': Timestamp.fromDate(endedAt),
        'distanceMeters': session.distanceMeters,
        'activeDurationSeconds': session.activeDurationSeconds,
        'points': session.points.map((point) => point.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      batch.set(dailyRef, <String, Object?>{
        'totalDistanceMeters': FieldValue.increment(session.distanceMeters),
        'totalDurationSeconds': FieldValue.increment(
          session.activeDurationSeconds,
        ),
        'sessionCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await batch.commit();
    } catch (error) {
      debugPrint('[DailyExploration] Oturum tamamlanamadı: $error');
    }

    DailyExploration? result;
    try {
      result = await fetchDaily(uid: _uid!, mapId: _mapId!, dayKey: _dayKey!);
    } catch (error) {
      debugPrint('[DailyExploration] Günlük özet okunamadı: $error');
    }
    result ??= _localExploration(session);
    _tracker = null;
    _pendingPoints.clear();
    return result;
  }

  Future<DailyExploration?> fetchDaily({
    required String uid,
    required String mapId,
    required String dayKey,
  }) async {
    final ref = _firestore
        .collection('userMapStates')
        .doc(uid)
        .collection('dailyExplorations')
        .doc('${dayKey}_$mapId');
    final results = await Future.wait<Object>(<Future<Object>>[
      ref.get(const GetOptions(source: Source.serverAndCache)),
      ref
          .collection('sessions')
          .orderBy('startedAt')
          .get(const GetOptions(source: Source.serverAndCache)),
    ]);
    final daily = results[0] as DocumentSnapshot<Map<String, dynamic>>;
    if (!daily.exists) return null;
    final sessionsSnapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;
    final data = daily.data() ?? const <String, dynamic>{};
    final sessions = <ExplorationSession>[];
    for (final doc in sessionsSnapshot.docs) {
      final raw = doc.data();
      final startedAt = _dateTime(raw['startedAt']);
      if (startedAt == null) continue;
      sessions.add(
        ExplorationSession(
          sessionId: doc.id,
          startedAt: startedAt,
          endedAt: _dateTime(raw['endedAt']),
          distanceMeters: (raw['distanceMeters'] as num?)?.toDouble() ?? 0,
          activeDurationSeconds:
              (raw['activeDurationSeconds'] as num?)?.toInt() ?? 0,
          points: _routePoints(raw['points']),
        ),
      );
    }
    return DailyExploration(
      userId: uid,
      mapId: (data['mapId'] as String?) ?? mapId,
      areaId: (data['areaId'] as String?) ?? mapId,
      mapName: (data['mapName'] as String?) ?? 'Keşif',
      dayKey: (data['dayKey'] as String?) ?? dayKey,
      date: _dateTime(data['date']) ?? _dateFromDayKey(dayKey),
      sessionCount: (data['sessionCount'] as num?)?.toInt() ?? sessions.length,
      totalDistanceMeters:
          (data['totalDistanceMeters'] as num?)?.toDouble() ??
          sessions.fold<double>(
            0,
            (total, item) => total + item.distanceMeters,
          ),
      totalDurationSeconds:
          (data['totalDurationSeconds'] as num?)?.toInt() ??
          sessions.fold<int>(
            0,
            (total, item) => total + item.activeDurationSeconds,
          ),
      earnedXp: (data['earnedXp'] as num?)?.toInt() ?? 0,
      newPoiIds: _stringList(data['newPoiIds']).toList(growable: false),
      sessions: sessions,
    );
  }

  DailyExploration _localExploration(ExplorationSession session) {
    return DailyExploration(
      userId: _uid!,
      mapId: _mapId!,
      areaId: _areaId!,
      mapName: _mapName!,
      dayKey: _dayKey!,
      date: _date!,
      sessionCount: 1,
      totalDistanceMeters: session.distanceMeters,
      totalDurationSeconds: session.activeDurationSeconds,
      earnedXp: 0,
      newPoiIds: const <String>[],
      sessions: <ExplorationSession>[session],
    );
  }

  Future<void> dispose() async {
    await _trackingSubscription?.cancel();
    _trackingSubscription = null;
  }

  static Set<String> _stringList(Object? raw) {
    if (raw is! Iterable) return <String>{};
    return raw.map((value) => value.toString()).toSet();
  }

  static List<RoutePoint> _routePoints(Object? raw) {
    if (raw is! Iterable) return const <RoutePoint>[];
    return raw
        .whereType<Map>()
        .map((value) => RoutePoint.fromMap(Map<String, dynamic>.from(value)))
        .toList(growable: false);
  }

  static DateTime? _dateTime(Object? raw) {
    if (raw is Timestamp) return raw.toDate().toLocal();
    if (raw is DateTime) return raw.toLocal();
    return null;
  }

  static DateTime _dateFromDayKey(String dayKey) {
    if (dayKey.length != 8) return DateTime.now();
    return DateTime(
      int.tryParse(dayKey.substring(0, 4)) ?? DateTime.now().year,
      int.tryParse(dayKey.substring(4, 6)) ?? 1,
      int.tryParse(dayKey.substring(6, 8)) ?? 1,
    );
  }
}

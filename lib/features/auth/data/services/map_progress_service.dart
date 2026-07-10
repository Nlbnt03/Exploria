import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' hide Source;

import '../../domain/models/campus_map_state.dart';
import '../../presentation/map/map_areas.dart';
import '../../domain/models/user_map_record.dart';

class MapProgressService {
  MapProgressService({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;

  CollectionReference<Map<String, dynamic>> get _mapStates =>
      _firestore.collection('userMapStates');

  CollectionReference<Map<String, dynamic>> _statesCollection(String uid) =>
      _mapStates.doc(uid).collection('states');

  static const _defaultTimeout = Duration(seconds: 15);

  Future<List<String>> fetchAllMapNames(String uid) async {
    final names = <String>{};

    // Read from new subcollection
    final snapshot = await _statesCollection(uid)
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(_defaultTimeout);
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = (data['status'] as String?)?.trim();
      if (status == 'deleted') continue;
      final mapName = (data['mapName'] as String?)?.trim();
      if (mapName != null && mapName.isNotEmpty) {
        names.add(mapName.toLowerCase());
      }
    }

    // Also read from old nested structure for migration
    try {
      final parentDoc = await _mapStates
          .doc(uid)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(_defaultTimeout);
      final data = parentDoc.data();
      if (data != null) {
        final mapStatesRaw = data['mapStates'];
        if (mapStatesRaw is Map<dynamic, dynamic>) {
          for (final value in mapStatesRaw.values) {
            if (value is! Map<dynamic, dynamic>) continue;
            final status = (value['status'] as String?)?.trim();
            if (status == 'deleted') continue;
            final mapName = (value['mapName'] as String?)?.trim();
            if (mapName != null && mapName.isNotEmpty) {
              names.add(mapName.toLowerCase());
            }
          }
        }
      }
    } catch (_) {
      // Old structure may not exist or may time out — ignore
    }

    return names.toList(growable: false);
  }

  Future<String?> fetchLastOpenedAreaId(String uid) async {
    final doc = await _mapStates
        .doc(uid)
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(_defaultTimeout);
    final data = doc.data();
    if (data == null) return null;

    final lastMapId = (data['lastOpenedMapId'] as String?)?.trim();
    if (lastMapId == null || lastMapId.isEmpty) return null;

    final stateDoc = await _statesCollection(uid)
        .doc(lastMapId)
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(_defaultTimeout);
    if (stateDoc.exists) {
      final stateData = stateDoc.data()!;
      final areaId = (stateData['areaId'] as String?)?.trim();
      return (areaId != null && areaId.isNotEmpty) ? areaId : lastMapId;
    }

    // Fallback: read from old nested mapStates structure
    final mapStatesRaw = data['mapStates'];
    if (mapStatesRaw is Map<dynamic, dynamic>) {
      final lastMapData = mapStatesRaw[lastMapId];
      if (lastMapData is Map<dynamic, dynamic>) {
        final areaId = (lastMapData['areaId'] as String?)?.trim();
        if (areaId != null && areaId.isNotEmpty) return areaId;
      }
    }

    return lastMapId;
  }

  Future<String> createMap({
    required String uid,
    required String areaId,
    required String mapName,
    MapAreaConfig? areaConfig,
  }) async {
    final normalizedName = _normalizeMapName(mapName);
    final config = areaConfig ?? resolveMapArea(areaId);
    final callable = _functions.httpsCallable('createMap');
    final result = await callable
        .call<Map<String, dynamic>>({
          'areaId': areaId,
          'title': normalizedName,
          'totalPois': config.totalPois,
          'bounds': _boundsToPayload(config.boundary),
        })
        .timeout(_defaultTimeout);

    final mapId = (result.data['mapId'] as String?)?.trim();
    if (mapId == null || mapId.isEmpty) {
      throw FirebaseException(
        plugin: 'map_progress_service',
        code: 'invalid-response',
        message: 'Harita oluşturma yanıtı geçersiz.',
      );
    }

    return mapId;
  }

  Stream<List<UserMapRecord>> watchMapHistory(String uid) {
    return _statesCollection(uid)
        .orderBy('updatedAt', descending: true)
        .limit(100)
        .snapshots()
        .map((snapshot) => _parseMapHistory(snapshot.docs))
        .timeout(
          _defaultTimeout * 2,
          onTimeout: (sink) => sink.add(const <UserMapRecord>[]),
        );
  }

  Future<UserMapRecord?> fetchMapById({
    required String uid,
    required String mapId,
  }) async {
    final doc = await _statesCollection(uid)
        .doc(mapId)
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(_defaultTimeout);
    if (doc.exists) {
      return _parseMapRecord(mapId, doc.data()!);
    }

    // Fallback: read from old nested mapStates structure for migration
    final parentDoc = await _mapStates
        .doc(uid)
        .get(const GetOptions(source: Source.serverAndCache))
        .timeout(_defaultTimeout);
    final parentData = parentDoc.data();
    if (parentData == null) return null;

    final mapStatesRaw = parentData['mapStates'];
    if (mapStatesRaw is! Map<dynamic, dynamic>) return null;

    final mapData = mapStatesRaw[mapId];
    if (mapData is! Map<dynamic, dynamic>) return null;

    return _parseMapRecord(mapId, mapData.cast<String, dynamic>());
  }

  Future<CampusMapState?> fetchMapState({
    required String uid,
    required String mapId,
  }) async {
    final record = await fetchMapById(uid: uid, mapId: mapId);
    return record?.state;
  }

  Future<void> markMapOpened({
    required String uid,
    required String mapId,
    required String areaId,
    required String mapName,
  }) async {
    final normalizedName = _normalizeMapName(mapName);

    await _firestore
        .runTransaction((tx) async {
          tx.set(_mapStates.doc(uid), {
            'lastOpenedMapId': mapId,
            'lastOpenedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          tx.set(_statesCollection(uid).doc(mapId), {
            'areaId': areaId,
            'mapName': normalizedName,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        })
        .timeout(_defaultTimeout);
  }

  Future<void> saveMapState({
    required String uid,
    required String mapId,
    required String areaId,
    required String mapName,
    required CampusMapState state,
    int totalPois = 0,
  }) async {
    final normalizedName = _normalizeMapName(mapName);

    await _firestore
        .runTransaction((tx) async {
          tx.set(_mapStates.doc(uid), {
            'lastOpenedMapId': mapId,
            'lastOpenedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

          tx.set(_statesCollection(uid).doc(mapId), {
            'areaId': areaId,
            'mapName': normalizedName,
            'revealedCellIds': state.revealedCellIds,
            'visitedPoiIds': state.visitedPoiIds,
            'lastInsidePosition': _positionToMap(state.lastInsidePosition),
            'cameraCenter': _positionToMap(state.cameraCenter),
            'zoom': state.zoom,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        })
        .timeout(_defaultTimeout);
  }

  Future<void> deleteMap({required String uid, required String mapId}) async {
    final callable = _functions.httpsCallable('deleteMap');
    await callable
        .call<Map<String, dynamic>>({'mapId': mapId})
        .timeout(_defaultTimeout);
  }

  List<UserMapRecord> _parseMapHistory(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final records = <UserMapRecord>[];
    for (final doc in docs) {
      final data = doc.data();
      final record = _parseMapRecord(doc.id, data);
      if (record == null) continue;
      if (record.status == 'deleted') continue;
      records.add(record);
    }

    records.sort((a, b) {
      final bTime =
          b.updatedAt ?? b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final aTime =
          a.updatedAt ?? a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return records;
  }

  UserMapRecord? _parseMapRecord(String mapId, Map<String, dynamic> raw) {
    final areaId = ((raw['areaId'] as String?)?.trim() ?? mapId);
    if (areaId.isEmpty) {
      return null;
    }
    final mapName = (raw['mapName'] as String?)?.trim();
    final resolvedMapName =
        mapName == null || mapName.isEmpty ? 'Harita: $mapId' : mapName;

    return UserMapRecord(
      mapId: mapId,
      areaId: areaId,
      mapName: resolvedMapName,
      state: CampusMapState(
        revealedCellIds: _parseStringList(raw['revealedCellIds']),
        visitedPoiIds: _parseStringList(raw['visitedPoiIds']),
        lastInsidePosition: _parsePosition(raw['lastInsidePosition']),
        cameraCenter: _parsePosition(raw['cameraCenter']),
        zoom: _parseDouble(raw['zoom']),
      ),
      status: (raw['status'] as String?)?.trim() ?? 'active',
      totalPois: _parseProgressInt(raw['progress'], 'totalPois'),
      visitedPois: _parseProgressInt(
        raw['progress'],
        'visitedPois',
      ).clamp(0, 1000000),
      progressPercent: _parseProgressDouble(raw['progress'], 'percent'),
      earnedXp: _parseProgressInt(raw['progress'], 'earnedXp'),
      createdAt: _parseDateTime(raw['createdAt']),
      updatedAt: _parseDateTime(raw['updatedAt']),
      completedAt: _parseDateTime(raw['completedAt']),
    );
  }

  String _normalizeMapName(String mapName) {
    final trimmed = mapName.trim();
    if (trimmed.isEmpty) {
      throw FirebaseException(
        plugin: 'map_progress_service',
        code: 'invalid-map-name',
        message: 'Harita adı boş olamaz.',
      );
    }

    if (trimmed.length <= 60) {
      return trimmed;
    }

    return trimmed.substring(0, 60);
  }

  List<String> _parseStringList(dynamic raw) {
    if (raw is! List<dynamic>) return const <String>[];

    final ids = <String>{};
    for (final value in raw) {
      if (value is! String) continue;
      final id = value.trim();
      if (id.isEmpty) continue;
      ids.add(id);
    }

    final normalized = ids.toList(growable: false)..sort();
    return normalized;
  }

  Position? _parsePosition(dynamic raw) {
    if (raw is! Map<dynamic, dynamic>) return null;

    final latRaw = raw['lat'];
    final lngRaw = raw['lng'];
    if (latRaw is! num || lngRaw is! num) {
      return null;
    }

    return Position(lngRaw.toDouble(), latRaw.toDouble());
  }

  double? _parseDouble(dynamic raw) {
    if (raw is num) return raw.toDouble();
    return null;
  }

  int _parseProgressInt(dynamic raw, String key) {
    if (raw is! Map<dynamic, dynamic>) return 0;
    final value = raw[key];
    if (value is num) return value.toInt();
    return 0;
  }

  double _parseProgressDouble(dynamic raw, String key) {
    if (raw is! Map<dynamic, dynamic>) return 0;
    final value = raw[key];
    if (value is num) return value.toDouble();
    return 0;
  }

  DateTime? _parseDateTime(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    return null;
  }

  Map<String, double>? _positionToMap(Position? position) {
    if (position == null) return null;

    return <String, double>{
      'lat': position.lat.toDouble(),
      'lng': position.lng.toDouble(),
    };
  }

  List<Map<String, double>> _boundsToPayload(List<Position> boundary) {
    return boundary
        .map(
          (point) => <String, double>{
            'lat': point.lat.toDouble(),
            'lng': point.lng.toDouble(),
          },
        )
        .toList(growable: false);
  }
}

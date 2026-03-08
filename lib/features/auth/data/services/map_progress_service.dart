import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../../domain/models/campus_map_state.dart';
import '../../domain/models/user_map_record.dart';

class MapProgressService {
  MapProgressService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _mapStates =>
      _firestore.collection('userMapStates');

  Future<List<String>> fetchAllMapNames(String uid) async {
    final doc = await _mapStates.doc(uid).get();
    final data = doc.data();
    if (data == null) return const [];

    final mapStatesRaw = data['mapStates'];
    if (mapStatesRaw is! Map<dynamic, dynamic>) {
      return const [];
    }

    final names = <String>[];
    for (final value in mapStatesRaw.values) {
      if (value is! Map<dynamic, dynamic>) continue;
      final mapName = (value['mapName'] as String?)?.trim();
      if (mapName != null && mapName.isNotEmpty) {
        names.add(mapName.toLowerCase());
      }
    }
    return names;
  }

  Future<String?> fetchLastOpenedAreaId(String uid) async {
    final doc = await _mapStates.doc(uid).get();
    final data = doc.data();
    if (data == null) return null;

    final lastMapId = (data['lastOpenedMapId'] as String?)?.trim();
    if (lastMapId == null || lastMapId.isEmpty) {
      return null;
    }

    final mapStates = data['mapStates'];
    if (mapStates is! Map<dynamic, dynamic>) {
      return null;
    }

    final lastMapData = mapStates[lastMapId];
    if (lastMapData is! Map<dynamic, dynamic>) {
      return null;
    }

    final areaId = (lastMapData['areaId'] as String?)?.trim();
    if (areaId == null || areaId.isEmpty) {
      return lastMapId;
    }

    return areaId;
  }

  Future<String> createMap({
    required String uid,
    required String areaId,
    required String mapName,
  }) async {
    final normalizedName = _normalizeMapName(mapName);
    final mapId = _generateMapId();

    await _mapStates.doc(uid).set({
      'lastOpenedMapId': mapId,
      'lastOpenedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'mapStates': {
        mapId: {
          'areaId': areaId,
          'mapName': normalizedName,
          'revealedCellIds': const <String>[],
          'visitedPoiIds': const <String>[],
          'lastInsidePosition': null,
          'cameraCenter': null,
          'zoom': null,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));

    return mapId;
  }

  Stream<List<UserMapRecord>> watchMapHistory(String uid) {
    return _mapStates
        .doc(uid)
        .snapshots()
        .map((snapshot) => _parseMapHistory(snapshot.data()));
  }

  Future<UserMapRecord?> fetchMapById({
    required String uid,
    required String mapId,
  }) async {
    final doc = await _mapStates.doc(uid).get();
    final data = doc.data();
    if (data == null) return null;

    final mapStatesRaw = data['mapStates'];
    if (mapStatesRaw is! Map<dynamic, dynamic>) {
      return null;
    }

    final mapData = mapStatesRaw[mapId];
    if (mapData is! Map<dynamic, dynamic>) {
      return null;
    }

    return _parseMapRecord(mapId, mapData);
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
  }) {
    final normalizedName = _normalizeMapName(mapName);

    return _mapStates.doc(uid).set({
      'lastOpenedMapId': mapId,
      'lastOpenedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'mapStates': {
        mapId: {
          'areaId': areaId,
          'mapName': normalizedName,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));
  }

  Future<void> saveMapState({
    required String uid,
    required String mapId,
    required String areaId,
    required String mapName,
    required CampusMapState state,
  }) {
    final normalizedName = _normalizeMapName(mapName);

    return _mapStates.doc(uid).set({
      'lastOpenedMapId': mapId,
      'lastOpenedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'mapStates': {
        mapId: {
          'areaId': areaId,
          'mapName': normalizedName,
          'revealedCellIds': state.revealedCellIds,
          'visitedPoiIds': state.visitedPoiIds,
          'lastInsidePosition': _positionToMap(state.lastInsidePosition),
          'cameraCenter': _positionToMap(state.cameraCenter),
          'zoom': state.zoom,
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
    }, SetOptions(merge: true));
  }

  Future<void> deleteMap({required String uid, required String mapId}) async {
    final docRef = _mapStates.doc(uid);

    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(docRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? <String, dynamic>{};
      final mapStatesRaw = data['mapStates'];
      if (mapStatesRaw is! Map<dynamic, dynamic> ||
          !mapStatesRaw.containsKey(mapId)) {
        return;
      }

      final updates = <String, dynamic>{
        'mapStates.$mapId': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final lastOpenedMapId = (data['lastOpenedMapId'] as String?)?.trim();
      if (lastOpenedMapId == mapId) {
        updates['lastOpenedMapId'] = FieldValue.delete();
        updates['lastOpenedAt'] = FieldValue.serverTimestamp();
      }

      tx.update(docRef, updates);
    });
  }

  List<UserMapRecord> _parseMapHistory(Map<String, dynamic>? data) {
    if (data == null) return const <UserMapRecord>[];

    final mapStatesRaw = data['mapStates'];
    if (mapStatesRaw is! Map<dynamic, dynamic>) {
      return const <UserMapRecord>[];
    }

    final records = <UserMapRecord>[];
    for (final entry in mapStatesRaw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || value is! Map<dynamic, dynamic>) {
        continue;
      }

      final record = _parseMapRecord(key, value);
      if (record == null) continue;
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

  UserMapRecord? _parseMapRecord(String mapId, Map<dynamic, dynamic> raw) {
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
      createdAt: _parseDateTime(raw['createdAt']),
      updatedAt: _parseDateTime(raw['updatedAt']),
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

  String _generateMapId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = math.Random()
        .nextInt(0xFFFFFF)
        .toRadixString(16)
        .padLeft(6, '0');
    return 'map_${timestamp}_$random';
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
}

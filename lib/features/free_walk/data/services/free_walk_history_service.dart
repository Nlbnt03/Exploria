import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/free_walk_tracker.dart';
import '../../domain/models/free_walk_result.dart';

class FreeWalkHistoryService {
  FreeWalkHistoryService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      _firestore
          .collection('userMapStates')
          .doc(uid)
          .collection('freeWalks');

  Future<FreeWalkResult> saveWalk({
    required String uid,
    required DateTime startedAt,
    required DateTime endedAt,
    required double distanceMeters,
    required int durationSeconds,
    required List<List<FreeWalkPoint>> segments,
  }) async {
    final ref = _collection(uid).doc();
    try {
      await ref.set(<String, Object?>{
        'startedAt': Timestamp.fromDate(startedAt),
        'endedAt': Timestamp.fromDate(endedAt),
        'distanceMeters': distanceMeters,
        'durationSeconds': durationSeconds,
        'segments': <Map<String, Object?>>[
          for (final segment in segments)
            <String, Object?>{
              'points': segment.map((point) => point.toMap()).toList(),
            },
        ],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Firestore's offline queue normally accepts this write; the card is
      // still shown to the user from the in-memory result below either way.
    }
    return FreeWalkResult(
      id: ref.id,
      userId: uid,
      startedAt: startedAt,
      endedAt: endedAt,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      segments: segments,
    );
  }

  Future<void> deleteWalk({required String uid, required String walkId}) {
    return _collection(uid).doc(walkId).delete();
  }

  Stream<List<FreeWalkResult>> watchHistory(String uid) {
    return _collection(uid)
        .orderBy('startedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => <FreeWalkResult>[
            for (final doc in snapshot.docs) _fromDoc(uid, doc),
          ],
        );
  }

  FreeWalkResult _fromDoc(
    String uid,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return FreeWalkResult(
      id: doc.id,
      userId: uid,
      startedAt: _dateTime(data['startedAt']) ?? DateTime.now(),
      endedAt: _dateTime(data['endedAt']) ?? DateTime.now(),
      distanceMeters: (data['distanceMeters'] as num?)?.toDouble() ?? 0,
      durationSeconds: (data['durationSeconds'] as num?)?.toInt() ?? 0,
      segments: _segments(data['segments']),
    );
  }

  static List<List<FreeWalkPoint>> _segments(Object? raw) {
    if (raw is! Iterable) return const <List<FreeWalkPoint>>[];
    return <List<FreeWalkPoint>>[
      for (final entry in raw)
        if (entry is Map)
          _points(entry['points']),
    ];
  }

  static List<FreeWalkPoint> _points(Object? raw) {
    if (raw is! Iterable) return const <FreeWalkPoint>[];
    return raw
        .whereType<Map>()
        .map((value) => FreeWalkPoint.fromMap(Map<String, dynamic>.from(value)))
        .toList(growable: false);
  }

  static DateTime? _dateTime(Object? raw) {
    if (raw is Timestamp) return raw.toDate().toLocal();
    if (raw is DateTime) return raw.toLocal();
    return null;
  }
}

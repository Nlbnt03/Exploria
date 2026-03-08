import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/badge.dart';

class BadgeService {
  BadgeService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _badgesOf(String uid) =>
      _firestore.collection('users').doc(uid).collection('badges');

  Stream<List<AppBadge>> watchBadges(String uid) {
    if (uid.trim().isEmpty) {
      return Stream.value(const <AppBadge>[]);
    }

    return _badgesOf(uid)
        .orderBy('earnedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(AppBadge.fromDoc).toList());
  }

  Future<List<AppBadge>> fetchBadges(String uid) async {
    if (uid.trim().isEmpty) {
      return const <AppBadge>[];
    }

    final snapshot =
        await _badgesOf(uid).orderBy('earnedAt', descending: true).get();
    return snapshot.docs.map(AppBadge.fromDoc).toList();
  }
}

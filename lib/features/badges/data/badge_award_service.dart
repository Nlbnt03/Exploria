import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../auth/data/services/badge_service.dart';
import '../../auth/domain/models/badge.dart';
import '../domain/badge_definitions.dart';
import '../../../providers/game_provider.dart';

class BadgeAwardService {
  final _badgeService = BadgeService();
  final _firestore = FirebaseFirestore.instance;
  static List<BadgeDefinition>? cachedBadges;

  Future<List<String>> checkAndAwardBadges({
    required String uid,
    required BadgeCheckContext context,
    required GameNotifier gameNotifier,
  }) async {
    final earnedBadgeIds = <String>[];

    try {
      final existingBadges = await _badgeService.fetchBadges(uid);
      final existingIds = existingBadges.map((b) => b.id).toSet();

      if (cachedBadges == null) {
        final snap = await _firestore.collection('badges').where('isActive', isEqualTo: true).get();
        cachedBadges = snap.docs.map((doc) => BadgeDefinition.fromJson(doc.data(), doc.id)).toList();
      }

      for (final def in cachedBadges!) {
        if (existingIds.contains(def.id)) continue;

        if (def.condition(context)) {
          await _awardBadge(uid: uid, def: def, gameNotifier: gameNotifier);
          earnedBadgeIds.add(def.id);
        }
      }
    } catch (e) {
      debugPrint('Error awarding badges: $e');
    }

    return earnedBadgeIds;
  }

  Future<void> _awardBadge({
    required String uid,
    required BadgeDefinition def,
    required GameNotifier gameNotifier,
  }) async {
    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('badges')
        .doc(def.id);

    await docRef.set({
      'id': def.id,
      'name': def.name,
      'description': def.description,
      'iconName': _getIconNameForCategory(def.category),
      'earnedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (def.xpReward != null && def.xpReward! > 0) {
      await gameNotifier.addXP(def.xpReward!);
    }
  }

  String _getIconNameForCategory(BadgeCategory category) {
    switch (category) {
      case BadgeCategory.exploration:
        return 'explore';
      case BadgeCategory.social:
        return 'people';
      case BadgeCategory.streak:
        return 'local_fire_department';
      case BadgeCategory.secret:
        return 'visibility_off';
    }
  }

  static Future<void> initBadges() async {
    final snap = await FirebaseFirestore.instance
        .collection('badges')
        .where('isActive', isEqualTo: true)
        .get();
    cachedBadges = snap.docs
        .map((doc) => BadgeDefinition.fromJson(doc.data(), doc.id))
        .toList();
    debugPrint('[Badges] ${cachedBadges!.length} rozet projenin önbelleğine yüklendi.');
  }
}

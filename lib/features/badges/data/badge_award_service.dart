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
    final earned = await checkNewBadges(uid: uid, context: context);
    await awardBadges(uid: uid, badges: earned, gameNotifier: gameNotifier);
    return earned.map((d) => d.id).toList();
  }

  /// Returns badge definitions that the user has just earned but not yet been awarded.
  /// Only performs Firestore reads — use [awardBadges] separately to write.
  Future<List<BadgeDefinition>> checkNewBadges({
    required String uid,
    required BadgeCheckContext context,
  }) async {
    try {
      final existingBadges = await _badgeService.fetchBadges(uid);
      final existingIds = existingBadges.map((b) => b.id).toSet();

      if (cachedBadges == null) {
        final snap =
            await _firestore
                .collection('badges')
                .where('isActive', isEqualTo: true)
                .get();
        cachedBadges =
            snap.docs
                .map((doc) => BadgeDefinition.fromJson(doc.data(), doc.id))
                .toList();
      }

      return cachedBadges!
          .where(
            (def) => !existingIds.contains(def.id) && def.condition(context),
          )
          .toList();
    } catch (e) {
      debugPrint('Error checking badges: $e');
      return [];
    }
  }

  /// Writes badge awards to Firestore. Safe to run with [unawaited] while showing the dialog.
  Future<void> awardBadges({
    required String uid,
    required List<BadgeDefinition> badges,
    required GameNotifier gameNotifier,
  }) async {
    for (final def in badges) {
      try {
        await _awardBadge(uid: uid, def: def, gameNotifier: gameNotifier);
      } catch (e) {
        debugPrint('Error awarding badge ${def.id}: $e');
      }
    }
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
      'images': def.images,
      'earnedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _addToProfileShowcase(uid, def.id);

    if (def.xpReward != null && def.xpReward! > 0) {
      await gameNotifier.addXP(def.xpReward!);
    }
  }

  Future<void> _addToProfileShowcase(String uid, String badgeId) async {
    final userRef = _firestore.collection('users').doc(uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(userRef);
      final rawFeatured = snapshot.data()?['featuredBadges'];
      final featured =
          rawFeatured is List
              ? rawFeatured.map((item) => item.toString()).toList()
              : <String>[];

      featured.remove(badgeId);
      featured.insert(0, badgeId);
      transaction.set(userRef, {
        'featuredBadges': featured.take(4).toList(),
      }, SetOptions(merge: true));
    });
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
    final snap =
        await FirebaseFirestore.instance
            .collection('badges')
            .where('isActive', isEqualTo: true)
            .get();
    cachedBadges =
        snap.docs
            .map((doc) => BadgeDefinition.fromJson(doc.data(), doc.id))
            .toList();
    debugPrint(
      '[Badges] ${cachedBadges!.length} rozet projenin önbelleğine yüklendi.',
    );
  }
}

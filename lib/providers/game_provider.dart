import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_xp.dart';
import '../models/leaderboard_entry.dart';
import '../models/weekly_quest.dart';
import '../models/weekly_quest_completion.dart';
import '../features/auth/data/services/leaderboard_service.dart';
import 'package:flutter/material.dart';
import '../features/badges/data/badge_award_service.dart';
import '../features/badges/domain/badge_definitions.dart';
// Callback for title change
typedef OnTitleChanged = void Function(UserTitle newTitle);

final gameProvider = AsyncNotifierProvider.autoDispose<GameNotifier, UserXP>(() {
  return GameNotifier();
});

class GameNotifier extends AutoDisposeAsyncNotifier<UserXP> {
  UserTitle? _previousTitle;
  StreamSubscription? _sub;
  OnTitleChanged? onTitleChanged;
  bool _pendingPerfectionistBadgeCheck = false;

  final List<WeeklyQuestCompletionInfo> _pendingQuestCompletions = [];

  /// Returns and clears quests that were just completed.
  /// Call immediately after [onPlaceVisited] to show celebration dialogs.
  List<WeeklyQuestCompletionInfo> consumePendingQuestCompletions() {
    final list = List<WeeklyQuestCompletionInfo>.from(_pendingQuestCompletions);
    _pendingQuestCompletions.clear();
    return list;
  }

  @override
  FutureOr<UserXP> build() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return UserXP(currentXP: 0, weeklyQuests: WeeklyQuests.empty());
    }

    final docRef = FirebaseFirestore.instance.collection('users').doc(uid);

    ref.onDispose(() {
      _sub?.cancel();
    });

    // Inital fetch
    final doc = await docRef.get();
    final userXP = _parseUserXP(doc);
    _previousTitle = userXP.currentTitle;

    // Ensure leaderboard entry exists so the user appears for friends even with 0 XP
    final data = doc.data();
    if (data != null) {
      final username = (data['username'] as String?)?.trim() ?? '';
      if (username.isNotEmpty) {
        final weeklyXP = (data['weeklyXP'] as num?)?.toInt() ?? 0;
        LeaderboardService().ensureLeaderboardEntry(
          uid: uid,
          username: username,
          title: userXP.titleName,
          titleColorHex: LeaderboardEntry.colorToHex(userXP.titleColor),
          totalXP: userXP.currentXP,
          weeklyXP: weeklyXP,
        );
      }
    }

    // Listen to changes
    _sub?.cancel();
    _sub = docRef.snapshots().listen((snapshot) {
      if (!snapshot.exists) return; // Prevent creating if user is deleted somehow
      
      final newXP = _parseUserXP(snapshot);
      
      // Check for title change
      if (_previousTitle != null && newXP.currentTitle != _previousTitle) {
        onTitleChanged?.call(newXP.currentTitle);
      }
      _previousTitle = newXP.currentTitle;
      
      // We check if weekStart is outdated, if so we update firestore (which will trigger another snapshot)
      final defaultStart = WeeklyQuests.getWeekStart(DateTime.now());
      if (newXP.weeklyQuests.weekStart != defaultStart) {
        // Reset quests and weeklyXP in firestore
        docRef.set({
          'weeklyQuests': WeeklyQuests.empty().toMap(),
          'weeklyXP': 0,
          'weeklyXPUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        // Also reset leaderboard entry
        LeaderboardService().resetWeeklyXP(uid);
        return; // the next snapshot will handle state
      }

      state = AsyncValue.data(newXP);
    });

    return userXP;
  }

  UserXP _parseUserXP(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    if (!snapshot.exists || snapshot.data() == null) {
      return UserXP(currentXP: 0, weeklyQuests: WeeklyQuests.empty());
    }
    final data = snapshot.data()!;
    final xp = (data['xp'] as num?)?.toInt() ?? 0;
    final questsMap = data['weeklyQuests'] as Map<String, dynamic>?;
    final quests = WeeklyQuests.fromMap(questsMap);
    return UserXP(currentXP: xp, weeklyQuests: quests);
  }

  Future<bool> addXP(int amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    try {
      bool isLevelUp = false;
      final leaderboardService = LeaderboardService();
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
        final snapshot = await transaction.get(docRef);
        final data = snapshot.data() ?? <String, dynamic>{};
        
        int currentXP = (data['xp'] as num?)?.toInt() ?? 0;
        int currentWeeklyXP = (data['weeklyXP'] as num?)?.toInt() ?? 0;
        final username = (data['username'] as String?)?.trim() ?? '';
        
        final newXP = currentXP + amount;
        final newWeeklyXP = currentWeeklyXP + amount;
        final oldTitle = UserXP(currentXP: currentXP, weeklyQuests: WeeklyQuests.empty()).currentTitle;
        final newUserXP = UserXP(currentXP: newXP, weeklyQuests: WeeklyQuests.empty());
        final newTitle = newUserXP.currentTitle;
        
        if (newTitle != oldTitle) {
          isLevelUp = true;
        }

        transaction.set(docRef, {
          'xp': newXP,
          'weeklyXP': newWeeklyXP,
          'weeklyXPUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Sync leaderboard atomically
        leaderboardService.syncLeaderboardInTransaction(
          transaction: transaction,
          uid: uid,
          totalXP: newXP,
          weeklyXP: newWeeklyXP,
          username: username,
          title: newUserXP.titleName,
          titleColorHex: LeaderboardEntry.colorToHex(newUserXP.titleColor),
        );
      });
      return isLevelUp;
    } catch (e) {
      debugPrint('Error saving XP: $e');
      return false;
    }
  }

  Future<void> onMapFirstEntered() async {
    await addXP(100);
  }

  /// İptal edilen mekan ziyareti için XP düşür
  Future<void> removeXP(int amount) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final leaderboardService = LeaderboardService();
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
        final snapshot = await transaction.get(docRef);
        final data = snapshot.data() ?? <String, dynamic>{};
        
        int currentXP = (data['xp'] as num?)?.toInt() ?? 0;
        int currentWeeklyXP = (data['weeklyXP'] as num?)?.toInt() ?? 0;
        final username = (data['username'] as String?)?.trim() ?? '';
        
        final newXP = (currentXP - amount).clamp(0, 999999);
        final newWeeklyXP = (currentWeeklyXP - amount).clamp(0, 999999);

        final newUserXP = UserXP(currentXP: newXP, weeklyQuests: WeeklyQuests.empty());

        transaction.set(docRef, {
          'xp': newXP,
          'weeklyXP': newWeeklyXP,
          'weeklyXPUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Sync leaderboard atomically
        leaderboardService.syncLeaderboardInTransaction(
          transaction: transaction,
          uid: uid,
          totalXP: newXP,
          weeklyXP: newWeeklyXP,
          username: username,
          title: newUserXP.titleName,
          titleColorHex: LeaderboardEntry.colorToHex(newUserXP.titleColor),
        );
      });
      ref.invalidateSelf();
    } catch (e) {
      debugPrint('Error removing XP: $e');
    }
  }

  Future<bool> onPlaceVisited(String placeId, String category, bool isCoop, {int? xpValue}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;
    
    // Calculate new quest state and XP to add inside a transaction
    try {
      bool isLevelUp = false;
      final leaderboardService = LeaderboardService();
      // Declared outside so post-transaction code can read the result.
      // Cleared at the top of the transaction body to survive retries.
      final Set<String> newlyCompletedKeys = {};
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docRef = FirebaseFirestore.instance.collection('users').doc(uid);
        final snapshot = await transaction.get(docRef);
        final data = snapshot.data() ?? <String, dynamic>{};

        int currentXP = (data['xp'] as num?)?.toInt() ?? 0;
        int currentWeeklyXP = (data['weeklyXP'] as num?)?.toInt() ?? 0;
        final username = (data['username'] as String?)?.trim() ?? '';
        final questsMap = data['weeklyQuests'] as Map<String, dynamic>?;
        
        // Parse current quests
        var quests = WeeklyQuests.fromMap(questsMap);
        
        int xpToAdd = xpValue ?? (isCoop ? 75 : 50);
        String today = "${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}";

        // newlyCompletedKeys is declared outside so we can read it after the
        // transaction, but cleared at the top so retries don't duplicate entries.
        newlyCompletedKeys.clear();

        WeeklyQuestItem ilkAdim = quests.ilkAdim;
        if (!ilkAdim.done) {
          ilkAdim = ilkAdim.copyWith(current: 1, done: true);
          xpToAdd += 50;
          newlyCompletedKeys.add('ilkAdim');
        }

        WeeklyQuestItem kasifRuhu = quests.kasifRuhu;
        if (!kasifRuhu.done) {
          int newCurrent = kasifRuhu.current + 1;
          bool newDone = newCurrent >= kasifRuhu.target;
          kasifRuhu = kasifRuhu.copyWith(current: newCurrent, done: newDone);
          if (newDone) {
            xpToAdd += 100;
            newlyCompletedKeys.add('kasifRuhu');
          }
        }

        WeeklyQuestItem cesitliKasif = quests.cesitliKasif;
        if (!cesitliKasif.done && category.isNotEmpty) {
          List<String> updatedCategories = List.from(cesitliKasif.categories);
          if (!updatedCategories.contains(category)) {
            updatedCategories.add(category);
          }
          bool newDone = updatedCategories.length >= cesitliKasif.target;
          cesitliKasif = cesitliKasif.copyWith(categories: updatedCategories, done: newDone);
          if (newDone) {
            xpToAdd += 75;
            newlyCompletedKeys.add('cesitliKasif');
          }
        }

        WeeklyQuestItem duzenliGezgin = quests.duzenliGezgin;
        if (!duzenliGezgin.done) {
          List<String> updatedDays = List.from(duzenliGezgin.activeDays);
          if (!updatedDays.contains(today)) {
            updatedDays.add(today);
          }
          bool newDone = updatedDays.length >= duzenliGezgin.target;
          duzenliGezgin = duzenliGezgin.copyWith(activeDays: updatedDays, done: newDone);
          if (newDone) {
            xpToAdd += 75;
            newlyCompletedKeys.add('duzenliGezgin');
          }
        }

        WeeklyQuestItem takimOyuncusu = quests.takimOyuncusu;
        WeeklyQuestItem takimKasifi = quests.takimKasifi;

        if (isCoop) {
          if (!takimOyuncusu.done) {
            takimOyuncusu = takimOyuncusu.copyWith(current: 1, done: true);
            xpToAdd += 100;
            newlyCompletedKeys.add('takimOyuncusu');
          }
          if (!takimKasifi.done) {
            int newCurrent = takimKasifi.current + 1;
            bool newDone = newCurrent >= takimKasifi.target;
            takimKasifi = takimKasifi.copyWith(current: newCurrent, done: newDone);
            if (newDone) {
              xpToAdd += 100;
              newlyCompletedKeys.add('takimKasifi');
            }
          }
        }

        WeeklyQuestItem tamHafta = quests.tamHafta;
        if (!tamHafta.done) {
          List<String> updatedDays = List.from(tamHafta.activeDays);
          if (!updatedDays.contains(today)) {
            updatedDays.add(today);
          }
          bool newDone = updatedDays.length >= tamHafta.target;
          tamHafta = tamHafta.copyWith(activeDays: updatedDays, done: newDone);
          if (newDone) {
            xpToAdd += 300;
            newlyCompletedKeys.add('tamHafta');
          }
        }

        // New total XP
        final finalXP = currentXP + xpToAdd;
        final finalWeeklyXP = currentWeeklyXP + xpToAdd;

        bool wasAllDone = quests.ilkAdim.done && quests.kasifRuhu.done && quests.cesitliKasif.done && quests.duzenliGezgin.done && quests.takimOyuncusu.done && quests.takimKasifi.done && quests.tamHafta.done;
        bool isAllDone = ilkAdim.done && kasifRuhu.done && cesitliKasif.done && duzenliGezgin.done && takimOyuncusu.done && takimKasifi.done && tamHafta.done;
        
        // Save for after transaction
        if (!wasAllDone && isAllDone) {
          _pendingPerfectionistBadgeCheck = true;
        }

        final oldTitle = UserXP(currentXP: currentXP, weeklyQuests: WeeklyQuests.empty()).currentTitle;
        final newUserXP = UserXP(currentXP: finalXP, weeklyQuests: WeeklyQuests.empty());
        final newTitle = newUserXP.currentTitle;
        if (newTitle != oldTitle) {
          isLevelUp = true;
        }

        // Apply
        final newQuests = WeeklyQuests(
          weekStart: quests.weekStart,
          ilkAdim: ilkAdim,
          kasifRuhu: kasifRuhu,
          cesitliKasif: cesitliKasif,
          duzenliGezgin: duzenliGezgin,
          takimOyuncusu: takimOyuncusu,
          takimKasifi: takimKasifi,
          tamHafta: tamHafta,
        );

        transaction.set(docRef, {
          'xp': finalXP,
          'weeklyXP': finalWeeklyXP,
          'weeklyXPUpdatedAt': FieldValue.serverTimestamp(),
          'weeklyQuests': newQuests.toMap(),
        }, SetOptions(merge: true));

        // Sync leaderboard atomically
        leaderboardService.syncLeaderboardInTransaction(
          transaction: transaction,
          uid: uid,
          totalXP: finalXP,
          weeklyXP: finalWeeklyXP,
          username: username,
          title: newUserXP.titleName,
          titleColorHex: LeaderboardEntry.colorToHex(newUserXP.titleColor),
        );
      });
      
      // Populate pending quest completions AFTER the transaction succeeds
      // so retries don't produce duplicates.
      for (final key in newlyCompletedKeys) {
        final info = WeeklyQuestCompletionInfo.definitions[key];
        if (info != null) _pendingQuestCompletions.add(info);
      }

      // BÖLÜM 2 — Rozet Kontrolü (arka planda, kullanıcıyı bekletmez)
      if (_pendingPerfectionistBadgeCheck) {
        _pendingPerfectionistBadgeCheck = false;
        unawaited(_checkBadgesAfterVisit(uid));
      }

      return isLevelUp;
    } catch (e) {
      debugPrint('Error updating quests and xp: $e');
      return false;
    }
  }

  Future<void> _checkBadgesAfterVisit(String uid) async {
    try {
      final bContext = BadgeCheckContext(
        totalVisited: 0,
        historicBuildingVisited: 0,
        mosqueVisited: 0,
        distinctCitiesVisited: 0,
        coopSessionsCompleted: 0,
        distinctCoopPartners: 0,
        coopMapJustCompleted: false,
        currentStreak: 0,
        allWeeklyQuestsJustCompleted: true,
        visitTime: DateTime.now(),
        recentVisitTimes: [],
      );
      await BadgeAwardService().checkAndAwardBadges(
        uid: uid,
        context: bContext,
        gameNotifier: this,
      );
    } catch (e) {
      debugPrint('Background badge check failed: $e');
    }
  }
}

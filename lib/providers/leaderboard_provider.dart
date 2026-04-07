import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/leaderboard_entry.dart';
import '../features/auth/data/services/leaderboard_service.dart';

final leaderboardServiceProvider = Provider<LeaderboardService>((ref) {
  return LeaderboardService();
});

final leaderboardProvider =
    AsyncNotifierProvider.autoDispose<LeaderboardNotifier, List<LeaderboardEntry>>(() {
  return LeaderboardNotifier();
});

class LeaderboardNotifier extends AutoDisposeAsyncNotifier<List<LeaderboardEntry>> {
  StreamSubscription? _sub;

  @override
  FutureOr<List<LeaderboardEntry>> build() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const <LeaderboardEntry>[];
    }

    final service = ref.watch(leaderboardServiceProvider);

    ref.onDispose(() {
      _sub?.cancel();
    });

    // Set up real-time listener
    final completer = Completer<List<LeaderboardEntry>>();
    _sub?.cancel();
    _sub = service.watchLeaderboard(uid).listen(
      (entries) {
        if (!completer.isCompleted) {
          completer.complete(entries);
        } else {
          state = AsyncValue.data(entries);
        }
      },
      onError: (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        } else {
          state = AsyncValue.error(error, stackTrace);
        }
      },
    );

    return completer.future;
  }

  /// Get the current user's rank (1-indexed). Returns null if not found.
  int? get currentUserRank {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    final entries = state.valueOrNull;
    if (entries == null || entries.isEmpty) return null;

    for (var i = 0; i < entries.length; i++) {
      if (entries[i].uid == uid) return i + 1;
    }
    return null;
  }

  /// Get the current user's leaderboard entry.
  LeaderboardEntry? get currentUserEntry {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    return state.valueOrNull?.cast<LeaderboardEntry?>().firstWhere(
      (e) => e?.uid == uid,
      orElse: () => null,
    );
  }
}

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/leaderboard_entry.dart';

class LeaderboardService {
  LeaderboardService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _leaderboard =>
      _firestore.collection('leaderboard');

  /// Watches the leaderboard for [currentUid] and their friends.
  /// Returns a stream of sorted [LeaderboardEntry] list.
  Stream<List<LeaderboardEntry>> watchLeaderboard(String currentUid) {
    if (currentUid.trim().isEmpty) {
      return Stream.value(const <LeaderboardEntry>[]);
    }

    // First, listen to the user's friends list, then pivot to leaderboard queries
    return _users.doc(currentUid).snapshots().asyncExpand((userSnapshot) {
      final userData = userSnapshot.data() ?? <String, dynamic>{};
      final friends = List<String>.from(userData['friends'] ?? <String>[]);

      // Always include the current user
      final allUids = <String>{currentUid, ...friends}.toList();

      if (allUids.isEmpty) {
        return Stream.value(const <LeaderboardEntry>[]);
      }

      // Chunk UIDs into groups of 10 for whereIn queries
      final chunks = <List<String>>[];
      for (var i = 0; i < allUids.length; i += 10) {
        chunks.add(allUids.sublist(i, i + 10 > allUids.length ? allUids.length : i + 10));
      }

      // Create a stream for each chunk
      final chunkStreams = chunks.map((chunk) {
        return _leaderboard
            .where(FieldPath.documentId, whereIn: chunk)
            .snapshots()
            .map((snapshot) {
          return snapshot.docs
              .map((doc) => LeaderboardEntry.fromMap(doc.id, doc.data()))
              .toList();
        });
      }).toList();

      if (chunkStreams.isEmpty) {
        return Stream.value(const <LeaderboardEntry>[]);
      }

      // If only one chunk, just use it directly
      if (chunkStreams.length == 1) {
        return chunkStreams.first.map(_sortEntries);
      }

      // Combine multiple chunk streams
      return _combineStreams(chunkStreams).map(_sortEntries);
    });
  }

  /// Combines multiple streams into a single stream that emits when any stream updates.
  Stream<List<LeaderboardEntry>> _combineStreams(
    List<Stream<List<LeaderboardEntry>>> streams,
  ) {
    final controller = StreamController<List<LeaderboardEntry>>();
    final latestData = List<List<LeaderboardEntry>?>.filled(streams.length, null);
    final subscriptions = <StreamSubscription>[];

    for (var i = 0; i < streams.length; i++) {
      final index = i;
      subscriptions.add(
        streams[index].listen(
          (data) {
            latestData[index] = data;
            // Only emit when we have data from all streams
            if (latestData.every((d) => d != null)) {
              final combined = <LeaderboardEntry>[];
              for (final list in latestData) {
                if (list != null) combined.addAll(list);
              }
              controller.add(combined);
            }
          },
          onError: controller.addError,
        ),
      );
    }

    controller.onCancel = () {
      for (final sub in subscriptions) {
        sub.cancel();
      }
    };

    return controller.stream;
  }

  /// Sort entries by weeklyXP descending, then totalXP as tiebreaker.
  List<LeaderboardEntry> _sortEntries(List<LeaderboardEntry> entries) {
    entries.sort((a, b) {
      final xpCompare = b.weeklyXP.compareTo(a.weeklyXP);
      if (xpCompare != 0) return xpCompare;
      return b.totalXP.compareTo(a.totalXP);
    });
    return entries;
  }

  /// Sync the leaderboard entry for a user after XP changes.
  /// Call this inside a Firestore transaction for atomicity.
  void syncLeaderboardInTransaction({
    required Transaction transaction,
    required String uid,
    required int totalXP,
    required int weeklyXP,
    required String username,
    required String title,
    required String titleColorHex,
  }) {
    final leaderboardRef = _leaderboard.doc(uid);
    transaction.set(leaderboardRef, {
      'username': username,
      'title': title,
      'titleColor': titleColorHex,
      'weeklyXP': weeklyXP,
      'totalXP': totalXP,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Reset weeklyXP for a user in both users and leaderboard collections.
  Future<void> resetWeeklyXP(String uid) async {
    final batch = _firestore.batch();
    batch.set(_users.doc(uid), {
      'weeklyXP': 0,
      'weeklyXPUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(_leaderboard.doc(uid), {
      'weeklyXP': 0,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await batch.commit();
  }

  /// Ensure a leaderboard document exists for the user.
  /// Called on app startup or first XP event.
  Future<void> ensureLeaderboardEntry({
    required String uid,
    required String username,
    required String title,
    required String titleColorHex,
    required int totalXP,
    required int weeklyXP,
  }) async {
    final doc = await _leaderboard.doc(uid).get();
    if (!doc.exists) {
      await _leaderboard.doc(uid).set({
        'username': username,
        'title': title,
        'titleColor': titleColorHex,
        'weeklyXP': weeklyXP,
        'totalXP': totalXP,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }
}

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/friend_ref.dart';
import '../models/invite.dart';
import '../models/live_location.dart';
import '../models/member.dart';
import '../models/room.dart';

class MultiRoomFirestoreService {
  MultiRoomFirestoreService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _rooms =>
      _firestore.collection('rooms');

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  CollectionReference<Map<String, dynamic>> get _invites =>
      _firestore.collection('invites');

  String? get currentUid => _auth.currentUser?.uid;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'unauthenticated',
        message: 'Kullanici oturumu bulunamadi.',
      );
    }
    return uid;
  }

  Future<String> createRoom(
    String roomName,
    String cityId, {
    bool reuseWaitingOrActive = false,
  }) async {
    final uid = _uid;
    final normalizedRoomName = roomName.trim();
    if (normalizedRoomName.isEmpty) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'invalid-room-name',
        message: 'Oda adi bos olamaz.',
      );
    }

    final normalizedCityId = cityId.trim().isEmpty ? 'istanbul' : cityId.trim();
    if (reuseWaitingOrActive) {
      final reusableRoom = await _findReusableHostRoom(
        hostId: uid,
        cityId: normalizedCityId,
      );
      if (reusableRoom != null) {
        await ensureRoomMembership(reusableRoom.id);
        return reusableRoom.id;
      }
    }

    final username = await _resolveUsername(uid);
    final roomRef = _rooms.doc();
    final memberRef = roomRef.collection('members').doc(uid);

    await _firestore.runTransaction((tx) async {
      tx.set(roomRef, {
        'hostId': uid,
        'cityId': normalizedCityId,
        'roomName': normalizedRoomName,
        'status': 'waiting',
        'minPlayers': 2,
        'createdAt': FieldValue.serverTimestamp(),
      });

      tx.set(memberRef, {
        'uid': uid,
        'username': username,
        'joinedAt': FieldValue.serverTimestamp(),
      });
    });

    return roomRef.id;
  }

  Future<Room?> _findReusableHostRoom({
    required String hostId,
    required String cityId,
  }) async {
    const reusableStatuses = <String>['active', 'waiting'];
    for (final status in reusableStatuses) {
      final query =
          await _rooms
              .where('cityId', isEqualTo: cityId)
              .where('hostId', isEqualTo: hostId)
              .where('status', isEqualTo: status)
              .limit(1)
              .get();
      if (query.docs.isNotEmpty) {
        return Room.fromDoc(query.docs.first);
      }
    }
    return null;
  }

  Future<Room?> fetchRoom(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      return null;
    }

    final snap = await _rooms.doc(normalizedRoomId).get();
    if (!snap.exists) {
      return null;
    }
    return Room.fromDoc(snap);
  }

  Future<void> ensureRoomMembership(String roomId) async {
    final normalizedRoomId = roomId.trim();
    if (normalizedRoomId.isEmpty) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'invalid-room-id',
        message: 'Gecersiz oda kimligi.',
      );
    }

    final uid = _uid;
    final username = await _resolveUsername(uid);
    await _rooms.doc(normalizedRoomId).collection('members').doc(uid).set({
      'uid': uid,
      'username': username,
      'joinedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Wraps a Firestore snapshot stream with auto-retry on error.
  /// On error, waits [delay] then re-subscribes automatically.
  Stream<T> _withAutoRetry<T>(Stream<T> Function() factory, {Duration delay = const Duration(seconds: 3)}) {
    StreamController<T>? controller;
    StreamSubscription<T>? sub;

    void start() {
      sub = factory().listen(
        (data) {
          controller?.add(data);
        },
        onError: (Object e) {
          debugPrint('[Firestore] Stream error, retrying in $delay: $e');
          sub?.cancel();
          Future.delayed(delay, () {
            if (controller != null && !controller.isClosed) start();
          });
        },
        onDone: () {
          debugPrint('[Firestore] Stream closed, reopening in $delay');
          Future.delayed(delay, () {
            if (controller != null && !controller.isClosed) start();
          });
        },
      );
    }

    controller = StreamController<T>(
      onCancel: () {
        sub?.cancel();
        controller?.close();
      },
    );

    start();
    return controller.stream;
  }

  Stream<Room?> listenRoom(String roomId) {
    return _withAutoRetry(
      () => _rooms.doc(roomId).snapshots().map((doc) {
        if (!doc.exists) return null;
        return Room.fromDoc(doc);
      }),
    );
  }

  Stream<List<Member>> listenMembers(String roomId) {
    return _withAutoRetry(
      () => _rooms
          .doc(roomId)
          .collection('members')
          .orderBy('joinedAt')
          .snapshots()
          .map((snapshot) => snapshot.docs.map(Member.fromDoc).toList()),
    );
  }

  Stream<List<LiveLocation>> listenLocations(String roomId) {
    return _withAutoRetry(
      () => _rooms
          .doc(roomId)
          .collection('locations')
          .snapshots()
          .map((snapshot) => snapshot.docs.map(LiveLocation.fromDoc).toList()),
    );
  }

  Stream<Set<String>> listenInMapUids(String roomId) {
    return _withAutoRetry(
      () => _rooms
          .doc(roomId)
          .collection('presence')
          .where('inMap', isEqualTo: true)
          .snapshots()
          .map((snapshot) {
            final uids = <String>{};
            for (final doc in snapshot.docs) {
              final uid = (doc.data()['uid'] as String?)?.trim() ?? doc.id.trim();
              if (uid.isNotEmpty) {
                uids.add(uid);
              }
            }
            return uids;
          }),
    );
  }

  Future<void> setMyInMapPresence(String roomId, {required bool inMap}) async {
    final uid = _uid;
    final ref = _rooms.doc(roomId).collection('presence').doc(uid);

    final payload = <String, dynamic>{
      'uid': uid,
      'inMap': inMap,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (inMap) {
      payload['enteredAt'] = FieldValue.serverTimestamp();
    }

    await ref.set(payload, SetOptions(merge: true));
  }

  Future<void> sendInvite(String roomId, String toUserId) async {
    final fromUserId = _uid;
    final normalizedToUserId = toUserId.trim();
    if (normalizedToUserId.isEmpty) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'invalid-user',
        message: 'Davet edilecek kullanici bos olamaz.',
      );
    }

    final roomSnap = await _rooms.doc(roomId).get();
    if (!roomSnap.exists) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'room-not-found',
        message: 'Oda bulunamadi.',
      );
    }

    final room = Room.fromDoc(roomSnap);
    final roomName = room.roomName.trim();
    final fromUsername = await _resolveUsername(fromUserId);
    if (room.hostId != fromUserId) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'only-host-can-invite',
        message: 'Sadece oda kurucusu davet gonderebilir.',
      );
    }

    final friendDoc =
        await _users
            .doc(fromUserId)
            .collection('friends')
            .doc(normalizedToUserId)
            .get();
    if (!friendDoc.exists) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'not-friend',
        message: 'Sadece arkadaslarini davet edebilirsin.',
      );
    }

    final inviteId = '${roomId}_${fromUserId}_$normalizedToUserId';
    final inviteRef = _invites.doc(inviteId);
    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(inviteRef);
      if (existing.exists) {
        final existingStatus = existing.data()?['status'] as String?;
        if (existingStatus == 'pending') {
          throw FirebaseException(
            plugin: 'multi_room_firestore_service',
            code: 'invite-already-exists',
            message: 'Bu kullanici icin zaten bir davet olusturulmus.',
          );
        }
        // Reddedilmiş/kabul edilmiş daveti üzerine yaz → Functions pending geçişini yakalar
      }

      tx.set(inviteRef, {
        'roomId': roomId,
        'roomName': roomName.isEmpty ? roomId : roomName,
        'fromUserId': fromUserId,
        'fromUsername': fromUsername,
        'toUserId': normalizedToUserId,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> acceptInvite(String inviteId) async {
    final currentUid = _uid;
    final inviteRef = _invites.doc(inviteId);
    final username = await _resolveUsername(currentUid);

    await _firestore.runTransaction((tx) async {
      final inviteSnap = await tx.get(inviteRef);
      if (!inviteSnap.exists) {
        throw FirebaseException(
          plugin: 'multi_room_firestore_service',
          code: 'invite-not-found',
          message: 'Davet bulunamadi.',
        );
      }

      final invite = Invite.fromDoc(inviteSnap);
      if (invite.toUserId != currentUid) {
        throw FirebaseException(
          plugin: 'multi_room_firestore_service',
          code: 'permission-denied',
          message: 'Bu daveti kabul etme yetkin yok.',
        );
      }
      if (!invite.isPending) {
        throw FirebaseException(
          plugin: 'multi_room_firestore_service',
          code: 'invite-not-pending',
          message: 'Bu davet artik beklemede degil.',
        );
      }

      final memberRef = _rooms
          .doc(invite.roomId)
          .collection('members')
          .doc(currentUid);
      tx.set(memberRef, {
        'uid': currentUid,
        'username': username,
        'joinedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.update(inviteRef, {
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> rejectInvite(String inviteId) async {
    final currentUid = _uid;
    final inviteRef = _invites.doc(inviteId);

    await _firestore.runTransaction((tx) async {
      final inviteSnap = await tx.get(inviteRef);
      if (!inviteSnap.exists) return;

      final invite = Invite.fromDoc(inviteSnap);
      if (invite.toUserId != currentUid) {
        throw FirebaseException(
          plugin: 'multi_room_firestore_service',
          code: 'permission-denied',
          message: 'Bu daveti reddetme yetkin yok.',
        );
      }

      tx.update(inviteRef, {
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> startRoom(String roomId) async {
    final uid = _uid;
    final roomRef = _rooms.doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'room-not-found',
        message: 'Oda bulunamadi.',
      );
    }
    final room = Room.fromDoc(roomSnap);
    if (room.hostId != uid) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'permission-denied',
        message: 'Sadece oda kurucusu baslatabilir.',
      );
    }

    final membersCount = await roomRef.collection('members').count().get();
    if ((membersCount.count ?? 0) < room.minPlayers) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'min-players-not-reached',
        message: 'Odayi baslatmak icin en az ${room.minPlayers} kisi gerekli.',
      );
    }

    await roomRef.update({
      'status': 'active',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> endRoom(String roomId) async {
    final uid = _uid;
    final roomRef = _rooms.doc(roomId);
    final roomSnap = await roomRef.get();
    if (!roomSnap.exists) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'room-not-found',
        message: 'Oda bulunamadi.',
      );
    }
    final room = Room.fromDoc(roomSnap);
    if (room.hostId != uid) {
      throw FirebaseException(
        plugin: 'multi_room_firestore_service',
        code: 'permission-denied',
        message: 'Sadece oda kurucusu odayi bitirebilir.',
      );
    }

    await roomRef.update({
      'status': 'finished',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> leaveRoom(String roomId) async {
    final uid = _uid;
    final roomRef = _rooms.doc(roomId);
    final memberRef = roomRef.collection('members').doc(uid);
    final locationRef = roomRef.collection('locations').doc(uid);

    // Host transfer (if needed) — must happen BEFORE deleting our membership,
    // because the room update rules require isRoomMember.
    final roomSnap = await roomRef.get();
    if (roomSnap.exists) {
      final room = Room.fromDoc(roomSnap);
      if (room.hostId == uid && !room.isFinished) {
        final membersSnap = await roomRef.collection('members').get();
        final nextHostUid = membersSnap.docs
            .where((d) => d.id != uid)
            .map((d) => (d.data()['uid'] as String?)?.trim() ?? d.id.trim())
            .where((id) => id.isNotEmpty)
            .firstOrNull;

        if (nextHostUid != null) {
          await roomRef.update({
            'hostId': nextHostUid,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          await roomRef.update({
            'status': 'finished',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    }

    // Now safe to delete our membership and location.
    await Future.wait([
      memberRef.delete().catchError((_) {}),
      locationRef.delete().catchError((_) {}),
    ]);
  }

  Future<void> updateMyLocation(String roomId, double lat, double lng) async {
    final uid = _uid;
    final ref = _rooms.doc(roomId).collection('locations').doc(uid);
    await ref.set({
      'lat': lat,
      'lng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Co-op check-in: awards XP and marks the venue as visited for all members
  /// except the current user (who is handled locally via gameProvider).
  /// Also writes a room-level visit record so every member's screen updates.
  Future<void> awardCoopCheckIn({
    required String roomId,
    required String mapId,
    required String venueId,
    required int xpValue,
    required List<String> memberUids,
  }) async {
    final currentUid = _uid;
    final batch = _firestore.batch();

    // Room-level visit — all members' screens observe this.
    batch.set(
      _rooms.doc(roomId).collection('visits').doc(venueId),
      {
        'venueId': venueId,
        'visitedBy': currentUid,
        'xpValue': xpValue,
        'visitedAt': FieldValue.serverTimestamp(),
      },
    );

    for (final uid in memberUids) {
      if (uid == currentUid) continue;

      batch.update(_firestore.collection('users').doc(uid), {
        'xp': FieldValue.increment(xpValue),
        'weeklyXP': FieldValue.increment(xpValue),
        'weeklyXPUpdatedAt': FieldValue.serverTimestamp(),
      });

      batch.set(
        _firestore.collection('userMapStates').doc(uid),
        {
          'mapStates': {
            mapId: {
              'visitedPoiIds': FieldValue.arrayUnion([venueId]),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          },
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  /// Streams the set of venueIds visited by any team member.
  Stream<Set<String>> listenRoomVisits(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('visits')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  /// Streams new check-in events (venue + xpValue) for showing XP animation.
  Stream<Map<String, dynamic>> listenRoomCheckInEvents(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('visits')
        .snapshots()
        .expand((snap) => snap.docChanges
            .where((c) => c.type == DocumentChangeType.added)
            .map((c) => <String, dynamic>{'id': c.doc.id, ...c.doc.data()!}));
  }

  /// Merges the caller's newly revealed fog cells into the shared room fog.
  Future<void> updateSharedFog(String roomId, List<String> newCellIds) async {
    if (newCellIds.isEmpty) return;
    await _rooms.doc(roomId).collection('shared').doc('fog').set(
      {'cells': FieldValue.arrayUnion(newCellIds)},
      SetOptions(merge: true),
    );
  }

  /// Streams the union of all teammates' revealed fog cells.
  Stream<List<String>> listenSharedFog(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('shared')
        .doc('fog')
        .snapshots()
        .map((snap) {
      final raw = snap.data()?['cells'];
      if (raw is! List) return const <String>[];
      return raw.map((e) => e.toString()).toList();
    });
  }

  Stream<List<Invite>> listenPendingInvites() {
    final uid = _uid;
    return _invites
        .where('toUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) {
          final invites = snapshot.docs.map(Invite.fromDoc).toList();
          invites.sort((a, b) {
            final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
            return bTime.compareTo(aTime);
          });
          return invites;
        });
  }

  Stream<int> listenPendingInvitesCountFor(String uid) {
    final normalizedUid = uid.trim();
    if (normalizedUid.isEmpty) {
      return Stream.value(0);
    }

    return _invites
        .where('toUserId', isEqualTo: normalizedUid)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  Stream<List<FriendRef>> listenMyFriends() {
    final uid = _uid;
    return _users
        .doc(uid)
        .collection('friends')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(FriendRef.fromDoc).toList());
  }

  Future<String> fetchRoomName(String roomId) async {
    final snap = await _rooms.doc(roomId).get();
    return (snap.data()?['roomName'] as String?)?.trim() ?? roomId;
  }

  Future<String> fetchUsername(String uid) async {
    return _resolveUsername(uid);
  }

  Future<String> _resolveUsername(String uid) async {
    final userDoc = await _users.doc(uid).get(
      const GetOptions(source: Source.serverAndCache),
    );
    final name = (userDoc.data()?['name'] as String?)?.trim() ?? '';
    final surname = (userDoc.data()?['surname'] as String?)?.trim() ?? '';
    final fullName = '$name $surname'.trim();
    if (fullName.isNotEmpty) {
      return fullName;
    }

    final username = (userDoc.data()?['username'] as String?)?.trim();
    if (username != null && username.isNotEmpty) {
      return username;
    }

    final userEmail = (userDoc.data()?['email'] as String?)?.trim();
    if (userEmail != null && userEmail.contains('@')) {
      return userEmail.split('@').first;
    }

    final email =
        uid == _auth.currentUser?.uid ? _auth.currentUser?.email?.trim() : null;
    if (email != null && email.contains('@')) {
      return email.split('@').first;
    }

    return uid;
  }
}

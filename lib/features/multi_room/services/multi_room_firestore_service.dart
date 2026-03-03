import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

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

  Future<String> createRoom(String roomName, String cityId) async {
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

  Stream<Room?> listenRoom(String roomId) {
    return _rooms.doc(roomId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Room.fromDoc(doc);
    });
  }

  Stream<List<Member>> listenMembers(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('members')
        .orderBy('joinedAt')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Member.fromDoc).toList());
  }

  Stream<List<LiveLocation>> listenLocations(String roomId) {
    return _rooms
        .doc(roomId)
        .collection('locations')
        .snapshots()
        .map((snapshot) => snapshot.docs.map(LiveLocation.fromDoc).toList());
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
        throw FirebaseException(
          plugin: 'multi_room_firestore_service',
          code: 'invite-already-exists',
          message: 'Bu kullanici icin zaten bir davet olusturulmus.',
        );
      }

      tx.set(inviteRef, {
        'roomId': roomId,
        'fromUserId': fromUserId,
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
    await _firestore.runTransaction((tx) async {
      final roomSnap = await tx.get(roomRef);
      if (roomSnap.exists) {
        final room = Room.fromDoc(roomSnap);
        if (room.hostId == uid && !room.isFinished) {
          tx.update(roomRef, {
            'status': 'finished',
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
      tx.delete(memberRef);
      tx.delete(locationRef);
    });
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

  Stream<List<Invite>> listenPendingInvites() {
    final uid = _uid;
    return _invites
        .where('toUserId', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(Invite.fromDoc).toList());
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
    final userDoc = await _users.doc(uid).get();
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

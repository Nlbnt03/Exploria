import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AppUserSummary {
  const AppUserSummary({
    required this.uid,
    required this.name,
    required this.surname,
    required this.username,
    required this.email,
    required this.photoUrl,
  });

  final String uid;
  final String name;
  final String surname;
  final String username;
  final String email;
  final String photoUrl;

  String get fullName => '$name $surname'.trim();

  factory AppUserSummary.fromUserDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? <String, dynamic>{};
    return AppUserSummary(
      uid: doc.id,
      name: (data['name'] as String?)?.trim() ?? '',
      surname: (data['surname'] as String?)?.trim() ?? '',
      username: (data['username'] as String?)?.trim() ?? '',
      email: (data['email'] as String?)?.trim() ?? '',
      photoUrl: (data['photoUrl'] as String?)?.trim() ?? '',
    );
  }

  factory AppUserSummary.fromFriendDoc(
    String friendUid,
    Map<String, dynamic> data,
  ) {
    return AppUserSummary(
      uid:
          (data['friendUid'] as String?)?.trim().isNotEmpty == true
              ? (data['friendUid'] as String).trim()
              : friendUid,
      name: (data['name'] as String?)?.trim() ?? '',
      surname: (data['surname'] as String?)?.trim() ?? '',
      username: (data['username'] as String?)?.trim() ?? '',
      email: (data['email'] as String?)?.trim() ?? '',
      photoUrl: (data['photoUrl'] as String?)?.trim() ?? '',
    );
  }
}

class FriendRequestView {
  const FriendRequestView({
    required this.requestId,
    required this.fromUid,
    required this.toUid,
    required this.status,
    required this.createdAt,
    required this.fromUser,
  });

  final String requestId;
  final String fromUid;
  final String toUid;
  final String status;
  final DateTime? createdAt;
  final AppUserSummary fromUser;
}

class FriendsService {
  FriendsService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _friendRequests =>
      _firestore.collection('friendRequests');
  CollectionReference<Map<String, dynamic>> get _multiInvites =>
      _firestore.collection('multiInvites');

  CollectionReference<Map<String, dynamic>> _friendsOf(String uid) =>
      _users.doc(uid).collection('friends');

  Future<List<AppUserSummary>> searchUsersByUsername({
    required String query,
    required String currentUid,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) {
      return const <AppUserSummary>[];
    }

    final snapshot =
        await _users
            .where('usernameLower', isGreaterThanOrEqualTo: normalized)
            .where('usernameLower', isLessThanOrEqualTo: '$normalized\uf8ff')
            .limit(15)
            .get();

    return snapshot.docs
        .where((doc) => doc.id != currentUid)
        .where((doc) => (doc.data()['emailVerified'] as bool?) == true)
        .map(AppUserSummary.fromUserDoc)
        .toList();
  }

  Stream<List<AppUserSummary>> watchFriends(String uid) {
    if (uid.trim().isEmpty) {
      return Stream.value(const <AppUserSummary>[]);
    }

    return _friendsOf(uid).orderBy('since', descending: true).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((doc) => AppUserSummary.fromFriendDoc(doc.id, doc.data()))
          .toList();
    });
  }

  Stream<Set<String>> watchFriendUids(String uid) {
    if (uid.trim().isEmpty) {
      return Stream.value(<String>{});
    }

    return _friendsOf(uid).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => doc.id).toSet();
    });
  }

  Stream<List<FriendRequestView>> watchIncomingRequests(String uid) {
    if (uid.trim().isEmpty) {
      return Stream.value(const <FriendRequestView>[]);
    }

    return _friendRequests.where('toUid', isEqualTo: uid).snapshots().asyncMap((
      snapshot,
    ) async {
      final views = <FriendRequestView>[];
      for (final requestDoc in snapshot.docs) {
        final requestData = requestDoc.data();
        final status = (requestData['status'] as String?)?.trim() ?? '';
        if (status != 'pending') {
          continue;
        }

        final fromUid = (requestData['fromUid'] as String?)?.trim() ?? '';
        if (fromUid.isEmpty) {
          continue;
        }

        final fromUserDoc = await _users.doc(fromUid).get();
        if (!fromUserDoc.exists) {
          continue;
        }

        final createdAt = requestData['createdAt'];
        views.add(
          FriendRequestView(
            requestId: requestDoc.id,
            fromUid: fromUid,
            toUid: (requestData['toUid'] as String?)?.trim() ?? '',
            status: status,
            createdAt:
                createdAt is Timestamp ? createdAt.toDate() : DateTime.now(),
            fromUser: AppUserSummary.fromUserDoc(fromUserDoc),
          ),
        );
      }
      views.sort((a, b) {
        final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      return views;
    });
  }

  Stream<int> watchIncomingRequestCount(String uid) {
    if (uid.trim().isEmpty) {
      return Stream.value(0);
    }

    return _friendRequests
        .where('toUid', isEqualTo: uid)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.where((doc) {
                final status = (doc.data()['status'] as String?)?.trim();
                return status == 'pending';
              }).length,
        );
  }

  Stream<Set<String>> watchOutgoingPendingRequestToUids(String uid) {
    if (uid.trim().isEmpty) {
      return Stream.value(<String>{});
    }

    return _friendRequests.where('fromUid', isEqualTo: uid).snapshots().map((
      snapshot,
    ) {
      final pendingToUids = <String>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final status = (data['status'] as String?)?.trim();
        final toUid = (data['toUid'] as String?)?.trim();
        if (status == 'pending' && toUid != null && toUid.isNotEmpty) {
          pendingToUids.add(toUid);
        }
      }
      return pendingToUids;
    });
  }

  Future<void> sendFriendRequest({
    required String fromUid,
    required String toUid,
  }) async {
    await _refreshAuthTokenBeforeWrite();

    if (fromUid == toUid) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'self-request',
        message: 'Kendine arkadaslik istegi gonderemezsin.',
      );
    }

    final requestRef = _friendRequests.doc('${fromUid}_$toUid');
    final reverseRef = _friendRequests.doc('${toUid}_$fromUid');
    final fromUserRef = _users.doc(fromUid);
    final toUserRef = _users.doc(toUid);
    final fromFriendRef = _friendsOf(fromUid).doc(toUid);
    final toFriendRef = _friendsOf(toUid).doc(fromUid);

    await _firestore.runTransaction((tx) async {
      final fromUser = await tx.get(fromUserRef);
      final toUser = await tx.get(toUserRef);
      final request = await tx.get(requestRef);
      final reverse = await tx.get(reverseRef);
      final fromFriend = await tx.get(fromFriendRef);
      final toFriend = await tx.get(toFriendRef);

      if (!fromUser.exists || !toUser.exists) {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'user-not-found',
          message: 'Kullanici bulunamadi.',
        );
      }

      if (fromFriend.exists || toFriend.exists) {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'already-friends',
          message: 'Bu kullanici zaten arkadas listende.',
        );
      }

      final requestStatus = (request.data()?['status'] as String?)?.trim();
      if (request.exists && requestStatus == 'pending') {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'request-already-sent',
          message: 'Bu kullaniciya zaten istek gonderdin.',
        );
      }

      final reverseStatus = (reverse.data()?['status'] as String?)?.trim();
      if (reverse.exists && reverseStatus == 'pending') {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'incoming-request-exists',
          message: 'Bu kullanicidan bekleyen bir istek var.',
        );
      }

      final fromData = fromUser.data() ?? <String, dynamic>{};
      final toData = toUser.data() ?? <String, dynamic>{};
      tx.set(requestRef, {
        'fromUid': fromUid,
        'toUid': toUid,
        'fromUsername': (fromData['username'] as String?)?.trim() ?? '',
        'toUsername': (toData['username'] as String?)?.trim() ?? '',
        'pairKey': _pairKey(fromUid, toUid),
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> acceptFriendRequest({
    required String requestId,
    required String currentUid,
  }) async {
    await _refreshAuthTokenBeforeWrite();

    final requestRef = _friendRequests.doc(requestId);

    await _firestore.runTransaction((tx) async {
      final requestSnap = await tx.get(requestRef);
      if (!requestSnap.exists) {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'request-not-found',
          message: 'Arkadaslik istegi bulunamadi.',
        );
      }

      final requestData = requestSnap.data() ?? <String, dynamic>{};
      final fromUid = (requestData['fromUid'] as String?)?.trim() ?? '';
      final toUid = (requestData['toUid'] as String?)?.trim() ?? '';
      final status = (requestData['status'] as String?)?.trim() ?? '';

      if (toUid != currentUid || fromUid.isEmpty) {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'invalid-request-owner',
          message: 'Bu istek bu kullaniciya ait degil.',
        );
      }
      if (status != 'pending') {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'request-closed',
          message: 'Bu istek zaten sonuclandirilmis.',
        );
      }

      final fromUserRef = _users.doc(fromUid);
      final toUserRef = _users.doc(currentUid);
      final fromFriendRef = _friendsOf(fromUid).doc(currentUid);
      final toFriendRef = _friendsOf(currentUid).doc(fromUid);

      final fromUserSnap = await tx.get(fromUserRef);
      final toUserSnap = await tx.get(toUserRef);
      final fromFriendSnap = await tx.get(fromFriendRef);
      final toFriendSnap = await tx.get(toFriendRef);

      if (!fromUserSnap.exists || !toUserSnap.exists) {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'user-not-found',
          message: 'Arkadas bilgisi okunamadi.',
        );
      }

      final fromData = fromUserSnap.data() ?? <String, dynamic>{};
      final toData = toUserSnap.data() ?? <String, dynamic>{};

      if (!fromFriendSnap.exists) {
        tx.set(fromFriendRef, _friendEdgeData(currentUid, toData));
      }
      if (!toFriendSnap.exists) {
        tx.set(toFriendRef, _friendEdgeData(fromUid, fromData));
      }

      if (!fromFriendSnap.exists) {
        tx.set(fromUserRef, {
          'friends': FieldValue.arrayUnion([currentUid]),
          'friendsCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      if (!toFriendSnap.exists) {
        tx.set(toUserRef, {
          'friends': FieldValue.arrayUnion([fromUid]),
          'friendsCount': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      tx.set(requestRef, {
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
        'respondedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> rejectFriendRequest({
    required String requestId,
    required String currentUid,
  }) async {
    await _refreshAuthTokenBeforeWrite();

    final requestRef = _friendRequests.doc(requestId);

    await _firestore.runTransaction((tx) async {
      final requestSnap = await tx.get(requestRef);
      if (!requestSnap.exists) {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'request-not-found',
          message: 'Arkadaslik istegi bulunamadi.',
        );
      }

      final data = requestSnap.data() ?? <String, dynamic>{};
      final toUid = (data['toUid'] as String?)?.trim() ?? '';
      final status = (data['status'] as String?)?.trim() ?? '';
      if (toUid != currentUid) {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'invalid-request-owner',
          message: 'Bu istek bu kullaniciya ait degil.',
        );
      }
      if (status != 'pending') {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'request-closed',
          message: 'Bu istek zaten sonuclandirilmis.',
        );
      }

      tx.set(requestRef, {
        'status': 'rejected',
        'updatedAt': FieldValue.serverTimestamp(),
        'respondedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  Future<void> sendMultiInvite({
    required String fromUid,
    required String toUid,
    String city = 'istanbul',
  }) async {
    await _refreshAuthTokenBeforeWrite();

    if (fromUid == toUid) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'self-invite',
        message: 'Kendini multi moda davet edemezsin.',
      );
    }

    final isFriend = await _friendsOf(fromUid).doc(toUid).get();
    if (!isFriend.exists) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'not-friends',
        message: 'Sadece arkadaslarini multi moda davet edebilirsin.',
      );
    }

    final inviteRef = _multiInvites.doc('${fromUid}_$toUid');
    final inviteDoc = await inviteRef.get();
    if (inviteDoc.exists) {
      final status = (inviteDoc.data()?['status'] as String?)?.trim();
      if (status == 'pending') {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'invite-already-sent',
          message: 'Bu arkadasa zaten bekleyen bir davetin var.',
        );
      }
    }

    await inviteRef.set({
      'fromUid': fromUid,
      'toUid': toUid,
      'mode': 'multi',
      'city': city,
      'status': 'pending',
      'updatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeFriend({
    required String currentUid,
    required String friendUid,
  }) async {
    await _refreshAuthTokenBeforeWrite();

    if (currentUid.trim().isEmpty || friendUid.trim().isEmpty) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'invalid-uid',
        message: 'Geçersiz kullanıcı kimliği.',
      );
    }
    if (currentUid == friendUid) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'self-remove',
        message: 'Kendini arkadaş listesinden çıkaramazsın.',
      );
    }

    final currentUserRef = _users.doc(currentUid);
    final myFriendRef = _friendsOf(currentUid).doc(friendUid);
    final friendSideRef = _friendsOf(friendUid).doc(currentUid);

    await _firestore.runTransaction((tx) async {
      final currentUserSnap = await tx.get(currentUserRef);
      final myFriendSnap = await tx.get(myFriendRef);
      final friendSideSnap = await tx.get(friendSideRef);

      if (!myFriendSnap.exists && !friendSideSnap.exists) {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'not-friends',
          message: 'Bu kullanıcı zaten arkadaş listende değil.',
        );
      }

      if (myFriendSnap.exists) {
        tx.delete(myFriendRef);
      }
      if (friendSideSnap.exists) {
        tx.delete(friendSideRef);
      }

      final userData = currentUserSnap.data() ?? <String, dynamic>{};
      final currentCount = (userData['friendsCount'] as num?)?.toInt() ?? 0;
      final updatedCount = currentCount > 0 ? currentCount - 1 : 0;

      tx.set(currentUserRef, {
        'friends': FieldValue.arrayRemove([friendUid]),
        'friendsCount': updatedCount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  String _pairKey(String uidA, String uidB) {
    final values = <String>[uidA, uidB]..sort();
    return '${values.first}_${values.last}';
  }

  Map<String, dynamic> _friendEdgeData(
    String friendUid,
    Map<String, dynamic> userData,
  ) {
    return <String, dynamic>{
      'friendUid': friendUid,
      'username': (userData['username'] as String?)?.trim() ?? '',
      'name': (userData['name'] as String?)?.trim() ?? '',
      'surname': (userData['surname'] as String?)?.trim() ?? '',
      'email': (userData['email'] as String?)?.trim() ?? '',
      'photoUrl': (userData['photoUrl'] as String?)?.trim() ?? '',
      'since': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _refreshAuthTokenBeforeWrite() async {
    await FirebaseAuth.instance.currentUser?.getIdTokenResult(true);
  }
}

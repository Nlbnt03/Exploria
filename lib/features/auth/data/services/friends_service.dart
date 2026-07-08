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

class BlockedUserSummary {
  const BlockedUserSummary({
    required this.uid,
    required this.name,
    required this.surname,
    required this.username,
    required this.photoUrl,
    required this.createdAt,
  });

  final String uid;
  final String name;
  final String surname;
  final String username;
  final String photoUrl;
  final DateTime? createdAt;

  String get fullName => '$name $surname'.trim();

  factory BlockedUserSummary.fromBlockedDoc(
    String blockedUid,
    Map<String, dynamic> data,
  ) {
    final createdAt = data['createdAt'];
    return BlockedUserSummary(
      uid:
          (data['blockedUid'] as String?)?.trim().isNotEmpty == true
              ? (data['blockedUid'] as String).trim()
              : blockedUid,
      name: (data['name'] as String?)?.trim() ?? '',
      surname: (data['surname'] as String?)?.trim() ?? '',
      username: (data['username'] as String?)?.trim() ?? '',
      photoUrl: (data['photoUrl'] as String?)?.trim() ?? '',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
    );
  }
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
  CollectionReference<Map<String, dynamic>> get _userReports =>
      _firestore.collection('userReports');

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

  Stream<List<BlockedUserSummary>> watchBlockedUsers(String uid) {
    if (uid.trim().isEmpty) {
      return Stream.value(const <BlockedUserSummary>[]);
    }

    return _users
        .doc(uid)
        .collection('blockedUsers')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map(
                (doc) => BlockedUserSummary.fromBlockedDoc(doc.id, doc.data()),
              )
              .toList();
        });
  }

  Stream<List<FriendRequestView>> watchIncomingRequests(String uid) {
    if (uid.trim().isEmpty) {
      return Stream.value(const <FriendRequestView>[]);
    }

    return _friendRequests.where('toUid', isEqualTo: uid).snapshots().asyncMap((
      snapshot,
    ) async {
      final pendingRequests = <Map<String, dynamic>>[];
      final fromUids = <String>[];

      for (final requestDoc in snapshot.docs) {
        final requestData = requestDoc.data();
        final status = (requestData['status'] as String?)?.trim() ?? '';
        if (status != 'pending') continue;

        final fromUid = (requestData['fromUid'] as String?)?.trim() ?? '';
        if (fromUid.isEmpty) continue;

        pendingRequests.add({
          ...requestData,
          '_docId': requestDoc.id,
          '_fromUid': fromUid,
        });
        fromUids.add(fromUid);
      }

      final userDocs = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      if (fromUids.isNotEmpty) {
        final results =
            await Future.wait<DocumentSnapshot<Map<String, dynamic>>>(
              fromUids.map((uid) => _users.doc(uid).get()),
            );
        for (var i = 0; i < fromUids.length; i++) {
          userDocs[fromUids[i]] = results[i];
        }
      }

      final views = <FriendRequestView>[];
      for (final req in pendingRequests) {
        final fromUid = req['_fromUid'] as String;
        final fromUserDoc = userDocs[fromUid];
        if (fromUserDoc == null || !fromUserDoc.exists) continue;

        final createdAt = req['createdAt'];
        views.add(
          FriendRequestView(
            requestId: req['_docId'] as String,
            fromUid: fromUid,
            toUid: (req['toUid'] as String?)?.trim() ?? '',
            status: (req['status'] as String?)?.trim() ?? '',
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
      final fromBlockedTo = await tx.get(
        _users.doc(fromUid).collection('blockedUsers').doc(toUid),
      );
      final toBlockedFrom = await tx.get(
        _users.doc(toUid).collection('blockedUsers').doc(fromUid),
      );

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

      if (fromBlockedTo.exists || toBlockedFrom.exists) {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'blocked-user',
          message: 'Bu kullanıcıya arkadaşlık isteği gönderilemez.',
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

  /// Cancel an outgoing friend request (sender withdraws).
  Future<void> cancelFriendRequest({
    required String fromUid,
    required String toUid,
  }) async {
    await _refreshAuthTokenBeforeWrite();

    final requestRef = _friendRequests.doc('${fromUid}_$toUid');

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
      final senderUid = (data['fromUid'] as String?)?.trim() ?? '';
      final status = (data['status'] as String?)?.trim() ?? '';
      if (senderUid != fromUid) {
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
        'status': 'cancelled',
        'updatedAt': FieldValue.serverTimestamp(),
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
    final friendUserRef = _users.doc(friendUid);
    final myFriendRef = _friendsOf(currentUid).doc(friendUid);
    final friendSideRef = _friendsOf(friendUid).doc(currentUid);
    // Arkadaşlığın kurulduğu yöne göre iki olası istek dokümanı da olabilir.
    final requestRefA = _friendRequests.doc('${currentUid}_$friendUid');
    final requestRefB = _friendRequests.doc('${friendUid}_$currentUid');

    await _firestore.runTransaction((tx) async {
      final currentUserSnap = await tx.get(currentUserRef);
      final friendUserSnap = await tx.get(friendUserRef);
      final myFriendSnap = await tx.get(myFriendRef);
      final friendSideSnap = await tx.get(friendSideRef);
      final requestSnapA = await tx.get(requestRefA);
      final requestSnapB = await tx.get(requestRefB);

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

      final currentUserData = currentUserSnap.data() ?? <String, dynamic>{};
      final currentCount =
          (currentUserData['friendsCount'] as num?)?.toInt() ?? 0;
      tx.set(currentUserRef, {
        'friends': FieldValue.arrayRemove([friendUid]),
        'friendsCount': currentCount > 0 ? currentCount - 1 : 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (friendUserSnap.exists) {
        final friendUserData = friendUserSnap.data() ?? <String, dynamic>{};
        final friendCount =
            (friendUserData['friendsCount'] as num?)?.toInt() ?? 0;
        tx.set(friendUserRef, {
          'friends': FieldValue.arrayRemove([currentUid]),
          'friendsCount': friendCount > 0 ? friendCount - 1 : 0,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // Kabul edilmiş eski istek dokümanı sıfırlanmazsa, taraflardan biri
      // (özellikle orijinal gönderen) arkadaşlıktan çıkarıldıktan sonra
      // aynı kişiye tekrar istek gönderemez. 'cancelled' durumuna çekilerek
      // yeniden istek gönderilebilir hale getirilir.
      for (final requestSnap in [requestSnapA, requestSnapB]) {
        if (requestSnap.exists && requestSnap.data()?['status'] == 'accepted') {
          tx.set(requestSnap.reference, {
            'status': 'cancelled',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    });
  }

  Future<void> reportUser({
    required String reporterUid,
    required AppUserSummary reportedUser,
    required String reason,
  }) async {
    await _refreshAuthTokenBeforeWrite();

    final normalizedReason = reason.trim();
    if (reporterUid.trim().isEmpty || reportedUser.uid.trim().isEmpty) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'invalid-uid',
        message: 'Geçersiz kullanıcı kimliği.',
      );
    }
    if (reporterUid == reportedUser.uid) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'self-report',
        message: 'Kendini bildiremezsin.',
      );
    }
    if (normalizedReason.isEmpty) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'invalid-report-reason',
        message: 'Bildirim nedeni seçmelisin.',
      );
    }

    await _userReports.add({
      'reporterUid': reporterUid,
      'reportedUid': reportedUser.uid,
      'reportedUsername': reportedUser.username,
      'reportedName': reportedUser.name,
      'reportedSurname': reportedUser.surname,
      'reason': normalizedReason,
      'context': 'social_friend_menu',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> blockUser({
    required String currentUid,
    required AppUserSummary blockedUser,
  }) async {
    await _refreshAuthTokenBeforeWrite();

    final blockedUid = blockedUser.uid.trim();
    if (currentUid.trim().isEmpty || blockedUid.isEmpty) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'invalid-uid',
        message: 'Geçersiz kullanıcı kimliği.',
      );
    }
    if (currentUid == blockedUid) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'self-block',
        message: 'Kendini engelleyemezsin.',
      );
    }

    final currentUserRef = _users.doc(currentUid);
    final blockedUserRef = _users.doc(blockedUid);
    final myFriendRef = _friendsOf(currentUid).doc(blockedUid);
    final blockedSideRef = _friendsOf(blockedUid).doc(currentUid);
    final myBlockRef = _users
        .doc(currentUid)
        .collection('blockedUsers')
        .doc(blockedUid);
    final requestRefA = _friendRequests.doc('${currentUid}_$blockedUid');
    final requestRefB = _friendRequests.doc('${blockedUid}_$currentUid');

    await _firestore.runTransaction((tx) async {
      final currentUserSnap = await tx.get(currentUserRef);
      final blockedUserSnap = await tx.get(blockedUserRef);
      final myFriendSnap = await tx.get(myFriendRef);
      final blockedSideSnap = await tx.get(blockedSideRef);
      final requestSnapA = await tx.get(requestRefA);
      final requestSnapB = await tx.get(requestRefB);

      if (!currentUserSnap.exists || !blockedUserSnap.exists) {
        throw FirebaseException(
          plugin: 'friends_service',
          code: 'user-not-found',
          message: 'Kullanıcı bulunamadı.',
        );
      }

      tx.set(myBlockRef, {
        'blockedUid': blockedUid,
        'username': blockedUser.username,
        'name': blockedUser.name,
        'surname': blockedUser.surname,
        'photoUrl': blockedUser.photoUrl,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (myFriendSnap.exists) {
        tx.delete(myFriendRef);
      }
      if (blockedSideSnap.exists) {
        tx.delete(blockedSideRef);
      }

      final currentUserData = currentUserSnap.data() ?? <String, dynamic>{};
      final currentCount =
          (currentUserData['friendsCount'] as num?)?.toInt() ?? 0;
      tx.set(currentUserRef, {
        'friends': FieldValue.arrayRemove([blockedUid]),
        'friendsCount':
            myFriendSnap.exists && currentCount > 0
                ? currentCount - 1
                : currentCount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final blockedUserData = blockedUserSnap.data() ?? <String, dynamic>{};
      final blockedCount =
          (blockedUserData['friendsCount'] as num?)?.toInt() ?? 0;
      tx.set(blockedUserRef, {
        'friends': FieldValue.arrayRemove([currentUid]),
        'friendsCount':
            blockedSideSnap.exists && blockedCount > 0
                ? blockedCount - 1
                : blockedCount,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      for (final requestSnap in [requestSnapA, requestSnapB]) {
        final status = (requestSnap.data()?['status'] as String?)?.trim();
        if (requestSnap.exists &&
            (status == 'pending' || status == 'accepted')) {
          tx.set(requestSnap.reference, {
            'status': 'cancelled',
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
      }
    });
  }

  Future<void> unblockUser({
    required String currentUid,
    required String blockedUid,
  }) async {
    await _refreshAuthTokenBeforeWrite();

    if (currentUid.trim().isEmpty || blockedUid.trim().isEmpty) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'invalid-uid',
        message: 'Geçersiz kullanıcı kimliği.',
      );
    }
    if (currentUid == blockedUid) {
      throw FirebaseException(
        plugin: 'friends_service',
        code: 'self-unblock',
        message: 'Kendin için engel kaydı kaldıramazsın.',
      );
    }

    await _users
        .doc(currentUid)
        .collection('blockedUsers')
        .doc(blockedUid)
        .delete();
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

import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreUserService {
  FirestoreUserService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9._-]{3,30}$');

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _usernames =>
      _firestore.collection('usernames');

  Future<Map<String, dynamic>> fetchUser(String uid) async {
    final doc = await _users.doc(uid).get();
    return doc.data() ?? <String, dynamic>{};
  }

  Future<void> upsertUser({
    required String uid,
    required String email,
    required String name,
    required String surname,
    required String username,
    required String role,
    required bool emailVerified,
  }) async {
    final cleanUsername = username.trim();
    final usernameLower = cleanUsername.toLowerCase();
    _validateUsername(
      cleanUsername: cleanUsername,
      usernameLower: usernameLower,
    );

    final ref = _users.doc(uid);
    final usernameRef = _usernames.doc(usernameLower);
    final createData = <String, dynamic>{
      'firebaseUid': uid,
      'email': email,
      'name': name,
      'surname': surname,
      'username': cleanUsername,
      'usernameLower': usernameLower,
      'role': role,
      'emailVerified': emailVerified,
      'photoUrl': '',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'friends': <String>[],
      'friendsCount': 0,
    };

    final updateData = <String, dynamic>{
      'firebaseUid': uid,
      'email': email,
      'name': name,
      'surname': surname,
      'username': cleanUsername,
      'usernameLower': usernameLower,
      'role': role,
      'emailVerified': emailVerified,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _firestore.runTransaction((tx) async {
      final userSnap = await tx.get(ref);
      final usernameSnap = await tx.get(usernameRef);
      final ownerUid = (usernameSnap.data()?['uid'] as String?)?.trim();

      if (ownerUid != null && ownerUid.isNotEmpty && ownerUid != uid) {
        throw FirebaseException(
          plugin: 'firestore_user_service',
          code: 'username-already-in-use',
          message: 'Bu kullanici adi zaten kullanimda.',
        );
      }

      final oldUsernameLower =
          (userSnap.data()?['usernameLower'] as String?)?.trim();
      if (oldUsernameLower != null &&
          oldUsernameLower.isNotEmpty &&
          oldUsernameLower != usernameLower) {
        final oldRef = _usernames.doc(oldUsernameLower);
        final oldSnap = await tx.get(oldRef);
        final oldOwner = (oldSnap.data()?['uid'] as String?)?.trim();
        if (oldOwner == uid) {
          tx.delete(oldRef);
        }
      }

      tx.set(usernameRef, {
        'uid': uid,
        'username': cleanUsername,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(
        ref,
        userSnap.exists ? updateData : createData,
        SetOptions(merge: true),
      );
    });
  }

  Future<void> updateEditableProfile({
    required String uid,
    required String name,
    required String surname,
    required String username,
  }) async {
    final cleanUsername = username.trim();
    final usernameLower = cleanUsername.toLowerCase();
    _validateUsername(
      cleanUsername: cleanUsername,
      usernameLower: usernameLower,
    );

    final userRef = _users.doc(uid);
    final usernameRef = _usernames.doc(usernameLower);

    await _firestore.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      if (!userSnap.exists) {
        throw FirebaseException(
          plugin: 'firestore_user_service',
          code: 'user-not-found',
          message: 'Kullanici bulunamadi.',
        );
      }

      final usernameSnap = await tx.get(usernameRef);
      final ownerUid = (usernameSnap.data()?['uid'] as String?)?.trim();
      if (ownerUid != null && ownerUid.isNotEmpty && ownerUid != uid) {
        throw FirebaseException(
          plugin: 'firestore_user_service',
          code: 'username-already-in-use',
          message: 'Bu kullanici adi zaten kullanimda.',
        );
      }

      final oldUsernameLower =
          (userSnap.data()?['usernameLower'] as String?)?.trim();
      if (oldUsernameLower != null &&
          oldUsernameLower.isNotEmpty &&
          oldUsernameLower != usernameLower) {
        final oldRef = _usernames.doc(oldUsernameLower);
        final oldSnap = await tx.get(oldRef);
        final oldOwner = (oldSnap.data()?['uid'] as String?)?.trim();
        if (oldOwner == uid) {
          tx.delete(oldRef);
        }
      }

      tx.set(usernameRef, {
        'uid': uid,
        'username': cleanUsername,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      tx.set(userRef, {
        'name': name,
        'surname': surname,
        'username': cleanUsername,
        'usernameLower': usernameLower,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  void _validateUsername({
    required String cleanUsername,
    required String usernameLower,
  }) {
    if (cleanUsername.length < 3) {
      throw FirebaseException(
        plugin: 'firestore_user_service',
        code: 'invalid-username',
        message: 'Kullanıcı adı en az 3 karakter olmalı.',
      );
    }
    if (!_usernamePattern.hasMatch(usernameLower)) {
      throw FirebaseException(
        plugin: 'firestore_user_service',
        code: 'invalid-username-format',
        message:
            'Kullanıcı adı sadece küçük harf, rakam, nokta, alt çizgi ve tire içerebilir.',
      );
    }
  }

  Future<void> deleteUser(String uid) async {
    final userRef = _users.doc(uid);
    final userDoc = await userRef.get();
    if (userDoc.exists) {
      final data = userDoc.data() ?? {};
      final usernameLower = (data['usernameLower'] as String?)?.trim();
      if (usernameLower != null && usernameLower.isNotEmpty) {
        await _usernames.doc(usernameLower).delete();
      }
      
      final friends = List<String>.from(data['friends'] ?? []);
      for (final friendUid in friends) {
        try {
          await _users.doc(friendUid).collection('friends').doc(uid).delete();
        } catch (_) {}
      }

      try {
        await _firestore.collection('leaderboard').doc(uid).delete();
      } catch (_) {}

      await userRef.delete();
    }
  }
}

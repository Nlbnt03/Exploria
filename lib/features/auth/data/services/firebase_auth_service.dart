import 'package:firebase_auth/firebase_auth.dart';

class FirebaseAuthService {
  FirebaseAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  Future<UserCredential> createUser({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  Future<User?> reloadCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    await user.reload();
    return _auth.currentUser;
  }

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    return user.getIdToken(forceRefresh);
  }

  Future<IdTokenResult?> getIdTokenResult({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) {
      return null;
    }
    return user.getIdTokenResult(forceRefresh);
  }

  Future<void> updateDisplayName(String fullName) async {
    await _auth.currentUser?.updateDisplayName(fullName);
  }

  Future<void> signOut() => _auth.signOut();

  String? get currentUid => _auth.currentUser?.uid;
}

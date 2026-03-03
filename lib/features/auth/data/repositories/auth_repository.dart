import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/exceptions/auth_flow_exception.dart';
import '../../domain/models/sign_up_profile.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_user_service.dart';
import '../services/pending_profile_store.dart';

enum SignInStatus { success, emailNotVerified }

class SignInResult {
  const SignInResult({required this.status, this.message});

  final SignInStatus status;
  final String? message;
}

class AuthRepository {
  AuthRepository({
    FirebaseAuthService? firebaseAuthService,
    FirestoreUserService? firestoreUserService,
    PendingProfileStore? pendingProfileStore,
  }) : _firebaseAuthService = firebaseAuthService ?? FirebaseAuthService(),
       _firestoreUserService = firestoreUserService ?? FirestoreUserService(),
       _pendingProfileStore =
           pendingProfileStore ?? const PendingProfileStore();

  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9._-]{3,30}$');

  final FirebaseAuthService _firebaseAuthService;
  final FirestoreUserService _firestoreUserService;
  final PendingProfileStore _pendingProfileStore;

  Future<void> signUp({
    required String name,
    required String surname,
    required String username,
    required String email,
    required String password,
  }) async {
    final cleanUsername = username.trim();
    if (!_usernamePattern.hasMatch(cleanUsername.toLowerCase())) {
      throw const AuthFlowException(
        'Kullanıcı adı formatı geçersiz. Sadece küçük harf, rakam, nokta, alt çizgi ve tire kullanabilirsin.',
      );
    }

    try {
      final credential = await _firebaseAuthService.createUser(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw const AuthFlowException('Kullanıcı oluşturulamadı.');
      }

      await _firebaseAuthService.updateDisplayName('$name $surname');
      await _pendingProfileStore.save(
        user.uid,
        SignUpProfile(
          name: name,
          surname: surname,
          username: cleanUsername,
          email: email,
        ),
      );
      await _firebaseAuthService.sendEmailVerification();
      await _firebaseAuthService.signOut();
    } on FirebaseAuthException catch (e) {
      throw AuthFlowException(_mapFirebaseSignUpError(e));
    } catch (e) {
      throw AuthFlowException('Kayıt işlemi başarısız: $e');
    }
  }

  Future<SignInResult> signInAndSync({
    required String email,
    required String password,
  }) async {
    try {
      await _firebaseAuthService.signIn(email: email, password: password);
      final user = await _firebaseAuthService.reloadCurrentUser();

      if (user == null) {
        throw const AuthFlowException('Kullanıcı oturumu açılamadı.');
      }

      if (!user.emailVerified) {
        await _firebaseAuthService.sendEmailVerification();
        await _firebaseAuthService.signOut();
        return const SignInResult(
          status: SignInStatus.emailNotVerified,
          message:
              'E-posta doğrulanmamış. Yeni doğrulama e-postası gönderildi.',
        );
      }

      // Firestore kurallarinda request.auth.token.email_verified kontrolu varsa
      // taze token alinmasi gecikmeli claim senkronizasyon hatalarini azaltir.
      final syncedUser = await _waitForVerifiedTokenClaim();

      final pendingProfile = await _pendingProfileStore.load(user.uid);
      final existingProfileData = await _fetchUserWithRetry(syncedUser.uid);
      final fallbackProfile = _fallbackProfileFromUser(user);
      final profile =
          pendingProfile ??
          _profileFromExistingData(
            data: existingProfileData,
            fallback: fallbackProfile,
          );

      await _upsertUserWithRetry(user: user, profile: profile);
      await _pendingProfileStore.clear(user.uid);

      return const SignInResult(status: SignInStatus.success);
    } on FirebaseAuthException catch (e) {
      throw AuthFlowException(_mapFirebaseSignInError(e));
    } on FirebaseException catch (e) {
      throw AuthFlowException(_mapFirestoreError(e));
    } on AuthFlowException {
      await _firebaseAuthService.signOut();
      rethrow;
    } catch (e) {
      await _firebaseAuthService.signOut();
      throw AuthFlowException('Giriş sonrası doğrulama adımı başarısız: $e');
    }
  }

  String _mapFirebaseSignUpError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'Bu e-posta adresi zaten kullanılıyor.';
      case 'invalid-email':
        return 'Geçersiz e-posta adresi.';
      case 'weak-password':
        return 'Şifre en az 6 karakter olmalı.';
      case 'operation-not-allowed':
        return 'Firebase Console > Authentication > Sign-in method altında Email/Password aktif değil.';
      case 'network-request-failed':
        return 'Ağ bağlantısı hatası. İnternet erişiminizi kontrol edin.';
      default:
        return 'Kayıt işlemi başarısız: ${e.message ?? e.code}';
    }
  }

  String _mapFirebaseSignInError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Geçersiz e-posta adresi.';
      case 'user-not-found':
      case 'invalid-credential':
      case 'wrong-password':
        return 'E-posta veya şifre hatalı.';
      case 'too-many-requests':
        return 'Çok fazla deneme yaptınız. Lütfen daha sonra tekrar deneyin.';
      case 'operation-not-allowed':
        return 'Firebase Console > Authentication > Sign-in method altında Email/Password aktif değil.';
      case 'network-request-failed':
        return 'Ağ bağlantısı hatası. İnternet erişiminizi kontrol edin.';
      default:
        return 'Giriş işlemi başarısız: ${e.message ?? e.code}';
    }
  }

  String _mapFirestoreError(FirebaseException e) {
    switch (e.code) {
      case 'username-already-in-use':
        return 'Bu kullanıcı adı zaten kullanımda. Profilinde farklı bir kullanıcı adı seçmelisin.';
      case 'invalid-username':
        return 'Kullanıcı adı geçersiz. En az 3 karakter olmalı.';
      case 'invalid-username-format':
        return 'Kullanıcı adı formatı geçersiz. Sadece küçük harf, rakam, nokta, alt çizgi ve tire kullanabilirsin.';
      case 'permission-denied':
        return 'Firestore yazma yetkisi yok. E-posta doğrulamasını ve güvenlik kurallarını kontrol edin.';
      case 'unavailable':
        return 'Firestore şu anda ulaşılamıyor. Bağlantını kontrol et.';
      case 'failed-precondition':
        return 'Firestore henüz etkin değil veya indeks/konfigürasyon eksik.';
      case 'not-found':
        return 'Beklenen Firestore kaynağı bulunamadı.';
      default:
        return 'Firestore hatası (${e.code}): ${e.message ?? ''}'.trim();
    }
  }

  Future<void> _upsertUserWithRetry({
    required User user,
    required SignUpProfile profile,
  }) async {
    User current = user;
    FirebaseException? lastPermissionDenied;

    for (var attempt = 0; attempt < 5; attempt++) {
      try {
        await _firestoreUserService.upsertUser(
          uid: current.uid,
          email: current.email ?? profile.email,
          name: profile.name,
          surname: profile.surname,
          username: profile.username,
          role: 'USER',
          emailVerified: true,
        );
        return;
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          rethrow;
        }
        lastPermissionDenied = e;
      }

      await Future<void>.delayed(Duration(seconds: attempt + 2));
      current = await _waitForVerifiedTokenClaim();
    }

    if (lastPermissionDenied != null) {
      throw lastPermissionDenied;
    }
  }

  Future<Map<String, dynamic>> _fetchUserWithRetry(String uid) async {
    FirebaseException? lastPermissionDenied;

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _firestoreUserService.fetchUser(uid);
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') {
          rethrow;
        }
        lastPermissionDenied = e;
      }

      await Future<void>.delayed(Duration(seconds: attempt + 1));
      await _waitForVerifiedTokenClaim();
    }

    if (lastPermissionDenied != null) {
      throw lastPermissionDenied;
    }
    return <String, dynamic>{};
  }

  Future<User> _waitForVerifiedTokenClaim() async {
    for (var attempt = 0; attempt < 6; attempt++) {
      final reloaded = await _firebaseAuthService.reloadCurrentUser();
      if (reloaded == null || !reloaded.emailVerified) {
        throw const AuthFlowException(
          'E-posta doğrulama bilgisi henüz senkronize olmadı. Lütfen birkaç saniye sonra tekrar deneyin.',
        );
      }

      final tokenResult = await _firebaseAuthService.getIdTokenResult(
        forceRefresh: true,
      );
      final emailVerifiedClaim = tokenResult?.claims?['email_verified'] == true;
      if (emailVerifiedClaim) {
        return reloaded;
      }

      await Future<void>.delayed(Duration(seconds: attempt + 1));
    }

    throw const AuthFlowException(
      'E-posta doğrulama bilgisi güvenlik tokenına henüz yansımadı. Lütfen kısa süre sonra tekrar deneyin.',
    );
  }

  SignUpProfile _fallbackProfileFromUser(User user) {
    final displayName = (user.displayName ?? '').trim();
    final parts =
        displayName.split(RegExp(r'\s+')).where((it) => it.isNotEmpty).toList();

    final name = parts.isNotEmpty ? parts.first : 'Kullanıcı';
    final surname = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final email = user.email ?? '';
    final username = email.contains('@') ? email.split('@').first : user.uid;

    return SignUpProfile(
      name: name,
      surname: surname,
      username: username,
      email: email,
    );
  }

  SignUpProfile _profileFromExistingData({
    required Map<String, dynamic> data,
    required SignUpProfile fallback,
  }) {
    final name = (data['name'] as String?)?.trim();
    final surname = (data['surname'] as String?)?.trim();
    final username = (data['username'] as String?)?.trim();
    final email = (data['email'] as String?)?.trim();

    return SignUpProfile(
      name: (name != null && name.isNotEmpty) ? name : fallback.name,
      surname: surname ?? fallback.surname,
      username:
          (username != null && username.isNotEmpty)
              ? username
              : fallback.username,
      email: (email != null && email.isNotEmpty) ? email : fallback.email,
    );
  }
}

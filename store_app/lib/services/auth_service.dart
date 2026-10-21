import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../google_sign_in_config.dart';

enum Role { guest, customer, admin }

class Session {
  final Role role;
  final String uid;
  final String email;
  final String name;

  const Session(this.role, {this.uid = '', this.email = '', this.name = ''});

  static const guest = Session(Role.guest);

  bool get signedIn => role != Role.guest;
}

/// حساب الزبون وحساب صاحب المتجر بنفس تسجيل الدخول.
/// الحساب يصير مدير إذا عنده وثيقة بـ admins/{uid}، وما يبين أي شي للزبون.
abstract class AuthService {
  Stream<Session> watchSession();
  Future<void> signIn(String email, String password);
  /// يرجع uid الحساب الجديد.
  Future<String> signUp(String name, String email, String password);
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();

  /// إذا false، زر كوكل ما يبين.
  bool get supportsGoogle;

  /// يرجع false إذا الزبون سكر نافذة كوكل بدون ما يختار حساب.
  Future<bool> signInWithGoogle();
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

String authErrorMessage(String code) => switch (code) {
      'invalid-credential' || 'wrong-password' || 'user-not-found' => 'الإيميل أو الباسورد غلط',
      'invalid-email' => 'الإيميل مو صحيح',
      'email-already-in-use' => 'هذا الإيميل عنده حساب. سجل دخول بدال ما تسوي حساب جديد.',
      'weak-password' => 'الباسورد ضعيف. خليه 6 أحرف أو أكثر.',
      'too-many-requests' => 'محاولات كثيرة. انتظر شوية وحاول مرة ثانية.',
      'network-request-failed' => 'ماكو اتصال بالإنترنت',
      'account-exists-with-different-credential' =>
        'هذا الإيميل عنده حساب بالباسورد. سجل دخول بالإيميل والباسورد.',
      'user-disabled' => 'هذا الحساب موقوف',
      _ => 'صار خطأ ($code)',
    };

class FirebaseAuthService implements AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  FirebaseAuthService({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  @override
  Stream<Session> watchSession() => _auth.userChanges().asyncMap((user) async {
        if (user == null) return Session.guest;
        var isAdmin = false;
        try {
          isAdmin = (await _db.collection('admins').doc(user.uid).get()).exists;
        } catch (_) {
          // إذا ما كدرنا نتأكد، نتعامل وياه كزبون.
        }
        return Session(
          isAdmin ? Role.admin : Role.customer,
          uid: user.uid,
          email: user.email ?? '',
          name: user.displayName ?? '',
        );
      });

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on FirebaseAuthException catch (e) {
      throw AuthException(authErrorMessage(e.code));
    }
  }

  @override
  Future<void> signIn(String email, String password) =>
      _guard(() => _auth.signInWithEmailAndPassword(email: email, password: password));

  @override
  Future<String> signUp(String name, String email, String password) => _guard(() async {
        final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
        final user = cred.user!;
        await user.updateDisplayName(name);
        await user.reload();
        return user.uid;
      });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email));

  Future<void>? _googleInit;

  Future<void> _initGoogle() => _googleInit ??= GoogleSignIn.instance.initialize(
        clientId: defaultTargetPlatform == TargetPlatform.iOS ? googleIosClientId : null,
        serverClientId: googleWebClientId,
      );

  @override
  bool get supportsGoogle => googleSignInConfigured;

  @override
  Future<bool> signInWithGoogle() async {
    final GoogleSignInAccount account;
    try {
      await _initGoogle();
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return false;
      throw AuthException('ما كدرنا نكمل الدخول بكوكل (${e.code.name})');
    }
    final idToken = account.authentication.idToken;
    if (idToken == null) throw AuthException('ما كدرنا نكمل الدخول بكوكل');
    await _guard(() => _auth.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken)));
    return true;
  }

  @override
  Future<void> signOut() async {
    // حتى المرة الجاية يسأله أي حساب كوكل يريد.
    if (_googleInit != null) {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {}
    }
    await _auth.signOut();
  }
}

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
  final bool usesPassword; // دخل بإيميل وباسورد (مو كوكل أو آبل)

  const Session(this.role, {this.uid = '', this.email = '', this.name = '', this.usesPassword = false});

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

  /// الدخول بآبل، بالآيفون بس.
  bool get supportsApple;

  /// يرجع false إذا الزبون سكر نافذة آبل.
  Future<bool> signInWithApple();

  /// توكن Firebase للسيرفر (يثبت منو الزبون). null إذا زائر.
  Future<String?> idToken({bool forceRefresh = false});

  /// يحذف الحساب ومعلوماته المحفوظة. يتأكد من صاحب الحساب أول:
  /// بالباسورد [password]، أو بنافذة كوكل/آبل. يرجع false إذا سكرها.
  Future<bool> deleteAccount({String? password});
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
      'requires-recent-login' => 'سجل خروج ودخول مرة ثانية، وبعدين احذف الحساب',
      'user-mismatch' => 'هذا مو نفس الحساب اللي داخل بيه',
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
        // الحساب المجهول (للرفع بس) يبقى زائر.
        if (user == null || user.isAnonymous) return Session.guest;
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
          usesPassword: user.providerData.any((p) => p.providerId == 'password'),
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
  Future<String?> idToken({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      return await user.getIdToken(forceRefresh);
    } catch (_) {
      return null;
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
    // بالمتصفح نافذة كوكل تنفتح من Firebase نفسه.
    if (kIsWeb) {
      try {
        await _auth.signInWithPopup(GoogleAuthProvider());
        return true;
      } on FirebaseAuthException catch (e) {
        if (e.code == 'popup-closed-by-user' || e.code == 'cancelled-popup-request') return false;
        throw AuthException(authErrorMessage(e.code));
      }
    }
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
  bool get supportsApple => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static bool _canceled(FirebaseAuthException e) =>
      e.code.contains('cancel') || (e.message ?? '').contains('1001');

  @override
  Future<bool> signInWithApple() async {
    try {
      await _auth.signInWithProvider(AppleAuthProvider()
        ..addScope('email')
        ..addScope('name'));
      return true;
    } on FirebaseAuthException catch (e) {
      if (_canceled(e)) return false;
      throw AuthException(authErrorMessage(e.code));
    }
  }

  @override
  Future<bool> deleteAccount({String? password}) async {
    final user = _auth.currentUser;
    if (user == null) return true;
    final providers = user.providerData.map((p) => p.providerId).toSet();
    try {
      // فايربيس يطلب تسجيل دخول جديد قبل الحذف، فنتأكد من صاحب الحساب.
      if (providers.contains('password')) {
        await user.reauthenticateWithCredential(
          EmailAuthProvider.credential(email: user.email ?? '', password: password ?? ''),
        );
      } else if (providers.contains('apple.com')) {
        await user.reauthenticateWithProvider(AppleAuthProvider());
      } else if (providers.contains('google.com') && kIsWeb) {
        await user.reauthenticateWithPopup(GoogleAuthProvider());
      } else if (providers.contains('google.com')) {
        await _initGoogle();
        final GoogleSignInAccount account;
        try {
          account = await GoogleSignIn.instance.authenticate();
        } on GoogleSignInException catch (e) {
          if (e.code == GoogleSignInExceptionCode.canceled) return false;
          rethrow;
        }
        final idToken = account.authentication.idToken;
        if (idToken == null) throw AuthException('ما كدرنا نتأكد من حساب كوكل');
        await user.reauthenticateWithCredential(GoogleAuthProvider.credential(idToken: idToken));
      }

      final profile = _db.collection('users').doc(user.uid);
      try {
        await profile.delete();
      } catch (_) {
        // إذا قواعد Firestore بعدها القديمة (ما تسمح بالحذف)، نمسح المعلومات على الأقل.
        await profile.set({'name': '', 'phone': '', 'address': ''}).catchError((_) {});
      }
      await user.delete();
      await signOut();
      return true;
    } on FirebaseAuthException catch (e) {
      if (_canceled(e)) return false;
      throw AuthException(authErrorMessage(e.code));
    } on GoogleSignInException catch (e) {
      throw AuthException('ما كدرنا نتأكد من حساب كوكل (${e.code.name})');
    }
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

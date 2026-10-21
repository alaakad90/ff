import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum AdminStatus { signedOut, notAdmin, admin }

class AdminSession {
  final AdminStatus status;
  final String uid;
  final String email;

  const AdminSession(this.status, {this.uid = '', this.email = ''});

  static const signedOut = AdminSession(AdminStatus.signedOut);
}

/// تسجيل دخول صاحب المتجر. الحساب يصير مدير إذا عنده وثيقة بـ admins/{uid}.
abstract class AuthService {
  Stream<AdminSession> watchSession();
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class FirebaseAuthService implements AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  FirebaseAuthService({FirebaseAuth? auth, FirebaseFirestore? db})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance;

  @override
  Stream<AdminSession> watchSession() => _auth.authStateChanges().asyncMap((user) async {
        if (user == null) return AdminSession.signedOut;
        final doc = await _db.collection('admins').doc(user.uid).get();
        return AdminSession(
          doc.exists ? AdminStatus.admin : AdminStatus.notAdmin,
          uid: user.uid,
          email: user.email ?? '',
        );
      });

  @override
  Future<void> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw AuthException(switch (e.code) {
        'invalid-credential' || 'wrong-password' || 'user-not-found' || 'invalid-email' =>
          'الإيميل أو الباسورد غلط',
        'too-many-requests' => 'محاولات كثيرة. انتظر شوية وحاول مرة ثانية.',
        'network-request-failed' => 'ماكو اتصال بالإنترنت',
        _ => 'ما كدرنا نسجل الدخول (${e.code})',
      });
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();
}

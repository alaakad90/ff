// إعدادات مشروع Firebase (lacasa-store-ef68f).
// هذني القيم مو سرية: تعرّف التطبيق على المشروع بس.
// الحماية الحقيقية بقواعد Firestore (firestore.rules).

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('التطبيق يشتغل على أندرويد وآيفون بس');
    }
  }

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyBkkOUdhha86PDajOaYKiNrNcscSwe96XQ',
    appId: '1:858636711977:android:18b384cc8ed43baf22c438',
    messagingSenderId: '858636711977',
    projectId: 'lacasa-store-ef68f',
    storageBucket: 'lacasa-store-ef68f.firebasestorage.app',
  );

  static const ios = FirebaseOptions(
    apiKey: 'AIzaSyA_MBBxrTESZhOta9bEllwFfTaaNmmxkWY',
    appId: '1:858636711977:ios:7b369b10ec1d089422c438',
    messagingSenderId: '858636711977',
    projectId: 'lacasa-store-ef68f',
    storageBucket: 'lacasa-store-ef68f.firebasestorage.app',
    iosBundleId: 'org.lacasa.lacasaStore',
  );
}

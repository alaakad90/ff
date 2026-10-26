import 'package:flutter/foundation.dart';

// معرّفات دخول كوكل. تنولد بـ Firebase لما يتفعل Google بـ Authentication.
// زر "المتابعة بحساب Google" ما يبين إلا لما تنحط القيم.

/// Web client ID: من google-services.json (oauth_client بـ client_type: 3).
/// يحتاجه الأندرويد حتى ياخذ idToken لـ Firebase.
const googleWebClientId =
    '858636711977-pmgddcilrsntj84dq2k8u44c69vrjv9m.apps.googleusercontent.com';

/// iOS client ID: من GoogleService-Info.plist (المفتاح CLIENT_ID).
/// والآيفون يحتاج هم REVERSED_CLIENT_ID بـ ios/Runner/Info.plist.
const googleIosClientId =
    '858636711977-17kd0ivmrgkah405244vmehp9a5np2g2.apps.googleusercontent.com';

/// بالمتصفح Firebase يفتح نافذة كوكل بنفسه، فما يحتاج المعرّفات.
bool get googleSignInConfigured => kIsWeb || switch (defaultTargetPlatform) {
      TargetPlatform.android => googleWebClientId.isNotEmpty,
      TargetPlatform.iOS => googleWebClientId.isNotEmpty && googleIosClientId.isNotEmpty,
      _ => false,
    };

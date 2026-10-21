import 'package:flutter/foundation.dart';

// معرّفات دخول كوكل. تنولد بـ Firebase لما يتفعل Google بـ Authentication.
// زر "المتابعة بحساب Google" ما يبين إلا لما تنحط القيم.

/// Web client ID: من google-services.json (oauth_client بـ client_type: 3).
/// يحتاجه الأندرويد حتى ياخذ idToken لـ Firebase.
const googleWebClientId = '';

/// iOS client ID: من GoogleService-Info.plist (المفتاح CLIENT_ID).
/// والآيفون يحتاج هم REVERSED_CLIENT_ID بـ ios/Runner/Info.plist.
const googleIosClientId = '';

bool get googleSignInConfigured => switch (defaultTargetPlatform) {
      TargetPlatform.android => googleWebClientId.isNotEmpty,
      TargetPlatform.iOS => googleWebClientId.isNotEmpty && googleIosClientId.isNotEmpty,
      _ => false,
    };

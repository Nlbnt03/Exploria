import 'dart:io';

import 'package:flutter/foundation.dart';

class AdConstants {
  AdConstants._();

  // Android App ID — AndroidManifest.xml'de de tanımlı
  static const String admobAppIdAndroid =
      'ca-app-pub-3400076691045068~9307109991';

  // iOS App ID — ios/Runner/Info.plist içinde GADApplicationIdentifier olarak da tanımlı
  static const String admobAppIdIOS = 'ca-app-pub-3400076691045068~1357714627';

  static String get bannerAdUnitId {
    if (kDebugMode && Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/2934735716';
    }
    if (kDebugMode) return 'ca-app-pub-3940256099942544/6300978111';
    if (Platform.isIOS) return 'ca-app-pub-3400076691045068/8618513157';
    return 'ca-app-pub-3400076691045068/3651458632';
  }

  static String get interstitialAdUnitId {
    if (kDebugMode && Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/4411468910';
    }
    if (kDebugMode) return 'ca-app-pub-3940256099942544/1033173712';
    if (Platform.isIOS) return 'ca-app-pub-3400076691045068/3213721770';
    return 'ca-app-pub-3400076691045068/1741656764';
  }

  static String get rewardedAdUnitId {
    if (kDebugMode && Platform.isIOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    }
    if (kDebugMode) return 'ca-app-pub-3940256099942544/5224354917';
    if (Platform.isIOS) return 'ca-app-pub-3400076691045068/7305431489';
    return 'ca-app-pub-3400076691045068/2931449500';
  }
}

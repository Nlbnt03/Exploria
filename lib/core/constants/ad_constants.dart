import 'dart:io';

class AdConstants {
  AdConstants._();

  // Android App ID — AndroidManifest.xml'de de tanımlı
  static const String admobAppIdAndroid =
      'ca-app-pub-3400076691045068~9307109991';

  // iOS App ID — Info.plist'e eklenecek (henüz eklenmedi)
  static const String admobAppIdIOS =
      'ca-app-pub-3400076691045068~1357714627';

  static String get bannerAdUnitId {
    if (Platform.isIOS) return 'ca-app-pub-3940256099942544/2435281174';
    return 'ca-app-pub-3940256099942544/9214589741';
  }

  static String get interstitialAdUnitId {
    if (Platform.isIOS) return 'ca-app-pub-3940256099942544/4411468910';
    return 'ca-app-pub-3940256099942544/1033173712';
  }

  static String get rewardedAdUnitId {
    if (Platform.isIOS) return 'ca-app-pub-3940256099942544/1712485313';
    return 'ca-app-pub-3940256099942544/5224354917';
  }
}

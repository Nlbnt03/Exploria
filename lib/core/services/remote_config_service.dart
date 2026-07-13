import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Uygulama içi "ayar" niteliğindeki sayısal değerleri (reklam sıklığı,
/// görev XP'leri, günlük ödül miktarı) yeni sürüm basmadan Firebase
/// konsolundan değiştirebilmek için Remote Config sarmalayıcısı.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  static const List<String> questKeys = [
    'ilkAdim',
    'kasifRuhu',
    'cesitliKasif',
    'duzenliGezgin',
    'takimOyuncusu',
    'takimKasifi',
    'tamHafta',
  ];

  static const Map<String, int> _defaults = {
    'interstitial_frequency': 2,
    'quest_xp_ilkAdim': 50,
    'quest_xp_kasifRuhu': 100,
    'quest_xp_cesitliKasif': 75,
    'quest_xp_duzenliGezgin': 75,
    'quest_xp_takimOyuncusu': 100,
    'quest_xp_takimKasifi': 100,
    'quest_xp_tamHafta': 300,
    'daily_ad_reward_xp': 25,
    'daily_ad_reward_max': 3,
  };

  FirebaseRemoteConfig? _rc;

  Future<void> initialize() async {
    final rc = FirebaseRemoteConfig.instance;
    try {
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await rc.setDefaults(_defaults);
      _rc = rc;
      await rc.fetchAndActivate();
    } catch (e) {
      debugPrint('[RemoteConfig] Fetch başarısız, varsayılanlar kullanılacak: $e');
    }
  }

  int _value(String key) => _rc?.getInt(key) ?? _defaults[key]!;

  int get interstitialFrequency => _value('interstitial_frequency').clamp(1, 999);

  int questXp(String key) => _value('quest_xp_$key');

  int get weeklyXpGoal =>
      questKeys.fold(0, (sum, key) => sum + questXp(key));

  int get dailyAdRewardXp => _value('daily_ad_reward_xp');

  int get dailyAdRewardMax => _value('daily_ad_reward_max');
}

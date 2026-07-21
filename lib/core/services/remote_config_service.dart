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
  Future<void>? _defaultsInitialization;
  Future<void>? _fetchInFlight;

  /// Makes local defaults available without waiting for a network request.
  Future<void> prepareDefaults() {
    return _defaultsInitialization ??= _prepareDefaults();
  }

  Future<void> _prepareDefaults() async {
    final rc = FirebaseRemoteConfig.instance;
    _rc = rc;
    try {
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 10),
          minimumFetchInterval: const Duration(hours: 1),
        ),
      );
      await rc.setDefaults(_defaults);
    } catch (e) {
      debugPrint('[RemoteConfig] Varsayılanlar hazırlanamadı: $e');
    }
  }

  /// Refreshes server values in the background. Local defaults remain usable
  /// if the network is slow or unavailable.
  Future<void> fetchLatest() {
    final running = _fetchInFlight;
    if (running != null) return running;
    final future = _fetchLatest();
    _fetchInFlight = future;
    return future.whenComplete(() {
      if (identical(_fetchInFlight, future)) _fetchInFlight = null;
    });
  }

  Future<void> _fetchLatest() async {
    await prepareDefaults();
    final rc = _rc;
    if (rc == null) return;
    try {
      await rc.fetchAndActivate();
    } catch (e) {
      debugPrint(
        '[RemoteConfig] Fetch başarısız, varsayılanlar kullanılacak: $e',
      );
    }
  }

  Future<void> initialize() async {
    await prepareDefaults();
    await fetchLatest();
  }

  int _value(String key) => _rc?.getInt(key) ?? _defaults[key]!;

  int get interstitialFrequency =>
      _value('interstitial_frequency').clamp(1, 999);

  int questXp(String key) => _value('quest_xp_$key');

  int get weeklyXpGoal => questKeys.fold(0, (sum, key) => sum + questXp(key));

  int get dailyAdRewardXp => _value('daily_ad_reward_xp');

  int get dailyAdRewardMax => _value('daily_ad_reward_max');
}

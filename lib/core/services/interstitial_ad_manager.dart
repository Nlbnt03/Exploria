import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../constants/ad_constants.dart';
import 'remote_config_service.dart';

class InterstitialAdManager {
  InterstitialAdManager._();
  static final InterstitialAdManager instance = InterstitialAdManager._();

  InterstitialAd? _interstitial;
  int _showCount = 0;
  int _exitAttempts = 0;
  DateTime? _lastShown;
  bool _loading = false;
  Timer? _retryTimer;
  int _loadFailures = 0;

  static const int _maxPerSession = 2;
  static const Duration _minInterval = Duration(seconds: 5);

  void init() {
    if (_interstitial == null && !_loading) _load();
  }

  void _load() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _loading = true;
    InterstitialAd.load(
      adUnitId: AdConstants.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loading = false;
          _loadFailures = 0;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (_) {
              _interstitial?.dispose();
              _interstitial = null;
              _load();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              debugPrint('[Ads] Interstitial failed to show: ${err.message}');
              ad.dispose();
              _interstitial = null;
              _loading = false;
              _scheduleRetry();
            },
          );
        },
        onAdFailedToLoad: (err) {
          debugPrint('[Ads] Interstitial failed to load: ${err.message}');
          _interstitial = null;
          _loading = false;
          _loadFailures++;
          _scheduleRetry();
        },
      ),
    );
  }

  void _scheduleRetry() {
    if (_interstitial != null || _loading) return;
    _retryTimer?.cancel();
    final delay = Duration(seconds: _loadFailures < 3 ? 5 : 20);
    _retryTimer = Timer(delay, () {
      if (_interstitial == null && !_loading) _load();
    });
  }

  bool get _canShow {
    if (_interstitial == null) return false;
    if (_showCount >= _maxPerSession) return false;
    final frequency = RemoteConfigService.instance.interstitialFrequency;
    if (_exitAttempts % frequency != 0) return false;
    if (_lastShown != null &&
        DateTime.now().difference(_lastShown!) < _minInterval) {
      return false;
    }
    return true;
  }

  /// Returns true if an ad was shown, false otherwise.
  /// When true, the returned Future completes once the ad is dismissed.
  Future<bool> show() async {
    _exitAttempts++;
    if (!_canShow) {
      return false;
    }

    final ad = _interstitial!;
    _interstitial = null;
    _showCount++;
    _lastShown = DateTime.now();

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) {
        ad.dispose();
        _load();
        completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        debugPrint('[Ads] Interstitial failed to show: ${err.message}');
        ad.dispose();
        _loading = false;
        _loadFailures++;
        _scheduleRetry();
        completer.complete(false);
      },
    );
    ad.show();
    return completer.future;
  }
}

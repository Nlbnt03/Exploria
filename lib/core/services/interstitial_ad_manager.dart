import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../constants/ad_constants.dart';

class InterstitialAdManager {
  InterstitialAdManager._();
  static final InterstitialAdManager instance = InterstitialAdManager._();

  InterstitialAd? _interstitial;
  int _showCount = 0;
  DateTime? _lastShown;
  bool _loading = false;
  bool _skipNext = false;

  static const int _maxPerSession = 2;
  static const Duration _minInterval = Duration(seconds: 5);

  void init() {
    if (_interstitial == null && !_loading) _load();
  }

  void _load() {
    _loading = true;
    InterstitialAd.load(
      adUnitId: AdConstants.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _loading = false;
          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (_) {
              _interstitial?.dispose();
              _interstitial = null;
              _load();
            },
            onAdFailedToShowFullScreenContent: (ad, err) {
              ad.dispose();
              _interstitial = null;
              _loading = false;
            },
          );
        },
        onAdFailedToLoad: (_) {
          _interstitial = null;
          _loading = false;
        },
      ),
    );
  }

  bool get _canShow {
    if (_interstitial == null) return false;
    if (_showCount >= _maxPerSession) return false;
    if (_skipNext) return false;
    if (_lastShown != null &&
        DateTime.now().difference(_lastShown!) < _minInterval) {
      return false;
    }
    return true;
  }

  /// Returns true if an ad was shown, false otherwise.
  /// When true, the returned Future completes once the ad is dismissed.
  Future<bool> show() async {
    if (!_canShow) {
      _skipNext = false;
      return false;
    }

    final ad = _interstitial!;
    _interstitial = null;
    _showCount++;
    _lastShown = DateTime.now();
    _skipNext = true;

    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) {
        ad.dispose();
        _load();
        completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        _loading = false;
        completer.complete(false);
      },
    );
    ad.show();
    return completer.future;
  }
}

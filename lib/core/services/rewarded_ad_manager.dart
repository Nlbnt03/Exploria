import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../constants/ad_constants.dart';

enum RewardResult { success, cancelled, notLoaded }

class RewardedAdManager {
  RewardedAdManager._();
  static final RewardedAdManager instance = RewardedAdManager._();

  RewardedAd? _ad;
  bool _isLoading = false;
  Completer<void>? _loadCompleter;

  void init() {
    if (_ad == null && !_isLoading) _load();
  }

  bool get isLoaded => _ad != null;

  void _load() {
    if (_isLoading) return;
    _isLoading = true;
    _loadCompleter = Completer<void>();

    RewardedAd.load(
      adUnitId: AdConstants.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _isLoading = false;
          _loadCompleter?.complete();
          _loadCompleter = null;
        },
        onAdFailedToLoad: (err) {
          _ad = null;
          _isLoading = false;
          _loadCompleter?.completeError(err);
          _loadCompleter = null;
        },
      ),
    );
  }

  Future<bool> _waitForLoad(Duration timeout) async {
    if (_ad != null) return true;
    if (!_isLoading) _load();
    final completer = _loadCompleter;
    if (completer == null) return false;
    try {
      await completer.future.timeout(timeout);
      return _ad != null;
    } catch (_) {
      return false;
    }
  }

  /// Shows a rewarded ad, loading first if needed (up to [loadTimeout]).
  /// Returns [RewardResult.success] only when the user fully watches and earns the reward.
  Future<RewardResult> show({
    Duration loadTimeout = const Duration(seconds: 12),
  }) async {
    if (_ad == null) {
      final loaded = await _waitForLoad(loadTimeout);
      if (!loaded) return RewardResult.notLoaded;
    }

    final ad = _ad!;
    _ad = null;

    bool rewarded = false;
    final completer = Completer<RewardResult>();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (_) {
        ad.dispose();
        _load(); // preload next
        if (!completer.isCompleted) {
          completer.complete(
            rewarded ? RewardResult.success : RewardResult.cancelled,
          );
        }
      },
      onAdFailedToShowFullScreenContent: (failedAd, _) {
        failedAd.dispose();
        _isLoading = false;
        _load();
        if (!completer.isCompleted) {
          completer.complete(RewardResult.notLoaded);
        }
      },
    );

    await ad.show(onUserEarnedReward: (_, __) => rewarded = true);
    return completer.future;
  }
}

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../core/constants/ad_constants.dart';

class AdaptiveBanner extends StatefulWidget {
  const AdaptiveBanner({super.key});

  @override
  State<AdaptiveBanner> createState() => _AdaptiveBannerState();
}

class _AdaptiveBannerState extends State<AdaptiveBanner> {
  BannerAd? _bannerAd;
  bool _isLoaded = false;
  bool _loading = false;
  double _adHeight = 50;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadAd();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  Future<void> _loadAd() async {
    if (_loading) return;
    _loading = true;
    try {
      await _bannerAd?.dispose();
      if (!mounted) return;

      final screenWidth = MediaQuery.of(context).size.width.toInt();
      final adSize = await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
        screenWidth,
      );
      if (adSize == null) {
        _loading = false;
        return;
      }

      _adHeight = adSize.height.toDouble();

      _bannerAd = BannerAd(
        adUnitId: AdConstants.bannerAdUnitId,
        size: adSize,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            _loading = false;
            if (mounted) setState(() => _isLoaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            _loading = false;
            ad.dispose();
          },
        ),
      )..load();
    } catch (_) {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoaded || _bannerAd == null) return const SizedBox.shrink();

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: _adHeight),
      child: SizedBox(
        width: double.infinity,
        height: _adHeight,
        child: AdWidget(ad: _bannerAd!),
      ),
    );
  }
}

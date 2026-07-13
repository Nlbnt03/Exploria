import 'dart:async';
import 'dart:io';

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../firebase_options.dart';
import '../core/services/interstitial_ad_manager.dart';
import '../core/services/notification_service.dart';
import '../core/services/remote_config_service.dart';
import '../core/services/rewarded_ad_manager.dart';
import 'app.dart';

/// Catches Flutter framework errors that would otherwise be silently handled.
void setupGlobalErrorHandler() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[Fatal] ${details.exception}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[Platform Error] $error\n$stack');
    return true;
  };
}

const _defaultMapboxAccessToken =
    'pk.eyJ1IjoieW5hbGJhbnQiLCJhIjoiY21xanl2MzJxMGJiZDN4cXh5bmFwMmpxMiJ9.TWXe1GbepbTJ9XJTtcTsJg';
Future<void>? _firebaseInitialization;
const int _mapboxCacheRefreshVersion = 2;
const String _mapboxCacheRefreshKey = 'mapbox_cache_refresh_version';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureFirebaseInitialized();
  await NotificationService.instance.initialize();
  await RemoteConfigService.instance.initialize();

  setupGlobalErrorHandler();

  MapboxMapsOptions.setTileStoreUsageMode(TileStoreUsageMode.DISABLED);
  MapboxOptions.setAccessToken(
    const String.fromEnvironment(
      'MAPBOX_ACCESS_TOKEN',
      defaultValue: _defaultMapboxAccessToken,
    ),
  );
  runApp(const ProviderScope(child: KesfedrioApp()));

  // Deferred until the first frame is on screen: the ATT system prompt only
  // renders once the app's window is key and visible, and AdMob must not be
  // initialized (and must not collect the IDFA) before that consent resolves.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_initializeAdsAfterTrackingConsent());
  });
}

Future<void> _initializeAdsAfterTrackingConsent() async {
  await requestTrackingAuthorizationIfNeeded();
  await MobileAds.instance.initialize();
  if (kDebugMode) {
    MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(testDeviceIds: ['C1C254FBA484927B27A7D7AE274D5207']),
    );
  }
  InterstitialAdManager.instance.init();
  RewardedAdManager.instance.init();
}

/// Shows the iOS App Tracking Transparency system prompt. AdMob must not
/// collect the IDFA before the user has responded to this consent request.
Future<void> requestTrackingAuthorizationIfNeeded() async {
  if (!Platform.isIOS) return;
  final status = await AppTrackingTransparency.trackingAuthorizationStatus;
  if (status == TrackingStatus.notDetermined) {
    // A short delay avoids the prompt racing the app's own splash/launch
    // animation, which can cause iOS to silently skip showing it.
    await Future.delayed(const Duration(milliseconds: 300));
    await AppTrackingTransparency.requestTrackingAuthorization();
  }
}

Future<void> ensureFirebaseInitialized() async {
  return _firebaseInitialization ??= Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  ).then((_) {
    firestore.FirebaseFirestore.instance.settings = firestore.Settings(
      persistenceEnabled: true,
      cacheSizeBytes: firestore.Settings.CACHE_SIZE_UNLIMITED,
    );
  });
}

Future<void> ensureFreshMapboxData() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final appliedVersion = prefs.getInt(_mapboxCacheRefreshKey) ?? 0;
    if (appliedVersion >= _mapboxCacheRefreshVersion) {
      return;
    }

    await MapboxMapsOptions.clearData();
    await prefs.setInt(_mapboxCacheRefreshKey, _mapboxCacheRefreshVersion);
  } catch (_) {
    // Cache cleanup is best-effort and should not block startup.
  }
}

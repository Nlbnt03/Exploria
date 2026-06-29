import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../firebase_options.dart';
import '../core/services/interstitial_ad_manager.dart';
import '../core/services/notification_service.dart';
import '../core/services/rewarded_ad_manager.dart';
import 'app.dart';

const _defaultMapboxAccessToken =
    'pk.eyJ1IjoieW5hbGJhbnQiLCJhIjoiY21xanl2MzJxMGJiZDN4cXh5bmFwMmpxMiJ9.TWXe1GbepbTJ9XJTtcTsJg';
Future<void>? _firebaseInitialization;
const int _mapboxCacheRefreshVersion = 2;
const String _mapboxCacheRefreshKey = 'mapbox_cache_refresh_version';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureFirebaseInitialized();
  await NotificationService.instance.initialize();
  unawaited(
    MobileAds.instance.initialize().then((_) {
      MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          testDeviceIds: ['C1C254FBA484927B27A7D7AE274D5207'],
        ),
      );
      InterstitialAdManager.instance.init();
      RewardedAdManager.instance.init();
    }),
  );

  MapboxMapsOptions.setTileStoreUsageMode(TileStoreUsageMode.DISABLED);
  MapboxOptions.setAccessToken(
    const String.fromEnvironment(
      'MAPBOX_ACCESS_TOKEN',
      defaultValue: _defaultMapboxAccessToken,
    ),
  );
  runApp(
    const ProviderScope(
      child: KesfedrioApp(),
    ),
  );
}

Future<void> ensureFirebaseInitialized() async {
  if (_firebaseInitialization == null) {
    _firebaseInitialization = Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).then((_) {
      firestore.FirebaseFirestore.instance.settings = firestore.Settings(
        persistenceEnabled: true,
        cacheSizeBytes: firestore.Settings.CACHE_SIZE_UNLIMITED,
      );
    });
  }
  return _firebaseInitialization;
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

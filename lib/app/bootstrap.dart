import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart' as firestore;

import '../firebase_options.dart';
import '../core/services/notification_service.dart';
import 'app.dart';

const _defaultMapboxAccessToken =
    'pk.eyJ1IjoieW5hbGJhbnQiLCJhIjoiY21tNnZ0ZWQ3MGszajJwczh0azl1MjU1ciJ9.nZDRb_apQzVD9zewlDGxDQ';
Future<void>? _firebaseInitialization;
const int _mapboxCacheRefreshVersion = 2;
const String _mapboxCacheRefreshKey = 'mapbox_cache_refresh_version';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ensureFirebaseInitialized();
  await NotificationService.instance.initialize();

  MapboxMapsOptions.setTileStoreUsageMode(TileStoreUsageMode.DISABLED);
  MapboxOptions.setAccessToken(
    const String.fromEnvironment(
      'MAPBOX_ACCESS_TOKEN',
      defaultValue: _defaultMapboxAccessToken,
    ),
  );
  runApp(
    const ProviderScope(
      child: ExploriaApp(),
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

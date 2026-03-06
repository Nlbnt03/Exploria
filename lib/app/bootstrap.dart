import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../firebase_options.dart';
import 'app.dart';

const _defaultMapboxAccessToken =
    'pk.eyJ1IjoieW5hbGJhbnQiLCJhIjoiY21tNnZ0ZWQ3MGszajJwczh0azl1MjU1ciJ9.nZDRb_apQzVD9zewlDGxDQ';
Future<void>? _firebaseInitialization;
const int _mapboxCacheRefreshVersion = 2;
const String _mapboxCacheRefreshKey = 'mapbox_cache_refresh_version';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxMapsOptions.setTileStoreUsageMode(TileStoreUsageMode.DISABLED);
  MapboxOptions.setAccessToken(
    const String.fromEnvironment(
      'MAPBOX_ACCESS_TOKEN',
      defaultValue: _defaultMapboxAccessToken,
    ),
  );
  runApp(const ExploriaApp());
}

Future<void> ensureFirebaseInitialized() {
  return _firebaseInitialization ??= Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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

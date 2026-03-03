import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

import '../firebase_options.dart';
import 'app.dart';

const _defaultMapboxAccessToken =
    'pk.eyJ1IjoieW5hbGJhbnQiLCJhIjoiY21tNnZ0ZWQ3MGszajJwczh0azl1MjU1ciJ9.nZDRb_apQzVD9zewlDGxDQ';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  MapboxOptions.setAccessToken(
    const String.fromEnvironment(
      'MAPBOX_ACCESS_TOKEN',
      defaultValue: _defaultMapboxAccessToken,
    ),
  );
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ExploriaApp());
}

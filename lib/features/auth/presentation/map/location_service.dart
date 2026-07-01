import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

enum LocationAccessStatus {
  granted,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  unavailable,
}

class LocationAccessResult {
  const LocationAccessResult({required this.status, this.position});

  final LocationAccessStatus status;
  final Position? position;

  bool get isGranted =>
      status == LocationAccessStatus.granted && position != null;
}

class LocationService {
  static LocationService? _instance;

  factory LocationService({Duration pollingInterval = const Duration(seconds: 4)}) {
    _instance ??= LocationService._internal();
    return _instance!;
  }

  LocationService._internal();

  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  StreamSubscription<geo.Position>? _positionSub;
  bool _running = false;
  bool _isBackground = false;
  int _activeControllers = 0;

  static final geo.ForegroundNotificationConfig _foregroundNotification =
      geo.ForegroundNotificationConfig(
    notificationTitle: 'Keşfedio',
    notificationText: 'Haritadaki ilerlemeniz takip ediliyor...',
  );

  Stream<Position> get positionStream => _controller.stream;
  bool get isRunning => _running;
  bool get isBackgroundMode => _isBackground;

  void registerConsumer() {
    _activeControllers++;
    if (!_running) {
      unawaited(start());
    }
  }

  void unregisterConsumer() {
    _activeControllers--;
    if (_activeControllers <= 0) {
      _activeControllers = 0;
      unawaited(stop());
    }
  }

  Future<bool> start({bool background = false}) async {
    if (_running) return true;

    final hasPermission = await _ensurePermission();
    if (!hasPermission) return false;

    _isBackground = background;
    _running = true;
    _positionSub = geo.Geolocator.getPositionStream(
      locationSettings: _buildSettings(),
    ).listen(
      (pos) {
        if (_running) {
          _controller.add(Position(pos.longitude, pos.latitude));
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
    return true;
  }

  Future<void> setBackgroundMode(bool background) async {
    if (!_running) {
      _isBackground = background;
      return;
    }

    _isBackground = background;
    await _positionSub?.cancel();
    _positionSub = geo.Geolocator.getPositionStream(
      locationSettings: _buildSettings(),
    ).listen(
      (pos) {
        if (_running) {
          _controller.add(Position(pos.longitude, pos.latitude));
        }
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  geo.LocationSettings _buildSettings() {
    final accuracy = _isBackground
        ? geo.LocationAccuracy.medium
        : geo.LocationAccuracy.high;
    final distanceFilter = _isBackground ? 12 : 4;

    if (Platform.isAndroid) {
      return geo.AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        foregroundNotificationConfig: _foregroundNotification,
      );
    }

    return geo.AppleSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
      showBackgroundLocationIndicator: true,
      pauseLocationUpdatesAutomatically: false,
    );
  }

  Future<void> stop() async {
    _running = false;
    _isBackground = false;
    await _positionSub?.cancel();
    _positionSub = null;
  }

  /// Full teardown — closes the stream controller and resets the singleton.
  /// Called only on logout or app-level destroy, NOT on per-map dispose.
  void shutdown() {
    stop();
    _controller.close();
    _instance = null;
  }

  Future<void> dispose() async {
    await stop();
  }

  static Future<LocationAccessResult> requestSinglePosition() async {
    try {
      final hasPermission = await _ensurePermissionStatic();
      if (!hasPermission) {
        final permission = await geo.Geolocator.checkPermission();
        if (permission == geo.LocationPermission.deniedForever) {
          return const LocationAccessResult(
            status: LocationAccessStatus.permissionDeniedForever,
          );
        }
        if (permission == geo.LocationPermission.denied) {
          return const LocationAccessResult(
            status: LocationAccessStatus.permissionDenied,
          );
        }
        if (!await geo.Geolocator.isLocationServiceEnabled()) {
          return const LocationAccessResult(
            status: LocationAccessStatus.serviceDisabled,
          );
        }
        return const LocationAccessResult(
          status: LocationAccessStatus.unavailable,
        );
      }

      final current = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return LocationAccessResult(
        status: LocationAccessStatus.granted,
        position: Position(current.longitude, current.latitude),
      );
    } on MissingPluginException {
      return const LocationAccessResult(
        status: LocationAccessStatus.unavailable,
      );
    } catch (_) {
      return const LocationAccessResult(
        status: LocationAccessStatus.unavailable,
      );
    }
  }

  Future<bool> _ensurePermission({bool requestBackground = false}) async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    if (permission == geo.LocationPermission.whileInUse && requestBackground) {
      permission = await geo.Geolocator.requestPermission();
    }

    return permission == geo.LocationPermission.always ||
        permission == geo.LocationPermission.whileInUse;
  }

  static Future<bool> _ensurePermissionStatic() async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }

    return permission == geo.LocationPermission.always ||
        permission == geo.LocationPermission.whileInUse;
  }

  static Future<geo.LocationPermission> requestAlwaysPermission() async {
    try {
      final permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.always) {
        return geo.LocationPermission.always;
      }
      return await geo.Geolocator.requestPermission();
    } catch (e) {
      debugPrint('[Location] Always permission request failed: $e');
      return geo.LocationPermission.denied;
    }
  }

  static Future<bool> hasBackgroundPermission() async {
    final permission = await geo.Geolocator.checkPermission();
    return permission == geo.LocationPermission.always;
  }
}

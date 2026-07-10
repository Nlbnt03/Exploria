import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart' as perm;

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

  factory LocationService({
    Duration pollingInterval = const Duration(seconds: 4),
    Future<bool> Function()? requestDisclosureConsent,
  }) {
    _instance ??= LocationService._internal();
    _instance!._requestDisclosureConsent = requestDisclosureConsent;
    return _instance!;
  }

  LocationService._internal();

  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  StreamSubscription<geo.Position>? _positionSub;
  Future<bool> Function()? _requestDisclosureConsent;
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
  }

  void unregisterConsumer() {
    _activeControllers--;
    if (_activeControllers <= 0) {
      _activeControllers = 0;
      unawaited(stop());
    }
  }

  Future<bool> start({
    bool background = false,
    bool requireBackgroundPermission = false,
  }) async {
    if (_running) return true;

    final hasPermission = await _ensurePermission(
      requestBackground: background || requireBackgroundPermission,
    );
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
    final accuracy =
        _isBackground ? geo.LocationAccuracy.medium : geo.LocationAccuracy.high;
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

  static Future<LocationAccessResult> requestSinglePosition({
    Future<bool> Function()? requestDisclosureConsent,
  }) async {
    try {
      final hasPermission = await _ensurePermissionStatic(
        requestDisclosureConsent: requestDisclosureConsent,
      );
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
      if (!await _confirmDisclosureConsent()) {
        return false;
      }
      permission = await geo.Geolocator.requestPermission();
    }

    if (requestBackground && !await hasBackgroundPermission()) {
      if (!await _confirmDisclosureConsent()) {
        return false;
      }
      final backgroundPermission = await requestAlwaysPermission();
      if (backgroundPermission == geo.LocationPermission.always ||
          await hasBackgroundPermission()) {
        permission = geo.LocationPermission.always;
      }
    }

    final hasForeground =
        permission == geo.LocationPermission.always ||
        permission == geo.LocationPermission.whileInUse;
    if (!hasForeground) return false;
    if (requestBackground) return await hasBackgroundPermission();
    return true;
  }

  static Future<bool> _ensurePermissionStatic({
    Future<bool> Function()? requestDisclosureConsent,
  }) async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      final accepted = await requestDisclosureConsent?.call() ?? true;
      if (!accepted) {
        return false;
      }
      permission = await geo.Geolocator.requestPermission();
    }

    return permission == geo.LocationPermission.always ||
        permission == geo.LocationPermission.whileInUse;
  }

  static Future<geo.LocationPermission> requestAlwaysPermission({
    Future<bool> Function()? requestDisclosureConsent,
  }) async {
    try {
      var permission = await geo.Geolocator.checkPermission();
      if (permission == geo.LocationPermission.always) {
        return geo.LocationPermission.always;
      }
      final accepted = await requestDisclosureConsent?.call() ?? true;
      if (!accepted) {
        return permission;
      }
      if (permission == geo.LocationPermission.denied) {
        permission = await geo.Geolocator.requestPermission();
      }

      if (permission != geo.LocationPermission.always &&
          permission != geo.LocationPermission.whileInUse) {
        return permission;
      }

      if (Platform.isAndroid) {
        final currentStatus = await perm.Permission.locationAlways.status;
        if (currentStatus.isGranted) {
          return geo.LocationPermission.always;
        }

        final requestedStatus = await perm.Permission.locationAlways.request();
        if (requestedStatus.isGranted) {
          return geo.LocationPermission.always;
        }
      } else {
        final requested = await _requestAlwaysOnIos();
        if (requested == geo.LocationPermission.always) {
          return geo.LocationPermission.always;
        }
      }
      return permission;
    } catch (e) {
      debugPrint('[Location] Always permission request failed: $e');
      return geo.LocationPermission.denied;
    }
  }

  static Future<bool> hasBackgroundPermission() async {
    final permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.always) return true;
    if (Platform.isAndroid) {
      final status = await perm.Permission.locationAlways.status;
      return status.isGranted;
    }
    return false;
  }

  Future<bool> _confirmDisclosureConsent() async {
    return await _requestDisclosureConsent?.call() ?? true;
  }

  static Future<geo.LocationPermission> _requestAlwaysOnIos() async {
    try {
      const channel = MethodChannel('kesfedio/location');
      final result = await channel
          .invokeMethod('requestAlwaysAuthorization')
          .timeout(const Duration(seconds: 8));
      if (result == true) {
        return geo.LocationPermission.always;
      }
    } on TimeoutException {
      debugPrint('[Location] iOS always permission request timed out.');
    } catch (e) {
      debugPrint('[Location] iOS always permission request failed: $e');
    }
    return geo.LocationPermission.denied;
  }
}

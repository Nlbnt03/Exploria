import 'dart:async';

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
  LocationService({this.pollingInterval = const Duration(seconds: 4)});

  final Duration pollingInterval;

  final StreamController<Position> _controller =
      StreamController<Position>.broadcast();

  Timer? _timer;
  bool _running = false;

  Stream<Position> get positionStream => _controller.stream;

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

  Future<bool> start() async {
    if (_running) return true;

    final hasPermission = await _ensurePermission();
    if (!hasPermission) return false;

    _running = true;
    await _pollCurrentLocation();
    _timer = Timer.periodic(pollingInterval, (_) => _pollCurrentLocation());
    return true;
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> dispose() async {
    await stop();
    await _controller.close();
  }

  Future<void> _pollCurrentLocation() async {
    if (!_running) return;
    try {
      final current = await geo.Geolocator.getCurrentPosition(
        locationSettings: const geo.LocationSettings(
          accuracy: geo.LocationAccuracy.high,
        ),
      );
      _controller.add(Position(current.longitude, current.latitude));
    } catch (_) {
      // Ignore transient GPS failures, the next tick will retry.
    }
  }

  Future<bool> _ensurePermission() async {
    return _ensurePermissionStatic();
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
}

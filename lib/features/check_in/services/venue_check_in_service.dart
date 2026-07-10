import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/check_in_provider.dart';

class VenueCheckInService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Sabit tolerans 80m + max 40m dinamik hata payı
  static const double baseThreshold = 80.0;
  static const double maxAccuracyAllowance = 40.0;

  // Cached connectivity — subscribe once, avoid platform channel on every check-in.
  static ConnectivityResult? _lastConnectivity;
  static bool _connectivityInitialized = false;

  static void _ensureConnectivityInit() {
    if (_connectivityInitialized) return;
    _connectivityInitialized = true;
    Connectivity().onConnectivityChanged.listen((results) {
      _lastConnectivity =
          results.isNotEmpty ? results.first : ConnectivityResult.none;
    });
    // Seed with initial value (best-effort, may not complete before first check-in).
    Connectivity().checkConnectivity().then((results) {
      _lastConnectivity =
          results.isNotEmpty ? results.first : ConnectivityResult.none;
    });
  }

  Future<CheckInState> processCheckIn({
    required String venueId,
    required String mapId,
    required double venueLat,
    required double venueLng,
    required int xpValue,
    double? userLat,
    double? userLng,
    required Function(double distance) onTooFar,
  }) async {
    final result = await processCheckInDetailed(
      venueId: venueId,
      mapId: mapId,
      venueLat: venueLat,
      venueLng: venueLng,
      xpValue: xpValue,
      userLat: userLat,
      userLng: userLng,
      onTooFar: onTooFar,
    );
    return result.state;
  }

  Future<CheckInResult> processCheckInDetailed({
    required String venueId,
    required String mapId,
    required double venueLat,
    required double venueLng,
    required int xpValue,
    double? userLat,
    double? userLng,
    required Function(double distance) onTooFar,
  }) async {
    try {
      // 1. Offline Kontrol (cached — platform kanalına gitmez)
      _ensureConnectivityInit();
      if (_lastConnectivity == ConnectivityResult.none) {
        return const CheckInResult(state: CheckInState.offline);
      }

      // 2. Mevcut GPS'i al (Eğer userLat/userLng dışarıdan verilmediyse)
      double currentLat = userLat ?? 0.0;
      double currentLng = userLng ?? 0.0;
      double accuracy = 10.0;
      bool isMocked = false;

      if (userLat == null || userLng == null) {
        Position position;
        try {
          position = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              timeLimit: Duration(seconds: 8),
            ),
          );
        } on TimeoutException {
          // iOS'ta ilk GPS fix'i Android'e göre belirgin şekilde yavaş
          // olabiliyor; taze bir son bilinen konum varsa onunla devam et.
          final lastKnown = await Geolocator.getLastKnownPosition();
          if (lastKnown == null) rethrow;
          position = lastKnown;
        }
        currentLat = position.latitude;
        currentLng = position.longitude;
        accuracy = position.accuracy;
        isMocked = position.isMocked;
      }

      // 4. Mesafe Kontrolü (Haversine Formülü)
      final double distance = Geolocator.distanceBetween(
        currentLat,
        currentLng,
        venueLat,
        venueLng,
      );

      final double dynamicThreshold =
          baseThreshold + accuracy.clamp(0.0, maxAccuracyAllowance);

      if (distance > dynamicThreshold) {
        onTooFar(distance);
        return const CheckInResult(state: CheckInState.tooFar);
      }

      // 5. Sunucu Taraflı Hız ve Transaction Kontrolü
      // Kullanıcı oturumu açık değilse hata ver
      if (_auth.currentUser == null) {
        return const CheckInResult(state: CheckInState.error);
      }

      final HttpsCallable callable = _functions.httpsCallable(
        'verifyAndCheckIn',
      );
      final response = await callable.call({
        'venueId': venueId,
        'mapId': mapId,
        'userLat': currentLat,
        'userLng': currentLng,
        'accuracy': accuracy,
        'isMocked': isMocked,
        'distance': distance,
        'xpValue': xpValue,
      });

      // Bulut fonksiyonundan dönen yanıta göre state belirle
      final data = Map<String, dynamic>.from(response.data as Map);
      final status = data['status'];
      if (status == 'success') {
        return CheckInResult(
          state: CheckInState.success,
          mapCompleted: data['mapCompleted'] == true,
          xpEligible: data['xpEligible'] == true,
          alreadyVisited: data['alreadyVisited'] == true,
        );
      } else if (status == 'speed_error') {
        return const CheckInResult(state: CheckInState.speedLimitError);
      } else {
        return const CheckInResult(state: CheckInState.error);
      }
    } catch (e) {
      debugPrint('Gezdim butonu servisinde hata: $e');
      return const CheckInResult(state: CheckInState.error);
    }
  }
}

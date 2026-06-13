import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/check_in_provider.dart';

class VenueCheckInService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Sabit tolerans 80m + max 40m dinamik hata payı
  static const double baseThreshold = 80.0;
  static const double maxAccuracyAllowance = 40.0;

  Future<CheckInState> processCheckIn({
    required String venueId,
    required String mapId,
    required double venueLat,
    required double venueLng,
    double? userLat,
    double? userLng,
    required Function(double distance) onTooFar,
  }) async {
    try {
      // --- GEÇİCİ TEST MODU (DEVRE DIŞI BIRAKILANLAR: Mock, GPS, Mesafe, Sunucu Hız Kontrolü) ---
      // UI ve Animasyonları emülatörde rahatça test edebilmeniz için sadece 800ms bekleyip başarılı döner.
      await Future.delayed(const Duration(milliseconds: 800));
      //return CheckInState.success;
      // ------------------------------------------------------------------------------------------

      // 1. Offline Kontrol
      final connectivityResults = await Connectivity().checkConnectivity();
      if (connectivityResults.contains(ConnectivityResult.none)) {
        return CheckInState.offline;
      }

      // 2. Mevcut GPS'i al (Eğer userLat/userLng dışarıdan verilmediyse)
      double currentLat = userLat ?? 0.0;
      double currentLng = userLng ?? 0.0;
      double accuracy = 10.0;

      if (userLat == null || userLng == null) {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            timeLimit: Duration(seconds: 4),
          ),
        );
        currentLat = position.latitude;
        currentLng = position.longitude;
        accuracy = position.accuracy;
      }

      // 4. Mesafe Kontrolü (Haversine Formülü)
      final double distance = Geolocator.distanceBetween(
        currentLat,
        currentLng,
        venueLat,
        venueLng,
      );

      final double dynamicThreshold = baseThreshold + accuracy.clamp(0.0, maxAccuracyAllowance);

      if (distance > dynamicThreshold) {
        onTooFar(distance);
        return CheckInState.tooFar;
      }

      // 5. Sunucu Taraflı Hız ve Transaction Kontrolü
      // TEST İÇİN DEVRE DIŞI BIRAKILDI: Cloud Function henüz deploy edilmedi.
      /*
      // Kullanıcı oturumu açık değilse hata ver
      if (_auth.currentUser == null) return CheckInState.error;

      final HttpsCallable callable = _functions.httpsCallable('verifyAndCheckIn');
      final response = await callable.call({
        'venueId': venueId,
        'mapId': mapId,
        'userLat': position.latitude,
        'userLng': position.longitude,
        'accuracy': position.accuracy,
        'isMocked': position.isMocked,
        'distance': distance,
      });

      // Bulut fonksiyonundan dönen yanıta göre state belirle
      final status = response.data['status'];
      if (status == 'success') {
        return CheckInState.success;
      } else if (status == 'speed_error') {
        return CheckInState.speedLimitError;
      } else {
        return CheckInState.error;
      }
      */
      return CheckInState.success;
    } catch (e) {
      print('Gezdim butonu servisinde hata: $e');
      return CheckInState.error;
    }
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/venue_check_in_service.dart';

enum CheckInState {
  idle,
  loading,
  success,
  tooFar,
  mocked,
  offline,
  speedLimitError,
  error
}

// Servisimizi Riverpod'la enjekte ediyoruz
final checkInServiceProvider = Provider<VenueCheckInService>((ref) {
  return VenueCheckInService();
});

class CheckInNotifier extends StateNotifier<CheckInState> {
  final VenueCheckInService _service;
  double? lastCalculatedDistance; // Mesafeyi saklamak için

  CheckInNotifier(this._service) : super(CheckInState.idle);

  Future<void> performCheckIn({
    required String venueId,
    required String mapId,
    required double venueLat,
    required double venueLng,
  }) async {
    // 1. Kullanıcıyı Loading durumuna al
    state = CheckInState.loading;
    lastCalculatedDistance = null;

    // 2. Doğrulama servisini çağır
    final result = await _service.processCheckIn(
      venueId: venueId,
      mapId: mapId,
      venueLat: venueLat,
      venueLng: venueLng,
      onTooFar: (dist) {
        // Hesaplanıp fazla çıkan mesafeyi gösterim için saklıyoruz
        lastCalculatedDistance = dist;
      },
    );

    // 3. Sonucu yansıt
    state = result;
  }
  
  void reset() => state = CheckInState.idle;
}

// UI tarafında kullanılacak Provider
final checkInProvider = StateNotifierProvider.autoDispose<CheckInNotifier, CheckInState>((ref) {
  return CheckInNotifier(ref.watch(checkInServiceProvider));
});

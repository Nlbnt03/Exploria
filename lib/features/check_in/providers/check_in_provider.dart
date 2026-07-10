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
  error,
}

class CheckInResult {
  const CheckInResult({
    required this.state,
    this.mapCompleted = false,
    this.xpEligible = false,
    this.alreadyVisited = false,
  });

  final CheckInState state;
  final bool mapCompleted;
  final bool xpEligible;
  final bool alreadyVisited;
}

// Servisimizi Riverpod'la enjekte ediyoruz
final checkInServiceProvider = Provider<VenueCheckInService>((ref) {
  return VenueCheckInService();
});

class CheckInNotifier extends StateNotifier<CheckInState> {
  final VenueCheckInService _service;
  double? lastCalculatedDistance; // Mesafeyi saklamak için
  CheckInResult? lastResult;

  CheckInNotifier(this._service) : super(CheckInState.idle);

  Future<void> performCheckIn({
    required String venueId,
    required String mapId,
    required double venueLat,
    required double venueLng,
    required int xpValue,
    double? userLat,
    double? userLng,
  }) async {
    // 1. Kullanıcıyı Loading durumuna al
    state = CheckInState.loading;
    lastCalculatedDistance = null;
    lastResult = null;

    // 2. Doğrulama servisini çağır
    final result = await _service.processCheckInDetailed(
      venueId: venueId,
      mapId: mapId,
      venueLat: venueLat,
      venueLng: venueLng,
      xpValue: xpValue,
      userLat: userLat,
      userLng: userLng,
      onTooFar: (dist) {
        // Hesaplanıp fazla çıkan mesafeyi gösterim için saklıyoruz
        lastCalculatedDistance = dist;
      },
    );

    // 3. Sonucu yansıt
    lastResult = result;
    state = result.state;
  }

  void reset() {
    lastResult = null;
    state = CheckInState.idle;
  }
}

// UI tarafında kullanılacak Provider
final checkInProvider =
    StateNotifierProvider.autoDispose<CheckInNotifier, CheckInState>((ref) {
      return CheckInNotifier(ref.watch(checkInServiceProvider));
    });

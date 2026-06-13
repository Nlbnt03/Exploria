import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/check_in_provider.dart';

class GezdimButton extends ConsumerWidget {
  final String venueId;
  final String mapId;
  final double venueLat;
  final double venueLng;
  final double? userLat;
  final double? userLng;
  final bool currentVisited;
  final VoidCallback onCheckInSuccess;
  final VoidCallback onCancelVisit;

  const GezdimButton({
    super.key,
    required this.venueId,
    required this.mapId,
    required this.venueLat,
    required this.venueLng,
    this.userLat,
    this.userLng,
    required this.currentVisited,
    required this.onCheckInSuccess,
    required this.onCancelVisit,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkInProvider);
    final notifier = ref.read(checkInProvider.notifier);

    // Başarılı işaretleme anında UI tetikleyicisi (Örn: XP Animasyonu)
    ref.listen(checkInProvider, (previous, next) {
      if (next == CheckInState.success && previous != CheckInState.success) {
        onCheckInSuccess();
      }
    });

    Widget buildButtonContent() {
      if (state == CheckInState.loading) {
        return const SizedBox(
          width: 24, height: 24,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
        );
      }
      
      if (currentVisited || state == CheckInState.success) {
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.undo, color: Colors.white),
            SizedBox(width: 8),
            Text('Gezmedim (İptal Et)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        );
      }

      return const Text('Gezdim ✓', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold));
    }

    Color getButtonColor() {
      if (currentVisited || state == CheckInState.success) return Colors.red.withAlpha(153);
      if (state == CheckInState.offline) return Colors.grey;
      return Theme.of(context).primaryColor;
    }

    void handlePress() {
      if (state == CheckInState.loading || state == CheckInState.offline) return;
      
      if (currentVisited || state == CheckInState.success) {
        onCancelVisit();
        notifier.reset();
        return;
      }
      
      notifier.performCheckIn(
        venueId: venueId,
        mapId: mapId,
        venueLat: venueLat,
        venueLng: venueLng,
        userLat: userLat,
        userLng: userLng,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton(
          onPressed: handlePress,
          style: ElevatedButton.styleFrom(
            backgroundColor: getButtonColor(),
            disabledBackgroundColor: getButtonColor().withAlpha(153),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: buildButtonContent(),
        ),
        
        // Hata ve Durum Mesajları
        if (state == CheckInState.tooFar && notifier.lastCalculatedDistance != null)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Bu mekana ~${notifier.lastCalculatedDistance!.toStringAsFixed(0)}m uzaktasınız.',
              style: const TextStyle(color: Colors.orange, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
        if (state == CheckInState.mocked)
          const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Text(
              'Mock location (Sahte Konum) tespit edildi!',
              style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
        if (state == CheckInState.speedLimitError)
          const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Text(
              'Şüpheli konum değişikliği tespit edildi!',
              style: TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
        if (state == CheckInState.offline)
          const Padding(
            padding: EdgeInsets.only(top: 8.0),
            child: Text(
              'İnternet bağlantısı gerekli.',
              style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

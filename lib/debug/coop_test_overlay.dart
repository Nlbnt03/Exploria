import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Debug-only widget — NEVER rendered in release builds (kDebugMode guard).
///
/// Simulates a second co-op user ("User B") walking around Büyükada:
///   ▶  Start  → adds fake member + presence to the room, starts walking path
///   ⏹  Stop   → cleans up all Firestore entries written by the simulator
///   📍 CheckIn → writes a fake check-in to the room's visits collection
///
/// Usage: add one line to MultiMapScreen's Stack (already done):
///   if (kDebugMode) CoopTestOverlay(roomId: widget.roomId),
class CoopTestOverlay extends StatefulWidget {
  const CoopTestOverlay({super.key, required this.roomId});

  final String roomId;

  @override
  State<CoopTestOverlay> createState() => _CoopTestOverlayState();
}

class _CoopTestOverlayState extends State<CoopTestOverlay> {
  // Sabit test UID — gerçek kullanıcıyla çakışmaması için prefix kullan.
  static const String _simUid = 'sim_user_b__debug';
  static const String _simUsername = '🤖 Sim-B';

  // Büyükada merkez çevresinde yaklaşık bir yürüme rotası.
  // Her adım ~40-60 metre ileri — fog hücrelerini kademeli açar.
  static const List<(double lat, double lng)> _path = [
    (40.8693, 29.1212),
    (40.8700, 29.1220),
    (40.8708, 29.1232),
    (40.8715, 29.1248),
    (40.8720, 29.1265),
    (40.8725, 29.1282),
    (40.8728, 29.1300),
    (40.8724, 29.1318),
    (40.8715, 29.1330),
    (40.8705, 29.1338),
    (40.8694, 29.1332),
    (40.8685, 29.1318),
    (40.8679, 29.1300),
    (40.8680, 29.1280),
    (40.8686, 29.1260),
    (40.8690, 29.1240),
    (40.8693, 29.1212), // geri dön
  ];

  final _db = FirebaseFirestore.instance;

  Timer? _walkTimer;
  int _step = 0;
  bool _running = false;
  bool _expanded = false;
  String _status = 'Hazır';

  // POI'ları check-in için listele (UI'da gösterilecek).
  List<Map<String, dynamic>> _roomPois = [];
  bool _poisLoaded = false;

  @override
  void dispose() {
    _walkTimer?.cancel();
    _cleanupFirestore();
    super.dispose();
  }

  // ─── Firestore helpers ────────────────────────────────────────────────────

  DocumentReference get _roomRef => _db.collection('rooms').doc(widget.roomId);

  Future<void> _setupFirestore() async {
    await _roomRef.collection('members').doc(_simUid).set({
      'uid': _simUid,
      'username': _simUsername,
      'joinedAt': FieldValue.serverTimestamp(),
    });
    await _roomRef.collection('presence').doc(_simUid).set({
      'uid': _simUid,
      'inMap': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _cleanupFirestore() async {
    try {
      await _roomRef.collection('members').doc(_simUid).delete();
      await _roomRef.collection('presence').doc(_simUid).delete();
      await _roomRef.collection('locations').doc(_simUid).delete();
    } catch (_) {}
  }

  Future<void> _writeLocation(double lat, double lng) async {
    await _roomRef.collection('locations').doc(_simUid).set({
      'uid': _simUid,
      'username': _simUsername,
      'lat': lat,
      'lng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // ─── Simulation control ───────────────────────────────────────────────────

  Future<void> _start() async {
    setState(() => _status = 'Başlatılıyor...');
    try {
      await _setupFirestore();
      // İlk konumu hemen yaz.
      final (lat0, lng0) = _path[0];
      await _writeLocation(lat0, lng0);
    } catch (e) {
      setState(() => _status = 'Hata: $e');
      return;
    }

    setState(() {
      _running = true;
      _step = 0;
      _status = 'Yürüyor...';
    });

    _walkTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      _step = (_step + 1) % _path.length;
      final (lat, lng) = _path[_step];
      await _writeLocation(lat, lng);
      if (mounted) {
        setState(() => _status = 'Adım $_step/${_path.length - 1}');
      }
    });
  }

  Future<void> _stop() async {
    _walkTimer?.cancel();
    _walkTimer = null;
    await _cleanupFirestore();
    if (mounted) {
      setState(() {
        _running = false;
        _step = 0;
        _status = 'Durduruldu';
        _poisLoaded = false;
        _roomPois = [];
      });
    }
  }

  /// Sim-B olarak seçilen venueId'ye check-in yapar.
  Future<void> _checkIn(String venueId, int xpValue) async {
    try {
      await _roomRef.collection('visits').doc(venueId).set({
        'venueId': venueId,
        'visitedBy': _simUid,
        'xpValue': xpValue,
        'visitedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _status = '✅ Check-in: $venueId');
    } catch (e) {
      if (mounted) setState(() => _status = '❌ $e');
    }
  }

  Future<void> _loadPois() async {
    if (_poisLoaded) return;
    try {
      final roomSnap = await _roomRef.get();
      final cityId = (roomSnap.data() as Map?)?['cityId'] as String? ?? '';
      if (cityId.isEmpty) return;

      final poisSnap = await _db
          .collection('maps')
          .doc(cityId)
          .collection('pois')
          .limit(20)
          .get(const GetOptions(source: Source.serverAndCache));

      setState(() {
        _roomPois = poisSnap.docs.map((d) {
          final data = d.data();
          return {
            'id': d.id,
            'name': data['name'] ?? d.id,
            'xp': (data['xpValue'] as num?)?.toInt() ?? 50,
          };
        }).toList();
        _poisLoaded = true;
      });
    } catch (_) {}
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return Positioned(
      top: 200,
      right: 8,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Ana buton
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                decoration: BoxDecoration(
                  color: _running
                      ? Colors.red.shade900
                      : const Color(0xFF1A0A2E),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _running ? Colors.red : Colors.deepPurpleAccent,
                    width: 1.5,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x66000000), blurRadius: 10),
                  ],
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _running ? Icons.sensors : Icons.science_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _running ? 'SİM ▼' : 'TEST ▼',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Genişletilmiş panel
            if (_expanded) ...[
              const SizedBox(height: 6),
              Container(
                width: 200,
                decoration: BoxDecoration(
                  color: const Color(0xEE0D0A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurpleAccent, width: 1),
                ),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Co-op Sim',
                      style: TextStyle(
                        color: Colors.deepPurpleAccent.shade100,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _status,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Start / Stop
                    _SimButton(
                      label: _running ? '⏹  Durdur' : '▶  Başlat (Sim-B yürür)',
                      color: _running ? Colors.red.shade700 : Colors.green.shade700,
                      onTap: _running ? _stop : _start,
                    ),
                    if (_running) ...[
                      const SizedBox(height: 6),
                      _SimButton(
                        label: '📍 POI Listesini Yükle',
                        color: Colors.blueGrey.shade700,
                        onTap: _loadPois,
                      ),
                      if (_roomPois.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        const Text(
                          'Sim-B Check-in:',
                          style: TextStyle(color: Colors.white54, fontSize: 10),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 120,
                          child: ListView.separated(
                            itemCount: _roomPois.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 4),
                            itemBuilder: (_, i) {
                              final poi = _roomPois[i];
                              return GestureDetector(
                                onTap: () => _checkIn(
                                  poi['id'] as String,
                                  poi['xp'] as int,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.deepPurple.withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${poi['name']} (+${poi['xp']} XP)',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 6),
                    Text(
                      'Sadece debug modda görünür',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 9,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SimButton extends StatelessWidget {
  const _SimButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// Lint: suppress unused import warning when math is not needed elsewhere.
// ignore: unused_element
double _unused() => math.pi;

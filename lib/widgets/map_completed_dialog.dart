import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../core/theme/app_colors.dart';
import '../features/badges/data/badge_award_service.dart';
import '../features/badges/domain/badge_definitions.dart';
import '../features/badges/presentation/widgets/badge_celebration_dialog.dart';
import '../providers/game_provider.dart';

class MapCompletedDialog extends StatefulWidget {
  final String mapName;
  final String? uid;
  final String? mapId;
  final GameNotifier? gameNotifier;
  final bool isCoop;

  const MapCompletedDialog({
    super.key, 
    required this.mapName,
    this.uid,
    this.mapId,
    this.gameNotifier,
    this.isCoop = false,
  });

  static void show(
    BuildContext context, 
    String mapName, {
    String? uid,
    String? mapId,
    GameNotifier? gameNotifier,
    bool isCoop = false,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'MapCompleted',
      barrierColor: Colors.black.withAlpha(200),
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) {
        return MapCompletedDialog(
          mapName: mapName,
          uid: uid,
          mapId: mapId,
          gameNotifier: gameNotifier,
          isCoop: isCoop,
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: anim1,
            curve: Curves.elasticOut,
          ),
          child: Opacity(
            opacity: anim1.value,
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<MapCompletedDialog> createState() => _MapCompletedDialogState();
}

class _MapCompletedDialogState extends State<MapCompletedDialog> with TickerProviderStateMixin {
  late AnimationController _glowController;
  late AnimationController _badgeController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _badgeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
    
    Future.delayed(const Duration(milliseconds: 400), () async {
      if (mounted) _badgeController.forward();
      
      // BÖLÜM 2 — Rozet Kontrolü (Harita Tamamlandı)
      if (widget.uid != null && widget.gameNotifier != null) {
        final bContext = BadgeCheckContext(
          totalVisited: 0,
          historicBuildingVisited: 0,
          mosqueVisited: 0,
          distinctCitiesVisited: 0,
          coopSessionsCompleted: 0,
          distinctCoopPartners: 0,
          coopMapJustCompleted: widget.isCoop,
          currentStreak: 0,
          allWeeklyQuestsJustCompleted: false,
          visitTime: DateTime.now(),
          recentVisitTimes: [],
          lastVisitedMapId: widget.mapId,
          lastVisitedMapCompletion: 1.0,
        );
        
        final newBadges = await BadgeAwardService().checkAndAwardBadges(
          uid: widget.uid!,
          context: bContext,
          gameNotifier: widget.gameNotifier!,
        );
        
        if (newBadges.isNotEmpty && mounted) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) BadgeCelebrationDialog.show(context, newBadges);
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _glowController.dispose();
    _badgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.fromLTRB(20, 40, 20, 24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withAlpha(50),
                blurRadius: 40,
                spreadRadius: 10,
              ),
            ],
            border: Border.all(
              color: Colors.amber.withAlpha(100),
              width: 2,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Glowing Badge Stack
              SizedBox(
                height: 160,
                width: 160,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _glowController,
                      builder: (context, child) {
                        return Container(
                          width: 120 + (_glowController.value * 20),
                          height: 120 + (_glowController.value * 20),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.amber.withAlpha(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.amber.withAlpha((_glowController.value * 100).toInt()),
                                blurRadius: 30,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    AnimatedBuilder(
                      animation: _badgeController,
                      builder: (context, child) {
                        return Transform.rotate(
                          angle: (1.0 - _badgeController.value) * math.pi,
                          child: Transform.scale(
                            scale: _badgeController.value,
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.amber,
                          gradient: LinearGradient(
                            colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: const Icon(
                          Icons.map_rounded,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Harika İş!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                '${widget.mapName} haritasındaki tüm mekanları keşfettin.',
                style: TextStyle(
                  color: Colors.white.withAlpha(200),
                  fontSize: 16,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'Muhteşem!',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

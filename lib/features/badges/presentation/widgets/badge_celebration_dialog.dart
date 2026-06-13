import 'package:flutter/material.dart';
import 'dart:async';
import '../../domain/badge_definitions.dart';
import '../../data/badge_award_service.dart';
import 'badge_hexagon.dart';
import '../../../../core/theme/app_colors.dart';

class BadgeCelebrationDialog extends StatefulWidget {
  final List<String> badgeIds;

  const BadgeCelebrationDialog({super.key, required this.badgeIds});

  static Future<void> show(BuildContext context, List<String> badgeIds) async {
    if (badgeIds.isEmpty) return;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'BadgeCelebration',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) {
        return BadgeCelebrationDialog(badgeIds: badgeIds);
      },
    );
  }

  @override
  State<BadgeCelebrationDialog> createState() => _BadgeCelebrationDialogState();
}

class _BadgeCelebrationDialogState extends State<BadgeCelebrationDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  Timer? _timer;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _scaleAnimation =
        CurvedAnimation(parent: _controller, curve: Curves.elasticOut);
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _startAnimation();
  }

  void _startAnimation() {
    _controller.forward(from: 0.0);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      _advanceOrClose();
    });
  }

  void _advanceOrClose() {
    _timer?.cancel();
    if (_currentIndex < widget.badgeIds.length - 1) {
      setState(() {
        _currentIndex++;
      });
      _startAnimation();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final badgeId = widget.badgeIds[_currentIndex];
    final badges = BadgeAwardService.cachedBadges ?? [];
    if (badges.isEmpty) return const SizedBox();

    final def = badges.firstWhere((d) => d.id == badgeId,
        orElse: () => badges.first);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _advanceOrClose,
        child: Center(
          child: ScaleTransition(
            scale: _scaleAnimation,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'YENİ ROZET KAZANDIN!',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.0,
                    ),
                  ),
                  const SizedBox(height: 32),
                  HexagonBadge(
                    definition: def,
                    isEarned: true,
                    size: 120.0,
                  ),
                  const SizedBox(height: 32),
                  Text(
                    def.name.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      def.description,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (def.xpReward != null && def.xpReward! > 0) ...[
                    const SizedBox(height: 24),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '+${def.xpReward} XP',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

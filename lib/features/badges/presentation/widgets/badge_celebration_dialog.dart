import 'package:flutter/material.dart';
import 'dart:async';
import '../../data/badge_award_service.dart';
import '../../domain/badge_definitions.dart';
import 'badge_hexagon.dart';
import 'badge_share_sheet.dart';
import '../../../../core/theme/app_colors.dart';

class BadgeCelebrationDialog extends StatefulWidget {
  final List<String> badgeIds;
  final bool showAsPill;

  const BadgeCelebrationDialog({
    super.key,
    required this.badgeIds,
    this.showAsPill = false,
  });

  static Future<void> show(
    BuildContext context,
    List<String> badgeIds, {
    bool showAsPill = false,
  }) async {
    if (badgeIds.isEmpty) return;
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'BadgeCelebration',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, anim1, anim2) {
        return BadgeCelebrationDialog(
          badgeIds: badgeIds,
          showAsPill: showAsPill,
        );
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
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);

    _startAnimation();
  }

  void _startAnimation() {
    _controller.forward(from: 0.0);
    _timer?.cancel();
    if (widget.showAsPill) return;
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

  Widget _buildXpChip(BadgeDefinition def) {
    if (def.xpReward == null || def.xpReward! <= 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.28),
            AppColors.secondary.withValues(alpha: 0.22),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.65)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.22),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Text(
        '+${def.xpReward} XP',
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildShareButton(BadgeDefinition def) {
    return ElevatedButton.icon(
      onPressed: () => BadgeShareSheet.show(context, def),
      icon: const Icon(
        Icons.ios_share_rounded,
        color: Color(0xFFFFD36A),
        size: 22,
      ),
      label: const Text(
        'Paylaş',
        style: TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.transparent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: EdgeInsets.zero,
      ).copyWith(backgroundColor: WidgetStateProperty.all(Colors.transparent)),
    );
  }

  Widget _buildGradientShareButton(BadgeDefinition def) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.36),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: _buildShareButton(def),
    );
  }

  Widget _buildContinueButton() {
    return TextButton(
      onPressed: _advanceOrClose,
      child: Text(
        _currentIndex < widget.badgeIds.length - 1
            ? 'Sonraki Rozet'
            : 'Devam Et',
        style: const TextStyle(
          color: AppColors.textMuted,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildPillCelebrationCard(BadgeDefinition def) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF210832), Color(0xFF10031D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.28),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.16),
            blurRadius: 36,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.22),
              ),
            ),
            child: const Text(
              'YENİ ROZET KAZANDIN!',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 15,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.7,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.045),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: HexagonBadge(
              definition: def,
              isEarned: true,
              size: 68.0,
              imageVariant: BadgeImageVariant.list,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            def.name.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            def.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 17,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 20),
          _buildXpChip(def),
          const SizedBox(height: 24),
          _buildGradientShareButton(def),
          const SizedBox(height: 12),
          _buildContinueButton(),
        ],
      ),
    );
  }

  Widget _buildMedalCelebrationCard(BadgeDefinition def) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 30),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF210832), Color(0xFF10031D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.52),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
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
          const SizedBox(height: 28),
          HexagonBadge(
            definition: def,
            isEarned: true,
            size: 200.0,
            imageVariant: BadgeImageVariant.premium,
          ),
          const SizedBox(height: 28),
          Text(
            def.name.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            def.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 20),
          _buildXpChip(def),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final badgeId = widget.badgeIds[_currentIndex];
    final badges = BadgeAwardService.cachedBadges ?? [];
    if (badges.isEmpty) return const SizedBox();

    final def = badges.firstWhere(
      (d) => d.id == badgeId,
      orElse: () => badges.first,
    );

    final content = Center(
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child:
                  widget.showAsPill
                      ? _buildPillCelebrationCard(def)
                      : _buildMedalCelebrationCard(def),
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body:
          widget.showAsPill
              ? content
              : GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _advanceOrClose,
                child: content,
              ),
    );
  }
}

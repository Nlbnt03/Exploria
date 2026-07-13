import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/suggestion_reward.dart';

class SuggestionApprovedDialog extends StatefulWidget {
  const SuggestionApprovedDialog({super.key, required this.reward});

  final SuggestionReward reward;

  static Future<void> show(BuildContext context, SuggestionReward reward) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'SuggestionApproved',
      barrierColor: Colors.black.withValues(alpha: 0.80),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (ctx, anim1, anim2) =>
          SuggestionApprovedDialog(reward: reward),
      transitionBuilder: (ctx, anim, secondaryAnim, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutBack);
        return Transform.scale(
          scale: 0.85 + (curved.value * 0.15),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
    );
  }

  @override
  State<SuggestionApprovedDialog> createState() =>
      _SuggestionApprovedDialogState();
}

class _SuggestionApprovedDialogState extends State<SuggestionApprovedDialog> {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1040),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            const Text(
              'Mekan Önerin Onaylandı!',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '"${widget.reward.name}" haritaya eklendi',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 20),
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(
                colors: [Color(0xFFFF922B), Color(0xFFFF6EC7)],
              ).createShader(bounds),
              child: Text(
                '+${widget.reward.xp} XP',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 40,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text(
                  'Harika!',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

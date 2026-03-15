import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_provider.dart';
import '../models/user_xp.dart';

class XPCard extends ConsumerWidget {
  const XPCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gameState = ref.watch(gameProvider);

    return gameState.when(
      data: (userXP) {
        return _XPCardContent(userXP: userXP);
      },
      loading: () => const _XPCardSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _XPCardContent extends StatelessWidget {
  final UserXP userXP;

  const _XPCardContent({required this.userXP});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1040),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: userXP.titleColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                userXP.titleEmoji,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: 8),
              Text(
                userXP.titleName,
                style: TextStyle(
                  color: userXP.titleColor,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                '${userXP.currentXP} XP',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: userXP.progressPercentage),
            duration: const Duration(milliseconds: 1200),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: value,
                      minHeight: 10,
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(userXP.titleColor),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (userXP.currentTitle != UserTitle.efsane)
                    Text(
                      'Sonraki unvana ${userXP.xpToNext} XP kaldı',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    )
                  else
                    const Text(
                      'Maksimum seviyeye ulaştın!',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _XPCardSkeleton extends StatelessWidget {
  const _XPCardSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1040),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

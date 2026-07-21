import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/models/daily_exploration.dart';
import 'exploration_share_card.dart';

enum DailyExplorationSummaryAction { share, skip }

class DailyExplorationSummarySheet extends StatelessWidget {
  const DailyExplorationSummarySheet({super.key, required this.exploration});

  final DailyExploration exploration;

  static Future<DailyExplorationSummaryAction> show(
    BuildContext context,
    DailyExploration exploration,
  ) async {
    return await showModalBottomSheet<DailyExplorationSummaryAction>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder:
              (_) => DailyExplorationSummarySheet(exploration: exploration),
        ) ??
        DailyExplorationSummaryAction.skip;
  }

  @override
  Widget build(BuildContext context) {
    final canShare = exploration.sessions.any(
      (session) => session.walkedSegments.isNotEmpty,
    );
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        decoration: const BoxDecoration(
          color: AppColors.bgBottom,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Bugünkü keşfin hazır',
              style: TextStyle(
                color: AppColors.textMain,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                _SummaryValue(
                  value: ExplorationShareFormatting.kilometers(
                    exploration.totalDistanceMeters,
                  ),
                  label: 'Mesafe',
                ),
                _SummaryValue(
                  value: '${exploration.newPlaceCount}',
                  label: 'Yeni yer',
                ),
                _SummaryValue(value: '+${exploration.earnedXp}', label: 'XP'),
                _SummaryValue(
                  value: '${exploration.sessionCount}',
                  label: 'Oturum',
                ),
              ],
            ),
            if (!canShare) ...<Widget>[
              const SizedBox(height: 14),
              const Text(
                'Kart oluşturmak için en az iki geçerli rota noktası gerekiyor.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed:
                  canShare
                      ? () => Navigator.pop(
                        context,
                        DailyExplorationSummaryAction.share,
                      )
                      : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: const Text(
                'Kartı gör ve paylaş',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed:
                  () => Navigator.pop(
                    context,
                    DailyExplorationSummaryAction.skip,
                  ),
              child: const Text(
                'Paylaşmadan çık',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: <Widget>[
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMain,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

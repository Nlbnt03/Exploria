import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/leaderboard_entry.dart';

class LeaderboardCard extends StatelessWidget {
  const LeaderboardCard({
    super.key,
    required this.rank,
    required this.entry,
    this.isCurrentUser = false,
  });

  final int rank;
  final LeaderboardEntry entry;
  final bool isCurrentUser;

  bool get isTop3 => rank <= 3;

  Color get _medalColor {
    switch (rank) {
      case 1:
        return const Color(0xFFFFD700); // Gold
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFCD7F32); // Bronze
      default:
        return AppColors.textMuted;
    }
  }

  String get _medalEmoji {
    switch (rank) {
      case 1:
        return '🥇';
      case 2:
        return '🥈';
      case 3:
        return '🥉';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: EdgeInsets.only(bottom: isTop3 ? 10 : 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? AppColors.primary.withValues(alpha: 0.15)
            : AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrentUser
              ? AppColors.primary.withValues(alpha: 0.7)
              : isTop3
                  ? _medalColor.withValues(alpha: 0.4)
                  : AppColors.inputBorder.withValues(alpha: 0.3),
          width: isCurrentUser ? 1.5 : 1.0,
        ),
        boxShadow: isCurrentUser
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ]
            : isTop3
                ? [
                    BoxShadow(
                      color: _medalColor.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
      ),
      child: Row(
        children: [
          // Rank indicator
          SizedBox(
            width: 36,
            child: isTop3
                ? Text(
                    _medalEmoji,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 22),
                  )
                : Text(
                    '#$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isCurrentUser
                          ? AppColors.primary
                          : AppColors.textMuted,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 10),

          // Avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isTop3
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _medalColor.withValues(alpha: 0.6),
                        _medalColor.withValues(alpha: 0.25),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.primary.withValues(alpha: 0.3),
                        AppColors.secondary.withValues(alpha: 0.15),
                      ],
                    ),
              border: Border.all(
                color: isTop3
                    ? _medalColor.withValues(alpha: 0.5)
                    : AppColors.inputBorder.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                entry.username.isEmpty
                    ? '?'
                    : entry.username[0].toUpperCase(),
                style: TextStyle(
                  color: isTop3 ? _medalColor : AppColors.textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Name & Title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.username.isEmpty ? 'Bilinmiyor' : entry.username,
                  style: TextStyle(
                    color: isCurrentUser
                        ? AppColors.primary
                        : AppColors.textMain,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.title.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.title,
                    style: TextStyle(
                      color: entry.titleColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Weekly XP
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isTop3
                  ? _medalColor.withValues(alpha: 0.12)
                  : AppColors.inputFill.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isTop3
                    ? _medalColor.withValues(alpha: 0.3)
                    : AppColors.inputBorder.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.bolt_rounded,
                  size: 16,
                  color: isTop3 ? _medalColor : AppColors.primary,
                ),
                const SizedBox(width: 3),
                Text(
                  '${entry.weeklyXP}',
                  style: TextStyle(
                    color: isTop3 ? _medalColor : AppColors.textMain,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

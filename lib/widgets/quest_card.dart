import 'package:flutter/material.dart';
import '../models/weekly_quest.dart';

enum QuestCategory {
  kesif('Keşif', Color(0xFF7B2FBE)), // Mor
  sosyal('Sosyal', Color(0xFF1D9E75)), // Yeşil
  ozel('Özel', Color(0xFFEF9F27)); // Amber

  final String label;
  final Color color;
  const QuestCategory(this.label, this.color);
}

class QuestCard extends StatelessWidget {
  final String title;
  final String description;
  final int xpReward;
  final QuestCategory category;
  final WeeklyQuestItem questItem;

  const QuestCard({
    super.key,
    required this.title,
    required this.description,
    required this.xpReward,
    required this.category,
    required this.questItem,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDone = questItem.done;
    final double progress = questItem.progressPercent;
    
    // UI configuration
    final Color bgColor = const Color(0xFF1E1040);
    final Color badgeColor = category.color;

    return Opacity(
      opacity: isDone ? 0.6 : 1.0,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDone ? Colors.white38 : badgeColor.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    category.label,
                    style: TextStyle(
                      color: badgeColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isDone ? Colors.green.withValues(alpha: 0.2) : Colors.white10,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isDone ? '✓ Tamamlandı (+${xpReward}XP)' : '+$xpReward XP',
                    style: TextStyle(
                      color: isDone ? Colors.green : Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                color: isDone ? Colors.white54 : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                decoration: isDone ? TextDecoration.lineThrough : null,
                decorationColor: Colors.white54,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(
                color: isDone ? Colors.white38 : Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 1000),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: value,
                          minHeight: 8,
                          backgroundColor: Colors.white.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isDone ? Colors.green : badgeColor,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${questItem.displayCurrent}/${questItem.target}',
                  style: TextStyle(
                    color: isDone ? Colors.white54 : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

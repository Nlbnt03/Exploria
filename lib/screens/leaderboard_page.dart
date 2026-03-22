import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../models/leaderboard_entry.dart';
import '../providers/leaderboard_provider.dart';
import '../widgets/leaderboard_card.dart';

class LeaderboardPage extends ConsumerStatefulWidget {
  const LeaderboardPage({super.key, this.onAddFriends});

  /// Callback to navigate to the friends tab.
  final VoidCallback? onAddFriends;

  @override
  ConsumerState<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends ConsumerState<LeaderboardPage> {
  Timer? _timer;
  String _timeRemaining = '';

  @override
  void initState() {
    super.initState();
    _updateTime();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _updateTime());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateTime() {
    final now = DateTime.now();
    int daysUntilMonday = 8 - now.weekday;
    if (daysUntilMonday == 8) daysUntilMonday = 1;
    final nextMonday = DateTime(now.year, now.month, now.day)
        .add(Duration(days: daysUntilMonday));
    final diff = nextMonday.difference(now);

    final String timeStr;
    if (diff.inDays > 0) {
      timeStr = '${diff.inDays} gün ${diff.inHours % 24} saat';
    } else {
      timeStr = '${diff.inHours} saat ${diff.inMinutes % 60} dk';
    }

    if (mounted) {
      setState(() => _timeRemaining = timeStr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final leaderboardAsync = ref.watch(leaderboardProvider);
    final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 126),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'Liderlik Tablosu',
            style: TextStyle(
              color: AppColors.textMain,
              fontSize: 32,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Haftalık arkadaş sıralaması',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),

          // Countdown
          _CountdownBanner(timeRemaining: _timeRemaining),
          const SizedBox(height: 16),

          // Content
          leaderboardAsync.when(
            data: (entries) {
              if (entries.isEmpty) {
                return _EmptyState(onAddFriends: widget.onAddFriends);
              }

              // Find current user entry
              LeaderboardEntry? currentUserEntry;
              int? currentUserRank;
              for (var i = 0; i < entries.length; i++) {
                if (entries[i].uid == currentUid) {
                  currentUserEntry = entries[i];
                  currentUserRank = i + 1;
                  break;
                }
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current user summary card
                  if (currentUserEntry != null)
                    _CurrentUserSummary(
                      entry: currentUserEntry,
                      rank: currentUserRank!,
                      totalParticipants: entries.length,
                    ),
                  if (currentUserEntry != null) const SizedBox(height: 20),

                  // Section header
                  Row(
                    children: [
                      const Icon(
                        Icons.people_rounded,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Sıralama (${entries.length} kişi)',
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Leaderboard list
                  ...List.generate(entries.length, (index) {
                    final entry = entries[index];
                    return LeaderboardCard(
                      rank: index + 1,
                      entry: entry,
                      isCurrentUser: entry.uid == currentUid,
                    );
                  }),
                ],
              );
            },
            loading: () => _LoadingSkeleton(),
            error: (error, _) => _ErrorState(error: error),
          ),
        ],
      ),
    );
  }
}

// ─── Countdown Banner ───────────────────────────────────────────────

class _CountdownBanner extends StatelessWidget {
  const _CountdownBanner({required this.timeRemaining});

  final String timeRemaining;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.2),
            AppColors.secondary.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.schedule_rounded,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          const Text(
            'Yenilenmeye kalan:',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            timeRemaining,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Current User Summary ───────────────────────────────────────────

class _CurrentUserSummary extends StatelessWidget {
  const _CurrentUserSummary({
    required this.entry,
    required this.rank,
    required this.totalParticipants,
  });

  final LeaderboardEntry entry;
  final int rank;
  final int totalParticipants;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF7B2FBE), Color(0xFF4A1B8A)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B2FBE).withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // Rank circle
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.15),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    rank <= 3
                        ? ['🥇', '🥈', '🥉'][rank - 1]
                        : '#$rank',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: rank <= 3 ? 24 : 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.username.isEmpty ? 'Sen' : entry.username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.title.isNotEmpty
                          ? entry.title
                          : 'Yolcu',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              // XP display
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.bolt_rounded,
                        color: Colors.amber,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${entry.weeklyXP}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Haftalık XP',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$totalParticipants kişi arasında ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '$rank. sıradasın',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
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

// ─── Empty State ────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.onAddFriends});

  final VoidCallback? onAddFriends;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.inputBorder.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.15),
            ),
            child: const Center(
              child: Icon(
                Icons.people_outline_rounded,
                color: AppColors.primary,
                size: 32,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Henüz arkadaşın yok',
            style: TextStyle(
              color: AppColors.textMain,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Arkadaş ekleyerek liderlik tablosunda\nyarışmaya başla!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton.icon(
                onPressed: onAddFriends,
                icon: const Icon(Icons.person_add_rounded, size: 20),
                label: const Text(
                  'Arkadaş Ekle',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Loading Skeleton ───────────────────────────────────────────────

class _LoadingSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Summary skeleton
        Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.inputBorder.withValues(alpha: 0.2),
            ),
          ),
          child: Center(
            child: CircularProgressIndicator(
              color: AppColors.primary.withValues(alpha: 0.5),
              strokeWidth: 2.5,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Card skeletons
        ...List.generate(5, (index) {
          return Container(
            width: double.infinity,
            height: 66,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.inputBorder.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Container(
                  width: 32,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.inputFill.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.inputFill.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 100,
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.inputFill.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 60,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppColors.inputFill.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 50,
                  height: 28,
                  margin: const EdgeInsets.only(right: 14),
                  decoration: BoxDecoration(
                    color: AppColors.inputFill.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

// ─── Error State ────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.red.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Colors.red,
            size: 36,
          ),
          const SizedBox(height: 12),
          const Text(
            'Liderlik tablosu yüklenemedi',
            style: TextStyle(
              color: AppColors.textMain,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

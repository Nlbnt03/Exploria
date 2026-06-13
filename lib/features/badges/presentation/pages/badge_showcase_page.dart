import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../auth/data/services/badge_service.dart';
import '../../../auth/domain/models/badge.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/badge_definitions.dart';
import '../widgets/badge_hexagon.dart';

class BadgeShowcasePageArgs {
  final String uid;
  final bool isCurrentUser;

  const BadgeShowcasePageArgs({
    required this.uid,
    required this.isCurrentUser,
  });
}

class BadgeShowcasePage extends StatefulWidget {
  final String uid;
  final bool isCurrentUser;

  const BadgeShowcasePage({
    super.key,
    required this.uid,
    required this.isCurrentUser,
  });

  @override
  State<BadgeShowcasePage> createState() => _BadgeShowcasePageState();
}

class _BadgeShowcasePageState extends State<BadgeShowcasePage> {
  final _badgeService = BadgeService();
  List<String> _featuredBadges = [];

  @override
  void initState() {
    super.initState();
    _loadFeaturedBadges();
  }

  Future<void> _loadFeaturedBadges() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
      if (!mounted) return;
      final data = doc.data();
      if (data != null && data.containsKey('featuredBadges')) {
        setState(() {
          _featuredBadges = List<String>.from(data['featuredBadges'] as List);
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleFeatured(String badgeId) async {
    if (!widget.isCurrentUser) return;

    final isCurrentlyFeatured = _featuredBadges.contains(badgeId);
    final newList = List<String>.from(_featuredBadges);

    if (isCurrentlyFeatured) {
      newList.remove(badgeId);
    } else {
      if (newList.length >= 4) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profilinde en fazla 4 rozet sergileyebilirsin.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      newList.add(badgeId);
    }

    setState(() {
      _featuredBadges = newList;
    });

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({'featuredBadges': newList});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rozet sergilenirken bir hata oluştu.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showBadgeDetails(BadgeDefinition def, bool isEarned, DateTime? earnedAt) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final isFeatured = _featuredBadges.contains(def.id);
            return Container(
              decoration: const BoxDecoration(
                color: AppColors.bgBottom,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.textMuted.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),
                  HexagonBadge(
                    definition: def,
                    isEarned: isEarned,
                    size: 96.0,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    (def.isHidden && !isEarned) ? '???' : def.name,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (!def.isHidden || isEarned)
                    Text(
                      def.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 15,
                      ),
                    ),
                  if (def.xpReward != null && def.xpReward! > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '+${def.xpReward} XP',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (isEarned) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.inputBorder.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 16, color: AppColors.textMuted),
                          const SizedBox(width: 8),
                          Text(
                            earnedAt != null
                                ? '${earnedAt.day}.${earnedAt.month}.${earnedAt.year} tarihinde kazanıldı'
                                : 'Kazanıldı',
                            style: const TextStyle(
                                color: AppColors.textMuted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    if (widget.isCurrentUser) ...[
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () async {
                          await _toggleFeatured(def.id);
                          setSheetState(() {});
                          if (mounted) setState(() {});
                        },
                        icon: Icon(
                          isFeatured
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          color: isFeatured ? Colors.amber : Colors.white,
                        ),
                        label: Text(
                          isFeatured ? 'Profilimden Kaldır' : 'Profilimde Sergile',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isFeatured ? AppColors.card : AppColors.primary,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          side: isFeatured
                              ? BorderSide(
                                  color: AppColors.inputBorder
                                      .withValues(alpha: 0.5))
                              : BorderSide.none,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: AppBar(
        title: const Text('Rozetler'),
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textMain,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('badges').where('isActive', isEqualTo: true).snapshots(),
        builder: (context, globalSnap) {
          if (globalSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: AppColors.primary));
          }
          final allBadgeDefs = globalSnap.data?.docs.map((doc) => BadgeDefinition.fromJson(doc.data() as Map<String, dynamic>, doc.id)).toList() ?? <BadgeDefinition>[];

          return StreamBuilder<List<AppBadge>>(
            stream: _badgeService.watchBadges(widget.uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              }

              final earnedList = snapshot.data ?? const <AppBadge>[];
              final earnedIds = earnedList.map((e) => e.id).toSet();

              final earnedDefs = allBadgeDefs.where((d) => earnedIds.contains(d.id)).toList();
              final unearnedDefs = allBadgeDefs.where((d) => !earnedIds.contains(d.id)).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.isCurrentUser) ...[
                  const Text(
                    'Kazanılan rozetlerin arasından 4 tanesini seçerek profilinde sergileyebilirsin.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                ],
                const Row(
                  children: [
                    Icon(
                      Icons.emoji_events_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Kazanılan Rozetler',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (earnedDefs.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Column(
                      children: [
                        Icon(
                          Icons.military_tech_outlined,
                          color: AppColors.textMuted,
                          size: 40,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Henüz rozet kazanılmamış',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Wrap(
                    spacing: 12,
                    runSpacing: 16,
                    children: earnedDefs.map((def) {
                      final earnedDoc =
                          earnedList.firstWhere((e) => e.id == def.id);
                      final isFeatured = _featuredBadges.contains(def.id);
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          HexagonBadge(
                            definition: def,
                            isEarned: true,
                            size: 72.0,
                            onTap: () => _showBadgeDetails(
                                def, true, earnedDoc.earnedAt),
                          ),
                          if (isFeatured)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: AppColors.bgBottom,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.star_rounded,
                                  color: Colors.amber,
                                  size: 16,
                                ),
                              ),
                            ),
                        ],
                      );
                    }).toList(),
                  ),
                if (unearnedDefs.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  const Divider(color: AppColors.inputBorder),
                  const SizedBox(height: 24),
                  const Text(
                    'Kazanılmamış Rozetler',
                    style: TextStyle(
                      color: AppColors.textMain,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 16,
                    children: unearnedDefs.map((def) {
                      return HexagonBadge(
                        definition: def,
                        isEarned: false,
                        size: 72.0,
                        onTap: () => _showBadgeDetails(def, false, null),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          );
            },
          );
        },
      ),
    );
  }
}

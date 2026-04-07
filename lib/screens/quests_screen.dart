import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/game_provider.dart';
import '../widgets/quest_card.dart';

class QuestsScreen extends ConsumerStatefulWidget {
  const QuestsScreen({super.key});

  @override
  ConsumerState<QuestsScreen> createState() => _QuestsScreenState();
}

class _QuestsScreenState extends ConsumerState<QuestsScreen> {
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
    // Next Monday midnight
    int daysUntilMonday = 8 - now.weekday;
    if (daysUntilMonday == 8) daysUntilMonday = 1;
    final nextMonday = DateTime(now.year, now.month, now.day).add(Duration(days: daysUntilMonday));
    final diff = nextMonday.difference(now);

    final String timeStr;
    if (diff.inDays > 0) {
      timeStr = '${diff.inDays} g ${diff.inHours % 24} s';
    } else {
      timeStr = '${diff.inHours} s ${diff.inMinutes % 60} dk';
    }

    if (mounted) {
      setState(() {
        _timeRemaining = timeStr;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final userXPAsync = ref.watch(gameProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Haftalık Görevler',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: userXPAsync.when(
        data: (userXP) {
          final quests = userXP.weeklyQuests;
          
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _XPSummary(
                quests: quests,
                timeRemaining: _timeRemaining,
                titleColor: userXP.titleColor,
              ),
              const SizedBox(height: 24),
              const _SectionHeader(title: 'Keşif Görevleri', icon: Icons.explore),
              const SizedBox(height: 12),
              QuestCard(
                title: 'İlk Adım',
                description: 'Haftanın ilk mekanını keşfet.',
                xpReward: 50,
                category: QuestCategory.kesif,
                questItem: quests.ilkAdim,
              ),
              const SizedBox(height: 10),
              QuestCard(
                title: 'Kaşif Ruhu',
                description: 'Toplamda 5 farklı mekan ziyaret et.',
                xpReward: 100,
                category: QuestCategory.kesif,
                questItem: quests.kasifRuhu,
              ),
              const SizedBox(height: 10),
              QuestCard(
                title: 'Çeşitli Kaşif',
                description: '2 farklı kategorideki (örn: Cami, Müze) mekanları ziyaret et.',
                xpReward: 75,
                category: QuestCategory.kesif,
                questItem: quests.cesitliKasif,
              ),
              const SizedBox(height: 24),
              const _SectionHeader(title: 'Sosyal Görevler', icon: Icons.groups),
              const SizedBox(height: 12),
              QuestCard(
                title: 'Takım Oyuncusu',
                description: 'Bir mekanı Co-op modunda keşfet.',
                xpReward: 100,
                category: QuestCategory.sosyal,
                questItem: quests.takimOyuncusu,
              ),
              const SizedBox(height: 10),
              QuestCard(
                title: 'Takım Kaşifi',
                description: 'Co-op modunda 5 farklı mekanı keşfet.',
                xpReward: 100,
                category: QuestCategory.sosyal,
                questItem: quests.takimKasifi,
              ),
              const SizedBox(height: 24),
              const _SectionHeader(title: 'Haftalık Özel Görevler', icon: Icons.star),
              const SizedBox(height: 12),
              QuestCard(
                title: 'Düzenli Gezgin',
                description: 'Hafta boyunca 3 farklı gün mekan ziyaret et.',
                xpReward: 75,
                category: QuestCategory.ozel,
                questItem: quests.duzenliGezgin,
              ),
              const SizedBox(height: 10),
              QuestCard(
                title: 'Tam Hafta',
                description: 'Hafta boyunca tam 5 farklı gün aktif olup mekan gez.',
                xpReward: 300,
                category: QuestCategory.ozel,
                questItem: quests.tamHafta,
              ),
              const SizedBox(height: 40),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Bir hata oluştu: $error', style: const TextStyle(color: Colors.white))),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  const _SectionHeader({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _XPSummary extends StatelessWidget {
  final dynamic quests;
  final String timeRemaining;
  final Color titleColor;

  const _XPSummary({
    required this.quests,
    required this.timeRemaining,
    required this.titleColor,
  });

  @override
  Widget build(BuildContext context) {
    int maxXP = 50 + 100 + 75 + 100 + 100 + 75 + 300;
    int earnedXP = 0;
    
    if (quests.ilkAdim.done) earnedXP += 50;
    if (quests.kasifRuhu.done) earnedXP += 100;
    if (quests.cesitliKasif.done) earnedXP += 75;
    if (quests.takimOyuncusu.done) earnedXP += 100;
    if (quests.takimKasifi.done) earnedXP += 100;
    if (quests.duzenliGezgin.done) earnedXP += 75;
    if (quests.tamHafta.done) earnedXP += 300;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E1040),
            titleColor.withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: titleColor.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Haftalık XP Özeti',
            style: TextStyle(color: titleColor, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$earnedXP',
                style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w900),
              ),
              const Text(
                ' / ',
                style: TextStyle(color: Colors.white70, fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Text(
                '$maxXP XP',
                style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: earnedXP / maxXP,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(titleColor),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: titleColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.schedule_rounded, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Yenilenmeye Kalan:',
                  style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Text(
                  timeRemaining,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

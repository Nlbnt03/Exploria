import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/weekly_quest_completion.dart';

class QuestCompletedDialog extends StatefulWidget {
  const QuestCompletedDialog({
    super.key,
    required this.info,
    required this.currentWeeklyXP,
    this.onViewQuests,
  });

  final WeeklyQuestCompletionInfo info;
  final int currentWeeklyXP;
  final VoidCallback? onViewQuests;

  static Future<void> show(
    BuildContext context,
    WeeklyQuestCompletionInfo info, {
    required int currentWeeklyXP,
    VoidCallback? onViewQuests,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'QuestCompleted',
      barrierColor: Colors.black.withValues(alpha: 0.80),
      transitionDuration: const Duration(milliseconds: 500),
      pageBuilder: (ctx, anim1, anim2) => QuestCompletedDialog(
        info: info,
        currentWeeklyXP: currentWeeklyXP,
        onViewQuests: onViewQuests,
      ),
    );
  }

  @override
  State<QuestCompletedDialog> createState() => _QuestCompletedDialogState();
}

class _QuestCompletedDialogState extends State<QuestCompletedDialog>
    with TickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final AnimationController _confettiCtrl;
  late final AnimationController _starPulseCtrl;

  late final Animation<double> _scaleAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _starPulse;

  final List<_Piece> _pieces = [];
  static const int _pieceCount = 90;

  @override
  void initState() {
    super.initState();

    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _starPulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnim = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.elasticOut,
    );
    _fadeAnim = CurvedAnimation(
      parent: _entryCtrl,
      curve: Curves.easeIn,
    );
    _starPulse = Tween<double>(begin: 0.92, end: 1.08).animate(
      CurvedAnimation(parent: _starPulseCtrl, curve: Curves.easeInOut),
    );

    _entryCtrl.forward();

    final rng = math.Random();
    for (var i = 0; i < _pieceCount; i++) {
      _pieces.add(_Piece(
        x: rng.nextDouble(),
        startY: -0.15 - rng.nextDouble() * 0.5,
        speed: 0.6 + rng.nextDouble() * 0.8,
        driftX: (rng.nextDouble() - 0.5) * 0.12,
        width: 6 + rng.nextDouble() * 8,
        height: 4 + rng.nextDouble() * 6,
        rotation: rng.nextDouble() * math.pi * 2,
        rotSpeed: (rng.nextDouble() - 0.5) * 8,
        color: _kConfettiColors[rng.nextInt(_kConfettiColors.length)],
      ));
    }
  }

  static const List<Color> _kConfettiColors = [
    Color(0xFFFF6B6B),
    Color(0xFFFFD93D),
    Color(0xFF6BCB77),
    Color(0xFF4D96FF),
    Color(0xFFFF922B),
    Color(0xFFDA77FF),
    Color(0xFFFF6EC7),
    Color(0xFF74C0FC),
  ];

  @override
  void dispose() {
    _entryCtrl.dispose();
    _confettiCtrl.dispose();
    _starPulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final goal = WeeklyQuestCompletionInfo.weeklyXPGoal;
    final progress = (widget.currentWeeklyXP / goal).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Konfeti (ekranın tamamında, tıklamaları geçir)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _confettiCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _ConfettiPainter(
                    pieces: _pieces,
                    progress: _confettiCtrl.value,
                    screenSize: size,
                  ),
                ),
              ),
            ),
          ),

          // Dialog içeriği
          Center(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: ScaleTransition(
                scale: _scaleAnim,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF1E0C35), Color(0xFF0F0620)],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.25),
                            blurRadius: 40,
                            spreadRadius: 4,
                          ),
                          const BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 30,
                            offset: Offset(0, 16),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.fromLTRB(28, 32, 28, 28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Yıldız ikonu
                          AnimatedBuilder(
                            animation: _starPulse,
                            builder: (_, __) => Transform.scale(
                              scale: _starPulse.value,
                              child: Container(
                                width: 80,
                                height: 80,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const RadialGradient(
                                    colors: [
                                      Color(0xFFFFD700),
                                      Color(0xFFFF8C00),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFFFFD700)
                                          .withValues(alpha: 0.55),
                                      blurRadius: 28,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.star_rounded,
                                  color: Colors.white,
                                  size: 44,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Üst etiket
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('★ ',
                                  style: TextStyle(
                                      color: AppColors.primary, fontSize: 13)),
                              Text(
                                'GÖREV TAMAMLANDI',
                                style: TextStyle(
                                  color: AppColors.primary.withValues(
                                      alpha: 0.9),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.0,
                                ),
                              ),
                              const Text(' ★',
                                  style: TextStyle(
                                      color: AppColors.primary, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 10),

                          // Görev adı
                          Text(
                            widget.info.questName,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 18),

                          // XP
                          ShaderMask(
                            shaderCallback: (bounds) =>
                                const LinearGradient(
                              colors: [Color(0xFFFF922B), Color(0xFFFF6EC7)],
                            ).createShader(bounds),
                            child: Text(
                              '+${widget.info.xpReward} XP',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 48,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Açıklama
                          Text(
                            '${widget.info.description} ${widget.info.emoji}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.65),
                              fontSize: 15,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Haftalık progress
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Haftalık hedef',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.55),
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    '${widget.currentWeeklyXP} / $goal XP',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.55),
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 6,
                                  backgroundColor: Colors.white
                                      .withValues(alpha: 0.1),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                    AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 28),

                          // Müthiş butonu
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    AppColors.primary,
                                    AppColors.secondary,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(),
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Text(
                                  'Müthiş!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Görevleri Gör
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                              widget.onViewQuests?.call();
                            },
                            child: Text(
                              'Görevleri Gör →',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
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

// ─── Konfeti parçacığı ────────────────────────────────────────────────────────

class _Piece {
  final double x;
  final double startY;
  final double speed;
  final double driftX;
  final double width;
  final double height;
  final double rotation;
  final double rotSpeed;
  final Color color;

  const _Piece({
    required this.x,
    required this.startY,
    required this.speed,
    required this.driftX,
    required this.width,
    required this.height,
    required this.rotation,
    required this.rotSpeed,
    required this.color,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Piece> pieces;
  final double progress; // 0..1 repeating
  final Size screenSize;

  const _ConfettiPainter({
    required this.pieces,
    required this.progress,
    required this.screenSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in pieces) {
      final y = (p.startY + progress * p.speed) * size.height;
      if (y < -20 || y > size.height + 20) continue;

      final x = (p.x + progress * p.driftX) * size.width;
      final angle = p.rotation + progress * p.rotSpeed;
      final opacity = (1.0 -
              ((y / size.height - 0.8) / 0.2).clamp(0.0, 1.0))
          .clamp(0.0, 1.0);

      paint.color = p.color.withValues(alpha: opacity);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.width,
          height: p.height,
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter old) => old.progress != progress;
}

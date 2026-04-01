import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../auth/domain/models/badge.dart';
import '../../domain/badge_definitions.dart';

class HexagonBadge extends StatelessWidget {
  const HexagonBadge({
    super.key,
    required this.definition,
    this.isEarned = true,
    this.size = 72.0,
    this.onTap,
  });

  final BadgeDefinition definition;
  final bool isEarned;
  final double size;
  final VoidCallback? onTap;

  Widget _buildBadgeIcon(String badgeId, bool isEarned) {
    if (definition.isHidden && !isEarned) {
      return const Text(
        '?',
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white54,
        ),
      );
    }

    String emoji;
    switch (badgeId) {
      case 'first_step': emoji = '👣'; break;
      case 'curious': emoji = '🧭'; break;
      case 'explorer': emoji = '🗺️'; break;
      case 'history_hunter': emoji = '🏛️'; break;
      case 'spiritual': emoji = '🕌'; break;
      case 'multi_city': emoji = '🌍'; break;
      case 'fatih_conqueror': emoji = '⭐'; break;
      case 'legend_explorer': emoji = '👑'; break;
      case 'team_player': emoji = '🤝'; break;
      case 'team_captain': emoji = '👥'; break;
      case 'weekly_leader': emoji = '🏆'; break;
      case 'co_conqueror': emoji = '💫'; break;
      case 'flame': emoji = '🔥'; break;
      case 'unstoppable': emoji = '⚡'; break;
      case 'perfectionist': emoji = '🎯'; break;
      case 'legend_streak': emoji = '💎'; break;
      case 'night_explorer': emoji = '🌙'; break;
      case 'early_bird': emoji = '🌅'; break;
      case 'speed_explorer': emoji = '🚀'; break;
      case 'winter_traveler': emoji = '❄️'; break;
      default: emoji = '🏅';
    }

    return Text(
      emoji,
      style: TextStyle(
        fontSize: size * 0.4,
        color: isEarned ? Colors.white : Colors.white54,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HexagonPainter(
          tier: definition.tier,
          isEarned: isEarned,
        ),
        child: Center(
          child: _buildBadgeIcon(definition.id, isEarned),
        ),
      ),
    );

    if (onTap != null) {
      child = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: child,
      );
    }

    if (!isEarned) {
      child = Opacity(
        opacity: 0.35,
        child: child,
      );
    }

    return child;
  }
}

class _HexagonPainter extends CustomPainter {
  _HexagonPainter({required this.tier, required this.isEarned});

  final BadgeTier tier;
  final bool isEarned;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Use flat-top hexagon (points are at left/right)
    // Angles for flat top: 0, 60, 120, 180, 240, 300 degrees
    // (Wait, standard flat top is 0, 60, etc.)
    final path = Path();
    for (int i = 0; i < 6; i++) {
      // 60 * i degrees. Flat top is when corners start at 0 deg (x=R, y=0) ?
      // Wait, pointy top starts at -90 deg. 
      // Flat top starts at 0 deg.
      final angle = (60 * i) * math.pi / 180;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    final innerPath = Path();
    final innerRadius = radius * 0.75;
    for (int i = 0; i < 6; i++) {
      final angle = (60 * i) * math.pi / 180;
      final x = center.dx + innerRadius * math.cos(angle);
      final y = center.dy + innerRadius * math.sin(angle);
      if (i == 0) {
        innerPath.moveTo(x, y);
      } else {
        innerPath.lineTo(x, y);
      }
    }
    innerPath.close();

    final paintOuter = Paint()..style = PaintingStyle.fill;
    final paintInner = Paint()..style = PaintingStyle.fill;
    final paintStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    if (!isEarned) {
      paintOuter.color = const Color(0xFF3D3848);
      paintInner.color = const Color(0xFF2A2535);
      paintStroke.color = const Color(0xFF5A5268);
    } else {
      switch (tier) {
        case BadgeTier.bronze:
          paintOuter.color = const Color(0xFF3D3840);
          paintInner.color = const Color(0xFF1A1724);
          paintStroke.color = const Color(0xFF7A7285);
          break;
        case BadgeTier.silver:
          paintOuter.shader = const LinearGradient(
            colors: [Color(0xFF7A5210), Color(0xFFC8922A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
          paintInner.color = const Color(0xFF1A1410);
          paintStroke.color = const Color(0xFFE8A83A);
          break;
        case BadgeTier.gold:
          paintOuter.shader = const LinearGradient(
            colors: [Color(0xFF5A2DB8), Color(0xFF9B6DFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
          paintInner.color = const Color(0xFF0E0B1A);
          paintStroke.color = const Color(0xFFB896FF);
          break;
        case BadgeTier.secret:
          paintOuter.shader = const LinearGradient(
            colors: [Color(0xFF8B1A1A), Color(0xFFE84040)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
          paintInner.color = const Color(0xFF130808);
          paintStroke.color = const Color(0xFFFF6464);
          break;
      }
    }

    canvas.drawPath(path, paintOuter);
    canvas.drawPath(innerPath, paintInner);
    canvas.drawPath(path, paintStroke);
  }

  @override
  bool shouldRepaint(covariant _HexagonPainter oldDelegate) {
    return oldDelegate.tier != tier || oldDelegate.isEarned != isEarned;
  }
}

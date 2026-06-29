import 'package:flutter/material.dart';
import 'dart:ui' as ui;

class AnimatedMapPin extends StatefulWidget {
  const AnimatedMapPin({super.key});

  @override
  State<AnimatedMapPin> createState() => _AnimatedMapPinState();
}

class _AnimatedMapPinState extends State<AnimatedMapPin>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _translateY;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Drop from above + bounce
    _translateY = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: -40.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -10.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -10.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 20,
      ),
    ]).animate(_ctrl);

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.6, end: 1.1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.1, end: 0.95),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.95, end: 1.0),
        weight: 20,
      ),
    ]).animate(_ctrl);

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, _translateY.value),
        child: Transform.scale(scale: _scale.value, child: child),
      ),
      child: const _PinGraphic(),
    );
  }
}

class _PinGraphic extends StatelessWidget {
  const _PinGraphic();

  @override
  Widget build(BuildContext context) {
    // 56 × 56 total; tip aligns to the tapped point via Positioned offset
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        children: [
          // Drop shadow
          Positioned(
            bottom: 0,
            left: 8,
            right: 8,
            child: Container(
              height: 6,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
          // Pin body
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SizedBox(
              width: 56,
              height: 50,
              child: CustomPaint(
                painter: _PinPainter(),
              ),
            ),
          ),
          // White inner circle
          Positioned(
            top: 10,
            left: 15,
            right: 15,
            child: Container(
              height: 26,
              width: 26,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinPainter extends CustomPainter {
  const _PinPainter();
  static const _pink = Color(0xFFE91E8C);

  @override
  void paint(Canvas canvas, ui.Size size) {
    final paint = Paint()..color = _pink;

    // Circle (head)
    final cx = size.width / 2;
    const cy = 20.0;
    const r = 20.0;
    canvas.drawCircle(Offset(cx, cy), r, paint);

    // Triangle (tail)
    final path = Path()
      ..moveTo(cx - 12, cy + 12)
      ..lineTo(cx, size.height)
      ..lineTo(cx + 12, cy + 12)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

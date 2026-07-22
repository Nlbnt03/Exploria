import 'dart:typed_data';

import 'package:flutter/material.dart';

/// A single stat cell in the bottom row of a [StoryShareCard] (value + label).
class ShareCardStat {
  const ShareCardStat({required this.value, required this.label});

  final String value;
  final String label;
}

/// Generic "story card" layout shared by every mode's share card (daily
/// exploration, free walk, ...), laid out on a fixed 360×640 design canvas.
/// [mapSnapshot] is a self-contained Mapbox Snapshotter image; this widget
/// only places that image in the card's map panel — it never redraws the
/// route itself. Callers supply already-formatted strings so this widget has
/// no knowledge of any particular mode's domain model.
class StoryShareCard extends StatelessWidget {
  const StoryShareCard({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.dateLabel,
    required this.mapSnapshot,
    required this.hasRoute,
    required this.heroValue,
    required this.heroUnit,
    required this.heroCaption,
    required this.stats,
    this.pillText,
    this.pillIcon = Icons.hub_outlined,
    this.noRouteMessage = 'Rota oluşturmak için biraz daha keşfet',
    this.backgroundColor = _bg,
  }) : assert(stats.length == 3);

  static const Size logicalSize = Size(360, 640);

  final String eyebrow;
  final String title;
  final String dateLabel;
  final Uint8List mapSnapshot;
  final bool hasRoute;
  final String heroValue;
  final String heroUnit;
  final String heroCaption;
  final List<ShareCardStat> stats;
  final String? pillText;
  final IconData pillIcon;
  final String noRouteMessage;
  final Color backgroundColor;

  static const _bg = Color(0xFFFAF7F1);
  static const _textMain = Color(0xFF10172F);
  static const _statLabel = Color(0xFF777582);
  static const _footerMuted = Color(0xFF75727D);
  static const _pink = Color(0xFFFF176B);
  static const _orange = Color(0xFFFF704D);

  static const _brandGradient = LinearGradient(colors: <Color>[_pink, _orange]);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: logicalSize.width,
      height: logicalSize.height,
      child: ColoredBox(
        color: backgroundColor,
        child: Stack(
          children: <Widget>[
            Positioned(
              left: 20,
              right: 20,
              top: 19,
              height: 25,
              child: Row(
                children: <Widget>[
                  Image.asset('assets/logo.png', width: 24, height: 24),
                  const SizedBox(width: 7),
                  const Text(
                    'Keşfedio',
                    style: TextStyle(
                      color: _textMain,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: _footerMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              top: 66,
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback:
                    (bounds) => _brandGradient.createShader(bounds),
                child: Text(
                  eyebrow,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              top: 86,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _textMain,
                  fontSize: 40,
                  height: 1.0,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.8,
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              top: 126,
              height: 255,
              child: _MapPanel(mapSnapshot: mapSnapshot),
            ),
            if (hasRoute && pillText != null)
              Positioned(
                left: 0,
                right: 0,
                top: 390,
                height: 34,
                child: Center(
                  child: _Pill(icon: pillIcon, text: pillText!),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: 429,
              child:
                  hasRoute
                      ? _HeroBlock(
                        value: heroValue,
                        unit: heroUnit,
                        caption: heroCaption,
                      )
                      : SizedBox(
                        height: 94,
                        child: _NoRouteMessage(message: noRouteMessage),
                      ),
            ),
            Positioned(
              left: 20,
              right: 20,
              top: 535,
              height: 56,
              child: Row(
                children: <Widget>[
                  for (final entry in stats.indexed) ...<Widget>[
                    if (entry.$1 > 0) const _StatDivider(),
                    Expanded(
                      child: _Stat(
                        value: entry.$2.value,
                        label: entry.$2.label,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Positioned(
              left: 0,
              right: 0,
              top: 612,
              child: Center(child: _Footer()),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({required this.mapSnapshot});

  final Uint8List mapSnapshot;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.memory(
        mapSnapshot,
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(1.2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: StoryShareCard._brandGradient,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Container(
        height: 34 - 2.4,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFCF7),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 13, color: StoryShareCard._orange),
            const SizedBox(width: 6),
            Text(
              text,
              style: const TextStyle(
                color: StoryShareCard._textMain,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroBlock extends StatelessWidget {
  const _HeroBlock({
    required this.value,
    required this.unit,
    required this.caption,
  });

  final String value;
  final String unit;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            ShaderMask(
              blendMode: BlendMode.srcIn,
              shaderCallback:
                  (bounds) => StoryShareCard._brandGradient.createShader(bounds),
              child: Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 70,
                  height: 0.9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              unit,
              style: const TextStyle(
                color: StoryShareCard._textMain,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          caption,
          style: const TextStyle(
            color: StoryShareCard._textMain,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _NoRouteMessage extends StatelessWidget {
  const _NoRouteMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: StoryShareCard._textMain,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFD7D3CC),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: StoryShareCard._textMain,
              fontSize: 24,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            color: StoryShareCard._statLabel,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: const TextStyle(
          color: StoryShareCard._footerMuted,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        children: const <InlineSpan>[
          TextSpan(text: 'Sisi dağıt, şehri keşfet · '),
          TextSpan(
            text: 'keşfedio',
            style: TextStyle(
              color: StoryShareCard._pink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../widgets/story_share_card.dart';
import '../../domain/models/daily_exploration.dart';

class ExplorationShareFormatting {
  const ExplorationShareFormatting._();

  static String kilometers(double meters, {bool includeUnit = true}) {
    final value = (meters / 1000).toStringAsFixed(1).replaceAll('.', ',');
    return includeUnit ? '$value km' : value;
  }

  static String duration(int seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '$minutes dk';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours sa' : '$hours sa $rest dk';
  }

  static String date(DateTime value) {
    const months = <String>[
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    const weekdays = <String>[
      'Pazartesi',
      'Salı',
      'Çarşamba',
      'Perşembe',
      'Cuma',
      'Cumartesi',
      'Pazar',
    ];
    final local = value.toLocal();
    return '${local.day} ${months[local.month - 1]} ${local.year} · '
        '${weekdays[local.weekday - 1]}';
  }
}

/// "İl · İlçe Haritası" -> small eyebrow "BUGÜNÜN KEŞFİ · İL" plus a short
/// main title ("İlçe", "Haritası" suffix dropped).
class _MapNameParts {
  const _MapNameParts({required this.eyebrow, required this.title});

  final String eyebrow;
  final String title;

  static final _mapSuffix = RegExp(r'\s*[Hh]arita(sı)?$');

  factory _MapNameParts.parse(String mapName) {
    final segments =
        mapName
            .split('·')
            .map((segment) => segment.trim())
            .where((segment) => segment.isNotEmpty)
            .toList();
    if (segments.length >= 2) {
      final city = segments.first;
      final district = segments[1].replaceAll(_mapSuffix, '').trim();
      return _MapNameParts(
        eyebrow: 'BUGÜNÜN KEŞFİ · ${city.toUpperCase()}',
        title: district.isEmpty ? segments[1] : district,
      );
    }
    final cleaned = mapName.replaceAll(_mapSuffix, '').trim();
    return _MapNameParts(
      eyebrow: 'BUGÜNÜN KEŞFİ',
      title: cleaned.isEmpty ? mapName : cleaned,
    );
  }
}

/// A single-composition "story card" summarizing one day's exploration, laid
/// out on a fixed 360×640 design canvas. [mapSnapshot] is a self-contained
/// Mapbox Snapshotter image; this widget only places that image in the
/// card's map panel — it never redraws the route itself.
class ExplorationShareCard extends StatelessWidget {
  const ExplorationShareCard({
    super.key,
    required this.exploration,
    required this.mapSnapshot,
  });

  static const Size logicalSize = StoryShareCard.logicalSize;

  final DailyExploration exploration;
  final Uint8List mapSnapshot;

  bool get _hasRoute => exploration.allPoints.length >= 2;

  @override
  Widget build(BuildContext context) {
    final parts = _MapNameParts.parse(exploration.mapName);
    final sessionCount =
        exploration.sessionCount < 1 ? 1 : exploration.sessionCount;
    return StoryShareCard(
      eyebrow: parts.eyebrow,
      title: parts.title,
      dateLabel: ExplorationShareFormatting.date(exploration.date),
      mapSnapshot: mapSnapshot,
      hasRoute: _hasRoute,
      heroValue: ExplorationShareFormatting.kilometers(
        exploration.totalDistanceMeters,
        includeUnit: false,
      ),
      heroUnit: 'km',
      heroCaption: 'yürüdün',
      pillText: '$sessionCount OTURUM · TEK GÜNLÜK ROTA',
      stats: <ShareCardStat>[
        ShareCardStat(value: '${exploration.newPlaceCount}', label: 'yeni yer'),
        ShareCardStat(value: '+${exploration.earnedXp}', label: 'XP'),
        ShareCardStat(
          value: ExplorationShareFormatting.duration(
            exploration.totalDurationSeconds,
          ),
          label: 'keşif süresi',
        ),
      ],
    );
  }
}

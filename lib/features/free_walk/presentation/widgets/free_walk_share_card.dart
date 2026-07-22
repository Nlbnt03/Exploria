import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../widgets/story_share_card.dart';
import '../../../daily_exploration/presentation/widgets/exploration_share_card.dart';
import '../../domain/models/free_walk_result.dart';

class FreeWalkShareFormatting {
  const FreeWalkShareFormatting._();

  static const List<String> _months = <String>[
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

  static String shortDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day} ${_months[local.month - 1]}';
  }

  static String startTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  static String pace(double distanceMeters, int durationSeconds) {
    if (distanceMeters < 50) return "--'--\"";
    final secondsPerKm = durationSeconds / (distanceMeters / 1000);
    final minutes = secondsPerKm ~/ 60;
    final seconds = (secondsPerKm.round() % 60).toString().padLeft(2, '0');
    return "$minutes'$seconds\"";
  }
}

/// The free-walk equivalent of [ExplorationShareCard]: same 360×640 story
/// card design (via [StoryShareCard]), with stats appropriate to a walk that
/// has no map, XP, or discovered places — just a route, a duration and a
/// pace.
class FreeWalkShareCard extends StatelessWidget {
  const FreeWalkShareCard({
    super.key,
    required this.result,
    required this.mapSnapshot,
  });

  static const Size logicalSize = StoryShareCard.logicalSize;

  final FreeWalkResult result;
  final Uint8List mapSnapshot;

  @override
  Widget build(BuildContext context) {
    final segmentCount = result.segmentCount < 1 ? 1 : result.segmentCount;
    return StoryShareCard(
      backgroundColor: Colors.white,
      eyebrow: 'SERBEST YÜRÜYÜŞ',
      title: FreeWalkShareFormatting.shortDate(result.startedAt),
      dateLabel: ExplorationShareFormatting.date(result.startedAt),
      mapSnapshot: mapSnapshot,
      hasRoute: result.hasRoute,
      heroValue: ExplorationShareFormatting.kilometers(
        result.distanceMeters,
        includeUnit: false,
      ),
      heroUnit: 'km',
      heroCaption: 'yürüdün',
      pillText:
          segmentCount <= 1
              ? 'SERBEST ROTA'
              : '$segmentCount DURAKLI · SERBEST ROTA',
      noRouteMessage: 'Rota oluşturmak için biraz daha yürü',
      stats: <ShareCardStat>[
        ShareCardStat(
          value: ExplorationShareFormatting.duration(result.durationSeconds),
          label: 'süre',
        ),
        ShareCardStat(
          value: FreeWalkShareFormatting.pace(
            result.distanceMeters,
            result.durationSeconds,
          ),
          label: 'tempo /km',
        ),
        ShareCardStat(
          value: FreeWalkShareFormatting.startTime(result.startedAt),
          label: 'başlangıç',
        ),
      ],
    );
  }
}

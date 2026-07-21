import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../domain/models/daily_exploration.dart';
import '../../presentation/widgets/exploration_share_card.dart';

class ExplorationShareService {
  const ExplorationShareService();

  Future<ShareResult> share({
    required BuildContext context,
    required DailyExploration exploration,
    required Uint8List pngBytes,
  }) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin =
        renderBox == null
            ? null
            : renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final safeMapId = exploration.mapId.replaceAll(
      RegExp(r'[^a-zA-Z0-9_-]'),
      '-',
    );
    final fileName = 'kesfedio-$safeMapId-${exploration.dayKey}.png';
    final distance = ExplorationShareFormatting.kilometers(
      exploration.totalDistanceMeters,
      includeUnit: false,
    );
    final text =
        'Bugün ${exploration.mapName} haritasında $distance km yürüdüm ve '
        '${exploration.newPlaceCount} yeni yer keşfettim! #Keşfedio';

    return Share.shareXFiles(
      <XFile>[XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName)],
      text: text,
      subject: 'Keşfedio • Bugünün keşfi',
      sharePositionOrigin: origin,
      fileNameOverrides: <String>[fileName],
    );
  }
}

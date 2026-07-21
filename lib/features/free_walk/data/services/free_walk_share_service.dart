import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../daily_exploration/presentation/widgets/exploration_share_card.dart';
import '../../domain/models/free_walk_result.dart';

class FreeWalkShareService {
  const FreeWalkShareService();

  Future<ShareResult> share({
    required BuildContext context,
    required FreeWalkResult result,
    required Uint8List pngBytes,
  }) async {
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin =
        renderBox == null
            ? null
            : renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final fileName = 'kesfedio-serbest-yuruyus-${result.id}.png';
    final distance = ExplorationShareFormatting.kilometers(
      result.distanceMeters,
      includeUnit: false,
    );
    final text =
        'Serbest yürüyüşte $distance km yürüdüm! #Keşfedio';

    return Share.shareXFiles(
      <XFile>[XFile.fromData(pngBytes, mimeType: 'image/png', name: fileName)],
      text: text,
      subject: 'Keşfedio • Serbest yürüyüş',
      sharePositionOrigin: origin,
      fileNameOverrides: <String>[fileName],
    );
  }
}

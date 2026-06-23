import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';

import '../domain/badge_definitions.dart';

class BadgeShareService {
  const BadgeShareService();

  Future<void> share(BuildContext context, BadgeDefinition definition) async {
    final imageUrl = definition.socialCardImageUrl;
    if (imageUrl == null) {
      throw StateError('Bu rozet için sosyal paylaşım kartı bulunamadı.');
    }

    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Sosyal paylaşım kartı indirilemedi.');
    }

    if (!context.mounted) return;
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin =
        renderBox == null
            ? null
            : renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final mimeType =
        response.headers['content-type']?.split(';').first.trim() ??
        'image/png';
    final extension = switch (mimeType) {
      'image/jpeg' => 'jpg',
      'image/webp' => 'webp',
      _ => 'png',
    };
    final fileName = 'kesfedio-${definition.id}.$extension';

    await Share.shareXFiles(
      [XFile.fromData(response.bodyBytes, mimeType: mimeType, name: fileName)],
      text: '${definition.name} rozetini Keşfedio’da kazandım!',
      subject: 'Keşfedio • ${definition.name}',
      sharePositionOrigin: origin,
      fileNameOverrides: [fileName],
    );
  }
}

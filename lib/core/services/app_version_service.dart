import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ForceUpdateInfo {
  const ForceUpdateInfo({
    required this.title,
    required this.message,
    required this.storeUrl,
    required this.currentBuildNumber,
    required this.minimumBuildNumber,
  });

  final String title;
  final String message;
  final String storeUrl;
  final int currentBuildNumber;
  final int minimumBuildNumber;
}

class AppVersionService {
  AppVersionService._();

  static final AppVersionService instance = AppVersionService._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<ForceUpdateInfo?> checkForRequiredUpdate() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

    final versionRef = _firestore.collection('appConfig').doc('version');
    DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await versionRef
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 2));
    } on TimeoutException {
      try {
        snapshot = await versionRef.get(const GetOptions(source: Source.cache));
      } catch (_) {
        return null;
      }
    } on FirebaseException {
      try {
        snapshot = await versionRef.get(const GetOptions(source: Source.cache));
      } catch (_) {
        return null;
      }
    }
    final data = snapshot.data();
    if (data == null) return null;

    final isIos = defaultTargetPlatform == TargetPlatform.iOS;
    final minimumBuildNumber =
        isIos
            ? _readInt(data['minBuildNumberIos'])
            : _readInt(data['minBuildNumberAndroid']);

    if (minimumBuildNumber <= 0 || currentBuildNumber >= minimumBuildNumber) {
      return null;
    }

    final storeUrl =
        isIos
            ? _readString(data['appStoreUrl'])
            : _readString(data['playStoreUrl']);

    return ForceUpdateInfo(
      title: _readString(
        data['forceUpdateTitle'],
        fallback: 'Güncelleme gerekli',
      ),
      message: _readString(
        data['forceUpdateMessage'],
        fallback:
            'Keşfedio\'yu kullanmaya devam etmek için lütfen son sürüme güncelleyin.',
      ),
      storeUrl: storeUrl,
      currentBuildNumber: currentBuildNumber,
      minimumBuildNumber: minimumBuildNumber,
    );
  }

  int _readInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _readString(Object? value, {String fallback = ''}) {
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return fallback;
  }
}

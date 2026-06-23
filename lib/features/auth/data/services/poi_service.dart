import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PoiService {
  final FirebaseFirestore _firestore;

  PoiService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Bir kerelik kullanilacak, lokal JSON listesini Firestore'a tasiyan arac.
  Future<void> migrateLocalPoisToFirestore() async {
    final areaJsonMap = {
      'istanbul_fatih': 'assets/fatih_pois.json',
      'istanbul_beyoglu': 'assets/beyoglu_pois.json',
      'istanbul_uskudar': 'assets/uskudar_pois.json',
      'istanbul_kadikoy': 'assets/kadikoy_pois.json',
      'ankara_merkez': 'assets/ankara_pois.json',
      'gebze_teknik': 'assets/gebze_teknik_pois.json',
    };

    final batch = _firestore.batch();
    int totalPoisMigrated = 0;

    for (final entry in areaJsonMap.entries) {
      final cityId = entry.key;
      final assetPath = entry.value;

      try {
        final rawJson = await rootBundle.loadString(assetPath);
        final decoded = jsonDecode(rawJson) as Map<String, dynamic>;

        // Fatih vb jsonlarda genelde 'mekanlar' keyi olur. Bazen 'places'.
        final List<dynamic> rawList =
            decoded['mekanlar'] ?? decoded['places'] ?? [];

        for (final rawPoi in rawList) {
          final poiMap = rawPoi as Map<String, dynamic>;
          final originalIdStr = poiMap['id'].toString();
          final docId = '${cityId}_$originalIdStr';

          final docRef = _firestore
              .collection('maps')
              .doc(cityId)
              .collection('pois')
              .doc(docId);

          // Mevcut POI'ye cityId ekle ve id'nin string olmasini garanti et
          final dataToSave =
              Map<String, dynamic>.from(poiMap)
                ..['cityId'] = cityId
                ..['id'] = originalIdStr;

          batch.set(docRef, dataToSave, SetOptions(merge: true));
          totalPoisMigrated++;
        }
      } catch (e) {
        debugPrint('Error migrating $cityId ($assetPath): $e');
      }
    }

    try {
      await batch.commit();
      debugPrint('Migration basarili. Toplam $totalPoisMigrated POI tasindi.');
    } catch (e) {
      debugPrint('Migration commit hatasi: $e');
    }
  }

  /// Belirli bir sehir (area) icin POI verilerini Firestore'dan ceker.
  Future<List<Map<String, dynamic>>> getPoisForCity(String cityId) async {
    try {
      final pois = _firestore.collection('maps').doc(cityId).collection('pois');
      QuerySnapshot<Map<String, dynamic>> snapshot;
      try {
        snapshot = await pois
            .where('isActive', isEqualTo: true)
            .orderBy('order')
            .get(const GetOptions(source: Source.serverAndCache));
      } on FirebaseException catch (error) {
        if (error.code != 'failed-precondition') rethrow;
        snapshot = await pois
            .where('isActive', isEqualTo: true)
            .get(const GetOptions(source: Source.serverAndCache));
      }

      // Fallback: if isActive filter returns nothing (field not set on documents),
      // fetch all POIs so maps migrated without isActive still render correctly.
      if (snapshot.docs.isEmpty) {
        snapshot = await pois.get(
          const GetOptions(source: Source.serverAndCache),
        );
      }

      final results =
          snapshot.docs
              .map((doc) => <String, dynamic>{'id': doc.id, ...doc.data()})
              .toList();
      results.sort(
        (a, b) => ((a['order'] as num?)?.toInt() ?? 0).compareTo(
          (b['order'] as num?)?.toInt() ?? 0,
        ),
      );
      return results;
    } catch (e) {
      debugPrint('Error fetching POIs for $cityId from Firestore: $e');
      return [];
    }
  }
}

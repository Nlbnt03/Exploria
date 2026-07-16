import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/data/services/poi_service.dart';
import '../../auth/domain/models/user_map_record.dart';
import '../models/passport_models.dart';

class PassportService {
  PassportService({FirebaseFirestore? firestore, PoiService? poiService})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _poiService = poiService ?? PoiService();

  final FirebaseFirestore _firestore;
  final PoiService _poiService;
  final Map<String, Future<_AreaCatalog>> _catalogLoads =
      <String, Future<_AreaCatalog>>{};

  Future<PassportCollection> buildCollection({
    required String uid,
    required List<UserMapRecord> records,
  }) async {
    if (uid.isEmpty || records.isEmpty) {
      return const PassportCollection(pages: <PassportRegionPage>[]);
    }

    final checkIns = await _loadCheckIns(uid);
    final byArea = <String, List<UserMapRecord>>{};
    for (final record in records) {
      (byArea[record.areaId] ??= <UserMapRecord>[]).add(record);
    }

    final pages = await Future.wait(
      byArea.entries.map(
        (entry) => _buildRegionPage(
          areaId: entry.key,
          records: entry.value,
          checkIns: checkIns,
        ),
      ),
    );
    pages.sort((a, b) => a.firstStartedAt.compareTo(b.firstStartedAt));
    return PassportCollection(pages: pages);
  }

  Future<PassportRegionPage> _buildRegionPage({
    required String areaId,
    required List<UserMapRecord> records,
    required List<_PassportCheckIn> checkIns,
  }) async {
    final catalog = await _loadAreaCatalog(areaId, records);
    final mapIds = records.map((record) => record.mapId).toSet();
    final visitedIds = <String>{
      for (final record in records) ...record.state.visitedPoiIds,
    };
    final visitDateByPoi = <String, DateTime>{};
    for (final checkIn in checkIns) {
      if (!visitedIds.contains(checkIn.venueId)) continue;
      if (checkIn.mapId.isNotEmpty && !mapIds.contains(checkIn.mapId)) {
        continue;
      }
      final existing = visitDateByPoi[checkIn.venueId];
      if (existing == null || checkIn.markedAt.isBefore(existing)) {
        visitDateByPoi[checkIn.venueId] = checkIn.markedAt;
      }
    }

    final fallbackVisitDate = records
        .map(
          (record) =>
              record.completedAt ?? record.updatedAt ?? record.createdAt,
        )
        .whereType<DateTime>()
        .fold<DateTime?>(
          null,
          (latest, date) =>
              latest == null || date.isAfter(latest) ? date : latest,
        );

    final slots = <PassportStampSlot>[];
    final catalogIds = <String>{};
    for (final poi in catalog.pois) {
      catalogIds.add(poi.id);
      slots.add(
        PassportStampSlot(
          poiId: poi.id,
          poiName: poi.name,
          category: PassportPoiCategory.fromRaw(poi.category),
          visitedAt:
              visitedIds.contains(poi.id)
                  ? visitDateByPoi[poi.id] ??
                      fallbackVisitDate ??
                      DateTime.now()
                  : null,
        ),
      );
    }

    for (final unknownVisitedId in visitedIds.difference(catalogIds)) {
      slots.add(
        PassportStampSlot(
          poiId: unknownVisitedId,
          poiName: 'Keşfedilen Mekan',
          category: PassportPoiCategory.other,
          visitedAt:
              visitDateByPoi[unknownVisitedId] ??
              fallbackVisitDate ??
              DateTime.now(),
        ),
      );
    }

    final recordTotal = records.fold<int>(
      0,
      (maximum, record) =>
          record.totalPois > maximum ? record.totalPois : maximum,
    );
    final totalPoiCount = <int>[
      catalog.pois.length,
      recordTotal,
      visitedIds.length,
    ].reduce((a, b) => a > b ? a : b);
    while (slots.length < totalPoiCount) {
      final index = slots.length + 1;
      slots.add(
        PassportStampSlot(
          poiId: 'empty-$areaId-$index',
          poiName: 'Keşfedilmemiş Mekan',
          category: PassportPoiCategory.other,
        ),
      );
    }

    final startedDates =
        records
            .map((record) => record.createdAt ?? record.updatedAt)
            .whereType<DateTime>();
    final firstStartedAt = startedDates.fold<DateTime?>(
      null,
      (earliest, date) =>
          earliest == null || date.isBefore(earliest) ? date : earliest,
    );
    final completionDates =
        records
            .where((record) => record.isCompleted)
            .map((record) => record.completedAt ?? record.updatedAt)
            .whereType<DateTime>();
    final completedAt = completionDates.fold<DateTime?>(
      null,
      (latest, date) => latest == null || date.isAfter(latest) ? date : latest,
    );

    return PassportRegionPage(
      areaId: areaId,
      regionName: catalog.name,
      colorHex: catalog.colorHex,
      totalPoiCount: totalPoiCount,
      slots: slots,
      firstStartedAt: firstStartedAt ?? DateTime.now(),
      completedAt: completedAt,
    );
  }

  Future<_AreaCatalog> _loadAreaCatalog(
    String areaId,
    List<UserMapRecord> records,
  ) {
    return _catalogLoads.putIfAbsent(
      areaId,
      () => _fetchAreaCatalog(areaId, records),
    );
  }

  Future<_AreaCatalog> _fetchAreaCatalog(
    String areaId,
    List<UserMapRecord> records,
  ) async {
    Map<String, dynamic>? areaData;
    try {
      final areaDoc = await _firestore
          .collection('maps')
          .doc(areaId)
          .get(const GetOptions(source: Source.serverAndCache));
      areaData = areaDoc.data();
    } catch (_) {
      // Offline/cache fallback is handled below.
    }

    List<Map<String, dynamic>> rawPois;
    try {
      rawPois = await _poiService
          .getPoisForCity(areaId)
          .timeout(
            const Duration(seconds: 12),
            onTimeout: () => const <Map<String, dynamic>>[],
          );
    } catch (_) {
      rawPois = const <Map<String, dynamic>>[];
    }

    final pois = <_PassportPoi>[];
    final seenIds = <String>{};
    for (final raw in rawPois) {
      final id = raw['id']?.toString().trim() ?? '';
      if (id.isEmpty || !seenIds.add(id)) continue;
      final name = (raw['name'] as String?)?.trim();
      pois.add(
        _PassportPoi(
          id: id,
          name: name == null || name.isEmpty ? 'Mekan' : name,
          category: (raw['category'] as String?)?.trim() ?? 'unknown',
        ),
      );
    }

    final configuredName = (areaData?['mapName'] as String?)?.trim();
    final fallbackName = records.first.mapName.trim();
    final rawColor = areaData?['passportColor'] ?? areaData?['colorHex'];
    return _AreaCatalog(
      name:
          configuredName == null || configuredName.isEmpty
              ? (fallbackName.isEmpty ? areaId : fallbackName)
              : configuredName,
      colorHex: PassportRegionPalette.sanitize(
        rawColor is String ? rawColor : null,
        areaId,
      ),
      pois: pois,
    );
  }

  Future<List<_PassportCheckIn>> _loadCheckIns(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('venue_checkins')
          .where('userId', isEqualTo: uid)
          .limit(1000)
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 12));
      return snapshot.docs
          .map((doc) {
            final data = doc.data();
            final markedAt = data['markedAt'];
            return _PassportCheckIn(
              venueId: (data['venueId'] as String?)?.trim() ?? '',
              mapId: (data['mapId'] as String?)?.trim() ?? '',
              markedAt:
                  markedAt is Timestamp ? markedAt.toDate() : DateTime.now(),
            );
          })
          .where((checkIn) => checkIn.venueId.isNotEmpty)
          .toList();
    } catch (_) {
      return const <_PassportCheckIn>[];
    }
  }
}

class _AreaCatalog {
  const _AreaCatalog({
    required this.name,
    required this.colorHex,
    required this.pois,
  });

  final String name;
  final String colorHex;
  final List<_PassportPoi> pois;
}

class _PassportPoi {
  const _PassportPoi({
    required this.id,
    required this.name,
    required this.category,
  });

  final String id;
  final String name;
  final String category;
}

class _PassportCheckIn {
  const _PassportCheckIn({
    required this.venueId,
    required this.mapId,
    required this.markedAt,
  });

  final String venueId;
  final String mapId;
  final DateTime markedAt;
}

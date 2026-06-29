import 'package:cloud_firestore/cloud_firestore.dart';
import '../../presentation/map/map_areas.dart';

class MapAreaFirestoreService {
  MapAreaFirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const _defaultTimeout = Duration(seconds: 15);

  Future<List<MapAreaConfig>> fetchAreas() async {
    final snap = await _firestore
        .collection('maps')
        .where('isPublished', isEqualTo: true)
        .get(const GetOptions(source: Source.server))
        .timeout(_defaultTimeout);

    final areas = <MapAreaConfig>[];
    for (final doc in snap.docs) {
      try {
        areas.add(MapAreaConfig.fromFirestoreData(doc.id, doc.data()));
      } on FormatException {
        // Invalid map documents are not safe to display or use as camera bounds.
      }
    }
    areas.sort((a, b) {
      final cityComparison = a.city.compareTo(b.city);
      return cityComparison != 0 ? cityComparison : a.title.compareTo(b.title);
    });
    return areas;
  }

  Future<MapAreaConfig?> fetchArea(String cityId) async {
    final doc = await _firestore
        .collection('maps')
        .doc(cityId)
        .get(const GetOptions(source: Source.server))
        .timeout(_defaultTimeout);
    final data = doc.data();
    if (!doc.exists || data == null || data['isPublished'] != true) {
      return null;
    }
    try {
      return MapAreaConfig.fromFirestoreData(doc.id, data);
    } on FormatException {
      return null;
    }
  }
}

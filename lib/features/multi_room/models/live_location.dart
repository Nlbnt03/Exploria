import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

class LiveLocation {
  const LiveLocation({
    required this.uid,
    required this.lat,
    required this.lng,
    this.username,
    this.updatedAt,
  });

  final String uid;
  final double lat;
  final double lng;
  final String? username;
  final DateTime? updatedAt;

  Position get position => Position(lng, lat);

  factory LiveLocation.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return LiveLocation(
      uid: doc.id,
      lat: (data['lat'] as num?)?.toDouble() ?? 0,
      lng: (data['lng'] as num?)?.toDouble() ?? 0,
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  LiveLocation withUsername(String? value) {
    return LiveLocation(
      uid: uid,
      lat: lat,
      lng: lng,
      username: value,
      updatedAt: updatedAt,
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class PlaceSuggestion {
  const PlaceSuggestion({
    required this.userId,
    required this.username,
    required this.latitude,
    required this.longitude,
    required this.name,
    required this.category,
    required this.description,
    required this.mapAreaId,
    this.id,
    this.photoUrl,
    this.status = 'pending',
    this.createdAt,
  });

  final String? id;
  final String userId;
  final String username;
  final double latitude;
  final double longitude;
  final String name;
  final String category;
  final String description;
  final String? photoUrl;
  final String mapAreaId;
  final String status;
  final DateTime? createdAt;

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'username': username,
      'latitude': latitude,
      'longitude': longitude,
      'name': name,
      'category': category,
      'description': description,
      if (photoUrl != null && photoUrl!.isNotEmpty) 'photoUrl': photoUrl,
      'mapAreaId': mapAreaId,
      'status': status,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory PlaceSuggestion.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    return PlaceSuggestion(
      id: doc.id,
      userId: data['userId'] as String? ?? '',
      username: data['username'] as String? ?? '',
      latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
      name: data['name'] as String? ?? '',
      category: data['category'] as String? ?? '',
      description: data['description'] as String? ?? '',
      photoUrl: data['photoUrl'] as String?,
      mapAreaId: data['mapAreaId'] as String? ?? '',
      status: data['status'] as String? ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

import 'package:cloud_firestore/cloud_firestore.dart';

class AppBadge {
  const AppBadge({
    required this.id,
    required this.name,
    required this.description,
    required this.iconName,
    this.earnedAt,
  });

  final String id;
  final String name;
  final String description;
  final String iconName;
  final DateTime? earnedAt;

  factory AppBadge.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final earnedAt = data['earnedAt'];
    return AppBadge(
      id: doc.id,
      name: (data['name'] as String?)?.trim() ?? '',
      description: (data['description'] as String?)?.trim() ?? '',
      iconName: (data['iconName'] as String?)?.trim() ?? 'emoji_events',
      earnedAt: earnedAt is Timestamp ? earnedAt.toDate() : null,
    );
  }
}

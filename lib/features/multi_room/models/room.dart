import 'package:cloud_firestore/cloud_firestore.dart';

class Room {
  const Room({
    required this.id,
    required this.hostId,
    required this.cityId,
    required this.roomName,
    required this.status,
    required this.minPlayers,
    this.createdAt,
  });

  final String id;
  final String hostId;
  final String cityId;
  final String roomName;
  final String status;
  final int minPlayers;
  final DateTime? createdAt;

  bool get isWaiting => status == 'waiting';
  bool get isActive => status == 'active';
  bool get isFinished => status == 'finished';

  factory Room.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Room(
      id: doc.id,
      hostId: (data['hostId'] as String?)?.trim() ?? '',
      cityId: (data['cityId'] as String?)?.trim() ?? '',
      roomName: (data['roomName'] as String?)?.trim() ?? '',
      status: (data['status'] as String?)?.trim() ?? 'waiting',
      minPlayers: (data['minPlayers'] as num?)?.toInt() ?? 2,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

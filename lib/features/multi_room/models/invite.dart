import 'package:cloud_firestore/cloud_firestore.dart';

class Invite {
  const Invite({
    required this.id,
    required this.roomId,
    this.roomName,
    required this.fromUserId,
    this.fromUsername,
    required this.toUserId,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String roomId;
  final String? roomName;
  final String fromUserId;
  final String? fromUsername;
  final String toUserId;
  final String status;
  final DateTime? createdAt;

  bool get isPending => status == 'pending';

  factory Invite.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Invite(
      id: doc.id,
      roomId: (data['roomId'] as String?)?.trim() ?? '',
      roomName: (data['roomName'] as String?)?.trim(),
      fromUserId: (data['fromUserId'] as String?)?.trim() ?? '',
      fromUsername: (data['fromUsername'] as String?)?.trim(),
      toUserId: (data['toUserId'] as String?)?.trim() ?? '',
      status: (data['status'] as String?)?.trim() ?? 'pending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

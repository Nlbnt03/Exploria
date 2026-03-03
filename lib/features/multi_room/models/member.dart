import 'package:cloud_firestore/cloud_firestore.dart';

class Member {
  const Member({required this.uid, required this.username, this.joinedAt});

  final String uid;
  final String username;
  final DateTime? joinedAt;

  factory Member.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return Member(
      uid: (data['uid'] as String?)?.trim() ?? doc.id,
      username: (data['username'] as String?)?.trim() ?? 'Kullanici',
      joinedAt: (data['joinedAt'] as Timestamp?)?.toDate(),
    );
  }
}

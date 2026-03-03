import 'package:cloud_firestore/cloud_firestore.dart';

class FriendRef {
  const FriendRef({required this.friendUid, required this.username});

  final String friendUid;
  final String username;

  factory FriendRef.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    return FriendRef(
      friendUid: (data['friendUid'] as String?)?.trim() ?? doc.id,
      username: (data['username'] as String?)?.trim() ?? doc.id,
    );
  }
}

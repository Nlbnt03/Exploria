import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/sign_up_profile.dart';

class PendingProfileStore {
  const PendingProfileStore();

  static String _key(String uid) => 'pending_profile_$uid';

  Future<void> save(String uid, SignUpProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(uid), jsonEncode(profile.toJson()));
  }

  Future<SignUpProfile?> load(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(uid));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    return SignUpProfile.fromJson(json);
  }

  Future<void> clear(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(uid));
  }
}

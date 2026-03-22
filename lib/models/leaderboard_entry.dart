import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class LeaderboardEntry {
  final String uid;
  final String username;
  final String title;
  final Color titleColor;
  final int weeklyXP;
  final int totalXP;
  final DateTime? updatedAt;

  const LeaderboardEntry({
    required this.uid,
    required this.username,
    required this.title,
    required this.titleColor,
    required this.weeklyXP,
    required this.totalXP,
    this.updatedAt,
  });

  factory LeaderboardEntry.fromMap(String uid, Map<String, dynamic> data) {
    Color parsedColor;
    final colorStr = (data['titleColor'] as String?)?.trim() ?? '';
    if (colorStr.isNotEmpty) {
      try {
        final hex = colorStr.replaceFirst('#', '');
        parsedColor = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {
        parsedColor = Colors.grey;
      }
    } else {
      parsedColor = Colors.grey;
    }

    final ts = data['updatedAt'];
    DateTime? updatedAt;
    if (ts is Timestamp) {
      updatedAt = ts.toDate();
    }

    return LeaderboardEntry(
      uid: uid,
      username: (data['username'] as String?)?.trim() ?? '',
      title: (data['title'] as String?)?.trim() ?? '',
      titleColor: parsedColor,
      weeklyXP: (data['weeklyXP'] as num?)?.toInt() ?? 0,
      totalXP: (data['totalXP'] as num?)?.toInt() ?? 0,
      updatedAt: updatedAt,
    );
  }

  /// Convert titleColor to hex string for Firestore storage.
  static String colorToHex(Color color) {
    final argb = color.toARGB32();
    return '#${argb.toRadixString(16).substring(2).toUpperCase()}';
  }
}

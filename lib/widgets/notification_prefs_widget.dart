import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ─── Veri modeli ──────────────────────────────────────────────────────────────
class NotificationPrefs {
  final bool weeklyTask;
  final bool friendRequest;
  final bool roomInvite;

  const NotificationPrefs({
    this.weeklyTask = true,
    this.friendRequest = true,
    this.roomInvite = true,
  });

  factory NotificationPrefs.fromMap(Map<String, dynamic> map) {
    return NotificationPrefs(
      weeklyTask: map['weeklyTask'] as bool? ?? true,
      friendRequest: map['friendRequest'] as bool? ?? true,
      roomInvite: map['roomInvite'] as bool? ?? true,
    );
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────
final notificationPrefsProvider =
    StreamProvider.autoDispose<NotificationPrefs>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return const Stream.empty();

  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snap) {
    final data = snap.data();
    if (data == null) return const NotificationPrefs();
    final prefs = data['notificationPrefs'];
    if (prefs is! Map<String, dynamic>) return const NotificationPrefs();
    return NotificationPrefs.fromMap(prefs);
  });
});

// ─── Widget ───────────────────────────────────────────────────────────────────
class NotificationPrefsWidget extends ConsumerWidget {
  const NotificationPrefsWidget({super.key});

  Future<void> _toggle(String field, bool value) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'notificationPrefs.$field': value,
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefsAsync = ref.watch(notificationPrefsProvider);

    return prefsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Tercihler yüklenemedi: $e'),
      ),
      data: (prefs) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PrefTile(
            icon: Icons.task_alt_rounded,
            title: 'Haftalık Görev Hatırlatıcı',
            subtitle: 'Tamamlanmamış görevler için günlük bildirim al',
            value: prefs.weeklyTask,
            onChanged: (v) => _toggle('weeklyTask', v),
          ),
          const Divider(height: 1, indent: 72),
          _PrefTile(
            icon: Icons.person_add_rounded,
            title: 'Arkadaşlık İsteği',
            subtitle: 'Yeni arkadaşlık isteklerinde bildirim al',
            value: prefs.friendRequest,
            onChanged: (v) => _toggle('friendRequest', v),
          ),
          const Divider(height: 1, indent: 72),
          _PrefTile(
            icon: Icons.meeting_room_rounded,
            title: 'Oda Daveti',
            subtitle: 'Bir odaya davet edildiğinde bildirim al',
            value: prefs.roomInvite,
            onChanged: (v) => _toggle('roomInvite', v),
          ),
        ],
      ),
    );
  }
}

// ─── Yardımcı hücre widget'ı ──────────────────────────────────────────────────
class _PrefTile extends StatelessWidget {
  const _PrefTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return SwitchListTile(
      secondary: CircleAvatar(
        backgroundColor: colorScheme.primaryContainer,
        child: Icon(icon, color: colorScheme.onPrimaryContainer, size: 20),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: colorScheme.onSurface.withOpacity(0.6),
        ),
      ),
      value: value,
      onChanged: onChanged,
      activeColor: colorScheme.primary,
    );
  }
}

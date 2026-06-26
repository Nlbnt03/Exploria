import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/invite.dart';
import '../../services/multi_room_firestore_service.dart';
import 'waiting_room_screen.dart';

class PendingInvitesScreen extends StatefulWidget {
  const PendingInvitesScreen({super.key});

  @override
  State<PendingInvitesScreen> createState() => _PendingInvitesScreenState();
}

class _PendingInvitesScreenState extends State<PendingInvitesScreen> {
  final MultiRoomFirestoreService _service = MultiRoomFirestoreService();
  final Set<String> _busyInvites = <String>{};
  List<Invite> _invites = [];
  Map<String, _InviteMeta> _metaByInviteId = {};

  Future<void> _loadMeta(List<Invite> invites) async {
    final missing = <_InviteMeta>[];
    for (final invite in invites) {
      final cachedName = invite.fromUsername?.trim() ?? '';
      final cachedRoom = invite.roomName?.trim() ?? '';
      final roomName = cachedRoom.isNotEmpty ? cachedRoom : invite.roomId;
      if (cachedName.isNotEmpty) {
        _metaByInviteId[invite.id] = _InviteMeta(
          roomName: roomName,
          fromUsername: cachedName,
        );
      } else {
        missing.add(_InviteMeta(
          inviteId: invite.id,
          roomName: roomName,
          fromUid: invite.fromUserId,
        ));
      }
    }

    if (missing.isEmpty) return;

    try {
      final results = await Future.wait(
        missing.map((m) => _service.fetchUsername(m.fromUid!)),
      );
      for (var i = 0; i < missing.length; i++) {
        final m = missing[i];
        final name = results[i].trim();
        _metaByInviteId[m.inviteId!] = _InviteMeta(
          roomName: m.roomName,
          fromUsername: name.isNotEmpty ? name : 'Kullanici',
        );
      }
    } catch (_) {
      for (final m in missing) {
        _metaByInviteId[m.inviteId!] = _InviteMeta(
          roomName: m.roomName,
          fromUsername: 'Kullanici',
        );
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _acceptInvite(Invite invite) async {
    if (_busyInvites.contains(invite.id)) {
      return;
    }

    setState(() => _busyInvites.add(invite.id));
    try {
      await _service.acceptInvite(invite.id);
      if (!mounted) {
        return;
      }
      await Navigator.pushNamed(
        context,
        AppRouter.waitingRoom,
        arguments: WaitingRoomScreenArgs(roomId: invite.roomId),
      );
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Davet kabul edilemedi: $e')));
    } finally {
      if (mounted) {
        setState(() => _busyInvites.remove(invite.id));
      }
    }
  }

  Future<void> _rejectInvite(Invite invite) async {
    if (_busyInvites.contains(invite.id)) {
      return;
    }

    setState(() => _busyInvites.add(invite.id));
    try {
      await _service.rejectInvite(invite.id);
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Davet reddedilemedi: $e')));
    } finally {
      if (mounted) {
        setState(() => _busyInvites.remove(invite.id));
      }
    }
  }

  String _formatInviteTime(DateTime? createdAt) {
    if (createdAt == null) {
      return 'Az once gonderildi';
    }
    final now = DateTime.now();
    final diff = now.difference(createdAt);
    if (diff.inMinutes < 1) {
      return 'Simdi gonderildi';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} dk once gonderildi';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} saat once gonderildi';
    }
    return '${diff.inDays} gun once gonderildi';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textMain,
        title: const Text('Oda Davetleri'),
      ),
      body: StreamBuilder<List<Invite>>(
        stream: _service.listenPendingInvites(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  'Davetler yuklenemedi: ${snapshot.error}',
                  style: const TextStyle(color: AppColors.textMain),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final invites = snapshot.data ?? const <Invite>[];
          if (invites.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 28),
                child: Text(
                  'Su an bekleyen oda davetin yok.\nYeni davet geldiginde burada gorunecek.',
                  style: TextStyle(color: AppColors.textMuted),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          // Pre-load missing usernames in batch
          if (_invites != invites) {
            _invites = invites;
            _metaByInviteId = {};
            _loadMeta(invites);
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: invites.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final invite = invites[index];
              final isBusy = _busyInvites.contains(invite.id);
              final meta = _metaByInviteId[invite.id];
              final roomName = meta?.roomName ?? invite.roomId;
              final fromUsername = meta?.fromUsername ?? 'Kullanici';

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.inputBorder.withValues(alpha: 0.45),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            roomName,
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Davet eden: $fromUsername',
                            style: const TextStyle(color: AppColors.textMuted),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatInviteTime(invite.createdAt),
                            style: const TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed:
                                      isBusy
                                          ? null
                                          : () => _acceptInvite(invite),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                  child:
                                      isBusy
                                          ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                          : const Text('Kabul Et'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed:
                                      isBusy
                                          ? null
                                          : () => _rejectInvite(invite),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textMain,
                                    side: BorderSide(
                                      color: AppColors.inputBorder.withValues(
                                        alpha: 0.7,
                                      ),
                                    ),
                                  ),
                                  child: const Text('Reddet'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
            },
          );
        },
      ),
    );
  }
}

class _InviteMeta {
  const _InviteMeta({
    required this.roomName,
    this.fromUsername = 'Kullanici',
    this.inviteId,
    this.fromUid,
  });

  final String roomName;
  final String fromUsername;
  final String? inviteId;
  final String? fromUid;
}

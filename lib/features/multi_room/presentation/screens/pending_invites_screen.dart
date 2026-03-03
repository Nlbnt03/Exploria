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

  Future<_InviteMeta> _loadInviteMeta(Invite invite) async {
    final fromUsername = await _service.fetchUsername(invite.fromUserId);
    return _InviteMeta(roomName: invite.roomId, fromUsername: fromUsername);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textMain,
        title: const Text('Pending Room Invites'),
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
              child: Text(
                'Bekleyen davet yok.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: invites.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final invite = invites[index];
              final isBusy = _busyInvites.contains(invite.id);

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.inputBorder.withValues(alpha: 0.45),
                  ),
                ),
                child: FutureBuilder<_InviteMeta>(
                  future: _loadInviteMeta(invite),
                  builder: (context, metaSnapshot) {
                    final roomName =
                        metaSnapshot.data?.roomName ?? invite.roomId;
                    final fromUsername =
                        metaSnapshot.data?.fromUsername ?? invite.fromUserId;

                    return Padding(
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
                                          : const Text('Accept'),
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
                                  child: const Text('Reject'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
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
  const _InviteMeta({required this.roomName, required this.fromUsername});

  final String roomName;
  final String fromUsername;
}

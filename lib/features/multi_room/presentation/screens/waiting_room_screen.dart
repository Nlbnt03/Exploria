import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../models/friend_ref.dart';
import '../../models/member.dart';
import '../../models/room.dart';
import '../../services/multi_room_firestore_service.dart';
import 'multi_map_screen.dart';

class WaitingRoomScreenArgs {
  const WaitingRoomScreenArgs({required this.roomId});

  final String roomId;
}

class WaitingRoomScreen extends StatefulWidget {
  const WaitingRoomScreen({super.key, required this.roomId});

  final String roomId;

  @override
  State<WaitingRoomScreen> createState() => _WaitingRoomScreenState();
}

class _WaitingRoomScreenState extends State<WaitingRoomScreen> {
  final MultiRoomFirestoreService _service = MultiRoomFirestoreService();

  StreamSubscription<Room?>? _roomSub;
  StreamSubscription<List<Member>>? _membersSub;

  Room? _room;
  List<Member> _members = const <Member>[];

  bool _isProcessing = false;
  bool _routeLocked = false;

  bool get _isHost => _room?.hostId == _service.currentUid;

  int get _minPlayers => _room?.minPlayers ?? 2;

  bool get _canStart =>
      _isHost && (_room?.isWaiting ?? false) && _members.length >= _minPlayers;

  @override
  void initState() {
    super.initState();

    _roomSub = _service
        .listenRoom(widget.roomId)
        .listen(
          _onRoomChanged,
          onError: (Object error) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Oda verisi alinamadi: $error')),
            );
          },
        );

    _membersSub = _service
        .listenMembers(widget.roomId)
        .listen(
          (members) {
            if (!mounted) {
              return;
            }
            setState(() => _members = members);
          },
          onError: (Object error) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Uyeler alinamadi: $error')));
          },
        );
  }

  void _onRoomChanged(Room? room) {
    if (!mounted) {
      return;
    }

    setState(() => _room = room);

    if (room == null) {
      if (_routeLocked) {
        return;
      }
      _routeLocked = true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Oda bulunamadi.')));
      Navigator.pushNamedAndRemoveUntil(context, AppRouter.home, (_) => false);
      return;
    }

    if (room.isActive) {
      _openMap();
      return;
    }

    if (room.isFinished) {
      _finishRoomAndGoHome();
    }
  }

  Future<void> _openMap() async {
    if (_routeLocked || !mounted) {
      return;
    }
    _routeLocked = true;
    await Navigator.pushReplacementNamed(
      context,
      AppRouter.multiMap,
      arguments: MultiMapScreenArgs(roomId: widget.roomId),
    );
  }

  void _finishRoomAndGoHome() {
    if (_routeLocked || !mounted) {
      return;
    }
    _routeLocked = true;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Oda sonlandirildi.')));
    Navigator.pushNamedAndRemoveUntil(context, AppRouter.home, (_) => false);
  }

  Future<void> _startExploration() async {
    if (_isProcessing || !_canStart) {
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await _service.startRoom(widget.roomId);
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Oda baslatilamadi: $e')));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _endRoom() async {
    if (_isProcessing || !_isHost) {
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await _service.endRoom(widget.roomId);
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Oda bitirilemedi: $e')));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _leaveRoom() async {
    if (_isProcessing) {
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await _service.leaveRoom(widget.roomId);
      if (!mounted) {
        return;
      }
      Navigator.pushNamedAndRemoveUntil(context, AppRouter.home, (_) => false);
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Odadan cikilamadi: $e')));
      setState(() => _isProcessing = false);
    }
  }

  Future<void> _openInviteFriends() async {
    final memberUids = _members.map((member) => member.uid).toSet();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder:
            (_) => _InviteFriendsScreen(
              roomId: widget.roomId,
              memberUids: memberUids,
            ),
      ),
    );
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _membersSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textMain,
        title: Text(room?.roomName ?? 'Lobi'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room == null ? 'Oda yukleniyor...' : 'Oda: ${room.roomName}',
                style: const TextStyle(
                  color: AppColors.textMain,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sehir: ${room?.cityId ?? 'istanbul'}',
                style: const TextStyle(color: AppColors.textMuted),
              ),
              const SizedBox(height: 4),
              Text(
                'Uyeler: ${_members.length}/$_minPlayers+',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              if (_members.length < _minPlayers)
                const Text(
                  'Oyuncular bekleniyor...',
                  style: TextStyle(
                    color: Color(0xFFFFCC80),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              if (_members.length >= _minPlayers)
                const Text(
                  'Minimum oyuncu sayisina ulasildi.',
                  style: TextStyle(
                    color: Color(0xFF9AE6B4),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              const SizedBox(height: 14),
              const Text(
                'Uyeler',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.inputBorder.withValues(alpha: 0.45),
                    ),
                  ),
                  child: ListView.separated(
                    itemCount: _members.length,
                    separatorBuilder:
                        (_, _) => Divider(
                          color: AppColors.inputBorder.withValues(alpha: 0.3),
                          height: 1,
                        ),
                    itemBuilder: (context, index) {
                      final member = _members[index];
                      final isHost = room?.hostId == member.uid;
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              isHost
                                  ? AppColors.primary.withValues(alpha: 0.9)
                                  : AppColors.inputFill,
                          child: Icon(
                            isHost ? Icons.shield_rounded : Icons.person,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          member.username,
                          style: const TextStyle(color: AppColors.textMain),
                        ),
                        trailing:
                            isHost
                                ? const Text(
                                  'KURUCU',
                                  style: TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                                : null,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_isHost)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isProcessing ? null : _openInviteFriends,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Arkadaş Davet Et'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textMain,
                          side: BorderSide(
                            color: AppColors.inputBorder.withValues(alpha: 0.7),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            _isProcessing
                                ? null
                                : (_room?.isActive ?? false)
                                ? _endRoom
                                : (_canStart ? _startExploration : null),
                        icon: Icon(
                          (_room?.isActive ?? false)
                              ? Icons.stop_circle_outlined
                              : Icons.play_arrow_rounded,
                        ),
                        label: Text(
                          (_room?.isActive ?? false)
                              ? 'Odayı Bitir'
                              : 'Keşfi Başlat',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              if (!_isHost)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isProcessing ? null : _leaveRoom,
                    icon: const Icon(Icons.exit_to_app_rounded),
                    label: const Text('Odadan Ayril'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textMain,
                      side: BorderSide(
                        color: AppColors.inputBorder.withValues(alpha: 0.7),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              if (_isHost)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: _isProcessing ? null : _leaveRoom,
                      child: const Text(
                        'Odadan ayrıl (kurucu ayrılırsa oda kapanır)',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteFriendsScreen extends StatefulWidget {
  const _InviteFriendsScreen({required this.roomId, required this.memberUids});

  final String roomId;
  final Set<String> memberUids;

  @override
  State<_InviteFriendsScreen> createState() => _InviteFriendsScreenState();
}

class _InviteFriendsScreenState extends State<_InviteFriendsScreen> {
  final MultiRoomFirestoreService _service = MultiRoomFirestoreService();
  String? _sendingUid;

  Future<void> _sendInvite(FriendRef friend) async {
    if (_sendingUid != null || widget.memberUids.contains(friend.friendUid)) {
      return;
    }

    setState(() => _sendingUid = friend.friendUid);

    try {
      await _service.sendInvite(widget.roomId, friend.friendUid);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${friend.username} kullanicisina davet gonderildi.'),
        ),
      );
    } on Exception catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Davet gonderilemedi: $e')));
    } finally {
      if (mounted) {
        setState(() => _sendingUid = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      appBar: AppBar(
        backgroundColor: AppColors.bgTop,
        foregroundColor: AppColors.textMain,
        title: const Text('Arkadaş Davet Et'),
      ),
      body: StreamBuilder<List<FriendRef>>(
        stream: _service.listenMyFriends(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Arkadaslar yuklenemedi: ${snapshot.error}',
                style: const TextStyle(color: AppColors.textMain),
                textAlign: TextAlign.center,
              ),
            );
          }

          final friends = snapshot.data ?? const <FriendRef>[];
          if (friends.isEmpty) {
            return const Center(
              child: Text(
                'Davet edecek arkadas bulunamadi.',
                style: TextStyle(color: AppColors.textMuted),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: friends.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final friend = friends[index];
              final alreadyInRoom = widget.memberUids.contains(
                friend.friendUid,
              );

              return Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.inputBorder.withValues(alpha: 0.4),
                  ),
                ),
                child: ListTile(
                  title: Text(
                    friend.username,
                    style: const TextStyle(color: AppColors.textMain),
                  ),
                  trailing:
                      alreadyInRoom
                          ? const Text(
                            'Odada',
                            style: TextStyle(
                              color: Color(0xFF9AE6B4),
                              fontWeight: FontWeight.w700,
                            ),
                          )
                          : ElevatedButton(
                            onPressed:
                                _sendingUid == friend.friendUid
                                    ? null
                                    : () => _sendInvite(friend),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child:
                                _sendingUid == friend.friendUid
                                    ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                    : const Text('Davet Et'),
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

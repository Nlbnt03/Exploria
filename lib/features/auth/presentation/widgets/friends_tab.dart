import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/services/friends_service.dart';
import '../../../multi_room/services/multi_room_firestore_service.dart';
import '../pages/user_profile_page.dart';

class FriendsTab extends StatefulWidget {
  const FriendsTab({
    super.key,
    required this.uid,
    this.focusIncomingRequests = false,
    this.onFocusHandled,
    this.onOpenRoomInvites,
  });

  final String uid;
  final bool focusIncomingRequests;
  final VoidCallback? onFocusHandled;
  final VoidCallback? onOpenRoomInvites;

  @override
  State<FriendsTab> createState() => _FriendsTabState();
}

class _FriendsTabState extends State<FriendsTab> {
  final FriendsService _friendsService = FriendsService();
  final MultiRoomFirestoreService _multiRoomService =
      MultiRoomFirestoreService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _incomingSectionKey = GlobalKey();

  List<AppUserSummary> _searchResults = const <AppUserSummary>[];
  bool _isSearching = false;
  final Set<String> _sendingRequestTo = <String>{};
  final Set<String> _cancellingRequestTo = <String>{};
  final Set<String> _processingRequests = <String>{};
  final Set<String> _removingFriends = <String>{};

  @override
  void initState() {
    super.initState();
    _focusIncomingIfNeeded();
  }

  @override
  void didUpdateWidget(covariant FriendsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusIncomingRequests && !oldWidget.focusIncomingRequests) {
      _focusIncomingIfNeeded();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _focusIncomingIfNeeded() {
    if (!widget.focusIncomingRequests) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }

      final incomingContext = _incomingSectionKey.currentContext;
      if (incomingContext != null) {
        await Scrollable.ensureVisible(
          incomingContext,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      } else if (_scrollController.hasClients) {
        await _scrollController.animateTo(
          250,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }

      widget.onFocusHandled?.call();
    });
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      _showMessage('Arama için en az 2 karakter gir.');
      setState(() => _searchResults = const <AppUserSummary>[]);
      return;
    }

    if (widget.uid.isEmpty) {
      _showMessage('Kullanıcı kimliği bulunamadı.');
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await _friendsService.searchUsersByUsername(
        query: query,
        currentUid: widget.uid,
      );
      if (!mounted) return;
      setState(() => _searchResults = results);
    } on FirebaseException catch (e) {
      _showMessage(_mapError(e));
    } catch (e) {
      _showMessage('Arama yapılırken hata oluştu: $e');
    } finally {
      if (mounted) {
        setState(() => _isSearching = false);
      }
    }
  }

  Future<void> _sendRequest(String toUid) async {
    if (_sendingRequestTo.contains(toUid)) {
      return;
    }

    setState(() => _sendingRequestTo.add(toUid));
    try {
      await _friendsService.sendFriendRequest(
        fromUid: widget.uid,
        toUid: toUid,
      );
      _showMessage('Arkadaşlık isteği gönderildi.');
    } on FirebaseException catch (e) {
      _showMessage(_mapError(e));
    } catch (e) {
      _showMessage('İstek gönderilemedi: $e');
    } finally {
      if (mounted) {
        setState(() => _sendingRequestTo.remove(toUid));
      }
    }
  }

  Future<void> _cancelRequest(String toUid) async {
    if (_cancellingRequestTo.contains(toUid)) return;

    setState(() => _cancellingRequestTo.add(toUid));
    try {
      await _friendsService.cancelFriendRequest(
        fromUid: widget.uid,
        toUid: toUid,
      );
      _showMessage('Arkadaşlık isteği geri alındı.');
    } on FirebaseException catch (e) {
      _showMessage(_mapError(e));
    } catch (e) {
      _showMessage('İstek geri alınamadı: $e');
    } finally {
      if (mounted) {
        setState(() => _cancellingRequestTo.remove(toUid));
      }
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    if (_processingRequests.contains(requestId)) {
      return;
    }

    setState(() => _processingRequests.add(requestId));
    try {
      await _friendsService.acceptFriendRequest(
        requestId: requestId,
        currentUid: widget.uid,
      );
      _showMessage('Arkadaşlık isteği kabul edildi.');
    } on FirebaseException catch (e) {
      _showMessage(_mapError(e));
    } catch (e) {
      _showMessage('İstek kabul edilemedi: $e');
    } finally {
      if (mounted) {
        setState(() => _processingRequests.remove(requestId));
      }
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    if (_processingRequests.contains(requestId)) {
      return;
    }

    setState(() => _processingRequests.add(requestId));
    try {
      await _friendsService.rejectFriendRequest(
        requestId: requestId,
        currentUid: widget.uid,
      );
      _showMessage('Arkadaşlık isteği reddedildi.');
    } on FirebaseException catch (e) {
      _showMessage(_mapError(e));
    } catch (e) {
      _showMessage('İstek reddedilemedi: $e');
    } finally {
      if (mounted) {
        setState(() => _processingRequests.remove(requestId));
      }
    }
  }

  Future<void> _removeFriend(String friendUid) async {
    if (_removingFriends.contains(friendUid)) {
      return;
    }

    setState(() => _removingFriends.add(friendUid));
    try {
      await _friendsService.removeFriend(
        currentUid: widget.uid,
        friendUid: friendUid,
      );
      _showMessage('Arkadaş listenden çıkarıldı.');
    } on FirebaseException catch (e) {
      _showMessage(_mapError(e));
    } catch (e) {
      _showMessage('Arkadaş çıkarılamadı: $e');
    } finally {
      if (mounted) {
        setState(() => _removingFriends.remove(friendUid));
      }
    }
  }

  String _mapError(FirebaseException e) {
    switch (e.code) {
      case 'already-friends':
        return 'Bu kullanıcı zaten arkadaş listende.';
      case 'request-already-sent':
        return 'Bu kullanıcıya zaten istek gönderdin.';
      case 'incoming-request-exists':
        return 'Bu kullanıcıdan bekleyen bir istek var. Gelen isteklerden kabul edebilirsin.';
      case 'username-already-in-use':
        return 'Bu kullanıcı adı başka bir hesap tarafından kullanılıyor.';
      case 'request-not-found':
        return 'Arkadaşlık isteği bulunamadı.';
      case 'invite-already-sent':
        return 'Bu arkadaşa zaten bekleyen bir multi davetin var.';
      case 'not-friends':
        return 'Sadece arkadaşlarını davet edebilirsin.';
      case 'self-remove':
        return 'Kendini arkadaş listesinden çıkaramazsın.';
      case 'permission-denied':
        return 'Firestore yetkisi yok. Güvenlik kurallarını kontrol etmelisin.';
      default:
        return e.message ?? 'Bilinmeyen bir hata oluştu (${e.code}).';
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 126),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Arkadaşlarım',
            style: TextStyle(
              color: AppColors.textMain,
              fontSize: 32,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _buildRoomInvitesButton(),
          const SizedBox(height: 16),
          _buildSearchSection(),
          const SizedBox(height: 16),
          Container(
            key: _incomingSectionKey,
            child: _buildIncomingRequestsSection(),
          ),
          const SizedBox(height: 16),
          _buildFriendsSection(),
        ],
      ),
    );
  }

  Widget _buildRoomInvitesButton() {
    final currentUid =
        widget.uid.trim().isNotEmpty
            ? widget.uid
            : (_multiRoomService.currentUid ?? '');
    return StreamBuilder<int>(
      stream: _multiRoomService.listenPendingInvitesCountFor(currentUid),
      builder: (context, snapshot) {
        final inviteCount = snapshot.data ?? 0;

        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed:
                widget.onOpenRoomInvites ??
                () => Navigator.pushNamed(context, AppRouter.pendingInvites),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.mark_email_unread_outlined),
                if (inviteCount > 0)
                  Positioned(
                    right: -8,
                    top: -8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        inviteCount > 99 ? '99+' : '$inviteCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            label: Text(
              inviteCount > 0
                  ? 'Oda Davetleri ($inviteCount)'
                  : 'Oda Davetleri',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textMain,
              side: BorderSide(
                color: AppColors.inputBorder.withValues(alpha: 0.7),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchSection() {
    return _SectionCard(
      title: 'Kullanıcı Ara',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: AppColors.textMain),
                  onSubmitted: (_) => _searchUsers(),
                  decoration: InputDecoration(
                    hintText: 'Kullanıcı adı ile ara',
                    hintStyle: const TextStyle(color: AppColors.textMuted),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppColors.textMuted,
                    ),
                    filled: true,
                    fillColor: AppColors.inputFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.inputBorder.withValues(alpha: 0.65),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.inputBorder.withValues(alpha: 0.65),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSearching ? null : _searchUsers,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child:
                      _isSearching
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text(
                            'Ara',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_searchResults.isEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sonuçlar burada listelenecek.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            )
          else
            StreamBuilder<Set<String>>(
              stream: _friendsService.watchOutgoingPendingRequestToUids(
                widget.uid,
              ),
              builder: (context, snapshot) {
                final pendingToUids = snapshot.data ?? <String>{};
                return StreamBuilder<Set<String>>(
                  stream: _friendsService.watchFriendUids(widget.uid),
                  builder: (context, friendSnapshot) {
                    final friendUids = friendSnapshot.data ?? <String>{};
                    return Column(
                      children:
                          _searchResults.map((user) {
                            final isSending = _sendingRequestTo.contains(
                              user.uid,
                            );
                            final isCancelling = _cancellingRequestTo
                                .contains(user.uid);
                            final isAlreadyRequested = pendingToUids.contains(
                              user.uid,
                            );
                            final isAlreadyFriend = friendUids.contains(
                              user.uid,
                            );

                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.inputFill.withValues(
                                  alpha: 0.85,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.inputBorder.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: AppColors.primary
                                        .withValues(alpha: 0.2),
                                    child: Text(
                                      user.username.isEmpty
                                          ? 'U'
                                          : user.username[0].toUpperCase(),
                                      style: const TextStyle(
                                        color: AppColors.textMain,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {
                                        Navigator.pushNamed(
                                          context,
                                          AppRouter.userProfile,
                                          arguments: UserProfilePageArgs(
                                            uid: user.uid,
                                          ),
                                        );
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            user.fullName.isEmpty
                                                ? user.username
                                                : user.fullName,
                                            style: const TextStyle(
                                              color: AppColors.textMain,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '@${user.username}',
                                            style: const TextStyle(
                                              color: AppColors.textMuted,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (isAlreadyFriend)
                                    OutlinedButton(
                                      onPressed: null,
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(56, 30),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        foregroundColor: AppColors.textMuted,
                                        textStyle: const TextStyle(fontSize: 12),
                                        side: BorderSide(
                                          color: AppColors.inputBorder
                                              .withValues(alpha: 0.4),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: const Text('Arkadaşın'),
                                    )
                                  else if (isAlreadyRequested)
                                    OutlinedButton(
                                      onPressed: isCancelling
                                          ? null
                                          : () => _cancelRequest(user.uid),
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(56, 30),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        foregroundColor: Colors.orangeAccent,
                                        textStyle: const TextStyle(fontSize: 11),
                                        side: BorderSide(
                                          color: Colors.orangeAccent
                                              .withValues(alpha: 0.5),
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: isCancelling
                                          ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: Colors.orangeAccent,
                                            ),
                                          )
                                          : const Text('Gönderildi'),
                                    )
                                  else
                                    ElevatedButton(
                                      onPressed: isSending
                                          ? null
                                          : () => _sendRequest(user.uid),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            AppColors.primary.withValues(
                                              alpha: 0.92,
                                            ),
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(56, 30),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 4,
                                        ),
                                        textStyle: const TextStyle(fontSize: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                      ),
                                      child: isSending
                                          ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: Colors.white,
                                            ),
                                          )
                                          : const Text('İstek'),
                                    ),
                                ],
                              ),
                            );
                          }).toList(),
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildIncomingRequestsSection() {
    return _SectionCard(
      title: 'Gelen İstekler',
      child: StreamBuilder<List<FriendRequestView>>(
        stream: _friendsService.watchIncomingRequests(widget.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text(
              'Gelen istekler yüklenirken bir hata oluştu.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }

          final requests = snapshot.data ?? const <FriendRequestView>[];
          if (requests.isEmpty) {
            return const Text(
              'Bekleyen arkadaşlık isteğin yok.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            );
          }

          return Column(
            children:
                requests.map((request) {
                  final isProcessing = _processingRequests.contains(
                    request.requestId,
                  );
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.inputBorder.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.2,
                              ),
                              child: Text(
                                request.fromUser.username.isEmpty
                                    ? 'U'
                                    : request.fromUser.username[0]
                                        .toUpperCase(),
                                style: const TextStyle(
                                  color: AppColors.textMain,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    request.fromUser.fullName.isEmpty
                                        ? request.fromUser.username
                                        : request.fromUser.fullName,
                                    style: const TextStyle(
                                      color: AppColors.textMain,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '@${request.fromUser.username}',
                                    style: const TextStyle(
                                      color: AppColors.textMuted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed:
                                    isProcessing
                                        ? null
                                        : () =>
                                            _rejectRequest(request.requestId),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.textMain,
                                  side: BorderSide(
                                    color: AppColors.inputBorder.withValues(
                                      alpha: 0.5,
                                    ),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('Reddet'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed:
                                    isProcessing
                                        ? null
                                        : () =>
                                            _acceptRequest(request.requestId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child:
                                    isProcessing
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
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
          );
        },
      ),
    );
  }

  Widget _buildFriendsSection() {
    return _SectionCard(
      title: 'Arkadaş Listen',
      child: StreamBuilder<List<AppUserSummary>>(
        stream: _friendsService.watchFriends(widget.uid),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text(
              'Arkadaş listesi yüklenirken bir hata oluştu.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }

          final friends = snapshot.data ?? const <AppUserSummary>[];
          if (friends.isEmpty) {
            return const Text(
              'Henüz arkadaşın yok. Üstteki arama bölümünden istek gönderebilirsin.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            );
          }

          return Column(
            children:
                friends.map((friend) {
                  final isRemoving = _removingFriends.contains(friend.uid);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.inputFill.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.inputBorder.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.primary.withValues(
                            alpha: 0.2,
                          ),
                          child: Text(
                            friend.username.isEmpty
                                ? 'U'
                                : friend.username[0].toUpperCase(),
                            style: const TextStyle(
                              color: AppColors.textMain,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pushNamed(
                                context,
                                AppRouter.userProfile,
                                arguments: UserProfilePageArgs(
                                  uid: friend.uid,
                                ),
                              );
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  friend.fullName.isEmpty
                                      ? friend.username
                                      : friend.fullName,
                                  style: const TextStyle(
                                    color: AppColors.textMain,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '@${friend.username}',
                                  style: const TextStyle(
                                    color: AppColors.textMuted,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed:
                              isRemoving
                                  ? null
                                  : () => _removeFriend(friend.uid),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(56, 30),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            foregroundColor: Colors.white,
                            textStyle: const TextStyle(fontSize: 12),
                            side: BorderSide(
                              color: AppColors.inputBorder.withValues(
                                alpha: 0.6,
                              ),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child:
                              isRemoving
                                  ? const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: Colors.white,
                                    ),
                                  )
                                  : const Text('Çıkar'),
                        ),
                      ],
                    ),
                  );
                }).toList(),
          );
        },
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.inputBorder.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

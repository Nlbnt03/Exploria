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
  bool _showAllFriends = false;
  static const int _initialFriendLimit = 1;

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
    if (!widget.focusIncomingRequests) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

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
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _sendRequest(String toUid) async {
    if (_sendingRequestTo.contains(toUid)) return;

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
      if (mounted) setState(() => _sendingRequestTo.remove(toUid));
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
      if (mounted) setState(() => _cancellingRequestTo.remove(toUid));
    }
  }

  Future<void> _acceptRequest(String requestId) async {
    if (_processingRequests.contains(requestId)) return;

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
      if (mounted) setState(() => _processingRequests.remove(requestId));
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    if (_processingRequests.contains(requestId)) return;

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
      if (mounted) setState(() => _processingRequests.remove(requestId));
    }
  }

  Future<void> _removeFriend(String friendUid) async {
    if (_removingFriends.contains(friendUid)) return;

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
      if (mounted) setState(() => _removingFriends.remove(friendUid));
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

  // ── Card decoration ─────────────────────────────────────────────

  static const BoxDecoration _cardDeco = BoxDecoration(
    color: AppColors.card,
    borderRadius: BorderRadius.all(Radius.circular(20)),
    border: Border.fromBorderSide(
      BorderSide(color: AppColors.inputBorder, width: 0.5),
    ),
  );

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 126),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRoomInvitesCard(),
          const SizedBox(height: 14),
          _buildSearchSection(),
          const SizedBox(height: 14),
          Container(key: _incomingSectionKey, child: _buildIncomingRequestsSection()),
          const SizedBox(height: 14),
          _buildFriendsSection(),
        ],
      ),
    );
  }

  // ── Room Invites Card ───────────────────────────────────────────

  Widget _buildRoomInvitesCard() {
    final currentUid =
        widget.uid.trim().isNotEmpty
            ? widget.uid
            : (_multiRoomService.currentUid ?? '');

    return StreamBuilder<int>(
      stream: _multiRoomService.listenPendingInvitesCountFor(currentUid),
      builder: (context, snapshot) {
        final inviteCount = snapshot.data ?? 0;

        return GestureDetector(
          onTap:
              widget.onOpenRoomInvites ??
              () => Navigator.pushNamed(context, AppRouter.pendingInvites),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDeco.copyWith(
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.primary, AppColors.secondary],
                    ),
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                  child: const Icon(
                    Icons.door_front_door_outlined,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Oda Davetleri',
                        style: TextStyle(
                          color: AppColors.textMain,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Seni keşfe çağıran arkadaşlar',
                        style: TextStyle(
                          color: AppColors.textMuted.withValues(alpha: 0.8),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                if (inviteCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    child: Text(
                      inviteCount > 99 ? '99+' : '$inviteCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  Icon(Icons.chevron_right, color: AppColors.textMuted),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Search Section ──────────────────────────────────────────────

  Widget _buildSearchSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.3,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _gradientButton(
                label: 'Ara',
                loading: _isSearching,
                onPressed: _isSearching ? null : _searchUsers,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_searchResults.isEmpty && !_isSearching)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Sonuçlar burada listelenecek.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            )
          else if (_searchResults.isNotEmpty)
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
                            return _SearchResultCard(
                              user: user,
                              isSending: _sendingRequestTo.contains(user.uid),
                              isCancelling: _cancellingRequestTo.contains(
                                user.uid,
                              ),
                              isAlreadyRequested: pendingToUids.contains(
                                user.uid,
                              ),
                              isAlreadyFriend: friendUids.contains(user.uid),
                              onSend: () => _sendRequest(user.uid),
                              onCancel: () => _cancelRequest(user.uid),
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  AppRouter.userProfile,
                                  arguments: UserProfilePageArgs(uid: user.uid),
                                );
                              },
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

  // ── Incoming Requests Section ───────────────────────────────────

  Widget _buildIncomingRequestsSection() {
    return StreamBuilder<List<FriendRequestView>>(
      stream: _friendsService.watchIncomingRequests(widget.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDeco,
            child: const Text(
              'Gelen istekler yüklenirken bir hata oluştu.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: _cardDeco,
            child: const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
          );
        }

        final requests = snapshot.data ?? const <FriendRequestView>[];

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: _cardDeco,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Gelen İstekler',
                    style: TextStyle(
                      color: AppColors.textMain,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (requests.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primary, AppColors.secondary],
                        ),
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                      ),
                      child: Text(
                        '${requests.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (requests.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        _scrollController.animateTo(
                          _scrollController.position.maxScrollExtent,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeOutCubic,
                        );
                      },
                      child: const Text(
                        'Tümü',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (requests.isEmpty)
                const Text(
                  'Bekleyen arkadaşlık isteğin yok.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                )
              else
                ...requests.map(
                  (request) => _RequestCard(
                    request: request,
                    isProcessing: _processingRequests.contains(
                      request.requestId,
                    ),
                    onAccept: () => _acceptRequest(request.requestId),
                    onReject: () => _rejectRequest(request.requestId),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        AppRouter.userProfile,
                        arguments: UserProfilePageArgs(uid: request.fromUid),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Friends Section ─────────────────────────────────────────────

  Widget _buildFriendsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDeco,
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
            return const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            );
          }

          final friends = snapshot.data ?? const <AppUserSummary>[];
          final displayedFriends = _showAllFriends
              ? friends
              : friends.take(_initialFriendLimit).toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Arkadaşların',
                    style: TextStyle(
                      color: AppColors.textMain,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    child: Text(
                      '${friends.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (friends.length > _initialFriendLimit)
                    GestureDetector(
                      onTap: () => setState(
                        () => _showAllFriends = !_showAllFriends,
                      ),
                      child: Text(
                        _showAllFriends ? 'Daha Az Göster' : 'Tümünü Göster (${friends.length})',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (friends.isEmpty)
                const Text(
                  'Henüz arkadaşın yok. Üstteki arama bölümünden istek gönderebilirsin.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                )
              else ...[
                ...displayedFriends.map(
                  (friend) => _FriendCard(
                    friend: friend,
                    isRemoving: _removingFriends.contains(friend.uid),
                    onRemove: () => _removeFriend(friend.uid),
                    onTap: () {
                      Navigator.pushNamed(
                        context,
                        AppRouter.userProfile,
                        arguments: UserProfilePageArgs(uid: friend.uid),
                      );
                    },
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────

  Widget _gradientButton({
    required String label,
    required bool loading,
    required VoidCallback? onPressed,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          shadowColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20),
        ),
        child:
            loading
                ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
                : Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Reusable card widgets
// ═══════════════════════════════════════════════════════════════════

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({
    required this.user,
    required this.isSending,
    required this.isCancelling,
    required this.isAlreadyRequested,
    required this.isAlreadyFriend,
    required this.onSend,
    required this.onCancel,
    required this.onTap,
  });

  final AppUserSummary user;
  final bool isSending;
  final bool isCancelling;
  final bool isAlreadyRequested;
  final bool isAlreadyFriend;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.inputFill.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.inputBorder.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          _AvatarCircle(username: user.username, uid: user.uid),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.fullName.isEmpty ? user.username : user.fullName,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${user.username}',
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
          if (isAlreadyFriend)
            _smallButton(
              label: 'Arkadaşın',
              backgroundColor: Colors.transparent,
              foregroundColor: AppColors.textMuted,
              borderColor: AppColors.inputBorder.withValues(alpha: 0.3),
              enabled: false,
            )
          else if (isAlreadyRequested)
            _smallButton(
              label: 'Gönderildi',
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.orangeAccent,
              borderColor: Colors.orangeAccent.withValues(alpha: 0.4),
              loading: isCancelling,
              onPressed: onCancel,
            )
          else
            _smallButton(
              label: 'İstek',
              backgroundColor: AppColors.primary.withValues(alpha: 0.92),
              foregroundColor: Colors.white,
              loading: isSending,
              onPressed: onSend,
            ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.request,
    required this.isProcessing,
    required this.onAccept,
    required this.onReject,
    required this.onTap,
  });

  final FriendRequestView request;
  final bool isProcessing;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.inputFill.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.inputBorder.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _AvatarCircle(
                username: request.fromUser.username,
                uid: request.fromUid,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GestureDetector(
                  onTap: onTap,
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
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${request.fromUser.username}',
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
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.inputBorder.withValues(alpha: 0.4),
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : onReject,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: AppColors.textMuted,
                      shadowColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Reddet',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [AppColors.greenAccept, Color(0xFF66BB6A)],
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shadowColor: Colors.transparent,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
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
                            : const Text(
                              'Kabul Et',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  const _FriendCard({
    required this.friend,
    required this.isRemoving,
    required this.onRemove,
    required this.onTap,
  });

  final AppUserSummary friend;
  final bool isRemoving;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
      decoration: BoxDecoration(
        color: AppColors.inputFill.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.inputBorder.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          _AvatarCircle(username: friend.username, uid: friend.uid),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: onTap,
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
                      fontSize: 15,
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
          PopupMenuButton<String>(
            icon: Icon(
              Icons.more_horiz_rounded,
              color: AppColors.textMuted.withValues(alpha: 0.7),
              size: 24,
            ),
            onSelected: (value) {
              if (value == 'remove') onRemove();
            },
            color: const Color(0xFF1F0A30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: AppColors.inputBorder.withValues(alpha: 0.3),
              ),
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'remove',
                height: 40,
                child:
                    isRemoving
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.redAccent,
                          ),
                        )
                        : const Row(
                          children: [
                            Icon(
                              Icons.person_remove_outlined,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Çıkar',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.username, required this.uid});

  final String username;
  final String uid;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          username.isEmpty
              ? uid.isNotEmpty
                  ? uid[0].toUpperCase()
                  : '?'
              : username[0].toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

Widget _smallButton({
  required String label,
  required Color backgroundColor,
  required Color foregroundColor,
  Color? borderColor,
  bool enabled = true,
  bool loading = false,
  VoidCallback? onPressed,
}) {
  final btnStyle = ElevatedButton.styleFrom(
    backgroundColor: backgroundColor,
    foregroundColor: foregroundColor,
    shadowColor: Colors.transparent,
    elevation: 0,
    minimumSize: const Size(56, 30),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    textStyle: const TextStyle(fontSize: 12),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: borderColor != null ? BorderSide(color: borderColor) : BorderSide.none,
    ),
  );

  if (!enabled) {
    return ElevatedButton(
      onPressed: null,
      style: btnStyle,
      child: Text(label),
    );
  }

  return ElevatedButton(
    onPressed: loading ? null : onPressed,
    style: btnStyle,
    child:
        loading
            ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: Colors.white,
              ),
            )
            : Text(label),
  );
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/services/friends_service.dart';
import 'user_profile_page.dart';

class FriendsListPageArgs {
  const FriendsListPageArgs({required this.uid});
  final String uid;
}

class FriendsListPage extends StatefulWidget {
  const FriendsListPage({super.key, required this.uid});

  final String uid;

  @override
  State<FriendsListPage> createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<FriendsListPage> {
  final FriendsService _friendsService = FriendsService();
  final Set<String> _unblockingUsers = <String>{};
  final Set<String> _reportingUsers = <String>{};
  final Set<String> _blockingUsers = <String>{};
  final Set<String> _removingUsers = <String>{};
  bool _showBlocked = false;

  Future<void> _showReportUserSheet(AppUserSummary user) async {
    if (_reportingUsers.contains(user.uid)) return;

    final reason = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1F0A30),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder:
          (context) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kullanıcıyı Bildir',
                    style: TextStyle(
                      color: AppColors.textMain,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${user.username}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ReportReasonTile(
                    label: 'Uygunsuz profil bilgisi',
                    onTap:
                        () => Navigator.pop(context, 'Uygunsuz profil bilgisi'),
                  ),
                  _ReportReasonTile(
                    label: 'Taciz veya kötüye kullanım',
                    onTap:
                        () => Navigator.pop(
                          context,
                          'Taciz veya kötüye kullanım',
                        ),
                  ),
                  _ReportReasonTile(
                    label: 'Spam veya yanıltıcı davranış',
                    onTap:
                        () => Navigator.pop(
                          context,
                          'Spam veya yanıltıcı davranış',
                        ),
                  ),
                  _ReportReasonTile(
                    label: 'Diğer',
                    onTap: () => Navigator.pop(context, 'Diğer'),
                  ),
                ],
              ),
            ),
          ),
    );

    if (reason == null || reason.trim().isEmpty) return;
    await _reportUser(user, reason);
  }

  Future<void> _reportUser(AppUserSummary user, String reason) async {
    if (_reportingUsers.contains(user.uid)) return;

    setState(() => _reportingUsers.add(user.uid));
    try {
      await _friendsService.reportUser(
        reporterUid: widget.uid,
        reportedUser: user,
        reason: reason,
      );
      _showMessage('Bildirimin alındı. 24 saat içinde incelenecek.');
    } on FirebaseException catch (e) {
      _showMessage(_mapError(e));
    } catch (e) {
      _showMessage('Kullanıcı bildirilemedi: $e');
    } finally {
      if (mounted) setState(() => _reportingUsers.remove(user.uid));
    }
  }

  Future<void> _confirmBlockUser(AppUserSummary user) async {
    if (_blockingUsers.contains(user.uid)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1F0A30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text(
              'Kullanıcıyı Engelle',
              style: TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Text(
              '@${user.username} engellenecek ve arkadaş listenden kaldırılacak.',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Engelle',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
    );

    if (confirmed == true) {
      await _blockUser(user);
    }
  }

  Future<void> _blockUser(AppUserSummary user) async {
    if (_blockingUsers.contains(user.uid)) return;

    setState(() => _blockingUsers.add(user.uid));
    try {
      await _friendsService.blockUser(
        currentUid: widget.uid,
        blockedUser: user,
      );
      _showMessage('Kullanıcı engellendi ve listenden kaldırıldı.');
    } on FirebaseException catch (e) {
      _showMessage(_mapError(e));
    } catch (e) {
      _showMessage('Kullanıcı engellenemedi: $e');
    } finally {
      if (mounted) setState(() => _blockingUsers.remove(user.uid));
    }
  }

  Future<void> _removeFriend(AppUserSummary user) async {
    if (_removingUsers.contains(user.uid)) return;

    setState(() => _removingUsers.add(user.uid));
    try {
      await _friendsService.removeFriend(
        currentUid: widget.uid,
        friendUid: user.uid,
      );
      _showMessage('Arkadaş listenden çıkarıldı.');
    } on FirebaseException catch (e) {
      _showMessage(_mapError(e));
    } catch (e) {
      _showMessage('Arkadaş çıkarılamadı: $e');
    } finally {
      if (mounted) setState(() => _removingUsers.remove(user.uid));
    }
  }

  Future<void> _unblockUser(BlockedUserSummary user) async {
    if (_unblockingUsers.contains(user.uid)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            backgroundColor: const Color(0xFF1F0A30),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text(
              'Engeli Kaldır',
              style: TextStyle(
                color: AppColors.textMain,
                fontWeight: FontWeight.w800,
              ),
            ),
            content: Text(
              '@${user.username} için engeli kaldırmak istiyor musun?',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Kaldır',
                  style: TextStyle(color: AppColors.primary),
                ),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    setState(() => _unblockingUsers.add(user.uid));
    try {
      await _friendsService.unblockUser(
        currentUid: widget.uid,
        blockedUid: user.uid,
      );
      _showMessage('Engel kaldırıldı.');
    } on FirebaseException catch (e) {
      _showMessage(e.message ?? 'Engel kaldırılamadı.');
    } catch (e) {
      _showMessage('Engel kaldırılamadı: $e');
    } finally {
      if (mounted) setState(() => _unblockingUsers.remove(user.uid));
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  String _mapError(FirebaseException e) {
    switch (e.code) {
      case 'not-friends':
        return 'Bu kullanıcı zaten arkadaş listende değil.';
      case 'self-remove':
        return 'Kendini arkadaş listesinden çıkaramazsın.';
      case 'self-report':
        return 'Kendini bildiremezsin.';
      case 'self-block':
        return 'Kendini engelleyemezsin.';
      case 'invalid-report-reason':
        return 'Bildirim nedeni seçmelisin.';
      case 'permission-denied':
        return 'Firestore yetkisi yok. Güvenlik kurallarını deploy etmelisin.';
      default:
        return e.message ?? 'Bilinmeyen bir hata oluştu (${e.code}).';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _buildHeader(),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildSegmentedControl(),
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _showBlocked ? _buildBlockedUsers() : _buildFriends(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.inputBorder.withValues(alpha: 0.45),
              ),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textMain,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Text(
            'Arkadaşlar',
            style: TextStyle(
              color: AppColors.textMain,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.inputBorder.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SegmentButton(
              label: 'Arkadaşlar',
              icon: Icons.groups_rounded,
              selected: !_showBlocked,
              onTap: () => setState(() => _showBlocked = false),
            ),
          ),
          Expanded(
            child: _SegmentButton(
              label: 'Engellenenler',
              icon: Icons.block_rounded,
              selected: _showBlocked,
              onTap: () => setState(() => _showBlocked = true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriends() {
    return StreamBuilder<List<AppUserSummary>>(
      stream: _friendsService.watchFriends(widget.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Arkadaşlar yüklenemedi',
            subtitle: 'Daha sonra tekrar dene.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        final friends = snapshot.data ?? const <AppUserSummary>[];
        if (friends.isEmpty) {
          return const _EmptyState(
            icon: Icons.groups_2_outlined,
            title: 'Henüz arkadaş yok',
            subtitle: 'Sosyal sekmesinden arkadaş ekleyebilirsin.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: friends.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final friend = friends[index];
            final isBusy =
                _reportingUsers.contains(friend.uid) ||
                _blockingUsers.contains(friend.uid) ||
                _removingUsers.contains(friend.uid);
            return _UserListTile(
              title:
                  friend.fullName.isEmpty ? friend.username : friend.fullName,
              subtitle: '@${friend.username}',
              username: friend.username,
              uid: friend.uid,
              trailing: _FriendActionsMenu(
                isBusy: isBusy,
                onReport: () => _showReportUserSheet(friend),
                onBlock: () => _confirmBlockUser(friend),
                onRemove: () => _removeFriend(friend),
              ),
              onTap: () {
                Navigator.pushNamed(
                  context,
                  AppRouter.userProfile,
                  arguments: UserProfilePageArgs(uid: friend.uid),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildBlockedUsers() {
    return StreamBuilder<List<BlockedUserSummary>>(
      stream: _friendsService.watchBlockedUsers(widget.uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Engellenenler yüklenemedi',
            subtitle: 'Firestore kurallarını ve bağlantını kontrol et.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          );
        }

        final blockedUsers = snapshot.data ?? const <BlockedUserSummary>[];
        if (blockedUsers.isEmpty) {
          return const _EmptyState(
            icon: Icons.block_rounded,
            title: 'Engellenen kullanıcı yok',
            subtitle: 'Engellediğin kullanıcılar burada görünür.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: blockedUsers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final user = blockedUsers[index];
            final isBusy = _unblockingUsers.contains(user.uid);
            return _UserListTile(
              title: user.fullName.isEmpty ? user.username : user.fullName,
              subtitle: '@${user.username}',
              username: user.username,
              uid: user.uid,
              trailing: TextButton(
                onPressed: isBusy ? null : () => _unblockUser(user),
                child:
                    isBusy
                        ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        )
                        : const Text(
                          'Engeli Kaldır',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(11),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        height: 44,
        decoration: BoxDecoration(
          gradient:
              selected
                  ? const LinearGradient(
                    colors: [AppColors.primary, AppColors.secondary],
                  )
                  : null,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? Colors.white : AppColors.textMuted,
              size: 18,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.textMuted,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserListTile extends StatelessWidget {
  const _UserListTile({
    required this.title,
    required this.subtitle,
    required this.username,
    required this.uid,
    required this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String username;
  final String uid;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        decoration: BoxDecoration(
          color: AppColors.inputFill.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.inputBorder.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            _AvatarCircle(username: username, uid: uid),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.isEmpty ? username : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMain,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _FriendActionsMenu extends StatelessWidget {
  const _FriendActionsMenu({
    required this.isBusy,
    required this.onReport,
    required this.onBlock,
    required this.onRemove,
  });

  final bool isBusy;
  final VoidCallback onReport;
  final VoidCallback onBlock;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      enabled: !isBusy,
      icon:
          isBusy
              ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
              : Icon(
                Icons.more_horiz_rounded,
                color: AppColors.textMuted.withValues(alpha: 0.75),
                size: 24,
              ),
      onSelected: (value) {
        if (value == 'report') onReport();
        if (value == 'block') onBlock();
        if (value == 'remove') onRemove();
      },
      color: const Color(0xFF1F0A30),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.inputBorder.withValues(alpha: 0.3)),
      ),
      itemBuilder:
          (context) => const [
            PopupMenuItem(
              value: 'report',
              height: 40,
              child: Row(
                children: [
                  Icon(
                    Icons.flag_outlined,
                    color: Colors.orangeAccent,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Kullanıcıyı Bildir',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'block',
              height: 40,
              child: Row(
                children: [
                  Icon(Icons.block_rounded, color: Colors.redAccent, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Kullanıcıyı Engelle',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem(
              value: 'remove',
              height: 40,
              child: Row(
                children: [
                  Icon(
                    Icons.person_remove_outlined,
                    color: Colors.redAccent,
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Arkadaşlıktan Çıkar',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
    );
  }
}

class _ReportReasonTile extends StatelessWidget {
  const _ReportReasonTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(
        Icons.report_gmailerrorred_outlined,
        color: AppColors.primary,
      ),
      title: Text(
        label,
        style: const TextStyle(
          color: AppColors.textMain,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textMuted,
      ),
      onTap: onTap,
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({required this.username, required this.uid});

  final String username;
  final String uid;

  @override
  Widget build(BuildContext context) {
    final letter =
        username.isNotEmpty
            ? username[0].toUpperCase()
            : uid.isNotEmpty
            ? uid[0].toUpperCase()
            : '?';

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
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.textMuted, size: 46),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMain,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

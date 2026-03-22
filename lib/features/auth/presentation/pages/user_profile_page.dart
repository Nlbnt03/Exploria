import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/animations/shimmer_loading.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../models/user_xp.dart';
import '../../../../models/weekly_quest.dart';
import '../../../../widgets/xp_card.dart';
import '../../data/services/friends_service.dart';
import '../../data/services/badge_service.dart';
import '../../domain/models/badge.dart' show AppBadge;

class UserProfilePageArgs {
  const UserProfilePageArgs({required this.uid});
  final String uid;
}

class UserProfilePage extends ConsumerStatefulWidget {
  const UserProfilePage({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends ConsumerState<UserProfilePage> {
  final BadgeService _badgeService = BadgeService();
  final FriendsService _friendsService = FriendsService();

  bool _sendingRequest = false;
  bool _cancellingRequest = false;

  Map<String, dynamic>? _userData;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    setState(() => _isLoading = true);
    try {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(widget.uid)
              .get();
      if (!mounted) return;
      setState(() {
        _userData = doc.data() ?? <String, dynamic>{};
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String get _displayName {
    if (_userData == null) return '';
    final name = (_userData!['name'] as String?)?.trim() ?? '';
    final surname = (_userData!['surname'] as String?)?.trim() ?? '';
    return '$name $surname'.trim();
  }

  String get _username {
    return (_userData?['username'] as String?)?.trim() ?? '';
  }

  String get _avatarLetter {
    final name = (_userData?['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) return name[0].toUpperCase();
    final uname = _username;
    if (uname.isNotEmpty) return uname[0].toUpperCase();
    return 'U';
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
        child: SizedBox.expand(
          child: SafeArea(
            child: _isLoading ? const ProfileShimmer() : _buildContent(),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    final currentUserUid = FirebaseAuth.instance.currentUser?.uid;
    final bool isCurrentUser = widget.uid == currentUserUid;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAppBar(),
          const SizedBox(height: 24),
          _buildProfileHeader(),
          if (!isCurrentUser) _buildFriendActionButton(currentUserUid ?? ''),
          const SizedBox(height: 24),
          _buildInfoSection(),
          const SizedBox(height: 24),
          if (isCurrentUser) ...[
            const XPCard(),
            const SizedBox(height: 24),
          ] else ...[
            _buildTitleSection(),
            const SizedBox(height: 24),
          ],
          _buildBadgesSection(),
        ],
      ),
    );
  }

  Future<void> _sendRequest() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;
    setState(() => _sendingRequest = true);
    try {
      await _friendsService.sendFriendRequest(
        fromUid: currentUid,
        toUid: widget.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Arkadaşlık isteği gönderildi'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bir hata oluştu.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingRequest = false);
    }
  }

  Future<void> _cancelRequest() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;
    setState(() => _cancellingRequest = true);
    try {
      await _friendsService.cancelFriendRequest(
        fromUid: currentUid,
        toUid: widget.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İstek iptal edildi'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bir hata oluştu.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _cancellingRequest = false);
    }
  }

  Future<void> _showRemoveFriendDialog() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text(
            'Arkadaşlıktan Çıkar',
            style: TextStyle(color: AppColors.textMain),
          ),
          content: Text(
            '${_displayName.isNotEmpty ? _displayName : _username} adlı kullanıcıyı arkadaşlıktan çıkarmak istediğine emin misin?',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                'Vazgeç',
                style: TextStyle(color: AppColors.textMuted),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Çıkar',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      _removeFriend();
    }
  }

  Future<void> _removeFriend() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return;
    try {
      await _friendsService.removeFriend(
        currentUid: currentUid,
        friendUid: widget.uid,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Arkadaşlıktan çıkarıldı'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bir hata oluştu.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _loadingIcon() => const SizedBox(
    width: 20,
    height: 20,
    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
  );

  Widget _buildFriendActionButton(String currentUserUid) {
    if (currentUserUid.isEmpty) return const SizedBox();

    return StreamBuilder<Set<String>>(
      stream: _friendsService.watchOutgoingPendingRequestToUids(currentUserUid),
      builder: (context, pendingSnapshot) {
        final pendingToUids = pendingSnapshot.data ?? <String>{};

        return StreamBuilder<Set<String>>(
          stream: _friendsService.watchFriendUids(currentUserUid),
          builder: (context, friendSnapshot) {
            final friendUids = friendSnapshot.data ?? <String>{};

            final isAlreadyRequested = pendingToUids.contains(widget.uid);
            final isAlreadyFriend = friendUids.contains(widget.uid);
            final isSending = _sendingRequest;
            final isCancelling = _cancellingRequest;

            Widget button;

            if (isAlreadyFriend) {
              button = ElevatedButton.icon(
                onPressed: () => _showRemoveFriendDialog(),
                icon: const Icon(Icons.person_remove_rounded, size: 20,color : Colors.white),
                label: const Text('Arkadaş'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.card,
                  foregroundColor: AppColors.textMain,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  side: BorderSide(
                    color: AppColors.inputBorder.withValues(alpha: 0.5),
                  ),
                ),
              );
            } else if (isAlreadyRequested) {
              button = ElevatedButton.icon(
                onPressed: isCancelling ? null : _cancelRequest,
                icon:
                    isCancelling
                        ? _loadingIcon()
                        : const Icon(Icons.close_rounded, size: 20,color : Colors.white),
                label: const Text('İstek Gönderildi'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent.withValues(alpha: 0.15),
                  foregroundColor: Colors.orangeAccent,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  side: BorderSide(
                    color: Colors.orangeAccent.withValues(alpha: 0.5),
                  ),
                ),
              );
            } else {
              button = ElevatedButton.icon(
                onPressed: isSending ? null : _sendRequest,
                icon:
                    isSending
                        ? _loadingIcon()
                        : const Icon(Icons.person_add_rounded, size: 20,color : Colors.white),
                label: const Text('İstek Gönder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: button,
            );
          },
        );
      },
    );
  }

  Widget _buildAppBar() {
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
        const Text(
          'Profil',
          style: TextStyle(
            color: AppColors.textMain,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildProfileHeader() {
    return Center(
      child: Column(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.primary, AppColors.secondary],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _avatarLetter,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _displayName.isNotEmpty ? _displayName : _username,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 26,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          if (_username.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '@$_username',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    final friendsCount = (_userData?['friendsCount'] as num?)?.toInt() ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.inputBorder.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatItem(
            label: 'Arkadaş',
            value: '$friendsCount',
            icon: Icons.groups_rounded,
          ),
          Container(
            width: 1,
            height: 40,
            color: AppColors.inputBorder.withValues(alpha: 0.35),
          ),
          StreamBuilder<List<AppBadge>>(
            stream: _badgeService.watchBadges(widget.uid),
            builder: (context, snapshot) {
              final badgeCount = snapshot.data?.length ?? 0;
              return _StatItem(
                label: 'Rozet',
                value: '$badgeCount',
                icon: Icons.emoji_events_rounded,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTitleSection() {
    final currentXP = (_userData?['xp'] as num?)?.toInt() ?? 0;
    final questsMap = _userData?['weeklyQuests'] as Map<String, dynamic>?;
    final quests =
        questsMap != null
            ? WeeklyQuests.fromMap(questsMap)
            : WeeklyQuests.empty();
    final userXP = UserXP(currentXP: currentXP, weeklyQuests: quests);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
      decoration: BoxDecoration(
        color: userXP.titleColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: userXP.titleColor.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(userXP.titleEmoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 8),
          Text(
            userXP.titleName,
            style: TextStyle(
              color: userXP.titleColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadgesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.inputBorder.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.emoji_events_rounded,
                color: AppColors.primary,
                size: 22,
              ),
              SizedBox(width: 8),
              Text(
                'Rozetler',
                style: TextStyle(
                  color: AppColors.textMain,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StreamBuilder<List<AppBadge>>(
            stream: _badgeService.watchBadges(widget.uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  ),
                );
              }

              final badges = snapshot.data ?? const <AppBadge>[];
              if (badges.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.military_tech_outlined,
                        color: AppColors.textMuted,
                        size: 40,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Henüz rozet kazanılmamış',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return Column(
                children:
                    badges.map((badge) => _BadgeCard(badge: badge)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: AppColors.textMain,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      ],
    );
  }
}

class _BadgeCard extends StatelessWidget {
  const _BadgeCard({required this.badge});

  final AppBadge badge;

  IconData get _icon {
    switch (badge.iconName) {
      case 'explore':
        return Icons.explore_rounded;
      case 'star':
        return Icons.star_rounded;
      case 'map':
        return Icons.map_rounded;
      case 'groups':
        return Icons.groups_rounded;
      case 'bolt':
        return Icons.bolt_rounded;
      case 'favorite':
        return Icons.favorite_rounded;
      case 'trophy':
      case 'emoji_events':
        return Icons.emoji_events_rounded;
      case 'local_fire':
        return Icons.local_fire_department_rounded;
      case 'diamond':
        return Icons.diamond_rounded;
      case 'rocket':
        return Icons.rocket_launch_rounded;
      default:
        return Icons.emoji_events_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.inputFill.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.inputBorder.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  badge.name,
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                if (badge.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    badge.description,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

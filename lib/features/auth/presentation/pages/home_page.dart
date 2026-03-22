import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/services/badge_service.dart';
import '../../data/services/firestore_user_service.dart';
import '../../data/services/friends_service.dart';
import '../../domain/models/badge.dart' show AppBadge;
import '../../domain/models/user_map_record.dart';
import '../../../multi_room/presentation/screens/multi_map_screen.dart';
import '../../../multi_room/services/multi_room_firestore_service.dart';
import '../../../multi_room/presentation/screens/waiting_room_screen.dart';
import 'city_selection_page.dart';
import 'user_profile_page.dart';
import '../../../../screens/quests_screen.dart';
import '../../../../screens/social_page.dart';
import '../../../../providers/game_provider.dart';
import '../../../../models/user_xp.dart';
import '../../../../screens/history_page.dart';

enum TravelMode { solo, multi }

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _isSigningOut = false;
  bool _focusIncomingRequests = false;
  int _selectedIndex = 0;
  TravelMode _selectedMode = TravelMode.solo;
  String? _firestoreName;

  @override
  void initState() {
    super.initState();
    _loadFirestoreName();
  }

  Future<void> _loadFirestoreName() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final data = await FirestoreUserService().fetchUser(uid);
      final name = (data['name'] as String?)?.trim() ?? '';
      if (name.isNotEmpty && mounted) {
        setState(() => _firestoreName = _capitalize(name));
      }
    } catch (_) {
      // Best-effort; falls back to displayName / email.
    }
  }

  static String _capitalize(String s) {
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1).toLowerCase();
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRouter.login,
      (route) => false,
    );
  }

  void _startJourney() {
    final mode = _selectedMode == TravelMode.solo ? 'solo' : 'multi';
    Navigator.pushNamed(
      context,
      AppRouter.citySelection,
      arguments: CitySelectionPageArgs(mode: mode),
    );
  }

  void _openIncomingRequests() {
    setState(() {
      _selectedIndex = 2;
      _focusIncomingRequests = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final fallbackName = (user?.displayName ?? '').trim();
    final titleName =
        _firestoreName ??
        (fallbackName.isNotEmpty
            ? fallbackName
            : (user?.email?.split('@').first ?? 'Kaşif'));

    final userXPStr = ref.watch(gameProvider);
    final hasIncompleteQuests = userXPStr.valueOrNull?.weeklyQuests.hasAnyIncomplete ?? false;

    final tabs = <Widget>[
      // 0: Ana Sayfa
      _HomeTab(
        uid: user?.uid ?? '',
        titleName: titleName,
        selectedMode: _selectedMode,
        onModeChanged: (mode) => setState(() => _selectedMode = mode),
        onOpenIncomingRequests: _openIncomingRequests,
        onStartJourney: _startJourney,
        onGoToQuests: () => setState(() {
          _selectedIndex = 1;
          _focusIncomingRequests = false;
        }),
      ),
      // 1: Görevler
      const QuestsScreen(),
      // 2: Sosyal (Arkadaşlar + Liderlik)
      SocialPage(
        uid: user?.uid ?? '',
        focusIncomingRequests: _focusIncomingRequests,
        onFocusHandled: () {
          if (!mounted || !_focusIncomingRequests) {
            return;
          }
          setState(() => _focusIncomingRequests = false);
        },
        onAddFriends: null, // already on the same page
      ),
      // 3: Profil (+ Geçmiş)
      _ProfileTab(
        uid: user?.uid ?? '',
        titleName: titleName,
        userEmail: user?.email ?? '',
        isSigningOut: _isSigningOut,
        onSignOut: _isSigningOut ? null : _signOut,
      ),
    ];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bgBottom,
        body: Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.bgTop, AppColors.bgBottom],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              SafeArea(
                child: IndexedStack(index: _selectedIndex, children: tabs),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: SafeArea(
                  top: false,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xD6190D2A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: AppColors.inputBorder.withValues(alpha: 0.45),
                      ),
                    ),
                    child: BottomNavigationBar(
                      currentIndex: _selectedIndex,
                      onTap:
                          (index) => setState(() {
                            _selectedIndex = index;
                            if (index != 2) {
                              _focusIncomingRequests = false;
                            }
                          }),
                      type: BottomNavigationBarType.fixed,
                      backgroundColor: Colors.transparent,
                      elevation: 0,
                      selectedItemColor: AppColors.primary,
                      unselectedItemColor: AppColors.textMuted,
                      selectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                      items: [
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.home_outlined),
                          activeIcon: Icon(Icons.home),
                          label: 'Ana Sayfa',
                        ),
                        BottomNavigationBarItem(
                          icon: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              const Icon(Icons.emoji_events_outlined),
                              if (hasIncompleteQuests)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          activeIcon: const Icon(Icons.emoji_events),
                          label: 'Görevler',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.groups_outlined),
                          activeIcon: Icon(Icons.groups_rounded),
                          label: 'Sosyal',
                        ),
                        const BottomNavigationBarItem(
                          icon: Icon(Icons.person_outline_rounded),
                          activeIcon: Icon(Icons.person_rounded),
                          label: 'Profil',
                        ),
                      ],
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

class _PageShell extends StatelessWidget {
  const _PageShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 126),
      child: child,
    );
  }
}

class _HomeTab extends StatelessWidget {
  const _HomeTab({
    required this.uid,
    required this.titleName,
    required this.selectedMode,
    required this.onModeChanged,
    required this.onOpenIncomingRequests,
    required this.onStartJourney,
    required this.onGoToQuests,
  });

  final String uid;
  final String titleName;
  final TravelMode selectedMode;
  final ValueChanged<TravelMode> onModeChanged;
  final VoidCallback onOpenIncomingRequests;
  final VoidCallback onStartJourney;
  final VoidCallback onGoToQuests;

  @override
  Widget build(BuildContext context) {
    final isSolo = selectedMode == TravelMode.solo;
    final title = isSolo ? 'Tekli Mod' : 'Çoklu Mod';
    final subtitle =
        isSolo
            ? 'Tek başına gez, kendi ritminde keşfet. Derin odak ve tam özgürlük.'
            : 'Ekibinle keşfet, rotaları birlikte tamamla ve daha hızlı ilerle.';
    final imageUrl =
        isSolo
            ? 'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?auto=format&fit=crop&w=1200&q=80'
            : 'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?auto=format&fit=crop&w=1200&q=80';
    final buttonText = isSolo ? 'TEKLİ KEŞFE BAŞLA' : 'ÇOKLU KEŞFE BAŞLA';
    final icon = isSolo ? Icons.person_rounded : Icons.groups_rounded;

    return _PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.primary, AppColors.secondary],
                  ),
                ),
                child: const Icon(
                  Icons.explore_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const Spacer(),
              _HistoryIcon(uid: uid),
              const SizedBox(width: 8),
              _IncomingRequestsBell(uid: uid, onTap: onOpenIncomingRequests),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Hoş geldin, $titleName',
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          _HomePageWeeklyQuestsSummary(onTap: onGoToQuests),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ModeChip(
                  title: 'Tekli',
                  icon: Icons.person_rounded,
                  isSelected: isSolo,
                  onTap: () => onModeChanged(TravelMode.solo),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeChip(
                  title: 'Çoklu',
                  icon: Icons.groups_rounded,
                  isSelected: !isSolo,
                  onTap: () => onModeChanged(TravelMode.multi),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _JourneyModeCard(
            title: title,
            subtitle: subtitle,
            imageUrl: imageUrl,
            buttonText: buttonText,
            icon: icon,
            onTap: onStartJourney,
          ),
        ],
      ),
    );
  }
}

class _HistoryIcon extends StatelessWidget {
  const _HistoryIcon({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => HistoryPage(uid: uid)),
          );
        },
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.inputBorder.withValues(alpha: 0.45),
            ),
          ),
          child: const Center(
            child: Icon(
              Icons.history,
              color: AppColors.textMain,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _IncomingRequestsBell extends StatelessWidget {
  _IncomingRequestsBell({required this.uid, required this.onTap});

  final String uid;
  final VoidCallback onTap;
  final FriendsService _friendsService = FriendsService();
  final MultiRoomFirestoreService _multiRoomService =
      MultiRoomFirestoreService();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _friendsService.watchIncomingRequestCount(uid),
      builder: (context, snapshot) {
        final friendCount = snapshot.data ?? 0;
        return StreamBuilder<int>(
          stream: _multiRoomService.listenPendingInvitesCountFor(uid),
          builder: (context, inviteSnapshot) {
            final roomInviteCount = inviteSnapshot.data ?? 0;
            final totalCount = friendCount + roomInviteCount;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  if (roomInviteCount > 0) {
                    Navigator.pushNamed(context, AppRouter.pendingInvites);
                    return;
                  }
                  onTap();
                },
                child: Ink(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.inputBorder.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Center(
                        child: Icon(
                          roomInviteCount > 0
                              ? Icons.mark_email_unread_outlined
                              : Icons.notifications_none_rounded,
                          color: AppColors.textMain,
                          size: 24,
                        ),
                      ),
                      if (totalCount > 0)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 19,
                              minHeight: 19,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.bgBottom,
                                width: 1.2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                totalCount > 99 ? '99+' : '$totalCount',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
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

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color:
              isSelected
                  ? AppColors.primary.withValues(alpha: 0.18)
                  : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                isSelected
                    ? AppColors.primary
                    : AppColors.inputBorder.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? AppColors.textMain : AppColors.textMuted,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JourneyModeCard extends StatelessWidget {
  const _JourneyModeCard({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.buttonText,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final String buttonText;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.24),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textMain,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              children: [
                AspectRatio(
                  aspectRatio: 24 / 9,
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) {
                      return Container(
                        color: const Color(0x33111111),
                        child: const Center(
                          child: Icon(
                            Icons.landscape_rounded,
                            color: AppColors.textMuted,
                            size: 36,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xB3000000), Color(0x22000000)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  buttonText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab({
    required this.uid,
    required this.titleName,
    required this.userEmail,
    required this.isSigningOut,
    required this.onSignOut,
  });

  final String uid;
  final String titleName;
  final String userEmail;
  final bool isSigningOut;
  final VoidCallback? onSignOut;

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  static final RegExp _usernamePattern = RegExp(r'^[a-z0-9._-]{3,30}$');

  final _firestoreUserService = FirestoreUserService();
  final _badgeService = BadgeService();
  final _nameController = TextEditingController();
  final _surnameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void didUpdateWidget(covariant _ProfileTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid ||
        oldWidget.userEmail != widget.userEmail) {
      _loadProfile();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    _emailController.text = widget.userEmail;

    final parts = widget.titleName.trim().split(RegExp(r'\s+'));
    final defaultName = parts.isNotEmpty ? parts.first : '';
    final defaultSurname = parts.length > 1 ? parts.sublist(1).join(' ') : '';
    final defaultUsername =
        widget.userEmail.contains('@')
            ? widget.userEmail.split('@').first
            : 'kullanici';

    if (widget.uid.isEmpty) {
      _nameController.text = defaultName;
      _surnameController.text = defaultSurname;
      _usernameController.text = defaultUsername;
      setState(() => _isLoading = false);
      return;
    }

    try {
      final data = await _firestoreUserService.fetchUser(widget.uid);
      _nameController.text =
          (data['name'] as String?)?.trim().isNotEmpty == true
              ? (data['name'] as String).trim()
              : defaultName;
      _surnameController.text =
          (data['surname'] as String?)?.trim() ?? defaultSurname;

      final username = (data['username'] as String?)?.trim();
      _usernameController.text =
          (username != null && username.isNotEmpty)
              ? username
              : defaultUsername;
    } catch (_) {
      _nameController.text = defaultName;
      _surnameController.text = defaultSurname;
      _usernameController.text = defaultUsername;
      _showMessage('Profil yüklenemedi, varsayılan bilgiler kullanıldı.');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (widget.uid.isEmpty) {
      _showMessage('Kullanıcı kimliği bulunamadı.');
      return;
    }

    final name = _nameController.text.trim();
    final surname = _surnameController.text.trim();
    final username = _usernameController.text.trim();

    if (name.isEmpty || username.isEmpty) {
      _showMessage('Ad ve kullanıcı adı zorunludur.');
      return;
    }
    if (username.length < 3) {
      _showMessage('Kullanıcı adı en az 3 karakter olmalı.');
      return;
    }
    if (!_usernamePattern.hasMatch(username.toLowerCase())) {
      _showMessage(
        'Kullanıcı adı sadece küçük harf, rakam, nokta, alt çizgi ve tire içerebilir.',
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _firestoreUserService.updateEditableProfile(
        uid: widget.uid,
        name: name,
        surname: surname,
        username: username,
      );

      await FirebaseAuth.instance.currentUser?.updateDisplayName(
        surname.isEmpty ? name : '$name $surname',
      );

      _showMessage('Profil bilgileri güncellendi.');
    } on FirebaseException catch (e) {
      switch (e.code) {
        case 'username-already-in-use':
          _showMessage('Bu kullanıcı adı zaten kullanımda.');
          break;
        case 'invalid-username':
          _showMessage('Kullanıcı adı en az 3 karakter olmalı.');
          break;
        case 'invalid-username-format':
          _showMessage(
            'Kullanıcı adı sadece küçük harf, rakam, nokta, alt çizgi ve tire içerebilir.',
          );
          break;
        default:
          _showMessage('Firestore hatası: ${e.code}');
      }
    } catch (e) {
      _showMessage('Güncelleme başarısız: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
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
    return _PageShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Profil',
            style: TextStyle(
              color: AppColors.textMain,
              fontSize: 32,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.inputBorder.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.secondary],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        _nameController.text.isEmpty
                            ? 'U'
                            : _nameController.text[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_nameController.text} ${_surnameController.text}'
                              .trim(),
                          style: const TextStyle(
                            color: AppColors.textMain,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _emailController.text,
                          style: const TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _ProfileInputField(
              label: 'Ad',
              controller: _nameController,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 12),
            _ProfileInputField(
              label: 'Soyad',
              controller: _surnameController,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 12),
            _ProfileInputField(
              label: 'Kullanıcı Adı',
              controller: _usernameController,
              enabled: !_isSaving,
            ),
            const SizedBox(height: 12),
            _ProfileInputField(
              label: 'E-posta (değiştirilemez)',
              controller: _emailController,
              enabled: false,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveProfile,
                icon:
                    _isSaving
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.save_rounded, color: Colors.white),
                label: Text(
                  _isSaving ? 'Kaydediliyor...' : 'Profili Güncelle',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 22),
          _buildMyBadgesSection(),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRouter.userProfile,
                  arguments: UserProfilePageArgs(uid: widget.uid),
                );
              },
              icon: const Icon(Icons.visibility_rounded),
              label: const Text(
                'Profilimi Önizle',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textMain,
                side: BorderSide(
                  color: AppColors.inputBorder.withValues(alpha: 0.7),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: widget.onSignOut,
              icon:
                  widget.isSigningOut
                      ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : const Icon(Icons.logout_rounded, color: Colors.white),
              label: Text(
                widget.isSigningOut ? 'Çıkış yapılıyor...' : 'Çıkış Yap',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary.withValues(alpha: 0.85),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyBadgesSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.inputBorder.withValues(alpha: 0.5),
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
                'Rozetlerim',
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
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                    ),
                  ),
                );
              }

              final badges = snapshot.data ?? const <AppBadge>[];
              if (badges.isEmpty) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: const Column(
                    children: [
                      Icon(
                        Icons.military_tech_outlined,
                        color: AppColors.textMuted,
                        size: 36,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Henüz rozet kazanmadın',
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
                children: badges.map((badge) {
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
                          child: const Icon(
                            Icons.emoji_events_rounded,
                            color: AppColors.primary,
                            size: 24,
                          ),
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
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileInputField extends StatelessWidget {
  const _ProfileInputField({
    required this.label,
    required this.controller,
    required this.enabled,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textMain,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          enabled: enabled,
          style: const TextStyle(color: AppColors.textMain),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.inputFill,
            hintStyle: const TextStyle(color: AppColors.textMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.inputBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: AppColors.inputBorder.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HomePageWeeklyQuestsSummary extends ConsumerWidget {
  const _HomePageWeeklyQuestsSummary({required this.onTap});
  
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userXPAsync = ref.watch(gameProvider);

    return userXPAsync.when(
      data: (userXP) {
        final quests = userXP.weeklyQuests;
        const int maxQuestXP = 50 + 100 + 75 + 100 + 100 + 75 + 300;
        int earnedQuestXP = 0;
        int completedCount = 0;
        const int totalQuests = 7;
        
        if (quests.ilkAdim.done) { earnedQuestXP += 50; completedCount++; }
        if (quests.kasifRuhu.done) { earnedQuestXP += 100; completedCount++; }
        if (quests.cesitliKasif.done) { earnedQuestXP += 75; completedCount++; }
        if (quests.takimOyuncusu.done) { earnedQuestXP += 100; completedCount++; }
        if (quests.takimKasifi.done) { earnedQuestXP += 100; completedCount++; }
        if (quests.duzenliGezgin.done) { earnedQuestXP += 75; completedCount++; }
        if (quests.tamHafta.done) { earnedQuestXP += 300; completedCount++; }

        final questProgress = maxQuestXP > 0 ? (earnedQuestXP / maxQuestXP) : 0.0;

        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF1E1040),
                userXP.titleColor.withValues(alpha: 0.15),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: userXP.titleColor.withValues(alpha: 0.35),
            ),
          ),
          child: Column(
            children: [
              // ── Level / XP Section ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: userXP.titleColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              userXP.titleEmoji,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userXP.titleName,
                                style: TextStyle(
                                  color: userXP.titleColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                '${userXP.currentXP} XP',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (userXP.currentTitle != UserTitle.efsane)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${userXP.xpToNext} XP kaldı',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '⭐ MAX',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(begin: 0, end: userXP.progressPercentage),
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 8,
                            backgroundColor: Colors.white.withValues(alpha: 0.08),
                            valueColor: AlwaysStoppedAnimation<Color>(userXP.titleColor),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // ── Divider ──
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 1,
                color: Colors.white.withValues(alpha: 0.08),
              ),
              // ── Weekly Quests Section ──
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '🏆',
                              style: TextStyle(fontSize: 18),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Haftalık Görevler',
                              style: TextStyle(
                                color: userXP.titleColor,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$completedCount/$totalQuests',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white.withValues(alpha: 0.4),
                              size: 12,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: questProgress),
                          duration: const Duration(milliseconds: 1200),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: LinearProgressIndicator(
                                value: value.isNaN ? 0 : value,
                                minHeight: 6,
                                backgroundColor: Colors.white.withValues(alpha: 0.08),
                                valueColor: AlwaysStoppedAnimation<Color>(userXP.titleColor.withValues(alpha: 0.7)),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 6),
                        Text(
                          earnedQuestXP > 0 
                            ? 'Bu hafta görevlerden +$earnedQuestXP XP' 
                            : 'Görevlere tıklayarak detay gör',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        height: 130,
        decoration: BoxDecoration(
          color: const Color(0xFF1E1040),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const SizedBox(),
    );
  }
}


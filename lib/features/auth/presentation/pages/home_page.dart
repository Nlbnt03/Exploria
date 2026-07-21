import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../widgets/adaptive_banner.dart';
import '../../data/services/firestore_user_service.dart';
import '../../data/services/friends_service.dart';
import '../../data/services/map_progress_service.dart';
import '../../domain/models/user_map_record.dart';
import '../../../multi_room/services/multi_room_firestore_service.dart';
import '../../../passport/presentation/passport_screen.dart';
import '../map/map_areas.dart';
import 'city_selection_page.dart';
import 'user_profile_page.dart';
import '../../../../models/user_xp.dart';
import '../../../../models/suggestion_reward.dart';
import '../../../../providers/game_provider.dart';
import '../../../../providers/leaderboard_provider.dart';
import '../../../../widgets/daily_reward_strip.dart';
import '../../../../widgets/suggestion_approved_dialog.dart';
import '../../../../screens/history_page.dart';
import '../../../../screens/quests_screen.dart';
import '../../../../screens/social_page.dart';

enum TravelMode { solo, multi, freeWalk }

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key, this.openFriendRequests = false});

  final bool openFriendRequests;

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  bool _isSigningOut = false;
  bool _focusIncomingRequests = false;
  int _selectedIndex = 2;
  TravelMode _selectedMode = TravelMode.solo;
  String? _firestoreName;
  final MapProgressService _passportMapService = MapProgressService();
  StreamSubscription<List<UserMapRecord>>? _passportHistorySubscription;
  final Set<String> _completedPassportAreaIds = <String>{};
  final Set<String> _seenPassportAreaIds = <String>{};
  String? _passportTargetAreaId;
  String? _passportCompletionAreaId;
  String? _passportCompletionName;
  bool _passportHistoryInitialized = false;
  List<UserMapRecord> _passportRecords = const <UserMapRecord>[];
  final Set<int> _initializedTabs = <int>{2};

  @override
  void initState() {
    super.initState();
    _loadFirestoreName();
    _watchPassportCompletions();
    if (widget.openFriendRequests) {
      _selectedIndex = 3;
      _focusIncomingRequests = true;
    }
  }

  @override
  void dispose() {
    unawaited(_passportHistorySubscription?.cancel());
    super.dispose();
  }

  String _passportSeenKey(String uid) => 'passport_seen_seals_$uid';

  Future<void> _watchPassportCompletions() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final key = _passportSeenKey(uid);
    final hasStoredBaseline = prefs.containsKey(key);
    _seenPassportAreaIds.addAll(prefs.getStringList(key) ?? const <String>[]);

    _passportHistorySubscription = _passportMapService
        .watchMapHistory(uid, includeDeleted: true)
        .listen((records) async {
          _passportRecords = records;
          final completedRecords =
              records
                  .where(
                    (record) =>
                        !record.isDeleted &&
                        (record.isCompleted || record.progressPercent >= 100),
                  )
                  .toList();
          final completedIds =
              completedRecords.map((record) => record.areaId).toSet();

          if (!_passportHistoryInitialized) {
            _passportHistoryInitialized = true;
            _completedPassportAreaIds
              ..clear()
              ..addAll(completedIds);
            if (!hasStoredBaseline) {
              _seenPassportAreaIds.addAll(completedIds);
              await prefs.setStringList(
                key,
                _seenPassportAreaIds.toList(growable: false),
              );
            }
            if (mounted) setState(() {});
            return;
          }

          final newlyCompleted = completedIds.difference(
            _completedPassportAreaIds,
          );
          _completedPassportAreaIds
            ..clear()
            ..addAll(completedIds);
          if (newlyCompleted.isNotEmpty) {
            final record = completedRecords.firstWhere(
              (item) => newlyCompleted.contains(item.areaId),
            );
            _passportCompletionAreaId = record.areaId;
            _passportCompletionName = _passportRegionName(record);
          }
          if (mounted) setState(() {});
        });
  }

  bool get _hasNewPassportSeal =>
      _completedPassportAreaIds.difference(_seenPassportAreaIds).isNotEmpty;

  String _passportRegionName(UserMapRecord record) {
    for (final area in selectableMapAreas) {
      if (area.id == record.areaId) return area.title;
    }
    return record.mapName;
  }

  Future<void> _markPassportSealsSeen(Iterable<String> areaIds) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _seenPassportAreaIds.addAll(areaIds);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _passportSeenKey(uid),
      _seenPassportAreaIds.toList(growable: false),
    );
    if (mounted) setState(() {});
  }

  void _openPassport({String? areaId}) {
    setState(() {
      _passportTargetAreaId = areaId;
      _passportCompletionAreaId = null;
      _passportCompletionName = null;
      _selectedIndex = 1;
      _focusIncomingRequests = false;
    });
    final seen = areaId == null ? _completedPassportAreaIds : <String>{areaId};
    unawaited(_markPassportSealsSeen(seen));
  }

  void _handleNavigationTap(int index) {
    if (index == 1) {
      _openPassport();
      return;
    }
    setState(() {
      _selectedIndex = index;
      if (index != 3) _focusIncomingRequests = false;
    });
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

  Future<void> _showSuggestionCelebrations(
    List<SuggestionReward> rewards,
  ) async {
    for (final reward in rewards) {
      if (!mounted) return;
      await SuggestionApprovedDialog.show(context, reward);
    }
  }

  Future<void> _signOut() async {
    setState(() => _isSigningOut = true);
    await FirebaseAuth.instance.signOut();
    ref.invalidate(gameProvider);
    ref.invalidate(leaderboardProvider);
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRouter.login,
      (route) => false,
    );
  }

  void _startJourney() {
    if (_selectedMode == TravelMode.freeWalk) {
      Navigator.pushNamed(context, AppRouter.freeWalkMap);
      return;
    }

    final mode = _selectedMode == TravelMode.solo ? 'solo' : 'multi';
    Navigator.pushNamed(
      context,
      AppRouter.citySelection,
      arguments: CitySelectionPageArgs(mode: mode),
    );
  }

  void _openIncomingRequests() {
    setState(() {
      _selectedIndex = 3;
      _focusIncomingRequests = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    _initializedTabs.add(_selectedIndex);
    final user = FirebaseAuth.instance.currentUser;
    final fallbackName = (user?.displayName ?? '').trim();
    final titleName =
        _firestoreName ??
        (fallbackName.isNotEmpty
            ? fallbackName
            : (user?.email?.split('@').first ?? 'Kaşif'));

    final userXPStr = ref.watch(gameProvider);
    final hasIncompleteQuests =
        userXPStr.valueOrNull?.weeklyQuests.hasAnyIncomplete ?? false;

    ref.listen(gameProvider, (previous, next) {
      final rewards =
          ref
              .read(gameProvider.notifier)
              .consumePendingSuggestionCelebrations();
      if (rewards.isNotEmpty) _showSuggestionCelebrations(rewards);
    });

    final tabs = <Widget>[
      // 0: Görevler
      _initializedTabs.contains(0)
          ? const QuestsScreen()
          : const SizedBox.shrink(),
      // 1: Pasaport
      _initializedTabs.contains(1)
          ? PassportScreen(
            uid: user?.uid ?? '',
            userName: titleName,
            records: _passportRecords,
            active: _selectedIndex == 1,
            initialAreaId: _passportTargetAreaId,
          )
          : const SizedBox.shrink(),
      // 2: Ana Sayfa
      _initializedTabs.contains(2)
          ? _HomeTab(
            uid: user?.uid ?? '',
            titleName: titleName,
            selectedMode: _selectedMode,
            onModeChanged: (mode) => setState(() => _selectedMode = mode),
            onOpenIncomingRequests: _openIncomingRequests,
            onStartJourney: _startJourney,
            onGoToQuests:
                () => setState(() {
                  _selectedIndex = 0;
                  _focusIncomingRequests = false;
                }),
            completedPassportName: _passportCompletionName,
            onOpenCompletedPassport:
                _passportCompletionAreaId == null
                    ? null
                    : () => _openPassport(areaId: _passportCompletionAreaId),
            onDismissPassportCompletion:
                () => setState(() {
                  _passportCompletionAreaId = null;
                  _passportCompletionName = null;
                }),
          )
          : const SizedBox.shrink(),
      // 3: Sosyal (Arkadaşlar + Liderlik)
      _initializedTabs.contains(3)
          ? SocialPage(
            uid: user?.uid ?? '',
            focusIncomingRequests: _focusIncomingRequests,
            onFocusHandled: () {
              if (!mounted || !_focusIncomingRequests) {
                return;
              }
              setState(() => _focusIncomingRequests = false);
            },
            onAddFriends: null, // already on the same page
          )
          : const SizedBox.shrink(),
      // 4: Profil
      _initializedTabs.contains(4)
          ? UserProfilePage(
            uid: user?.uid ?? '',
            isTab: true,
            isSigningOut: _isSigningOut,
            onSignOut: _isSigningOut ? null : _signOut,
          )
          : const SizedBox.shrink(),
    ];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bgBottom,
        body: Column(
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.bgTop, AppColors.bgBottom],
                  ),
                ),
                child: SafeArea(
                  child: IndexedStack(index: _selectedIndex, children: tabs),
                ),
              ),
            ),
            if (_selectedIndex != 1 && _selectedIndex != 2)
              const AdaptiveBanner(),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                    onTap: _handleNavigationTap,
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
                      BottomNavigationBarItem(
                        icon: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Icon(Icons.menu_book_outlined),
                            if (_hasNewPassportSeal)
                              Positioned(
                                right: -3,
                                top: -3,
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF6B73C),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        activeIcon: const Icon(Icons.menu_book_rounded),
                        label: 'Pasaport',
                      ),
                      const BottomNavigationBarItem(
                        icon: Icon(Icons.home_outlined),
                        activeIcon: Icon(Icons.home_rounded),
                        label: 'Ana Sayfa',
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
    required this.completedPassportName,
    required this.onOpenCompletedPassport,
    required this.onDismissPassportCompletion,
  });

  final String uid;
  final String titleName;
  final TravelMode selectedMode;
  final ValueChanged<TravelMode> onModeChanged;
  final VoidCallback onOpenIncomingRequests;
  final VoidCallback onStartJourney;
  final VoidCallback onGoToQuests;
  final String? completedPassportName;
  final VoidCallback? onOpenCompletedPassport;
  final VoidCallback onDismissPassportCompletion;

  @override
  Widget build(BuildContext context) {
    final isSolo = selectedMode == TravelMode.solo;
    final isMulti = selectedMode == TravelMode.multi;
    final isFreeWalk = selectedMode == TravelMode.freeWalk;
    final title = switch (selectedMode) {
      TravelMode.solo => 'Tekli Mod',
      TravelMode.multi => 'Çoklu Mod',
      TravelMode.freeWalk => 'Serbest Yürüyüş',
    };
    final subtitle = switch (selectedMode) {
      TravelMode.solo =>
        'Tek başına gez, kendi ritminde keşfet. Derin odak ve tam özgürlük.',
      TravelMode.multi =>
        'Ekibinle keşfet, rotaları birlikte tamamla ve daha hızlı ilerle.',
      TravelMode.freeWalk =>
        'Şehir veya alan seçmeden bulunduğun yerde yürüyüşe çık. Sis ve sınır olmadan haritanı aç.',
    };
    final imageUrl = switch (selectedMode) {
      TravelMode.solo =>
        'https://images.unsplash.com/photo-1464822759023-fed622ff2c3b?auto=format&fit=crop&w=1200&q=80',
      TravelMode.multi =>
        'https://images.unsplash.com/photo-1529156069898-49953e39b3ac?auto=format&fit=crop&w=1200&q=80',
      TravelMode.freeWalk =>
        'https://images.unsplash.com/photo-1476480862126-209bfaa8edc8?auto=format&fit=crop&w=1200&q=80',
    };
    final buttonText = switch (selectedMode) {
      TravelMode.solo => 'TEKLİ KEŞFE BAŞLA',
      TravelMode.multi => 'ÇOKLU KEŞFE BAŞLA',
      TravelMode.freeWalk => 'SERBEST YÜRÜYÜŞÜ AÇ',
    };
    final icon = switch (selectedMode) {
      TravelMode.solo => Icons.person_rounded,
      TravelMode.multi => Icons.groups_rounded,
      TravelMode.freeWalk => Icons.directions_walk_rounded,
    };

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
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x55222040),
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset('assets/logo.png', fit: BoxFit.cover),
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
          if (completedPassportName != null &&
              onOpenCompletedPassport != null) ...[
            const SizedBox(height: 14),
            _PassportCompletionCard(
              regionName: completedPassportName!,
              onTap: onOpenCompletedPassport!,
              onDismiss: onDismissPassportCompletion,
            ),
          ],
          const SizedBox(height: 14),
          _HomePageWeeklyQuestsSummary(onTap: onGoToQuests),
          const SizedBox(height: 12),
          const DailyRewardStrip(),
          const SizedBox(height: 12),
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
                  isSelected: isMulti,
                  onTap: () => onModeChanged(TravelMode.multi),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeChip(
                  title: 'Serbest',
                  icon: Icons.directions_walk_rounded,
                  isSelected: isFreeWalk,
                  onTap: () => onModeChanged(TravelMode.freeWalk),
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

class _PassportCompletionCard extends StatelessWidget {
  const _PassportCompletionCard({
    required this.regionName,
    required this.onTap,
    required this.onDismiss,
  });

  final String regionName;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('passport-completion-card'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(15, 14, 8, 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF3D2458), Color(0xFF241438)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFF6B73C).withValues(alpha: 0.62),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF6B73C).withValues(alpha: 0.12),
                blurRadius: 18,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF6B73C).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFF6B73C)),
                ),
                child: const Icon(
                  Icons.workspace_premium_rounded,
                  color: Color(0xFFF6B73C),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$regionName sayfan tamamlandı!\n',
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const TextSpan(
                        text: 'Mührü görmek için pasaportu aç',
                        style: TextStyle(
                          color: Color(0xFFF6B73C),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Kapat',
                onPressed: onDismiss,
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.textMuted,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
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
            child: Icon(Icons.history, color: AppColors.textMain, size: 24),
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
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    placeholder:
                        (context, url) =>
                            Container(color: const Color(0x33111111)),
                    errorWidget:
                        (context, url, error) => Container(
                          color: const Color(0x33111111),
                          child: const Center(
                            child: Icon(
                              Icons.landscape_rounded,
                              color: AppColors.textMuted,
                              size: 36,
                            ),
                          ),
                        ),
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

        if (quests.ilkAdim.done) {
          earnedQuestXP += 50;
          completedCount++;
        }
        if (quests.kasifRuhu.done) {
          earnedQuestXP += 100;
          completedCount++;
        }
        if (quests.cesitliKasif.done) {
          earnedQuestXP += 75;
          completedCount++;
        }
        if (quests.takimOyuncusu.done) {
          earnedQuestXP += 100;
          completedCount++;
        }
        if (quests.takimKasifi.done) {
          earnedQuestXP += 100;
          completedCount++;
        }
        if (quests.duzenliGezgin.done) {
          earnedQuestXP += 75;
          completedCount++;
        }
        if (quests.tamHafta.done) {
          earnedQuestXP += 300;
          completedCount++;
        }

        final questProgress =
            maxQuestXP > 0 ? (earnedQuestXP / maxQuestXP) : 0.0;

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
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: userXP.titleColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Center(
                            child: Text(
                              userXP.titleEmoji,
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                userXP.titleName,
                                style: TextStyle(
                                  color: userXP.titleColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                '${userXP.currentXP} XP',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (userXP.currentTitle != UserTitle.efsane)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${userXP.xpToNext} XP kaldı',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              '⭐ MAX',
                              style: TextStyle(
                                color: Colors.amber,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TweenAnimationBuilder<double>(
                      tween: Tween<double>(
                        begin: 0,
                        end: userXP.progressPercentage,
                      ),
                      duration: const Duration(milliseconds: 1200),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: LinearProgressIndicator(
                            value: value,
                            minHeight: 6,
                            backgroundColor: Colors.white.withValues(
                              alpha: 0.08,
                            ),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              userXP.titleColor,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // ── Divider ──
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
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
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('🏆', style: TextStyle(fontSize: 15)),
                            const SizedBox(width: 6),
                            Text(
                              'Haftalık Görevler',
                              style: TextStyle(
                                color: userXP.titleColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$completedCount/$totalQuests',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              color: Colors.white.withValues(alpha: 0.4),
                              size: 11,
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0, end: questProgress),
                          duration: const Duration(milliseconds: 1200),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: LinearProgressIndicator(
                                value: value.isNaN ? 0 : value,
                                minHeight: 5,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.08,
                                ),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  userXP.titleColor.withValues(alpha: 0.7),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 4),
                        Text(
                          earnedQuestXP > 0
                              ? 'Bu hafta görevlerden +$earnedQuestXP XP'
                              : 'Görevlere tıklayarak detay gör',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 10,
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
      loading:
          () => Container(
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

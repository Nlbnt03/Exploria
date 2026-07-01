import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../features/auth/data/services/friends_service.dart';
import '../features/auth/presentation/widgets/friends_tab.dart';
import 'leaderboard_page.dart';

class SocialPage extends StatefulWidget {
  const SocialPage({
    super.key,
    this.initialTabIndex = 0,
    required this.uid,
    this.focusIncomingRequests = false,
    this.onFocusHandled,
    this.onAddFriends,
  });

  final int initialTabIndex;
  final String uid;
  final bool focusIncomingRequests;
  final VoidCallback? onFocusHandled;
  final VoidCallback? onAddFriends;

  @override
  State<SocialPage> createState() => SocialPageState();
}

class SocialPageState extends State<SocialPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FriendsService _friendsService = FriendsService();
  String _userInitial = '?';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    _loadUserInitial();
  }

  @override
  void didUpdateWidget(covariant SocialPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusIncomingRequests && !oldWidget.focusIncomingRequests) {
      _tabController.animateTo(0);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void switchToTab(int index) {
    if (index >= 0 && index < 2) {
      _tabController.animateTo(index);
    }
  }

  Future<void> _loadUserInitial() async {
    final doc = await _firestore.collection('users').doc(widget.uid).get();
    if (!mounted) return;
    final data = doc.data();
    if (data == null) return;
    final name = (data['name'] as String?)?.trim() ?? '';
    if (name.isNotEmpty) {
      setState(() => _userInitial = name[0].toUpperCase());
      return;
    }
    final username = (data['username'] as String?)?.trim() ?? '';
    if (username.isNotEmpty) {
      setState(() => _userInitial = username[0].toUpperCase());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sosyal',
                      style: TextStyle(
                        color: AppColors.textMain,
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    StreamBuilder<int>(
                      stream: _friendsService
                          .watchFriends(widget.uid)
                          .map((list) => list.length),
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        return StreamBuilder<int>(
                          stream:
                              _friendsService.watchIncomingRequestCount(
                                widget.uid,
                              ),
                          builder: (context, requestSnapshot) {
                            final requestCount = requestSnapshot.data ?? 0;
                            return Text(
                              '$count arkadaş · $requestCount yeni istek',
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 14,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              Container(
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
                    _userInitial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.15),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              indicator: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.secondary],
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textMuted,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.groups_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('Arkadaşlar'),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.leaderboard_rounded, size: 18),
                      SizedBox(width: 6),
                      Text('Liderlik'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              FriendsTab(
                uid: widget.uid,
                focusIncomingRequests: widget.focusIncomingRequests,
                onFocusHandled: widget.onFocusHandled,
              ),
              LeaderboardPage(
                onAddFriends:
                    widget.onAddFriends ??
                    () {
                      _tabController.animateTo(0);
                    },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

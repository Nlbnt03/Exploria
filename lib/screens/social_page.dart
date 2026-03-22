import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
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

  /// 0 = Arkadaşlar, 1 = Liderlik
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
  }

  @override
  void didUpdateWidget(covariant SocialPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If incoming requests just got flagged, switch to Arkadaşlar tab
    if (widget.focusIncomingRequests && !oldWidget.focusIncomingRequests) {
      _tabController.animateTo(0);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Programmatic tab switch (for deep navigation from outside).
  void switchToTab(int index) {
    if (index >= 0 && index < 2) {
      _tabController.animateTo(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
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
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.inputBorder.withValues(alpha: 0.3),
                  ),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  indicator: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  labelColor: AppColors.primary,
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
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Tab 0: Arkadaşlar
              FriendsTab(
                uid: widget.uid,
                focusIncomingRequests: widget.focusIncomingRequests,
                onFocusHandled: widget.onFocusHandled,
              ),
              // Tab 1: Liderlik
              LeaderboardPage(
                onAddFriends: widget.onAddFriends ??
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

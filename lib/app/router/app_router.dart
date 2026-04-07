import 'package:flutter/material.dart';

import '../../core/animations/page_transitions.dart';
import '../../features/auth/presentation/map/map_areas.dart';
import '../../features/auth/presentation/pages/city_map_page.dart';
import '../../features/auth/presentation/pages/city_selection_page.dart';
import '../../features/auth/presentation/pages/map_preview_page.dart';
import '../../features/auth/presentation/pages/forgot_password_page.dart';
import '../../features/auth/presentation/pages/home_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/sign_up_page.dart';
import '../../features/auth/presentation/pages/startup_splash_page.dart';
import '../../features/auth/presentation/pages/user_profile_page.dart';
import '../../features/multi_room/presentation/screens/create_room_screen.dart';
import '../../features/multi_room/presentation/screens/multi_map_screen.dart';
import '../../features/multi_room/presentation/screens/pending_invites_screen.dart';
import '../../features/multi_room/presentation/screens/waiting_room_screen.dart';
import '../../features/onboarding/presentation/pages/onboarding_page.dart';

class HomePageArgs {
  const HomePageArgs({this.openFriendRequests = false});
  final bool openFriendRequests;
}

class AppRouter {
  static const String startup = '/startup';
  static const String login = '/login';
  static const String signUp = '/sign-up';
  static const String home = '/home';
  static const String citySelection = '/city-selection';
  static const String cityMap = '/city-map';
  static const String forgotPassword = '/forgot-password';
  static const String createMultiRoom = '/create-multi-room';
  static const String waitingRoom = '/waiting-room';
  static const String pendingInvites = '/pending-invites';
  static const String multiMap = '/multi-map';
  static const String userProfile = '/user-profile';
  static const String mapPreview = '/map-preview';
  static const String onboarding = '/onboarding';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case startup:
        return FadeScaleRoute<void>(
          builder: (_) => const StartupSplashPage(),
          settings: settings,
        );
      case login:
        return FadeScaleRoute<void>(
          builder: (_) => const LoginPage(),
          settings: settings,
        );
      case signUp:
        return FadeScaleRoute<void>(
          builder: (_) => const SignUpPage(),
          settings: settings,
        );
      case forgotPassword:
        return FadeScaleRoute<void>(
          builder: (_) => const ForgotPasswordPage(),
          settings: settings,
        );
      case home:
        final args = settings.arguments;
        final openFriendRequests =
            args is HomePageArgs ? args.openFriendRequests : false;
        return FadeScaleRoute<void>(
          builder: (_) => HomePage(openFriendRequests: openFriendRequests),
          settings: settings,
        );
      case citySelection:
        final args = settings.arguments;
        final mode = args is CitySelectionPageArgs ? args.mode : 'solo';
        return SlideLeftRoute<void>(
          builder: (_) => CitySelectionPage(mode: mode),
          settings: settings,
        );
      case cityMap:
        final args = settings.arguments;
        final areaId = args is CityMapPageArgs ? args.areaId : defaultMapAreaId;
        final mapId = args is CityMapPageArgs ? args.mapId : areaId;
        final mapName = args is CityMapPageArgs ? args.mapName : 'Yeni Harita';
        final initialUserPosition =
            args is CityMapPageArgs ? args.initialUserPosition : null;
        return SlideLeftRoute<void>(
          builder:
              (_) => CityMapPage(
                areaId: areaId,
                mapId: mapId,
                mapName: mapName,
                initialUserPosition: initialUserPosition,
              ),
          settings: settings,
        );
      case createMultiRoom:
        final args = settings.arguments;
        final cityId = args is CreateRoomScreenArgs ? args.cityId : 'istanbul';
        final initialRoomName =
            args is CreateRoomScreenArgs ? args.initialRoomName : null;
        return SlideUpRoute<void>(
          builder:
              (_) => CreateRoomScreen(
                cityId: cityId,
                initialRoomName: initialRoomName,
              ),
          settings: settings,
        );
      case waitingRoom:
        final args = settings.arguments;
        final roomId = args is WaitingRoomScreenArgs ? args.roomId : '';
        return SlideLeftRoute<void>(
          builder: (_) => WaitingRoomScreen(roomId: roomId),
          settings: settings,
        );
      case pendingInvites:
        return SlideUpRoute<void>(
          builder: (_) => const PendingInvitesScreen(),
          settings: settings,
        );
      case multiMap:
        final args = settings.arguments;
        final roomId = args is MultiMapScreenArgs ? args.roomId : '';
        return SlideLeftRoute<void>(
          builder: (_) => MultiMapScreen(roomId: roomId),
          settings: settings,
        );
      case userProfile:
        final args = settings.arguments;
        final uid = args is UserProfilePageArgs ? args.uid : '';
        return SlideUpRoute<void>(
          builder: (_) => UserProfilePage(uid: uid),
          settings: settings,
        );
      case mapPreview:
        final args = settings.arguments;
        final areaId = args is MapPreviewPageArgs ? args.areaId : defaultMapAreaId;
        final mode = args is MapPreviewPageArgs ? args.mode : 'solo';
        return SlideLeftRoute<void>(
          builder: (_) => MapPreviewPage(areaId: areaId, mode: mode),
          settings: settings,
        );
      case onboarding:
        return FadeScaleRoute<void>(
          builder: (_) => const OnboardingPage(),
          settings: settings,
        );
      default:
        return FadeScaleRoute<void>(
          builder: (_) => const LoginPage(),
          settings: settings,
        );
    }
  }
}

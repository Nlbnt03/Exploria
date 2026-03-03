import 'package:flutter/material.dart';

import '../../features/auth/presentation/map/gtu_boundary.dart';
import '../../features/auth/presentation/pages/city_map_page.dart';
import '../../features/auth/presentation/pages/city_selection_page.dart';
import '../../features/auth/presentation/pages/home_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/auth/presentation/pages/sign_up_page.dart';
import '../../features/multi_room/presentation/screens/create_room_screen.dart';
import '../../features/multi_room/presentation/screens/multi_map_screen.dart';
import '../../features/multi_room/presentation/screens/pending_invites_screen.dart';
import '../../features/multi_room/presentation/screens/waiting_room_screen.dart';

class AppRouter {
  static const String login = '/login';
  static const String signUp = '/sign-up';
  static const String home = '/home';
  static const String citySelection = '/city-selection';
  static const String cityMap = '/city-map';
  static const String createMultiRoom = '/create-multi-room';
  static const String waitingRoom = '/waiting-room';
  static const String pendingInvites = '/pending-invites';
  static const String multiMap = '/multi-map';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case login:
        return MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
          settings: settings,
        );
      case signUp:
        return MaterialPageRoute<void>(
          builder: (_) => const SignUpPage(),
          settings: settings,
        );
      case home:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
          settings: settings,
        );
      case citySelection:
        final args = settings.arguments;
        final mode = args is CitySelectionPageArgs ? args.mode : 'solo';
        return MaterialPageRoute<void>(
          builder: (_) => CitySelectionPage(mode: mode),
          settings: settings,
        );
      case cityMap:
        final args = settings.arguments;
        final areaId =
            args is CityMapPageArgs ? args.areaId : defaultCampusAreaId;
        final mapId = args is CityMapPageArgs ? args.mapId : areaId;
        final mapName = args is CityMapPageArgs ? args.mapName : 'Yeni Harita';
        final initialUserPosition =
            args is CityMapPageArgs ? args.initialUserPosition : null;
        return MaterialPageRoute<void>(
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
        return MaterialPageRoute<void>(
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
        return MaterialPageRoute<void>(
          builder: (_) => WaitingRoomScreen(roomId: roomId),
          settings: settings,
        );
      case pendingInvites:
        return MaterialPageRoute<void>(
          builder: (_) => const PendingInvitesScreen(),
          settings: settings,
        );
      case multiMap:
        final args = settings.arguments;
        final roomId = args is MultiMapScreenArgs ? args.roomId : '';
        return MaterialPageRoute<void>(
          builder: (_) => MultiMapScreen(roomId: roomId),
          settings: settings,
        );
      default:
        return MaterialPageRoute<void>(
          builder: (_) => const LoginPage(),
          settings: settings,
        );
    }
  }
}

import 'package:flutter/material.dart';

import '../core/services/notification_service.dart';
import '../core/theme/app_theme.dart';
import 'router/app_router.dart';

class KesfedrioApp extends StatelessWidget {
  const KesfedrioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Keşfedio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      navigatorKey: NotificationService.navigatorKey,
      initialRoute: AppRouter.startup,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}

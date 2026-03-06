import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'router/app_router.dart';

class ExploriaApp extends StatelessWidget {
  const ExploriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Exploria',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      initialRoute: AppRouter.startup,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}

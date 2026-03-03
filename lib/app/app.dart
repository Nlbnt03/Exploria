import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'router/app_router.dart';

class ExploriaApp extends StatelessWidget {
  const ExploriaApp({super.key});

  @override
  Widget build(BuildContext context) {
    final hasSession = FirebaseAuth.instance.currentUser != null;
    return MaterialApp(
      title: 'Exploria',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      initialRoute: hasSession ? AppRouter.home : AppRouter.login,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}

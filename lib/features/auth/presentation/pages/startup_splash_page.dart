import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../app/bootstrap.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';

class StartupSplashPage extends StatefulWidget {
  const StartupSplashPage({super.key});

  @override
  State<StartupSplashPage> createState() => _StartupSplashPageState();
}

class _StartupSplashPageState extends State<StartupSplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Object? _initializationError;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
    unawaited(_prepareApp());
  }

  Future<void> _prepareApp() async {
    setState(() => _initializationError = null);
    try {
      await Future.wait<void>(<Future<void>>[
        ensureFirebaseInitialized(),
        ensureFreshMapboxData(),
        Future<void>.delayed(const Duration(milliseconds: 900)),
      ]);
      if (!mounted) return;
      final hasSession = FirebaseAuth.instance.currentUser != null;
      Navigator.pushReplacementNamed(
        context,
        hasSession ? AppRouter.home : AppRouter.login,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _initializationError = error);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          final pulse = 0.75 + 0.25 * math.sin(t * math.pi * 2);
          final sweep = (t * 2) - 0.5;

          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[AppColors.bgTop, AppColors.bgBottom],
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Positioned(
                  left: -100 + (sweep * 30),
                  top: 120,
                  child: _GlowBlob(
                    size: 240,
                    color: AppColors.primary.withValues(alpha: 0.18 * pulse),
                  ),
                ),
                Positioned(
                  right: -120 - (sweep * 25),
                  bottom: 90,
                  child: _GlowBlob(
                    size: 280,
                    color: AppColors.secondary.withValues(alpha: 0.14 * pulse),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Transform.scale(
                        scale: 0.94 + (pulse * 0.08),
                        child: Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: <Color>[
                                AppColors.primary,
                                AppColors.secondary,
                              ],
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.45,
                                ),
                                blurRadius: 30,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.explore_rounded,
                            color: Colors.white,
                            size: 42,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'EXPLORIA',
                        style: TextStyle(
                          color: AppColors.textMain,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Exploria Hazırlanıyor...',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: 48,
                        height: 48,
                        child: CircularProgressIndicator(
                          strokeWidth: 3.2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppColors.primary.withValues(alpha: 0.95),
                          ),
                          backgroundColor: AppColors.inputBorder.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                      if (_initializationError != null) ...<Widget>[
                        const SizedBox(height: 20),
                        TextButton.icon(
                          onPressed: () => unawaited(_prepareApp()),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Tekrar Dene'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textMain,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

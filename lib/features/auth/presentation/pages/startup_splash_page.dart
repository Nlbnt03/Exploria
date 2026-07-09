import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/bootstrap.dart';
import '../../../../app/router/app_router.dart';
import '../../../../core/services/app_version_service.dart';
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
  ForceUpdateInfo? _forceUpdateInfo;

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
    setState(() {
      _initializationError = null;
      _forceUpdateInfo = null;
    });
    try {
      await Future.wait<void>(<Future<void>>[
        ensureFirebaseInitialized(),
        ensureFreshMapboxData(),
        Future<void>.delayed(const Duration(milliseconds: 900)),
      ]);
      if (!mounted) return;
      final forceUpdateInfo =
          await AppVersionService.instance.checkForRequiredUpdate();
      if (!mounted) return;
      if (forceUpdateInfo != null) {
        setState(() => _forceUpdateInfo = forceUpdateInfo);
        return;
      }

      final user = FirebaseAuth.instance.currentUser;
      final hasSession = user != null;

      String nextRoute = AppRouter.login;
      if (hasSession) {
        final prefs = await SharedPreferences.getInstance();
        final hasSeenOnboarding =
            prefs.getBool('has_seen_onboarding_${user.uid}') ?? false;
        nextRoute = hasSeenOnboarding ? AppRouter.home : AppRouter.onboarding;
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, nextRoute);
    } catch (error) {
      if (!mounted) return;
      setState(() => _initializationError = error);
    }
  }

  Future<void> _openStore() async {
    final updateInfo = _forceUpdateInfo;
    if (updateInfo == null || updateInfo.storeUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncelleme bağlantısı bulunamadı.')),
      );
      return;
    }

    final uri = Uri.tryParse(updateInfo.storeUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncelleme bağlantısı açılamadı.')),
      );
      return;
    }

    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted || opened) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Mağaza bağlantısı açılamadı.')),
    );
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
                  child:
                      _forceUpdateInfo == null
                          ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              _AnimatedLogo(pulse: pulse),
                              const SizedBox(height: 18),
                              const Text(
                                'KEŞFEDİO',
                                style: TextStyle(
                                  color: AppColors.textMain,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.4,
                                ),
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'Keşfedio Hazırlanıyor...',
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
                                  backgroundColor: AppColors.inputBorder
                                      .withValues(alpha: 0.25),
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
                          )
                          : _ForceUpdatePanel(
                            updateInfo: _forceUpdateInfo!,
                            pulse: pulse,
                            onOpenStore: _openStore,
                            onRetry: () => unawaited(_prepareApp()),
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

class _AnimatedLogo extends StatelessWidget {
  const _AnimatedLogo({required this.pulse});

  final double pulse;

  @override
  Widget build(BuildContext context) {
    return Transform.scale(
      scale: 0.94 + (pulse * 0.08),
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.45),
              blurRadius: 30,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.asset('assets/logo.png', fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _ForceUpdatePanel extends StatelessWidget {
  const _ForceUpdatePanel({
    required this.updateInfo,
    required this.pulse,
    required this.onOpenStore,
    required this.onRetry,
  });

  final ForceUpdateInfo updateInfo;
  final double pulse;
  final VoidCallback onOpenStore;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Container(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.inputBorder.withValues(alpha: 0.55),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.16),
                blurRadius: 32,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _AnimatedLogo(pulse: pulse),
              const SizedBox(height: 22),
              Text(
                updateInfo.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMain,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                updateInfo.message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 15,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: onOpenStore,
                  icon: const Icon(Icons.system_update_alt_rounded),
                  label: const Text('Güncelle'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textMain,
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar Kontrol Et'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textMuted,
                  textStyle: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
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

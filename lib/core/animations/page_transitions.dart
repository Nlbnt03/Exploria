import 'package:flutter/material.dart';

/// Aşağıdan yukarı kayarak gelen sayfa geçişi.
/// Modal tarzı sayfalar için (profil, davetler, oda oluşturma).
class SlideUpRoute<T> extends PageRouteBuilder<T> {
  SlideUpRoute({
    required WidgetBuilder builder,
    super.settings,
  }) : super(
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.0, 0.3),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// Hafifçe büyüyerek ve fade-in ile açılan sayfa geçişi.
/// Ana akış sayfaları için (home, login, sign-up).
class FadeScaleRoute<T> extends PageRouteBuilder<T> {
  FadeScaleRoute({
    required WidgetBuilder builder,
    super.settings,
  }) : super(
          transitionDuration: const Duration(milliseconds: 400),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
                child: child,
              ),
            );
          },
        );
}

/// Sağdan sola kayarak gelen sayfa geçişi.
/// Detay/ilerleme sayfaları için (harita seçimi, şehir haritası, çoklu harita).
class SlideLeftRoute<T> extends PageRouteBuilder<T> {
  SlideLeftRoute({
    required WidgetBuilder builder,
    super.settings,
  }) : super(
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            // Mevcut sayfa hafifçe sola kayar ve kararır.
            final secondaryCurved = CurvedAnimation(
              parent: secondaryAnimation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(curved),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.5, end: 1.0).animate(curved),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset.zero,
                    end: const Offset(-0.15, 0.0),
                  ).animate(secondaryCurved),
                  child: child,
                ),
              ),
            );
          },
        );
}

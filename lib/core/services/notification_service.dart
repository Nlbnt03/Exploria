import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../app/router/app_router.dart';
import '../../features/auth/presentation/pages/home_page.dart';


// ─── Arka-plan mesaj handler'ı (top-level fonksiyon zorunluluğu) ──────────────
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase zaten initialize edilmiş olmalı (bootstrap.dart).
  debugPrint('[FCM Background] ${message.messageId}');
}

// ─── Yerel bildirim kanalı (Android) ─────────────────────────────────────────
const _androidChannel = AndroidNotificationChannel(
  'kesfedio_high_importance',
  'Keşfedio Bildirimleri',
  description: 'Keşfedio uygulamasından gelen önemli bildirimler.',
  importance: Importance.high,
);

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  // Navigator key — main.dart'ta MaterialApp'e verilmeli
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // ─── Başlatma ──────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    // 1. Arka-plan handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 2. İzin iste
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 3. Yerel bildirim eklentisini başlat
    await _initLocalNotifications();

    // 4. FCM token'ı Firestore'a kaydet ve genel kanala abone ol
    await _saveTokenToFirestore();
    _messaging.onTokenRefresh.listen((_) => _saveTokenToFirestore());
    try {
      await _messaging.subscribeToTopic('announcements');
      debugPrint('[FCM] Abone olundu: announcements');
    } catch (e) {
      debugPrint('[FCM] announcements kanalına abone olunamadı: $e');
    }
    // 5. Dinleyicileri kur
    _setupMessageListeners();
  }

  // ─── Yerel bildirim eklentisi ──────────────────────────────────────────────
  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();

    await _localNotifications.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null) _navigate(payload, {});
      },
    );

    // Android için yüksek öncelikli kanal oluştur
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);
    }
  }

  // ─── Token kaydetme ────────────────────────────────────────────────────────
  Future<void> saveToken() => _saveTokenToFirestore();

  Future<void> _saveTokenToFirestore() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      final token = await _messaging.getToken();
      if (token == null) return;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fcmToken': token});

      debugPrint('[FCM] Token kaydedildi: $token');
    } catch (e) {
      debugPrint('[FCM] Token alınırken hata oluştu (iOS Simulator olabilir): $e');
    }
  }

  // ─── Mesaj dinleyicileri ───────────────────────────────────────────────────
  void _setupMessageListeners() {
    // Foreground: in-app bildirim göster
    FirebaseMessaging.onMessage.listen(
      (message) {
        _showLocalNotification(message);
      },
      onError: (error, stackTrace) {
        debugPrint('[FCM] Foreground listener hatası: $error');
      },
      cancelOnError: false,
    );

    // Arka-plan/kapalı → bildirime tıklandı
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleMessageTap(message);
    });

    // Uygulama tamamen kapalıyken bildirime tıklanıp açıldı (cold start)
    _messaging.getInitialMessage().then((message) {
      if (message != null) _handleMessageTap(message);
    });
  }

  // ─── Foreground bildirim banner'ı ─────────────────────────────────────────
  void _showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data['route'],
    );
  }

  // ─── Bildirime tıklama → sayfa yönlendirme ────────────────────────────────

  // Kullanıcı giriş yapmamışsa gidilecek rota burada saklanır.
  String? _pendingRoute;
  Map<String, dynamic> _pendingData = {};

  void _handleMessageTap(RemoteMessage message) {
    final route = message.data['route'] as String?;
    if (route == null) return;
    _navigate(route, message.data);
  }

  void _navigate(String route, Map<String, dynamic> data) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    // ── Auth Guard ──────────────────────────────────────────
    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    if (!isLoggedIn) {
      // Rota sakla, login sayfasına yönlendir
      _pendingRoute = route;
      _pendingData = data;
      debugPrint('[FCM] Kullanıcı giriş yapmamış, login sayfasına yönlendirildi.');
      navigator.pushNamedAndRemoveUntil(
        AppRouter.login,
        (r) => false,
      );
      return;
    }
    // ───────────────────────────────────────────────────────

    _routeToPage(navigator, route, data);
  }

  /// Giriş sonrası bekleyen bildirimi işle.
  /// Login sayfasından başarılı giriş yapıldıktan sonra çağır:
  ///   NotificationService.instance.consumePendingRoute();
  void consumePendingRoute() {
    final route = _pendingRoute;
    final data = Map<String, dynamic>.from(_pendingData);
    _pendingRoute = null;
    _pendingData = {};

    if (route == null) return;

    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    debugPrint('[FCM] Bekleyen rota işleniyor: $route');
    _routeToPage(navigator, route, data);
  }

  void _routeToPage(
    NavigatorState navigator,
    String route,
    Map<String, dynamic> data,
  ) {
    if (route == '/tasks') {
      navigator.pushNamed(AppRouter.home);
    } else if (route == '/friend-requests') {
      navigator.pushNamed(
        AppRouter.home,
        arguments: const HomePageArgs(openFriendRequests: true),
      );
    } else if (route == '/pending-invites') {
      navigator.pushNamed(AppRouter.pendingInvites);
    } else {
      navigator.pushNamed(AppRouter.home);
    }
  }
}


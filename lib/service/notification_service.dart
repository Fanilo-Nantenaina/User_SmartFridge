import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:vibration/vibration.dart';

// ==========================================
// HANDLER BACKGROUND (TOP-LEVEL FUNCTION)
// ==========================================
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print('🔔 Message background: ${message.notification?.title}');

  if (message.notification != null) {
    await NotificationService().showNotification(
      title: message.notification!.title ?? 'Smart Fridge',
      body: message.notification!.body ?? '',
      payload: message.data['alert_id']?.toString(),
      alertType: message.data['alert_type'],
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
  FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  // Préférences
  bool _vibrationEnabled = true;
  bool _soundEnabled = true;

  // ==========================================
  // INITIALISATION PRINCIPALE
  // ==========================================
  Future<void> initialize() async {
    try {
      await _initializeFirebase();
      await _initializeLocalNotifications();
      await _requestPermissions();
      await _setupMessageHandlers();
      await _loadPreferences();

      print('✅ NotificationService initialized');
    } catch (e) {
      print('❌ NotificationService init error: $e');
    }
  }

  // ==========================================
  // FIREBASE
  // ==========================================
  Future<void> _initializeFirebase() async {
    try {
      _fcmToken = await _firebaseMessaging.getToken();
      print('📱 FCM Token: $_fcmToken');

      // Écouter les changements de token
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        _saveFCMTokenToBackend(newToken);
      });

      // Sauvegarder immédiatement
      if (_fcmToken != null) {
        await _saveFCMTokenToBackend(_fcmToken!);
      }
    } catch (e) {
      print('❌ Firebase init error: $e');
    }
  }

  Future<void> _saveFCMTokenToBackend(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);

      // TODO: Envoyer au backend
      // final api = ClientApiService();
      // await api.saveFCMToken(token);

      print('✅ FCM Token saved');
    } catch (e) {
      print('❌ Error saving FCM token: $e');
    }
  }

  // ==========================================
  // NOTIFICATIONS LOCALES
  // ==========================================
  Future<void> _initializeLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // Créer le canal Android
    if (Platform.isAndroid) {
      await _createAndroidChannel();
    }
  }

  Future<void> _createAndroidChannel() async {
    const channel = AndroidNotificationChannel(
      'smart_fridge_alerts',
      'Alertes Smart Fridge',
      description: 'Notifications pour les alertes du frigo',
      importance: Importance.max,
      enableVibration: true,
      playSound: true,
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  // ==========================================
  // PERMISSIONS
  // ==========================================
  Future<void> _requestPermissions() async {
    if (Platform.isIOS) {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      print('iOS permission status: ${settings.authorizationStatus}');
    }

    if (Platform.isAndroid && Platform.version.contains('13')) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  // ==========================================
  // MESSAGE HANDLERS
  // ==========================================
  Future<void> _setupMessageHandlers() async {
    // App en foreground
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // App en background (click)
    FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

    // App fermée (click)
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      _handleBackgroundMessage(initialMessage);
    }

    // Background handler global
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    print('📨 Foreground message: ${message.notification?.title}');

    final notification = message.notification;
    final data = message.data;

    if (notification != null) {
      await showNotification(
        title: notification.title ?? 'Smart Fridge',
        body: notification.body ?? '',
        payload: data['alert_id']?.toString(),
        alertType: data['alert_type'],
      );
    }
  }

  Future<void> _handleBackgroundMessage(RemoteMessage message) async {
    print('📨 Background message opened: ${message.notification?.title}');

    final data = message.data;

    // TODO: Navigation
    if (data['action'] == 'open_alert') {
      print('Navigate to alert: ${data['alert_id']}');
    }
  }

  // ==========================================
  // AFFICHER NOTIFICATION
  // ==========================================
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    String? alertType,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'smart_fridge_alerts',
      'Alertes Smart Fridge',
      channelDescription: 'Notifications pour les alertes du frigo',
      importance: Importance.max,
      priority: Priority.high,

      // Vibration
      enableVibration: _vibrationEnabled,
      vibrationPattern: _vibrationEnabled ? Int64List.fromList([0, 500, 200, 500]) : null,

      // Son
      playSound: _soundEnabled,
      sound: _soundEnabled ? const RawResourceAndroidNotificationSound('notification') : null,

      // Apparence
      icon: '@mipmap/ic_launcher',
      color: _getColorForAlertType(alertType),
      styleInformation: BigTextStyleInformation(body),

      number: 1,
      autoCancel: true,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: _soundEnabled,
      sound: _soundEnabled ? 'notification.aiff' : null,
      badgeNumber: 1,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: payload,
    );

    // Vibration additionnelle
    if (_vibrationEnabled && Platform.isAndroid) {
      await _triggerVibration();
    }
  }

  // ==========================================
  // VIBRATION
  // ==========================================
  Future<void> _triggerVibration() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        await Vibration.vibrate(pattern: [0, 500, 200, 500]);
      }
    } catch (e) {
      print('Vibration error: $e');
    }
  }

  Color _getColorForAlertType(String? alertType) {
    switch (alertType) {
      case 'EXPIRED':
        return const Color(0xFFD32F2F);
      case 'EXPIRY_SOON':
        return const Color(0xFFF57C00);
      case 'LOST_ITEM':
        return const Color(0xFFFDD835);
      case 'LOW_STOCK':
        return const Color(0xFF1976D2);
      default:
        return const Color(0xFF6A1B9A);
    }
  }

  // ==========================================
  // TAP NOTIFICATION
  // ==========================================
  void _onNotificationTap(NotificationResponse response) {
    print('👆 Notification tapped: ${response.payload}');

    // TODO: Navigation
    if (response.payload != null) {
      // NavigationService.navigateToAlert(int.parse(response.payload!));
    }
  }

  // ==========================================
  // NOTIFICATIONS PROGRAMMÉES
  // ==========================================
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      'smart_fridge_scheduled',
      'Rappels programmés',
      channelDescription: 'Rappels pour les produits',
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: _vibrationEnabled,
      playSound: _soundEnabled,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: _soundEnabled,
    );

    await _localNotifications.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledDate, tz.local),
      NotificationDetails(android: androidDetails, iOS: iosDetails),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  // ==========================================
  // ANNULER
  // ==========================================
  Future<void> cancelNotification(int id) async {
    await _localNotifications.cancel(id);
  }

  Future<void> cancelAllNotifications() async {
    await _localNotifications.cancelAll();
  }

  // ==========================================
  // PRÉFÉRENCES
  // ==========================================
  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _vibrationEnabled = prefs.getBool('notification_vibration') ?? true;
    _soundEnabled = prefs.getBool('notification_sound') ?? true;
  }

  Future<void> setVibrationEnabled(bool enabled) async {
    _vibrationEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_vibration', enabled);
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _soundEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notification_sound', enabled);
  }

  bool get vibrationEnabled => _vibrationEnabled;
  bool get soundEnabled => _soundEnabled;
}
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Notificaciones locales (llamadas entrantes, avisos).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  void Function(String? payload)? onTap;

  Future<void> init() async {
    if (_ready) return;
    try {
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(android: android, iOS: ios),
        onDidReceiveNotificationResponse: (resp) {
          onTap?.call(resp.payload);
        },
      );

      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'conecta_calls',
          'Llamadas Conecta',
          description: 'Notificaciones de videollamadas entrantes',
          importance: Importance.max,
          playSound: true,
          enableVibration: true,
        ),
      );
      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          'conecta_general',
          'Conecta',
          description: 'Avisos generales',
          importance: Importance.defaultImportance,
        ),
      );

      _ready = true;
    } catch (e) {
      debugPrint('NotificationService init: $e');
    }
  }

  Future<void> showIncomingCall({
    required String callerName,
    required String payload,
  }) async {
    if (!_ready) await init();
    try {
      await _plugin.show(
        id: 9001,
        title: 'Llamada entrante',
        body: '$callerName te está llamando · Toca para abrir',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'conecta_calls',
            'Llamadas Conecta',
            channelDescription: 'Videollamadas entrantes',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.call,
            fullScreenIntent: true,
            playSound: true,
            enableVibration: true,
            ongoing: true,
            autoCancel: false,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('showIncomingCall: $e');
    }
  }

  Future<void> cancelIncomingCall() async {
    try {
      await _plugin.cancel(id: 9001);
    } catch (_) {}
  }

  Future<void> showSimple({
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
    try {
      await _plugin.show(
        id: DateTime.now().millisecondsSinceEpoch % 100000,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'conecta_general',
            'Conecta',
            importance: Importance.defaultImportance,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('showSimple: $e');
    }
  }
}

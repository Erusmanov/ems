import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

/// Системные push-уведомления на телефон (запрос Михаила 02.08):
/// пользователь не смотрит в приложение постоянно — о пересечении
/// критического порога SOC сообщаем через шторку.
class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Гейт из настроек («Уведомление о низком SOC»).
  static bool enabled = true;

  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    _inited = true;
    // ВАЖНО: без DarwinInitializationSettings инициализация на iOS кидала
    // исключение прямо в main() → вечный белый экран (репорт Михаила 23.08)
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      await _plugin.initialize(
          settings: const InitializationSettings(
              android: android, iOS: darwin));
      await Permission.notification.request();
    } catch (_) {
      // уведомления не критичны — приложение должно запускаться всегда
    }
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'soc_alerts',
      'Заряд батарей',
      channelDescription:
          'Предупреждения о низком заряде банков АКБ',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  /// SOC банка пересёк критический порог (сверху вниз).
  static Future<void> lowSoc(
      String bankName, double soc, double threshold) async {
    if (!enabled) return;
    try {
      await _plugin.show(
        id: bankName.hashCode & 0x7fffffff,
        title: 'Критический заряд',
        body: '«$bankName»: SOC ${soc.toStringAsFixed(0)} % — ниже '
            'критического порога ${threshold.round()} %',
        notificationDetails: _details,
      );
    } catch (_) {
      // уведомления не критичны для работы приложения
    }
  }
}

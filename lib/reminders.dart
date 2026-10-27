import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'db.dart';
import 'models.dart';
import 'settings.dart';

/// Ежедневные напоминания о повторении.
///
/// Уведомления планируются на ближайшие [_days] дней вперёд и пересоздаются
/// при каждом открытии главного экрана. Если приложение не открывать две
/// недели, напоминания прекратятся сами.
class Reminders {
  Reminders._();
  static final Reminders instance = Reminders._();

  static const int _days = 14;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  /// Последняя ошибка (для диагностики в настройках).
  String? lastError;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'daily_review',
      'Ежедневное напоминание',
      channelDescription: 'Напоминание о повторении слов',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Можно ли ставить точные будильники (нужно для уведомлений ровно в срок).
  Future<bool> canScheduleExact() async {
    if (!await _init()) return false;
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Открывает системный экран «Будильники и напоминания».
  Future<void> requestExact() async {
    if (!await _init()) return;
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (e) {
      lastError = '$e';
    }
  }

  Future<bool> notificationsEnabled() async {
    if (!await _init()) return false;
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<int> pendingCount() async {
    if (!await _init()) return -1;
    try {
      return (await _plugin.pendingNotificationRequests()).length;
    } catch (e) {
      lastError = '$e';
      return -1;
    }
  }

  /// Показывает уведомление сразу. Возвращает null, если всё хорошо,
  /// иначе текст ошибки.
  Future<String?> showNow() async {
    if (!await _init()) return 'Не удалось инициализировать: $lastError';
    try {
      await _plugin.show(
          900, 'Немецкие слова', 'Проверка: уведомления работают.', _details);
      return null;
    } catch (e) {
      lastError = '$e';
      return '$e';
    }
  }

  /// Ставит тестовое уведомление через [seconds] секунд.
  Future<String?> scheduleTest({int seconds = 60}) async {
    if (!await _init()) return 'Не удалось инициализировать: $lastError';
    try {
      final exact = await canScheduleExact();
      await _plugin.zonedSchedule(
        901,
        'Немецкие слова',
        'Проверка: запланированное уведомление пришло.',
        tz.TZDateTime.from(
            DateTime.now().add(Duration(seconds: seconds)), tz.UTC),
        _details,
        androidScheduleMode: exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      return null;
    } catch (e) {
      lastError = '$e';
      return '$e';
    }
  }

  Future<bool> _init() async {
    if (_inited) return true;
    try {
      tz_data.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      _inited = true;
      return true;
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }

  /// Просит у системы разрешение на уведомления (Android 13+).
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> cancel() async {
    if (!await _init()) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Пересоздаёт напоминания по текущим настройкам.
  ///
  /// [dueCount] — сколько слов к повторению сейчас (попадает в текст ближайшего
  /// уведомления). [skipToday] — сегодня уже занимались, сегодняшнее
  /// напоминание не нужно.
  Future<void> sync({int dueCount = 0, bool skipToday = false}) async {
    final s = AppSettings.instance;
    if (!s.reminderEnabled) {
      await cancel();
      return;
    }
    if (!await _init()) return;
    try {
      await _plugin.cancelAll();
      final exact = await canScheduleExact();
      final now = DateTime.now();
      final hour = s.reminderMinutes ~/ 60;
      final minute = s.reminderMinutes % 60;
      var first = true;
      for (var i = 0; i < _days; i++) {
        final local = DateTime(now.year, now.month, now.day + i, hour, minute);
        if (!local.isAfter(now)) continue;
        if (i == 0 && skipToday) continue;
        final body = (first && dueCount > 0)
            ? 'К повторению: ${wordsCount(dueCount)}. Загляните на несколько минут.'
            : 'Пора повторить немецкие слова.';
        first = false;
        await _plugin.zonedSchedule(
          i + 1,
          'Немецкие слова',
          body,
          tz.TZDateTime.from(local, tz.UTC),
          _details,
          androidScheduleMode: exact
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
      lastError = null;
    } catch (e) {
      // Уведомления — дополнительная функция, ошибка не должна ломать приложение.
      lastError = '$e';
    }
  }
}

/// Обновляет напоминания с учётом того, сколько слов ждёт повторения и
/// занимался ли пользователь сегодня. Если напоминания выключены — ничего не
/// делает.
Future<void> refreshReminders() async {
  if (!AppSettings.instance.reminderEnabled) return;
  try {
    final plan = await AppDb.instance.buildReviewPlan();
    final now = DateTime.now();
    final today = await AppDb.instance
        .answersSince(DateTime(now.year, now.month, now.day));
    await Reminders.instance.sync(
      dueCount: plan.dueCount + plan.staleCount,
      skipToday: today > 0,
    );
  } catch (_) {}
}

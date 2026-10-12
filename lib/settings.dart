import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Настройки приложения. Хранятся на устройстве (shared_preferences).
class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  SharedPreferences? _prefs;

  /// Тема оформления.
  ThemeMode themeMode = ThemeMode.system;

  /// Произносить немецкое слово автоматически, когда оно показано.
  bool autoSpeak = false;

  /// Скорость речи (0.2–0.8).
  double speechRate = 0.45;

  /// Мягкая проверка письма по умолчанию (иначе — строгая).
  bool softCheck = false;

  /// Сколько вопросов в сессии «умного повторения».
  int sessionSize = 20;

  /// Сколько новых слов добавлять в одну сессию.
  int newPerSession = 5;

  /// Через сколько дней без письменного ответа слово считается «давно не писали».
  int staleDays = 7;

  /// Ежедневное напоминание о повторении.
  bool reminderEnabled = false;

  /// Время напоминания: минут от полуночи (по умолчанию 19:00).
  int reminderMinutes = 19 * 60;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _prefs = p;
      final tm = p.getString('themeMode');
      themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == tm,
        orElse: () => ThemeMode.system,
      );
      autoSpeak = p.getBool('autoSpeak') ?? autoSpeak;
      speechRate = p.getDouble('speechRate') ?? speechRate;
      softCheck = p.getBool('softCheck') ?? softCheck;
      sessionSize = p.getInt('sessionSize') ?? sessionSize;
      newPerSession = p.getInt('newPerSession') ?? newPerSession;
      staleDays = p.getInt('staleDays') ?? staleDays;
      reminderEnabled = p.getBool('reminderEnabled') ?? reminderEnabled;
      reminderMinutes = p.getInt('reminderMinutes') ?? reminderMinutes;
    } catch (_) {
      // Без сохранённых настроек приложение работает со значениями по умолчанию.
    }
  }

  /// Меняет настройки и сохраняет их.
  Future<void> update(void Function() change) async {
    change();
    notifyListeners();
    final p = _prefs;
    if (p == null) return;
    try {
      await p.setString('themeMode', themeMode.name);
      await p.setBool('autoSpeak', autoSpeak);
      await p.setDouble('speechRate', speechRate);
      await p.setBool('softCheck', softCheck);
      await p.setInt('sessionSize', sessionSize);
      await p.setInt('newPerSession', newPerSession);
      await p.setInt('staleDays', staleDays);
      await p.setBool('reminderEnabled', reminderEnabled);
      await p.setInt('reminderMinutes', reminderMinutes);
    } catch (_) {}
  }
}

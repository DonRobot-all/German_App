import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../backup.dart';
import '../db.dart';
import '../reminders.dart';
import '../settings.dart';
import '../tts.dart';
import '../updater.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final AppSettings _s = AppSettings.instance;
  bool _checking = false;
  bool _busy = false;
  DateTime? _lastBackup;

  @override
  void initState() {
    super.initState();
    _loadLastBackup();
  }

  Future<void> _loadLastBackup() async {
    final t = await lastBackupTime();
    if (!mounted) return;
    setState(() => _lastBackup = t);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Сохраняет все данные в файл и открывает окно «Поделиться»: оттуда файл
  /// можно отправить в Telegram, на Диск или сохранить в «Файлы».
  Future<void> _backup() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final json = await buildBackupJson();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${backupFileName(DateTime.now())}');
      await file.writeAsString(json, flush: true);
      final res = await Share.shareXFiles(
        [XFile(file.path, mimeType: 'application/json')],
        subject: 'Резервная копия «Немецкие слова»',
      );
      if (res.status != ShareResultStatus.dismissed) {
        await markBackupDone();
        await _loadLastBackup();
      }
    } catch (e) {
      _snack('Не удалось сделать копию: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Выбор файла копии и восстановление из него.
  Future<void> _restore() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final pick = await FilePicker.platform
          .pickFiles(type: FileType.any, withData: true);
      if (pick == null || pick.files.isEmpty) return;
      final bytes = pick.files.single.bytes;
      if (bytes == null) {
        _snack('Не удалось прочитать файл');
        return;
      }
      final BackupData data;
      try {
        data = parseBackup(utf8.decode(bytes));
      } on FormatException catch (e) {
        _snack('Файл не подходит: ${e.message}');
        return;
      }
      if (!mounted) return;
      final when = data.created == null
          ? 'дата неизвестна'
          : formatBackupDate(data.created!);
      final mode = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Восстановить из копии?'),
          content: Text(
            'Копия от $when\n'
            'Наборов: ${data.setCount}, слов: ${data.wordCount}, '
            'записей прогресса: ${data.progressCount}.\n\n'
            '«Объединить»: добавит то, чего нет на телефоне, а если запись '
            'есть и там и там, оставит более свежую.\n\n'
            '«Заменить всё»: сотрёт все данные в приложении и поставит данные '
            'из копии.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('Объединить'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('Заменить всё'),
            ),
          ],
        ),
      );
      if (mode == null) return;
      final r = await restoreBackup(data, replace: mode == 'replace');
      _snack('Готово: наборов ${r.sets}, слов ${r.words}, прогресса ${r.progress}');
    } catch (e) {
      _snack('Не удалось восстановить: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
  String? _updateText;
  UpdateInfo? _updateInfo;

  Future<void> _checkUpdates() async {
    setState(() {
      _checking = true;
      _updateText = null;
      _updateInfo = null;
    });
    final r = await checkForUpdate();
    if (!mounted) return;
    setState(() {
      _checking = false;
      switch (r.status) {
        case UpdateStatus.available:
          _updateInfo = r.info;
          _updateText = 'Доступна новая версия: сборка ${r.info!.build}.';
        case UpdateStatus.upToDate:
          _updateText = 'У вас последняя версия.';
        case UpdateStatus.unknown:
          _updateText = r.message ?? 'Не удалось проверить обновления.';
      }
    });
  }

  void _change(void Function() f) {
    _s.update(f);
    setState(() {});
  }

  Widget _section(String title) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 6),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _intChoice({
    required List<int> values,
    required int current,
    required void Function(int) onChanged,
    String Function(int)? label,
  }) {
    final list = values.contains(current) ? values : [...values, current];
    return SegmentedButton<int>(
      showSelectedIcon: false,
      segments: [
        for (final v in list)
          ButtonSegment<int>(
            value: v,
            label: Text(label == null ? '$v' : label(v)),
          ),
      ],
      selected: {current},
      onSelectionChanged: (sel) => onChanged(sel.first),
    );
  }

  String get _reminderTimeText {
    final m = _s.reminderMinutes;
    final h = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '$h:$mm';
  }

  Future<void> _toggleReminder(bool value) async {
    if (value) {
      final granted = await Reminders.instance.requestPermission();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Нет разрешения на уведомления. Разрешите их для приложения '
              'в настройках Android.',
            ),
          ),
        );
        return;
      }
    }
    _change(() => _s.reminderEnabled = value);
    if (value) {
      await refreshReminders();
    } else {
      await Reminders.instance.cancel();
    }
  }

  Future<void> _pickReminderTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _s.reminderMinutes ~/ 60,
        minute: _s.reminderMinutes % 60,
      ),
    );
    if (t == null) return;
    _change(() => _s.reminderMinutes = t.hour * 60 + t.minute);
    await refreshReminders();
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Сбросить прогресс?'),
        content: const Text(
          'Все уровни, ошибки и статистика будут стёрты. '
          'Сами слова и наборы останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AppDb.instance.resetProgress();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Прогресс сброшен')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          _section('Тема'),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                label: Text('Системная'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                label: Text('Светлая'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                label: Text('Тёмная'),
              ),
            ],
            selected: {_s.themeMode},
            onSelectionChanged: (sel) => _change(() => _s.themeMode = sel.first),
          ),
          _section('Озвучка'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Произносить автоматически'),
            subtitle: const Text(
              'Немецкое слово звучит, когда оно показано или раскрыто',
            ),
            value: _s.autoSpeak,
            onChanged: (v) => _change(() => _s.autoSpeak = v),
          ),
          Text('Скорость речи', style: theme.textTheme.bodyMedium),
          Slider(
            value: _s.speechRate.clamp(0.2, 0.8).toDouble(),
            min: 0.2,
            max: 0.8,
            divisions: 12,
            label: _s.speechRate.toStringAsFixed(2),
            onChanged: (v) => _change(() => _s.speechRate = v),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () =>
                  Speaker.instance.speak('Guten Tag! Wie geht es dir?'),
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('Проверить звучание'),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Нет звука? Установите немецкий голос в настройках Android: '
            'Язык и ввод → Синтез речи → Голосовой движок Google → '
            'Установить голосовые данные → Немецкий.',
            style: theme.textTheme.bodySmall,
          ),
          _section('Проверка письменных ответов'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Мягкая проверка по умолчанию'),
            subtitle: const Text(
              'ae/oe/ue вместо ä/ö/ü, любой регистр, опечатка в одну букву. '
              'Артикль обязателен всегда. Выключено — строгая проверка.',
            ),
            value: _s.softCheck,
            onChanged: (v) => _change(() => _s.softCheck = v),
          ),
          _section('Умное повторение'),
          Text('Вопросов в сессии', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          _intChoice(
            values: const [10, 20, 30, 50],
            current: _s.sessionSize,
            onChanged: (v) => _change(() => _s.sessionSize = v),
          ),
          const SizedBox(height: 16),
          Text('Новых слов за сессию', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          _intChoice(
            values: const [0, 3, 5, 10],
            current: _s.newPerSession,
            onChanged: (v) => _change(() => _s.newPerSession = v),
          ),
          const SizedBox(height: 16),
          Text(
            '«Давно не писали» — через сколько дней без письменного ответа',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 6),
          _intChoice(
            values: const [3, 7, 14, 30],
            current: _s.staleDays,
            onChanged: (v) => _change(() => _s.staleDays = v),
            label: (v) => '$v дн.',
          ),
          _section('Напоминание'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Ежедневное напоминание'),
            subtitle: const Text(
              'Уведомление в выбранное время. Если сегодня вы уже занимались, '
              'оно не придёт.',
            ),
            value: _s.reminderEnabled,
            onChanged: _toggleReminder,
          ),
          if (_s.reminderEnabled)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Время напоминания'),
              trailing: Text(
                _reminderTimeText,
                style: theme.textTheme.titleMedium,
              ),
              onTap: _pickReminderTime,
            ),
          if (_s.reminderEnabled)
            Text(
              'Напоминания планируются на 14 дней вперёд и обновляются при '
              'каждом открытии приложения. Если не открывать его две недели, '
              'они прекратятся.',
              style: theme.textTheme.bodySmall,
            ),
          _section('О приложении'),
          Text(
            kBuildNumber > 0
                ? 'Сборка $kBuildNumber'
                : 'Сборка без номера (локальная)',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _checking ? null : _checkUpdates,
              icon: const Icon(Icons.system_update_alt),
              label: Text(_checking ? 'Проверяю…' : 'Проверить обновления'),
            ),
          ),
          if (_updateText != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_updateText!, style: theme.textTheme.bodyMedium),
            ),
          if (_updateInfo != null)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton(
                  onPressed: () => openDownload(_updateInfo!),
                  child: const Text('Скачать и установить'),
                ),
              ),
            ),
          _section('Данные'),
          Text(
            _lastBackup == null
                ? 'Резервная копия ещё не делалась.'
                : 'Последняя копия: ${formatBackupDate(_lastBackup!)}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'В копию входят все наборы, слова, уровни и статистика. При '
            'переустановке приложения без копии всё будет потеряно.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _backup,
                icon: const Icon(Icons.upload_file),
                label: const Text('Сохранить копию'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _restore,
                icon: const Icon(Icons.download),
                label: const Text('Восстановить'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _confirmReset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Сбросить прогресс обучения'),
            ),
          ),
        ],
      ),
    );
  }
}

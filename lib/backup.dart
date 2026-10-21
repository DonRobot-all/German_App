import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'db.dart';

/// Версия формата файла резервной копии.
const int kBackupFormat = 1;

/// Таблицы, которые входят в копию (в порядке восстановления).
const List<String> kBackupTables = [
  'word_sets',
  'words',
  'set_words',
  'word_progress',
  'answer_log',
];

const String _kLastBackupKey = 'last_backup_ms';

/// Разобранный файл копии.
class BackupData {
  const BackupData(this.created, this.tables);

  final DateTime? created;
  final Map<String, List<Map<String, Object?>>> tables;

  List<Map<String, Object?>> rows(String table) => tables[table] ?? const [];

  int get setCount => rows('word_sets').where((r) => r['deleted'] != 1).length;
  int get wordCount => rows('words').where((r) => r['deleted'] != 1).length;
  int get progressCount => rows('word_progress').length;
}

/// Сколько записей добавлено или обновлено при восстановлении.
class RestoreResult {
  const RestoreResult(this.sets, this.words, this.progress);

  final int sets;
  final int words;
  final int progress;
}

/// Собирает все данные приложения в одну JSON-строку.
Future<String> buildBackupJson() async {
  final d = await AppDb.instance.db;
  final tables = <String, Object?>{};
  for (final t in kBackupTables) {
    tables[t] = await d.query(t);
  }
  return jsonEncode(<String, Object?>{
    'app': 'german_words',
    'format': kBackupFormat,
    'created': DateTime.now().millisecondsSinceEpoch,
    'tables': tables,
  });
}

/// Разбирает и проверяет файл копии. При ошибке бросает [FormatException]
/// с понятным сообщением.
BackupData parseBackup(String text) {
  final Object? json;
  try {
    json = jsonDecode(text);
  } on FormatException {
    throw const FormatException('это не файл резервной копии');
  }
  if (json is! Map || json['app'] != 'german_words') {
    throw const FormatException('это не файл резервной копии этого приложения');
  }
  final format = json['format'];
  if (format is! int || format > kBackupFormat) {
    throw const FormatException(
      'копия создана более новой версией приложения, обновите приложение',
    );
  }
  final rawTables = json['tables'];
  if (rawTables is! Map) {
    throw const FormatException('в файле нет данных');
  }
  final tables = <String, List<Map<String, Object?>>>{};
  for (final t in kBackupTables) {
    final raw = rawTables[t];
    if (raw == null) continue;
    if (raw is! List) throw FormatException('повреждена таблица «$t»');
    tables[t] = [
      for (final r in raw)
        if (r is Map)
          Map<String, Object?>.from(r)
        else
          throw FormatException('повреждена таблица «$t»'),
    ];
  }
  final created = json['created'];
  return BackupData(
    created is int ? DateTime.fromMillisecondsSinceEpoch(created) : null,
    tables,
  );
}

num _updatedAt(Object? v) => v is num ? v : 0;

/// Ключ строки в таблице для сравнения копии с текущими данными.
String _rowKey(String table, Map<String, Object?> r) {
  switch (table) {
    case 'set_words':
      return '${r['set_id']}|${r['word_id']}';
    case 'word_progress':
      return '${r['word_id']}|${r['direction']}';
    case 'answer_log':
      return '${r['ts']}|${r['word_id']}|${r['direction']}';
    default:
      return '${r['id']}';
  }
}

/// Восстанавливает данные из копии.
///
/// [replace] = true: сначала стирает все текущие данные приложения.
/// [replace] = false: объединяет. Недостающее добавляется, а если запись есть
/// и там и там, остаётся более свежая (по updated_at).
Future<RestoreResult> restoreBackup(
  BackupData backup, {
  required bool replace,
}) async {
  final d = await AppDb.instance.db;
  var sets = 0;
  var words = 0;
  var progress = 0;

  await d.transaction((txn) async {
    // Берём только те столбцы, которые есть в текущей базе: так копия от
    // другой версии приложения не сломает вставку.
    final columns = <String, Set<String>>{};
    for (final t in kBackupTables) {
      final info = await txn.rawQuery('PRAGMA table_info($t)');
      columns[t] = {for (final r in info) r['name'] as String};
    }

    if (replace) {
      for (final t in kBackupTables) {
        await txn.delete(t);
      }
    }

    for (final t in kBackupTables) {
      final cols = columns[t]!;
      // Что уже есть: ключ → updated_at (для answer_log updated_at нет).
      final existing = <String, num>{};
      if (!replace) {
        final rows = await txn.query(t);
        for (final r in rows) {
          existing[_rowKey(t, r)] = _updatedAt(r['updated_at']);
        }
      }

      for (final raw in backup.rows(t)) {
        final key = _rowKey(t, raw);
        final have = existing[key];
        if (have != null) {
          // Журнал ответов не перезаписываем; остальное только если копия свежее.
          if (t == 'answer_log') continue;
          if (_updatedAt(raw['updated_at']) <= have) continue;
        }
        final clean = <String, Object?>{
          for (final e in raw.entries)
            if (cols.contains(e.key) && !(t == 'answer_log' && e.key == 'id'))
              e.key: e.value,
        };
        await txn.insert(t, clean, conflictAlgorithm: ConflictAlgorithm.replace);
        existing[key] = _updatedAt(raw['updated_at']);
        if (t == 'word_sets') sets++;
        if (t == 'words') words++;
        if (t == 'word_progress') progress++;
      }
    }
  });
  return RestoreResult(sets, words, progress);
}

/// Когда в последний раз выгружали копию (по данным этого телефона).
Future<DateTime?> lastBackupTime() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt(_kLastBackupKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  } catch (_) {
    return null;
  }
}

Future<void> markBackupDone() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastBackupKey, DateTime.now().millisecondsSinceEpoch);
  } catch (_) {}
}

String _two(int n) => n.toString().padLeft(2, '0');

String formatBackupDate(DateTime t) =>
    '${_two(t.day)}.${_two(t.month)}.${t.year} ${_two(t.hour)}:${_two(t.minute)}';

/// Имя файла копии: german-words-backup-2026-10-21.json
String backupFileName(DateTime t) =>
    'german-words-backup-${t.year}-${_two(t.month)}-${_two(t.day)}.json';

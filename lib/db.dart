import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

/// Локальная база данных (SQLite).
///
/// Задел под будущую синхронизацию: у всех записей UUID-идентификаторы,
/// поле updated_at и «мягкое» удаление (deleted = 1).
class AppDb {
  AppDb._();
  static final AppDb instance = AppDb._();

  static final Uuid _uuid = Uuid();
  Database? _db;

  String newId() => _uuid.v4();

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'german_words.db');
    return openDatabase(path, version: 1, onCreate: _onCreate);
  }

  Future<void> _onCreate(Database d, int version) async {
    await d.execute('''
      CREATE TABLE word_sets(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE words(
        id TEXT PRIMARY KEY,
        german TEXT NOT NULL,
        article TEXT,
        plural TEXT,
        pos TEXT NOT NULL,
        translations TEXT NOT NULL,
        example TEXT,
        note TEXT,
        present3 TEXT,
        preterite TEXT,
        perfect TEXT,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0
      )''');
    await d.execute('''
      CREATE TABLE set_words(
        set_id TEXT NOT NULL,
        word_id TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        deleted INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY(set_id, word_id)
      )''');
    // Прогресс по словам (понадобится в итерациях 2–4: тренировка и повторение).
    // Отдельная запись на каждое направление: 'ru_de' и 'de_ru'.
    await d.execute('''
      CREATE TABLE word_progress(
        word_id TEXT NOT NULL,
        direction TEXT NOT NULL,
        level INTEGER NOT NULL DEFAULT 0,
        next_due INTEGER,
        last_seen INTEGER,
        last_written INTEGER,
        errors INTEGER NOT NULL DEFAULT 0,
        streak INTEGER NOT NULL DEFAULT 0,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY(word_id, direction)
      )''');
  }

  // ---------- Наборы ----------

  Future<List<WordSet>> listSets() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT s.id, s.name, s.description,
        (SELECT COUNT(*) FROM set_words sw
           JOIN words w ON w.id = sw.word_id
          WHERE sw.set_id = s.id AND sw.deleted = 0 AND w.deleted = 0) AS cnt
      FROM word_sets s
      WHERE s.deleted = 0
      ORDER BY s.name COLLATE NOCASE
    ''');
    return rows
        .map((r) => WordSet(
              id: r['id'] as String,
              name: r['name'] as String,
              description: r['description'] as String,
              wordCount: (r['cnt'] as num).toInt(),
            ))
        .toList();
  }

  Future<void> createSet(String name, String description) async {
    final d = await db;
    await d.insert('word_sets', {
      'id': newId(),
      'name': name,
      'description': description,
      'updated_at': _now(),
      'deleted': 0,
    });
  }

  Future<void> updateSet(String id, String name, String description) async {
    final d = await db;
    await d.update(
      'word_sets',
      {'name': name, 'description': description, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteSet(String id) async {
    final d = await db;
    await d.update(
      'word_sets',
      {'deleted': 1, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------- Слова ----------

  Future<List<Word>> listWords(String setId) async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT w.* FROM words w
        JOIN set_words sw ON sw.word_id = w.id
       WHERE sw.set_id = ? AND sw.deleted = 0 AND w.deleted = 0
       ORDER BY w.german COLLATE NOCASE
    ''', [setId]);
    return rows.map(Word.fromMap).toList();
  }

  /// Создаёт или обновляет слово и привязывает его к набору.
  Future<void> saveWord(Word word, String setId) async {
    final d = await db;
    final now = _now();
    await d.transaction((txn) async {
      await txn.insert(
        'words',
        word.toMap(now),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        'set_words',
        {
          'set_id': setId,
          'word_id': word.id,
          'updated_at': now,
          'deleted': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> deleteWord(String id) async {
    final d = await db;
    await d.update(
      'words',
      {'deleted': 1, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

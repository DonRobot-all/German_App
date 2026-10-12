import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';
import 'settings.dart';
import 'srs.dart';
import 'stats.dart';

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
    return openDatabase(
      path,
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onUpgrade(Database d, int oldVersion, int newVersion) async {
    // v2: журнал ответов для статистики.
    if (oldVersion < 2) await _createLog(d);
  }

  Future<void> _createLog(Database d) async {
    await d.execute('''
      CREATE TABLE IF NOT EXISTS answer_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ts INTEGER NOT NULL,
        word_id TEXT NOT NULL,
        direction TEXT NOT NULL,
        correct INTEGER NOT NULL,
        written INTEGER NOT NULL
      )''');
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
    await _createLog(d);
  }

  // ---------- Прогресс и повторение ----------

  /// Весь прогресс, ключ — progressKey(слово, направление).
  Future<Map<String, WordProgress>> loadProgress() async {
    final d = await db;
    final rows = await d.query('word_progress');
    final result = <String, WordProgress>{};
    for (final r in rows) {
      final p = WordProgress.fromMap(r);
      result[progressKey(p.wordId, p.direction)] = p;
    }
    return result;
  }

  /// Записывает ответ пользователя и пересчитывает уровень и срок показа.
  Future<void> recordAnswer(
    String wordId,
    String direction, {
    required bool correct,
    required bool written,
  }) async {
    final d = await db;
    final rows = await d.query(
      'word_progress',
      where: 'word_id = ? AND direction = ?',
      whereArgs: [wordId, direction],
    );
    final old = rows.isEmpty ? null : WordProgress.fromMap(rows.first);
    final now = DateTime.now();
    final updated = applyAnswer(
      old,
      wordId: wordId,
      direction: direction,
      correct: correct,
      written: written,
      now: now,
    );
    await d.insert(
      'word_progress',
      updated.toMap(now),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    await _log(d, wordId, direction, correct: correct, written: written);
  }

  Future<void> _log(
    Database d,
    String wordId,
    String direction, {
    required bool correct,
    required bool written,
  }) async {
    await d.insert('answer_log', {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'word_id': wordId,
      'direction': direction,
      'correct': correct ? 1 : 0,
      'written': written ? 1 : 0,
    });
  }

  /// Повторный верный письменный ответ внутри сессии после ошибки:
  /// уровень и срок не меняются, обновляется только «когда писали».
  Future<void> touchWritten(String wordId, String direction) async {
    final d = await db;
    final now = DateTime.now().millisecondsSinceEpoch;
    await d.update(
      'word_progress',
      {'last_seen': now, 'last_written': now, 'updated_at': now},
      where: 'word_id = ? AND direction = ?',
      whereArgs: [wordId, direction],
    );
    await _log(d, wordId, direction, correct: true, written: true);
  }

  /// Собирает очередь «умного повторения» по всем словам приложения.
  Future<ReviewPlan> buildReviewPlan() async {
    final words = await listAllWords();
    final progress = await loadProgress();
    final s = AppSettings.instance;
    return buildPlan(
      words: words,
      progress: progress,
      now: DateTime.now(),
      sessionSize: s.sessionSize,
      newLimit: s.newPerSession,
      staleDays: s.staleDays,
    );
  }

  /// Данные для экрана статистики.
  Future<StatsData> loadStats() async {
    final d = await db;
    final words = await listAllWords();
    final progress = await loadProgress();
    final since = DateTime.now()
        .subtract(const Duration(days: 400))
        .millisecondsSinceEpoch;
    final rows = await d.query(
      'answer_log',
      columns: ['ts', 'correct'],
      where: 'ts >= ?',
      whereArgs: [since],
      orderBy: 'ts',
    );
    final log = [
      for (final r in rows)
        AnswerLogEntry(
          DateTime.fromMillisecondsSinceEpoch((r['ts'] as num).toInt()),
          (r['correct'] as num).toInt() == 1,
        ),
    ];
    return buildStats(
      words: words,
      progress: progress,
      log: log,
      now: DateTime.now(),
    );
  }

  /// Сколько ответов дано начиная с момента [t].
  Future<int> answersSince(DateTime t) async {
    final d = await db;
    final rows = await d.rawQuery(
      'SELECT COUNT(*) AS c FROM answer_log WHERE ts >= ?',
      [t.millisecondsSinceEpoch],
    );
    return rows.isEmpty ? 0 : (rows.first['c'] as num).toInt();
  }

  /// Стирает весь прогресс обучения и журнал ответов (слова остаются).
  Future<void> resetProgress() async {
    final d = await db;
    await d.delete('word_progress');
    await d.delete('answer_log');
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

  /// Все слова приложения (из всех наборов, без дублей).
  /// Нужны, чтобы подбирать неверные варианты ответа в тесте.
  Future<List<Word>> listAllWords() async {
    final d = await db;
    final rows = await d.rawQuery('''
      SELECT DISTINCT w.* FROM words w
        JOIN set_words sw ON sw.word_id = w.id
        JOIN word_sets s ON s.id = sw.set_id
       WHERE w.deleted = 0 AND sw.deleted = 0 AND s.deleted = 0
    ''');
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

  /// Добавляет много слов в набор одной транзакцией (импорт).
  Future<void> addWords(String setId, List<Word> words) async {
    if (words.isEmpty) return;
    final d = await db;
    final now = _now();
    await d.transaction((txn) async {
      final batch = txn.batch();
      for (final w in words) {
        batch.insert(
          'words',
          w.toMap(now),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        batch.insert(
          'set_words',
          {
            'set_id': setId,
            'word_id': w.id,
            'updated_at': now,
            'deleted': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
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

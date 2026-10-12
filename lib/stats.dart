import 'models.dart';
import 'srs.dart';

/// Один ответ из журнала.
class AnswerLogEntry {
  const AnswerLogEntry(this.time, this.correct);

  final DateTime time;
  final bool correct;
}

class ProblemWord {
  const ProblemWord(this.word, this.errors);

  final Word word;
  final int errors;
}

class StatsData {
  const StatsData({
    required this.totalWords,
    required this.newWords,
    required this.learningWords,
    required this.learnedWords,
    required this.levelCounts,
    required this.problems,
    required this.streak,
    required this.answersToday,
    required this.answersWeek,
    required this.correctWeek,
    required this.last14,
    required this.totalAnswers,
  });

  final int totalWords;

  /// Слова, по которым ещё не было ни одного ответа.
  final int newWords;

  /// Слова в процессе изучения.
  final int learningWords;

  /// Слова, у которых оба направления дошли до последнего уровня.
  final int learnedWords;

  /// Сколько направлений слов на каждом уровне (0–6).
  final List<int> levelCounts;

  /// Слова с наибольшим числом ошибок.
  final List<ProblemWord> problems;

  /// Сколько дней подряд были занятия.
  final int streak;
  final int answersToday;
  final int answersWeek;
  final int correctWeek;

  /// Число ответов по дням, последние 14 дней (последний элемент — сегодня).
  final List<int> last14;
  final int totalAnswers;
}

int dayKey(DateTime t) => t.year * 10000 + t.month * 100 + t.day;

StatsData buildStats({
  required List<Word> words,
  required Map<String, WordProgress> progress,
  required List<AnswerLogEntry> log,
  required DateTime now,
}) {
  var newWords = 0;
  var learning = 0;
  var learned = 0;
  final levelCounts = List<int>.filled(kMaxLevel + 1, 0);
  final problems = <ProblemWord>[];

  for (final w in words) {
    final pDe = progress[progressKey(w.id, 'de_ru')];
    final pRu = progress[progressKey(w.id, 'ru_de')];
    for (final p in [pDe, pRu]) {
      if (p != null) {
        final lv = p.level.clamp(0, kMaxLevel).toInt();
        levelCounts[lv]++;
      }
    }
    if (pDe == null && pRu == null) {
      newWords++;
    } else if (pDe != null &&
        pRu != null &&
        pDe.level >= kMaxLevel &&
        pRu.level >= kMaxLevel) {
      learned++;
    } else {
      learning++;
    }
    final errors = (pDe?.errors ?? 0) + (pRu?.errors ?? 0);
    if (errors > 0) problems.add(ProblemWord(w, errors));
  }
  problems.sort((a, b) => b.errors.compareTo(a.errors));

  // Активность по дням.
  final perDay = <int, int>{};
  for (final e in log) {
    final k = dayKey(e.time);
    perDay[k] = (perDay[k] ?? 0) + 1;
  }
  final today = DateTime(now.year, now.month, now.day);

  var streak = 0;
  var cursor = today;
  if (!perDay.containsKey(dayKey(cursor))) {
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }
  while (perDay.containsKey(dayKey(cursor))) {
    streak++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
  }

  final last14 = <int>[
    for (var i = 13; i >= 0; i--)
      perDay[dayKey(DateTime(today.year, today.month, today.day - i))] ?? 0,
  ];

  final weekStart = DateTime(today.year, today.month, today.day - 6);
  var answersWeek = 0;
  var correctWeek = 0;
  for (final e in log) {
    if (!e.time.isBefore(weekStart)) {
      answersWeek++;
      if (e.correct) correctWeek++;
    }
  }

  return StatsData(
    totalWords: words.length,
    newWords: newWords,
    learningWords: learning,
    learnedWords: learned,
    levelCounts: levelCounts,
    problems: problems.take(10).toList(),
    streak: streak,
    answersToday: perDay[dayKey(today)] ?? 0,
    answersWeek: answersWeek,
    correctWeek: correctWeek,
    last14: last14,
    totalAnswers: log.length,
  );
}

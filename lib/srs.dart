import 'dart:math';

import 'models.dart';
import 'study.dart';

/// Через сколько показывать слово снова, в зависимости от уровня (0–6).
const List<Duration> kIntervals = [
  Duration(minutes: 10), // 0 — после ошибки
  Duration(days: 1), // 1
  Duration(days: 3), // 2
  Duration(days: 7), // 3
  Duration(days: 14), // 4
  Duration(days: 30), // 5
  Duration(days: 90), // 6 — слово считается выученным
];

const int kMaxLevel = 6;

/// Выше этого уровня слово не поднимается ответами «из вариантов» и
/// «знаю/не знаю»: угадать проще, чем написать. Дальше — только письмом.
const int kChoiceMaxLevel = 3;

String progressKey(String wordId, String direction) => '$wordId|$direction';

/// Прогресс по одному слову в одном направлении ('ru_de' или 'de_ru')
/// или по одному навыку ('article', 'forms', 'prep').
class WordProgress {
  const WordProgress({
    required this.wordId,
    required this.direction,
    required this.level,
    required this.errors,
    required this.streak,
    this.nextDue,
    this.lastSeen,
    this.lastWritten,
  });

  final String wordId;
  final String direction;
  final int level;
  final int errors;
  final int streak;
  final DateTime? nextDue;
  final DateTime? lastSeen;
  final DateTime? lastWritten;

  factory WordProgress.fromMap(Map<String, Object?> m) {
    DateTime? ts(Object? v) => v == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch((v as num).toInt());
    return WordProgress(
      wordId: m['word_id'] as String,
      direction: m['direction'] as String,
      level: (m['level'] as num).toInt(),
      errors: (m['errors'] as num).toInt(),
      streak: (m['streak'] as num).toInt(),
      nextDue: ts(m['next_due']),
      lastSeen: ts(m['last_seen']),
      lastWritten: ts(m['last_written']),
    );
  }

  Map<String, Object?> toMap(DateTime now) => {
        'word_id': wordId,
        'direction': direction,
        'level': level,
        'next_due': nextDue?.millisecondsSinceEpoch,
        'last_seen': lastSeen?.millisecondsSinceEpoch,
        'last_written': lastWritten?.millisecondsSinceEpoch,
        'errors': errors,
        'streak': streak,
        'updated_at': now.millisecondsSinceEpoch,
      };
}

/// Новый прогресс после ответа.
///
/// Верно: уровень +1 (ответом «из вариантов» не выше [kChoiceMaxLevel]).
/// Неверно: уровень 0, следующий показ через 10 минут, счётчик ошибок +1.
WordProgress applyAnswer(
  WordProgress? old, {
  required String wordId,
  required String direction,
  required bool correct,
  required bool written,
  required DateTime now,
}) {
  final level0 = old?.level ?? 0;
  var errors = old?.errors ?? 0;
  int level;
  int streak;
  if (correct) {
    if (written) {
      level = min(level0 + 1, kMaxLevel);
    } else {
      level = level0 >= kChoiceMaxLevel ? level0 : level0 + 1;
    }
    streak = (old?.streak ?? 0) + 1;
  } else {
    level = 0;
    errors += 1;
    streak = 0;
  }
  return WordProgress(
    wordId: wordId,
    direction: direction,
    level: level,
    errors: errors,
    streak: streak,
    nextDue: now.add(kIntervals[level]),
    lastSeen: now,
    lastWritten: written ? now : old?.lastWritten,
  );
}

/// Почему слово попало в сессию.
enum ReviewReason {
  /// Недавняя ошибка, срок (10 минут) наступил.
  relearn,

  /// Просрочено по лестнице интервалов.
  overdue,

  /// Давно не писали (или поднялось выше уровня 1 только выбором из вариантов).
  stale,

  /// Новое слово.
  fresh,
}

class ReviewItem {
  const ReviewItem(
    this.word,
    this.direction,
    this.reason,
    this.level, {
    this.aspect,
  });

  final Word word;

  /// Направление перевода. Для заданий-«аспектов» не используется.
  final QuestionDirection direction;
  final ReviewReason reason;
  final int level;

  /// null: обычный перевод слова. Иначе kAspectArticle / kAspectForms /
  /// kAspectPrep: отдельный навык этого слова.
  final String? aspect;

  /// Ключ в word_progress: 'ru_de', 'de_ru' или имя аспекта.
  String get progressDirection => aspect ?? dirKey(direction);
}

class ReviewPlan {
  const ReviewPlan({
    required this.items,
    required this.dueCount,
    required this.staleCount,
    required this.newCount,
    required this.wordCount,
    this.nextDue,
  });

  /// Вопросы будущей сессии (уже отобраны и перемешаны).
  final List<ReviewItem> items;

  /// Всего слов с наступившим сроком (ошибки + просроченные).
  final int dueCount;

  /// Всего слов, которые давно не писали.
  final int staleCount;

  /// Новых слов, доступных для изучения.
  final int newCount;

  /// Всего слов в приложении.
  final int wordCount;

  /// Ближайший срок среди ещё не наступивших.
  final DateTime? nextDue;
}

class _Cand {
  const _Cand(this.item, this.sortKey);

  final ReviewItem item;
  final int sortKey;
}

/// Собирает очередь для «умного повторения».
///
/// Приоритет: 1) недавние ошибки, срок которых наступил; 2) просроченные
/// слова (чем больше просрочка, тем выше); 3) слова, которые давно не
/// писали; 4) новые слова (не больше [newLimit] за сессию).
ReviewPlan buildPlan({
  required List<Word> words,
  required Map<String, WordProgress> progress,
  required DateTime now,
  int sessionSize = 20,
  int newLimit = 5,
  int staleDays = 7,
  Random? random,
}) {
  final rnd = random ?? Random();
  final relearn = <_Cand>[];
  final overdue = <_Cand>[];
  final stale = <_Cand>[];
  final freshFollow = <ReviewItem>[]; // RU→DE для уже начатых слов
  final freshNew = <ReviewItem>[]; // DE→RU для совсем новых слов
  DateTime? nextDue;

  /// Раскладывает уже начатое задание по спискам: ошибка, просрочено или
  /// «давно не писали». Для будущих сроков запоминает ближайший.
  void existing(
    WordProgress p,
    ReviewItem Function(ReviewReason reason, int level) make,
  ) {
    final due = p.nextDue;
    if (due == null || !due.isAfter(now)) {
      final overdueMs = due == null ? 0 : now.difference(due).inMilliseconds;
      if (p.level == 0) {
        relearn.add(_Cand(make(ReviewReason.relearn, p.level), overdueMs));
      } else {
        overdue.add(_Cand(make(ReviewReason.overdue, p.level), overdueMs));
      }
      return;
    }

    final soonest = nextDue;
    if (soonest == null || due.isBefore(soonest)) nextDue = due;

    // Срок по лестнице ещё не пришёл, но письменно слово давно не писали.
    if (p.level >= 1) {
      final lw = p.lastWritten;
      final bool isStale;
      final int age;
      if (lw == null) {
        // Письменно ещё ни разу: проверяем письмом, как только слово
        // перешло на уровень 2 одними вариантами ответа.
        isStale = p.level >= 2;
        age = p.lastSeen == null ? 0 : now.difference(p.lastSeen!).inMinutes;
      } else {
        final d = now.difference(lw);
        isStale = d > Duration(days: staleDays);
        age = d.inMinutes;
      }
      if (isStale) {
        stale.add(_Cand(make(ReviewReason.stale, p.level), age));
      }
    }
  }

  for (final w in words) {
    final pDeRu = progress[progressKey(w.id, 'de_ru')];
    final pRuDe = progress[progressKey(w.id, 'ru_de')];

    for (final dir in QuestionDirection.values) {
      final isRuDe = dir == QuestionDirection.ruToDe;
      final p = isRuDe ? pRuDe : pDeRu;

      if (p == null) {
        // Новое слово начинаем с DE→RU. RU→DE добавляем, когда DE→RU уже
        // хотя бы раз был пройден верно (уровень 1 и выше).
        if (!isRuDe) {
          freshNew.add(ReviewItem(w, dir, ReviewReason.fresh, 0));
        } else if (pDeRu != null && pDeRu.level >= 1) {
          freshFollow.add(ReviewItem(w, dir, ReviewReason.fresh, 0));
        }
        continue;
      }
      existing(p, (r, lv) => ReviewItem(w, dir, r, lv));
    }

    // Артикль, формы глагола, предлог: отдельные навыки со своими уровнями.
    // Начинаем их, когда само слово уже хотя бы раз пройдено верно.
    for (final asp in w.aspects) {
      final pa = progress[progressKey(w.id, asp)];
      ReviewItem make(ReviewReason r, int lv) =>
          ReviewItem(w, QuestionDirection.deToRu, r, lv, aspect: asp);
      if (pa == null) {
        if (pDeRu != null && pDeRu.level >= 1) {
          freshFollow.add(make(ReviewReason.fresh, 0));
        }
      } else {
        existing(pa, make);
      }
    }
  }

  relearn.sort((a, b) => b.sortKey.compareTo(a.sortKey));
  overdue.sort((a, b) => b.sortKey.compareTo(a.sortKey));
  stale.sort((a, b) => b.sortKey.compareTo(a.sortKey));
  freshNew.shuffle(rnd);
  freshFollow.shuffle(rnd);

  final picked = <ReviewItem>[];
  var room = sessionSize;
  for (final list in [relearn, overdue, stale]) {
    for (final c in list) {
      if (room <= 0) break;
      picked.add(c.item);
      room--;
    }
  }
  final freshAll = [...freshFollow, ...freshNew];
  final newTake = min(min(newLimit, room), freshAll.length);
  for (var i = 0; i < newTake; i++) {
    picked.add(freshAll[i]);
  }

  // Перемешиваем, чтобы сессия не была предсказуемой, и разводим
  // два вопроса по одному слову, чтобы они не шли подряд.
  picked.shuffle(rnd);
  for (var i = 1; i < picked.length; i++) {
    if (picked[i].word.id != picked[i - 1].word.id) continue;
    for (var k = i + 1; k < picked.length; k++) {
      if (picked[k].word.id != picked[i].word.id) {
        final t = picked[i];
        picked[i] = picked[k];
        picked[k] = t;
        break;
      }
    }
  }

  return ReviewPlan(
    items: picked,
    dueCount: relearn.length + overdue.length,
    staleCount: stale.length,
    newCount: freshAll.length,
    wordCount: words.length,
    nextDue: nextDue,
  );
}

/// «сегодня в 18:20», «завтра в 09:00» или «25.10».
String formatWhen(DateTime t, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final diff = day.difference(today).inDays;
  if (diff <= 0) return 'сегодня в ${two(t.hour)}:${two(t.minute)}';
  if (diff == 1) return 'завтра в ${two(t.hour)}:${two(t.minute)}';
  return '${two(t.day)}.${two(t.month)}';
}

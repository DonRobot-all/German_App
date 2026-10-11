import 'dart:math';

import 'models.dart';

/// Направление тренировки, которое выбирает пользователь.
enum StudyDirection { ruDe, deRu, mixed }

extension StudyDirectionLabel on StudyDirection {
  String get label {
    switch (this) {
      case StudyDirection.ruDe:
        return 'RU → DE';
      case StudyDirection.deRu:
        return 'DE → RU';
      case StudyDirection.mixed:
        return 'Вперемешку';
    }
  }
}

/// Направление одного конкретного вопроса.
enum QuestionDirection { ruToDe, deToRu }

QuestionDirection pickDirection(StudyDirection d, Random rnd) {
  switch (d) {
    case StudyDirection.ruDe:
      return QuestionDirection.ruToDe;
    case StudyDirection.deRu:
      return QuestionDirection.deToRu;
    case StudyDirection.mixed:
      return rnd.nextBool() ? QuestionDirection.ruToDe : QuestionDirection.deToRu;
  }
}

/// Ключ направления для хранения прогресса.
String dirKey(QuestionDirection d) =>
    d == QuestionDirection.ruToDe ? 'ru_de' : 'de_ru';

/// Все варианты перевода: «стол; столик».
String russianFull(Word w) => w.translations.join('; ');

/// Короткая форма для вариантов ответа (не больше двух переводов).
String russianShort(Word w) => w.translations.take(2).join('; ');

class QuizQuestion {
  const QuizQuestion({
    required this.word,
    required this.direction,
    required this.options,
    required this.correctIndex,
  });

  final Word word;
  final QuestionDirection direction;

  /// Слова-варианты (включая правильное).
  final List<Word> options;
  final int correctIndex;

  /// Текст вопроса.
  String get prompt =>
      direction == QuestionDirection.ruToDe ? russianFull(word) : word.title;

  /// Текст варианта ответа. Немецкие слова показываются с артиклем.
  String optionText(int i) => direction == QuestionDirection.ruToDe
      ? options[i].title
      : russianShort(options[i]);
}

/// Составляет вопросы для теста.
///
/// [words] — слова сессии, [pool] — все слова приложения (запас для неверных
/// вариантов, если в наборе их мало).
List<QuizQuestion> buildQuiz({
  required List<Word> words,
  required List<Word> pool,
  required StudyDirection direction,
  int optionCount = 4,
  Random? random,
}) {
  final rnd = random ?? Random();
  final shuffled = List<Word>.of(words)..shuffle(rnd);
  final result = <QuizQuestion>[];
  for (final w in shuffled) {
    final dir = pickDirection(direction, rnd);
    final distractors =
        _pickDistractors(w, dir, words, pool, rnd, optionCount - 1);
    if (distractors.isEmpty) continue;
    final options = <Word>[w, ...distractors]..shuffle(rnd);
    result.add(QuizQuestion(
      word: w,
      direction: dir,
      options: options,
      correctIndex: options.indexWhere((o) => o.id == w.id),
    ));
  }
  return result;
}

/// Составляет один вопрос с вариантами ответа по слову [word].
/// Неверные варианты берутся из [pool]. Если подобрать нечего — null.
QuizQuestion? buildSingleQuestion({
  required Word word,
  required QuestionDirection direction,
  required List<Word> pool,
  int optionCount = 4,
  Random? random,
}) {
  final rnd = random ?? Random();
  final distractors =
      _pickDistractors(word, direction, pool, pool, rnd, optionCount - 1);
  if (distractors.isEmpty) return null;
  final options = <Word>[word, ...distractors]..shuffle(rnd);
  return QuizQuestion(
    word: word,
    direction: direction,
    options: options,
    correctIndex: options.indexWhere((o) => o.id == word.id),
  );
}

/// Выбирает неверные варианты. Предпочитает слова той же части речи, для
/// существительных — с тем же артиклем, похожей длины и с той же первой буквой.
List<Word> _pickDistractors(
  Word target,
  QuestionDirection dir,
  List<Word> setWords,
  List<Word> pool,
  Random rnd,
  int count,
) {
  String keyOf(Word w) =>
      (dir == QuestionDirection.ruToDe ? w.title : russianShort(w))
          .toLowerCase();

  final targetKey = keyOf(target);
  final targetTr = target.translations.map((t) => t.toLowerCase()).toSet();

  bool ok(Word c) {
    if (c.id == target.id) return false;
    // Слово с тем же переводом тоже могло бы быть правильным ответом.
    if (c.translations.any((t) => targetTr.contains(t.toLowerCase()))) {
      return false;
    }
    return keyOf(c) != targetKey;
  }

  double score(Word c) {
    var s = rnd.nextDouble();
    if (c.pos == target.pos) s += 3;
    if (target.pos == Pos.noun &&
        c.pos == Pos.noun &&
        c.article != null &&
        c.article == target.article) {
      s += 2;
    }
    if ((c.german.length - target.german.length).abs() <= 2) s += 1;
    if (c.german.isNotEmpty &&
        target.german.isNotEmpty &&
        c.german[0].toLowerCase() == target.german[0].toLowerCase()) {
      s += 1;
    }
    return s;
  }

  final chosen = <Word>[];
  final usedKeys = <String>{targetKey};

  void take(Iterable<Word> source) {
    final scored = <MapEntry<Word, double>>[
      for (final c in source)
        if (ok(c)) MapEntry(c, score(c)),
    ];
    scored.sort((a, b) => b.value.compareTo(a.value));
    for (final e in scored) {
      if (chosen.length >= count) break;
      if (usedKeys.add(keyOf(e.key))) chosen.add(e.key);
    }
  }

  take(setWords);
  if (chosen.length < count) take(pool);
  return chosen;
}

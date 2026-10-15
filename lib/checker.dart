import 'models.dart';

/// Результат проверки письменного ответа.
class AnswerCheck {
  const AnswerCheck(this.accepted, [this.note]);

  /// Засчитан ли ответ как правильный.
  final bool accepted;

  /// Пояснение для пользователя («артикль неверный», «опечатка» и т. п.).
  final String? note;
}

/// Расстояние Левенштейна между двумя строками.
int editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final cur = List<int>.filled(b.length + 1, 0);
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      var v = prev[j] + 1;
      if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
      if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
      cur[j] = v;
    }
    prev = cur;
  }
  return prev[b.length];
}

String _collapse(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

/// Нижний регистр, ä→ae, ö→oe, ü→ue, ß→ss.
String _foldAe(String s) => s
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss');

/// Нижний регистр, ä→a, ö→o, ü→u, ß→ss.
String _foldPlain(String s) => s
    .toLowerCase()
    .replaceAll('ä', 'a')
    .replaceAll('ö', 'o')
    .replaceAll('ü', 'u')
    .replaceAll('ß', 'ss');

enum _Match {
  /// Совпало буква в букву.
  exact,

  /// Отличается только регистром или написанием умлаутов (ae/ue/ss).
  folded,

  /// Ошибка в одну букву.
  typo,

  none,
}

_Match _matchWord(String expected, String typed) {
  if (typed == expected) return _Match.exact;
  final e1 = _foldAe(expected);
  final t1 = _foldAe(typed);
  if (e1 == t1) return _Match.folded;
  if (_foldPlain(expected) == _foldPlain(typed)) return _Match.folded;
  if (e1.length >= 4 && editDistance(t1, e1) <= 1) return _Match.typo;
  return _Match.none;
}

/// Проверка ответа по-немецки.
///
/// Для существительных артикль обязателен: нужно писать «der Tisch».
/// [soft] = false (строгий режим): регистр, умлауты и каждая буква должны
/// совпадать. [soft] = true: допускаются ae/oe/ue/ss вместо ä/ö/ü/ß, любой
/// регистр и опечатка в одну букву (артикль всё равно обязателен).
AnswerCheck checkGerman(Word w, String input, {required bool soft}) {
  final typed = _collapse(input);
  if (typed.isEmpty) return const AnswerCheck(false, 'Ответ не введён.');

  final expArticle = w.pos == Pos.noun ? w.article : null;
  String? typedArticle;
  var typedWord = typed;
  if (expArticle != null) {
    final m = RegExp(r'^(der|die|das)\s+(.+)$', caseSensitive: false)
        .firstMatch(typed);
    if (m != null) {
      typedArticle = m.group(1)!.toLowerCase();
      typedWord = m.group(2)!;
    }
  }

  final level = _matchWord(w.german, typedWord);
  final wordRight = level == _Match.exact || level == _Match.folded;

  if (expArticle != null) {
    if (typedArticle == null) {
      return AnswerCheck(
        false,
        level == _Match.none ? null : 'Нужен артикль: der, die или das.',
      );
    }
    if (typedArticle != expArticle) {
      return AnswerCheck(
        false,
        wordRight ? 'Слово верное, а артикль нет.' : null,
      );
    }
  }

  if (level == _Match.exact) return const AnswerCheck(true);

  if (level == _Match.folded) {
    if (soft) {
      return AnswerCheck(true, 'Правильно пишется: ${w.title}');
    }
    final sameLetters = typedWord.toLowerCase() == w.german.toLowerCase();
    if (sameLetters) {
      return AnswerCheck(
        false,
        w.pos == Pos.noun
            ? 'Существительное пишется с большой буквы.'
            : 'Проверьте регистр букв.',
      );
    }
    return const AnswerCheck(false, 'Проверьте написание: умлауты ä, ö, ü и ß.');
  }

  if (level == _Match.typo) {
    if (soft) {
      return AnswerCheck(true, 'Засчитано, но есть опечатка. Правильно: ${w.title}');
    }
    return const AnswerCheck(
      false,
      'Почти правильно, но в строгом режиме это ошибка.',
    );
  }

  return const AnswerCheck(false);
}

String _normRu(String s) {
  var t = s.toLowerCase().replaceAll('ё', 'е');
  t = t.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  t = t.replaceAll(RegExp(r'[.,!?;:"«»]'), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Проверка ответа по-русски. Правильным считается любой из вариантов
/// перевода. «ё» и «е» равнозначны, скобки и знаки препинания игнорируются.
AnswerCheck checkRussian(Word w, String input, {required bool soft}) {
  final typed = _normRu(input);
  if (typed.isEmpty) return const AnswerCheck(false, 'Ответ не введён.');

  final candidates =
      w.translations.map(_normRu).where((t) => t.isNotEmpty).toList();
  if (candidates.contains(typed)) return const AnswerCheck(true);

  final near = candidates.any(
    (c) => c.length >= 4 && editDistance(typed, c) <= 1,
  );
  if (near) {
    if (soft) {
      return AnswerCheck(
        true,
        'Засчитано, но есть опечатка. Правильно: ${w.translations.join('; ')}',
      );
    }
    return const AnswerCheck(
      false,
      'Почти правильно, но в строгом режиме это ошибка.',
    );
  }
  return const AnswerCheck(false);
}

/// Проверка одной формы глагола («geht», «ging», «ist gegangen»).
///
/// Допускается лишнее местоимение в начале («er geht»). Если в эталоне
/// несколько вариантов через «/», подойдёт любой.
AnswerCheck checkForm(String expected, String input, {required bool soft}) {
  var typed = _collapse(input);
  if (typed.isEmpty) return const AnswerCheck(false, 'Ответ не введён.');
  typed = typed
      .replaceFirst(
        RegExp(r'^(ich|du|er/sie/es|er|sie|es|wir|ihr)\s+',
            caseSensitive: false),
        '',
      )
      .trim();

  final variants = expected
      .split(RegExp(r'\s*/\s*'))
      .map(_collapse)
      .where((s) => s.isNotEmpty)
      .toList();
  if (variants.isEmpty) variants.add(_collapse(expected));

  var best = _Match.none;
  for (final v in variants) {
    final m = _matchWord(v, typed);
    if (m == _Match.exact) return const AnswerCheck(true);
    if (m == _Match.folded && best != _Match.folded) best = m;
    if (m == _Match.typo && best == _Match.none) best = m;
  }
  if (soft && best == _Match.folded) {
    return AnswerCheck(true, 'Правильно пишется: ${variants.first}');
  }
  if (soft && best == _Match.typo) {
    return AnswerCheck(true, 'Засчитано, но есть опечатка: ${variants.first}');
  }
  if (best == _Match.folded) {
    return const AnswerCheck(false, 'Проверьте регистр и умлауты.');
  }
  if (best == _Match.typo) {
    return const AnswerCheck(false, 'Почти правильно, но в строгом режиме это ошибка.');
  }
  return const AnswerCheck(false);
}

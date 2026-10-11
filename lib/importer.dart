import 'models.dart';

/// Слово, разобранное из текста, до сохранения в базу.
class DraftWord {
  const DraftWord({
    required this.german,
    required this.pos,
    required this.translations,
    this.article,
    this.plural,
    this.example,
    this.note,
    this.present3,
    this.preterite,
    this.perfect,
    this.warnings = const [],
  });

  final String german;
  final Pos pos;
  final List<String> translations;
  final String? article;
  final String? plural;
  final String? example;
  final String? note;
  final String? present3;
  final String? preterite;
  final String? perfect;

  /// Замечания по разбору («нет артикля» и т. п.), не блокируют импорт.
  final List<String> warnings;

  String get title =>
      (pos == Pos.noun && article != null) ? '$article $german' : german;

  /// Ключ для поиска дублей.
  String get key => '${article ?? ''}|${german.toLowerCase()}';

  String? get pluralLine =>
      (pos == Pos.noun && plural != null) ? 'мн. ч.: die $plural' : null;

  String? get verbFormsLine {
    if (pos != Pos.verb) return null;
    final parts = <String>[
      if (present3 != null) present3!,
      if (preterite != null) preterite!,
      if (perfect != null) perfect!,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Word toWord(String id) => Word(
        id: id,
        german: german,
        pos: pos,
        translations: translations,
        article: article,
        plural: plural,
        example: example,
        note: note,
        present3: present3,
        preterite: preterite,
        perfect: perfect,
      );
}

/// Ключ для сравнения уже существующего слова с импортируемым.
String wordKey(Word w) => '${w.article ?? ''}|${w.german.toLowerCase()}';

class ImportParseResult {
  const ImportParseResult({
    required this.words,
    required this.errors,
    required this.duplicates,
  });

  final List<DraftWord> words;

  /// Строки, которые не удалось разобрать.
  final List<String> errors;

  /// Сколько строк пропущено как повторы внутри самого списка.
  final int duplicates;
}

final RegExp _cyrillic = RegExp(r'[а-яёА-ЯЁ]');
final RegExp _articleRe = RegExp(r'^(der|die|das)\s+(.+)$', caseSensitive: false);
final RegExp _dieRe = RegExp(r'^die\s+', caseSensitive: false);

const Set<String> _headerWords = {
  'немецкое слово',
  'немецкий',
  'слово',
  'german',
  'deutsch',
  'wort',
  'term',
  'термин',
};

bool _hasCyrillic(String s) => _cyrillic.hasMatch(s);

String? _opt(String s) {
  final t = s.trim();
  return t.isEmpty ? null : t;
}

/// Делит перевод на варианты по «;» и «,», не трогая запятые в скобках.
List<String> splitTranslations(String s) {
  final out = <String>[];
  final sb = StringBuffer();
  var depth = 0;
  for (final ch in s.split('')) {
    if (ch == '(') {
      depth++;
    } else if (ch == ')') {
      if (depth > 0) depth--;
    }
    if (depth == 0 && (ch == ';' || ch == ',' || ch == '\n')) {
      out.add(sb.toString());
      sb.clear();
    } else {
      sb.write(ch);
    }
  }
  out.add(sb.toString());
  return out.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
}

bool _looksInfinitive(String ru) {
  final t = ru.trim().toLowerCase().replaceAll(RegExp(r'\s*\(.*\)$'), '');
  return RegExp(r'(ть|ться|ти|тись|чь)$').hasMatch(t);
}

bool _isSingleLowerInfinitive(String g) {
  if (g.contains(' ') || g.isEmpty) return false;
  final first = g[0];
  if (first != first.toLowerCase()) return false;
  return g.endsWith('en') || g.endsWith('n');
}

bool _isSingleCapitalized(String g) {
  if (g.contains(' ') || g.isEmpty) return false;
  final first = g[0];
  return first != first.toLowerCase();
}

Pos? _posFromCell(String s) {
  final t = s.trim().toLowerCase();
  if (t.isEmpty) return null;
  if (t.startsWith('сущ') || t.startsWith('noun') || t.startsWith('nomen')) {
    return Pos.noun;
  }
  if (t.startsWith('гл') || t.startsWith('verb')) return Pos.verb;
  if (t.startsWith('прил') || t.startsWith('adj')) return Pos.adjective;
  return null;
}

/// Находит разделитель: берётся первый из списка, который есть хотя бы
/// в половине строк.
String _detectSeparator(List<String> lines) {
  const candidates = ['\t', ';', ' — ', ' – ', ' - ', ','];
  for (final sep in candidates) {
    final n = lines.where((l) => l.contains(sep)).length;
    if (n > 0 && n * 2 >= lines.length) return sep;
  }
  return '\t';
}

/// Делит строку на ячейки. Поддерживает ячейки в кавычках («как в CSV»).
List<String> _splitLine(String line, String sep) {
  final noQuotes = !line.contains('"');
  if (sep.length > 1 || (sep == ',' && noQuotes)) {
    // Для «,» и « - » делим только по первому вхождению: дальше идёт перевод,
    // в котором могут быть свои запятые.
    final i = line.indexOf(sep);
    if (i < 0) return [line.trim()];
    return [line.substring(0, i).trim(), line.substring(i + sep.length).trim()];
  }
  final out = <String>[];
  final sb = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        sb.write(ch);
      }
    } else if (ch == '"') {
      inQuotes = true;
    } else if (line.startsWith(sep, i)) {
      out.add(sb.toString().trim());
      sb.clear();
      i += sep.length - 1;
    } else {
      sb.write(ch);
    }
  }
  out.add(sb.toString().trim());
  return out;
}

DraftWord? _buildDraft(List<String> cells, int lineNo, List<String> errors) {
  String cell(int i) => i < cells.length ? cells[i].trim() : '';

  var c0 = cell(0);
  var c1 = cell(1);
  if (c0.isEmpty || c1.isEmpty) {
    errors.add('Строка $lineNo: нужны слово и перевод');
    return null;
  }

  final warnings = <String>[];
  final cyr0 = _hasCyrillic(c0);
  final cyr1 = _hasCyrillic(c1);
  if (cyr0 && !cyr1) {
    // Quizlet и подобные: русское слово слева, немецкое справа.
    final t = c0;
    c0 = c1;
    c1 = t;
  } else if (!cyr0 && !cyr1) {
    warnings.add('в переводе нет русских букв');
  }

  String? plural = _opt(cell(2));
  final posHint = _posFromCell(cell(3));
  String? present3 = _opt(cell(4));
  String? preterite = _opt(cell(5));
  String? perfect = _opt(cell(6));
  final example = _opt(cell(7));
  final note = _opt(cell(8));

  var main = c0;

  // «der Tisch (Pl. Tische)»
  final pl = RegExp(r'\(\s*pl\.?\s*:?\s*(?:die\s+)?([^)]+)\)',
          caseSensitive: false)
      .firstMatch(main);
  if (pl != null) {
    plural ??= pl.group(1)!.trim();
    main = main.replaceFirst(pl.group(0)!, '').trim();
  }

  // «der Tisch, die Tische» или «gehen, ging, ist gegangen»
  var formsFromText = false;
  final parts = main
      .split(',')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
  if (parts.length >= 2) {
    final first = parts.first;
    if (_articleRe.hasMatch(first)) {
      if (_dieRe.hasMatch(parts[1])) {
        plural ??= parts[1].replaceFirst(_dieRe, '').trim();
      }
      main = first;
    } else if (!first.contains(' ') &&
        (parts.length == 3 || parts.length == 4)) {
      if (parts.length == 4) {
        present3 ??= parts[1];
        preterite ??= parts[2];
        perfect ??= parts[3];
      } else {
        preterite ??= parts[1];
        perfect ??= parts[2];
      }
      main = first;
      formsFromText = true;
    }
  }

  String german;
  String? article;
  final m = _articleRe.firstMatch(main);
  if (m != null) {
    article = m.group(1)!.toLowerCase();
    german = m.group(2)!.trim();
  } else {
    german = main.trim();
  }
  if (german.isEmpty) {
    errors.add('Строка $lineNo: пустое немецкое слово');
    return null;
  }

  final translations = splitTranslations(c1);
  if (translations.isEmpty) {
    errors.add('Строка $lineNo: нет перевода');
    return null;
  }

  final Pos pos;
  if (article != null) {
    pos = Pos.noun;
  } else if (posHint != null) {
    pos = posHint;
  } else if (formsFromText ||
      present3 != null ||
      preterite != null ||
      perfect != null) {
    pos = Pos.verb;
  } else if (_isSingleLowerInfinitive(german) &&
      translations.every(_looksInfinitive)) {
    pos = Pos.verb;
  } else if (_isSingleCapitalized(german)) {
    pos = Pos.noun;
  } else {
    pos = Pos.other;
  }

  if (pos == Pos.noun) {
    if (article == null) {
      warnings.add('нет артикля: добавьте его вручную');
    }
    if (german[0] == german[0].toLowerCase() &&
        german[0] != german[0].toUpperCase()) {
      german = german[0].toUpperCase() + german.substring(1);
      warnings.add('первая буква исправлена на заглавную');
    }
  }

  String? cleanPlural;
  if (pos == Pos.noun && plural != null) {
    final p = plural.replaceFirst(_dieRe, '').trim();
    cleanPlural = p.isEmpty ? null : p;
  }

  final isVerb = pos == Pos.verb;
  return DraftWord(
    german: german,
    pos: pos,
    translations: translations,
    article: pos == Pos.noun ? article : null,
    plural: cleanPlural,
    example: example,
    note: note,
    present3: isVerb ? present3 : null,
    preterite: isVerb ? preterite : null,
    perfect: isVerb ? perfect : null,
    warnings: warnings,
  );
}

/// Разбирает вставленный текст: одно слово в строке.
///
/// Понимает:
/// - два столбца «слово — перевод» (Quizlet, CSV, «слово - перевод»);
///   если русское слово слева, столбцы меняются местами сами;
/// - артикль в слове: «der Tisch»; множественное число: «der Tisch, die Tische»
///   или «der Tisch (Pl. Tische)»;
/// - формы глагола: «gehen, ging, ist gegangen»;
/// - полный формат экспорта этого приложения (9 столбцов, первая строка с
///   заголовком пропускается).
ImportParseResult parseWordList(String raw) {
  final text = raw.replaceAll('﻿', '').replaceAll(' ', ' ');
  final lines = text.split(RegExp(r'\r?\n'));

  final numbered = <MapEntry<int, String>>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i].trim();
    if (l.isEmpty || l.startsWith('#')) continue;
    numbered.add(MapEntry(i + 1, l));
  }
  if (numbered.isEmpty) {
    return const ImportParseResult(words: [], errors: [], duplicates: 0);
  }

  final sep = _detectSeparator(numbered.map((e) => e.value).toList());
  final errors = <String>[];
  final words = <DraftWord>[];
  final seen = <String>{};
  var duplicates = 0;

  var first = true;
  for (final e in numbered) {
    final cells = _splitLine(e.value, sep);
    if (first) {
      first = false;
      if (_headerWords.contains(cells.first.trim().toLowerCase())) continue;
    }
    if (cells.length < 2) {
      errors.add('Строка ${e.key}: не найден разделитель между словом и переводом');
      continue;
    }
    final d = _buildDraft(cells, e.key, errors);
    if (d == null) continue;
    if (!seen.add(d.key)) {
      duplicates++;
      continue;
    }
    words.add(d);
  }
  return ImportParseResult(words: words, errors: errors, duplicates: duplicates);
}

const String kExportHeader =
    'Немецкое слово\tПеревод\tМн. число\tЧасть речи\tPräsens\tPräteritum\tPerfekt\tПример\tЗаметка';

/// Текст для копирования: таблица с табуляциями. Его же понимает импорт.
String exportWords(List<Word> words) {
  String f(String? s) => (s ?? '').replaceAll(RegExp(r'[\t\r\n]+'), ' ').trim();
  const posShort = <Pos, String>{
    Pos.noun: 'сущ.',
    Pos.verb: 'гл.',
    Pos.adjective: 'прил.',
    Pos.other: 'другое',
  };
  final b = StringBuffer(kExportHeader);
  for (final w in words) {
    b.write('\n');
    b.write([
      f(w.title),
      f(w.translations.join('; ')),
      f(w.plural),
      posShort[w.pos] ?? 'другое',
      f(w.present3),
      f(w.preterite),
      f(w.perfect),
      f(w.example),
      f(w.note),
    ].join('\t'));
  }
  return b.toString();
}

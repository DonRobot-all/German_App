import 'dart:convert';

/// Часть речи.
enum Pos { noun, verb, adjective, other }

extension PosLabel on Pos {
  String get label {
    switch (this) {
      case Pos.noun:
        return 'Существительное';
      case Pos.verb:
        return 'Глагол';
      case Pos.adjective:
        return 'Прилагательное';
      case Pos.other:
        return 'Другое';
    }
  }
}

const List<String> kArticles = ['der', 'die', 'das'];

/// Падежи после предлога у глаголов с управлением.
const List<String> kCases = ['Akk', 'Dat'];

/// Предлоги, которые встречаются в глаголах с управлением.
const List<String> kPrepositions = [
  'an',
  'auf',
  'aus',
  'bei',
  'bis',
  'durch',
  'für',
  'gegen',
  'in',
  'mit',
  'nach',
  'ohne',
  'über',
  'um',
  'unter',
  'von',
  'vor',
  'zu',
];

Pos posFromName(String? name) {
  for (final p in Pos.values) {
    if (p.name == name) return p;
  }
  return Pos.other;
}

/// «1 слово», «2 слова», «5 слов».
String wordsCount(int n) {
  final m10 = n % 10;
  final m100 = n % 100;
  if (m10 == 1 && m100 != 11) return '$n слово';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n слова';
  return '$n слов';
}

class WordSet {
  const WordSet({
    required this.id,
    required this.name,
    required this.description,
    required this.wordCount,
  });

  final String id;
  final String name;
  final String description;
  final int wordCount;
}

class Word {
  const Word({
    required this.id,
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
    this.prepCase,
  });

  final String id;

  /// Немецкое слово без артикля (для глагола — инфинитив).
  final String german;
  final Pos pos;

  /// der / die / das (только для существительных).
  final String? article;

  /// Форма множественного числа без артикля, например «Tische».
  final String? plural;

  /// Варианты русского перевода.
  final List<String> translations;
  final String? example;
  final String? note;

  /// Глагол: Präsens, 3-е лицо ед. ч. (er/sie/es), например «geht».
  final String? present3;

  /// Глагол: Präteritum, например «ging».
  final String? preterite;

  /// Глагол: Perfekt, например «ist gegangen».
  final String? perfect;

  /// Глагол с предлогом: падеж после предлога, 'Akk' или 'Dat'.
  final String? prepCase;

  /// Предлог глагола с управлением: для «abhängen von» это «von».
  /// У глаголов без предлога — null.
  String? get prep {
    if (pos != Pos.verb) return null;
    final parts = german.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    final last = parts.last.toLowerCase();
    return kPrepositions.contains(last) ? last : null;
  }

  /// Глагол без предлога: «abhängen» из «abhängen von».
  String? get prepStem {
    if (prep == null) return null;
    final parts = german.trim().split(RegExp(r'\s+'));
    return parts.sublist(0, parts.length - 1).join(' ');
  }

  String? get prepLine =>
      (prep != null && prepCase != null) ? 'управление: $prep + $prepCase.' : null;

  /// Слово так, как оно должно писаться: «der Tisch».
  String get title =>
      (pos == Pos.noun && article != null) ? '$article $german' : german;

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

  Map<String, Object?> toMap(int updatedAt) => {
        'id': id,
        'german': german,
        'article': article,
        'plural': plural,
        'pos': pos.name,
        'translations': jsonEncode(translations),
        'example': example,
        'note': note,
        'present3': present3,
        'preterite': preterite,
        'perfect': perfect,
        'prep_case': prepCase,
        'updated_at': updatedAt,
        'deleted': 0,
      };

  factory Word.fromMap(Map<String, Object?> m) {
    final raw = jsonDecode(m['translations'] as String) as List<dynamic>;
    return Word(
      id: m['id'] as String,
      german: m['german'] as String,
      pos: posFromName(m['pos'] as String?),
      translations: raw.map((e) => e.toString()).toList(),
      article: m['article'] as String?,
      plural: m['plural'] as String?,
      example: m['example'] as String?,
      note: m['note'] as String?,
      present3: m['present3'] as String?,
      preterite: m['preterite'] as String?,
      perfect: m['perfect'] as String?,
      prepCase: m['prep_case'] as String?,
    );
  }
}

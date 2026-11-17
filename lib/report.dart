import 'db.dart';
import 'models.dart';

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${_two(d.day)}.${_two(d.month)}';

String _times(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return '$n раз';
  return '$n раз';
}

String _kindLabel(String direction) {
  switch (direction) {
    case 'de_ru':
      return 'Перевод DE→RU';
    case 'ru_de':
      return 'Перевод RU→DE';
    case kAspectArticle:
      return 'Артикли';
    case kAspectForms:
      return 'Формы глаголов';
    case kAspectPrep:
      return 'Глаголы с предлогами';
    case kAspectDictation:
      return 'Диктовка';
  }
  return direction;
}

/// Текстовый отчёт об успехах за последние [days] дней (1 = только сегодня).
/// Его удобно отправить преподавателю в любом мессенджере.
Future<String> buildProgressReport({
  required int days,
  String name = '',
}) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = DateTime(today.year, today.month, today.day - (days - 1));
  final d = await AppDb.instance.db;
  final rows = await d.query(
    'answer_log',
    columns: ['ts', 'word_id', 'direction', 'correct'],
    where: 'ts >= ?',
    whereArgs: [start.millisecondsSinceEpoch],
    orderBy: 'ts',
  );

  var total = 0, right = 0;
  final perDay = <int, List<int>>{}; // индекс дня -> [всего, верно]
  final perKind = <String, List<int>>{};
  final wrongByWord = <String, int>{};
  for (final r in rows) {
    final t = DateTime.fromMillisecondsSinceEpoch((r['ts'] as num).toInt());
    final day = DateTime(t.year, t.month, t.day).difference(start).inDays;
    final ok = (r['correct'] as num).toInt() == 1;
    total++;
    if (ok) right++;
    final a = perDay.putIfAbsent(day, () => [0, 0]);
    a[0]++;
    if (ok) a[1]++;
    final k = perKind.putIfAbsent(r['direction'] as String, () => [0, 0]);
    k[0]++;
    if (ok) k[1]++;
    if (!ok) {
      final id = r['word_id'] as String;
      wrongByWord[id] = (wrongByWord[id] ?? 0) + 1;
    }
  }

  final words = {for (final w in await AppDb.instance.listAllWords()) w.id: w};
  final stats = await AppDb.instance.loadStats();

  final b = StringBuffer();
  b.writeln(name.trim().isEmpty
      ? 'Отчёт об изучении немецкого'
      : 'Отчёт об изучении немецкого: ${name.trim()}');
  b.writeln(days == 1
      ? 'Дата: ${_date(today)}.${today.year}'
      : 'Период: ${_date(start)} – ${_date(today)}.${today.year} ($days дн.)');
  b.writeln();
  if (total == 0) {
    b.writeln('За этот период ответов не было.');
  } else {
    final pct = (right * 100 / total).round();
    b.writeln('Ответов: $total');
    b.writeln('Верных: $right ($pct%)');
    b.writeln('Ошибок: ${total - right}');
    b.writeln('Дней с занятиями: ${perDay.length} из $days');
    if (days > 1 && days <= 14) {
      b.writeln();
      b.writeln('По дням:');
      for (var i = 0; i < days; i++) {
        final day = DateTime(start.year, start.month, start.day + i);
        final a = perDay[i];
        b.writeln(a == null
            ? '${_date(day)} — не занимался'
            : '${_date(day)} — ${a[0]} отв., верно ${a[1]}');
      }
    }
    if (perKind.isNotEmpty) {
      b.writeln();
      b.writeln('По видам тренировок:');
      final kinds = perKind.entries.toList()
        ..sort((x, y) => y.value[0].compareTo(x.value[0]));
      for (final e in kinds) {
        b.writeln('${_kindLabel(e.key)}: ${e.value[0]}, верно ${e.value[1]}');
      }
    }
    if (wrongByWord.isNotEmpty) {
      b.writeln();
      b.writeln('Чаще всего ошибки:');
      final list = wrongByWord.entries.toList()
        ..sort((x, y) => y.value.compareTo(x.value));
      for (final e in list.take(8)) {
        final w = words[e.key];
        if (w == null) continue;
        b.writeln('${w.title} — ${w.translations.join('; ')} (${_times(e.value)})');
      }
    }
  }
  b.writeln();
  b.writeln('Всего слов: ${stats.totalWords}, выучено: ${stats.learnedWords}, '
      'в изучении: ${stats.learningWords}.');
  b.writeln('Дней подряд: ${stats.streak}.');
  return b.toString().trimRight();
}

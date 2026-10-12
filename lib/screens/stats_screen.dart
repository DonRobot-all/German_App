import 'dart:math';

import 'package:flutter/material.dart';

import '../db.dart';
import '../stats.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  StatsData? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await AppDb.instance.loadStats();
    if (!mounted) return;
    setState(() => _data = d);
  }

  Widget _section(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _tile(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Text(
                value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, int v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(k)),
          Text('$v', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  static const List<String> _levelNames = [
    '0 · после ошибки',
    '1 · через 1 день',
    '2 · через 3 дня',
    '3 · через 7 дней',
    '4 · через 14 дней',
    '5 · через 30 дней',
    '6 · выучено',
  ];

  Widget _levels(BuildContext context, StatsData d) {
    final theme = Theme.of(context);
    final maxV = d.levelCounts.fold<int>(0, max);
    return Column(
      children: [
        for (var i = 0; i < d.levelCounts.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 128,
                  child: Text(_levelNames[i], style: theme.textTheme.bodySmall),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      minHeight: 10,
                      value: maxV == 0 ? 0 : d.levelCounts[i] / maxV,
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${d.levelCounts[i]}',
                    textAlign: TextAlign.right,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (d.totalAnswers == 0)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Пока нет ответов. Статистика появится после первой '
                      'тренировки.',
                    ),
                  ),
                Row(
                  children: [
                    _tile(context, '${d.streak}', 'дней подряд'),
                    _tile(context, '${d.answersToday}', 'ответов сегодня'),
                    _tile(
                      context,
                      d.answersWeek == 0
                          ? '—'
                          : '${(d.correctWeek * 100 / d.answersWeek).round()}%',
                      'верных за 7 дней',
                    ),
                  ],
                ),
                _section(context, 'Слова'),
                _kv(context, 'Всего', d.totalWords),
                _kv(context, 'Новые (ещё не изучались)', d.newWords),
                _kv(context, 'В изучении', d.learningWords),
                _kv(context, 'Выучено (оба направления, уровень 6)',
                    d.learnedWords),
                _section(context, 'Ответов по дням, последние 14 дней'),
                _ActivityChart(
                  counts: d.last14,
                  today: DateTime.now(),
                ),
                _section(context, 'Слова по уровням (направления)'),
                _levels(context, d),
                _section(context, 'Больше всего ошибок'),
                if (d.problems.isEmpty)
                  const Text('Ошибок пока нет.')
                else
                  for (final p in d.problems)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        p.word.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(p.word.translations.join('; ')),
                      trailing: Text('ошибок: ${p.errors}'),
                    ),
              ],
            ),
    );
  }
}

/// Столбики активности. Один ряд данных: один цвет, без легенды; подписаны
/// только максимум и сегодняшний день, остальное — во всплывающей подсказке.
class _ActivityChart extends StatelessWidget {
  const _ActivityChart({required this.counts, required this.today});

  final List<int> counts;
  final DateTime today;

  static const List<String> _months = [
    'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
    'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxV = counts.fold<int>(0, max);
    const barArea = 96.0;
    final base = DateTime(today.year, today.month, today.day);

    return SizedBox(
      height: 16 + barArea + 4 + 16,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < counts.length; i++)
            Expanded(
              child: Builder(
                builder: (context) {
                  final n = counts[i];
                  final isToday = i == counts.length - 1;
                  final day = DateTime(
                    base.year,
                    base.month,
                    base.day - (counts.length - 1 - i),
                  );
                  final showLabel = n > 0 && (n == maxV || isToday);
                  final h = n == 0 || maxV == 0
                      ? 2.0
                      : max(4.0, n / maxV * barArea);
                  return Tooltip(
                    message: '${day.day} ${_months[day.month - 1]}: $n',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            height: 16,
                            child: showLabel
                                ? Text(
                                    '$n',
                                    style: theme.textTheme.labelSmall,
                                  )
                                : null,
                          ),
                          Container(
                            height: h,
                            decoration: BoxDecoration(
                              color: n == 0
                                  ? theme.colorScheme.outlineVariant
                                  : theme.colorScheme.primary,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            height: 16,
                            child: Text(
                              '${day.day}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: isToday ? FontWeight.bold : null,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

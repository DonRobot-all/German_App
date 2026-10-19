import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../study.dart';
import '../tts.dart';
import 'study_screens.dart';

/// Глаголы с предлогом: «abhängen von», «sich freuen auf».
List<Word> prepVerbWords(List<Word> words) => [
      for (final w in words)
        if (w.prep != null) w,
    ];

/// Тренировка глаголов с управлением: по глаголу и переводу выбрать предлог
/// и, если падеж задан, падеж после него.
class PrepScreen extends StatefulWidget {
  const PrepScreen({super.key, required this.words});

  final List<Word> words;

  @override
  State<PrepScreen> createState() => _PrepScreenState();
}

class _PrepScreenState extends State<PrepScreen> {
  final Random _rnd = Random();
  late List<Word> _queue;
  final List<Word> _wrong = [];
  List<String> _options = [];
  int _index = 0;
  int _correct = 0;
  String? _pickedPrep;
  String? _pickedCase;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _begin(widget.words);
  }

  void _begin(List<Word> words) {
    _queue = List<Word>.of(words)..shuffle(_rnd);
    _wrong.clear();
    _index = 0;
    _correct = 0;
    _finished = false;
    _prepare();
  }

  void _prepare() {
    final w = _queue[_index];
    final right = w.prep!;
    final others = [
      for (final p in kPrepositions)
        if (p != right) p,
    ]..shuffle(_rnd);
    _options = [right, ...others.take(5)]..shuffle(_rnd);
    _pickedPrep = null;
    _pickedCase = null;
  }

  bool get _needsCase => _queue[_index].prepCase != null;

  /// Ответ полностью дан: выбран предлог и (если нужен) падеж.
  bool get _answered =>
      _pickedPrep != null && (!_needsCase || _pickedCase != null);

  void _pickPrep(String p) {
    if (_pickedPrep != null) return;
    setState(() => _pickedPrep = p);
    _afterPick();
  }

  void _pickCase(String c) {
    if (_pickedPrep == null || _pickedCase != null) return;
    setState(() => _pickedCase = c);
    _afterPick();
  }

  void _afterPick() {
    if (!_answered) return;
    final w = _queue[_index];
    final ok = _pickedPrep == w.prep && (!_needsCase || _pickedCase == w.prepCase);
    setState(() {
      if (ok) {
        _correct++;
      } else {
        _wrong.add(w);
      }
    });
  }

  void _next() {
    setState(() {
      if (_index + 1 >= _queue.length) {
        _finished = true;
      } else {
        _index++;
        _prepare();
      }
    });
  }

  Color? _color(bool isRight, bool isPicked) {
    if (!_answered) return null;
    if (isRight) return Colors.green.withAlpha(90);
    if (isPicked) return Colors.red.withAlpha(90);
    return null;
  }

  Widget _questionView(BuildContext context) {
    final theme = Theme.of(context);
    final w = _queue[_index];
    final answered = _answered;
    final ok = answered &&
        _pickedPrep == w.prep &&
        (!_needsCase || _pickedCase == w.prepCase);
    final isLast = _index + 1 >= _queue.length;
    final full = w.prepCase == null ? w.german : '${w.german} + ${w.prepCase}.';
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_index + (answered ? 1 : 0)) / _queue.length,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${_index + 1} / ${_queue.length}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        Text('Какой предлог?', style: theme.textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        Text(
                          answered ? full : '${w.prepStem} …',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        if (answered)
                          SpeakButton(
                            key: ValueKey<String>('pp-$_index'),
                            text: w.german,
                          ),
                        const SizedBox(height: 4),
                        Text(
                          russianFull(w),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _options)
                    SizedBox(
                      width: 96,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                          backgroundColor:
                              _color(p == w.prep, p == _pickedPrep),
                        ),
                        onPressed: _pickedPrep == null ? () => _pickPrep(p) : null,
                        child: Text(p, style: const TextStyle(fontSize: 18)),
                      ),
                    ),
                ],
              ),
              if (_pickedPrep != null && _needsCase) ...[
                const SizedBox(height: 20),
                Text(
                  'Падеж после предлога',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final c in kCases)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 52),
                              backgroundColor:
                                  _color(c == w.prepCase, c == _pickedCase),
                            ),
                            onPressed: _pickedCase == null ? () => _pickCase(c) : null,
                            child: Text(c, style: const TextStyle(fontSize: 18)),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (answered) ...[
                const SizedBox(height: 16),
                Text(
                  ok ? 'Верно!' : 'Неверно. Правильно: $full',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ok ? Colors.green : theme.colorScheme.error,
                  ),
                ),
                if (w.example != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      w.example!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: answered ? _next : null,
                child: Text(isLast ? 'Результат' : 'Дальше'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultView() {
    final weak = List<Word>.of(_wrong);
    return StudyResultView(
      headline: '$_correct из ${_queue.length}',
      subtitle: 'глаголов с предлогом угадано',
      weakTitle: 'Ошибки (${weak.length})',
      weak: weak,
      onRepeat: () => setState(() => _begin(weak)),
      onClose: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Глаголы с предлогами')),
      body: _finished ? _resultView() : _questionView(context),
    );
  }
}

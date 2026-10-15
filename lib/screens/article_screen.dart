import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../settings.dart';
import '../study.dart';
import '../tts.dart';
import 'study_screens.dart';

/// Слова, подходящие для тренировки артиклей: существительные с артиклем.
List<Word> articleWords(List<Word> words) => [
      for (final w in words)
        if (w.pos == Pos.noun && w.article != null) w,
    ];

/// Тренировка артиклей: показано слово без артикля, нужно выбрать der/die/das.
class ArticleScreen extends StatefulWidget {
  const ArticleScreen({super.key, required this.words});

  final List<Word> words;

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late List<Word> _queue;
  final List<Word> _wrong = [];
  int _index = 0;
  int _correct = 0;
  String? _picked;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _begin(widget.words);
  }

  void _begin(List<Word> words) {
    _queue = List<Word>.of(words)..shuffle(Random());
    _wrong.clear();
    _index = 0;
    _correct = 0;
    _picked = null;
    _finished = false;
  }

  void _pick(String article) {
    if (_picked != null) return;
    final w = _queue[_index];
    setState(() {
      _picked = article;
      if (article == w.article) {
        _correct++;
      } else {
        _wrong.add(w);
      }
    });
    if (AppSettings.instance.autoSpeak) {
      Speaker.instance.speak(w.title);
    }
  }

  void _next() {
    setState(() {
      if (_index + 1 >= _queue.length) {
        _finished = true;
      } else {
        _index++;
        _picked = null;
      }
    });
  }

  Color? _buttonColor(String a, Word w) {
    final picked = _picked;
    if (picked == null) return null;
    if (a == w.article) return Colors.green.withAlpha(90);
    if (a == picked) return Colors.red.withAlpha(90);
    return null;
  }

  Widget _questionView(BuildContext context) {
    final theme = Theme.of(context);
    final w = _queue[_index];
    final answered = _picked != null;
    final ok = _picked == w.article;
    final isLast = _index + 1 >= _queue.length;
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
                  child: Column(
                    children: [
                      Text('Какой артикль?', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 8),
                      Text(
                        answered ? w.title : w.german,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
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
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final a in kArticles)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 64),
                            backgroundColor: _buttonColor(a, w),
                          ),
                          onPressed: answered ? null : () => _pick(a),
                          child: Text(a, style: const TextStyle(fontSize: 22)),
                        ),
                      ),
                    ),
                ],
              ),
              if (answered) ...[
                const SizedBox(height: 16),
                Text(
                  ok ? 'Верно!' : 'Неверно, правильно: ${w.article}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: ok ? Colors.green : theme.colorScheme.error,
                  ),
                ),
                if (w.pluralLine != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      w.pluralLine!,
                      textAlign: TextAlign.center,
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
      subtitle: 'артиклей угадано',
      weakTitle: 'Ошибки (${weak.length})',
      weak: weak,
      onRepeat: () => setState(() => _begin(weak)),
      onClose: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Артикли')),
      body: _finished ? _resultView() : _questionView(context),
    );
  }
}

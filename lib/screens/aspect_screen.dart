import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import 'aspect_widgets.dart';
import 'study_screens.dart';

/// Отдельная тренировка одного навыка: артикли, формы глаголов или предлоги.
/// Ответы записываются в уровни слов и в статистику.
class AspectScreen extends StatefulWidget {
  const AspectScreen({
    super.key,
    required this.aspect,
    required this.words,
    this.soft = false,
  });

  /// kAspectArticle, kAspectForms, kAspectPrep или kAspectDictation.
  final String aspect;
  final List<Word> words;

  /// Мягкая проверка (для форм глаголов и диктовки).
  final bool soft;

  @override
  State<AspectScreen> createState() => _AspectScreenState();
}

class _AspectScreenState extends State<AspectScreen> {
  late List<Word> _queue;
  final List<Word> _wrong = [];
  int _index = 0;
  int _correct = 0;
  int _round = 0; // меняется при повторе, чтобы вопросы не переиспользовали состояние
  bool _answered = false;
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
    _round++;
    _answered = false;
    _finished = false;
  }

  String get _title {
    switch (widget.aspect) {
      case kAspectArticle:
        return 'Артикли';
      case kAspectPrep:
        return 'Глаголы с предлогами';
      case kAspectDictation:
        return widget.soft ? 'Диктовка (мягко)' : 'Диктовка';
      default:
        return widget.soft ? 'Формы глаголов (мягко)' : 'Формы глаголов';
    }
  }

  String get _doneText {
    switch (widget.aspect) {
      case kAspectArticle:
        return 'артиклей угадано';
      case kAspectPrep:
        return 'глаголов с предлогом угадано';
      case kAspectDictation:
        return 'слов записано верно';
      default:
        return 'глаголов без ошибок во всех формах';
    }
  }

  void _onAnswered(bool correct) {
    final w = _queue[_index];
    unawaited(AppDb.instance.recordAnswer(
      w.id,
      widget.aspect,
      correct: correct,
      written: true,
    ));
    setState(() {
      _answered = true;
      if (correct) {
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
        _answered = false;
      }
    });
  }

  Widget _questionView() {
    final isLast = _index + 1 >= _queue.length;
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_index + (_answered ? 1 : 0)) / _queue.length,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            '${_index + 1} / ${_queue.length}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: buildAspectQuestion(
            key: ValueKey<String>('q-$_round-$_index'),
            aspect: widget.aspect,
            word: _queue[_index],
            soft: widget.soft,
            onAnswered: _onAnswered,
            onNext: _next,
            nextLabel: isLast ? 'Результат' : 'Дальше',
          ),
        ),
      ],
    );
  }

  Widget _resultView() {
    final weak = List<Word>.of(_wrong);
    return StudyResultView(
      headline: '$_correct из ${_queue.length}',
      subtitle: _doneText,
      weakTitle: 'Ошибки (${weak.length})',
      weak: weak,
      onRepeat: () => setState(() => _begin(weak)),
      onClose: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: _finished ? _resultView() : _questionView(),
    );
  }
}

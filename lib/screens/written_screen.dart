import 'dart:math';

import 'package:flutter/material.dart';

import '../checker.dart';
import '../models.dart';
import '../study.dart';
import 'study_screens.dart';

class _WrittenQuestion {
  const _WrittenQuestion(this.word, this.direction);

  final Word word;
  final QuestionDirection direction;
}

/// Тренировка с письменным вводом ответа.
class WrittenScreen extends StatefulWidget {
  const WrittenScreen({
    super.key,
    required this.words,
    required this.direction,
    required this.soft,
  });

  final List<Word> words;
  final StudyDirection direction;

  /// Мягкая проверка (ae/ue, любой регистр, опечатка в одну букву).
  final bool soft;

  @override
  State<WrittenScreen> createState() => _WrittenScreenState();
}

class _WrittenScreenState extends State<WrittenScreen> {
  late List<_WrittenQuestion> _questions;
  final List<Word> _wrong = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  int _index = 0;
  int _correct = 0;
  AnswerCheck? _result;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _begin(widget.words);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _begin(List<Word> words) {
    final rnd = Random();
    final list = List<Word>.of(words)..shuffle(rnd);
    _questions = [
      for (final w in list)
        _WrittenQuestion(w, pickDirection(widget.direction, rnd)),
    ];
    _index = 0;
    _correct = 0;
    _wrong.clear();
    _result = null;
    _finished = false;
    _controller.clear();
  }

  void _submit({bool giveUp = false}) {
    if (_result != null) return;
    final q = _questions[_index];
    final AnswerCheck res;
    if (giveUp) {
      res = const AnswerCheck(false);
    } else {
      if (_controller.text.trim().isEmpty) return;
      res = q.direction == QuestionDirection.ruToDe
          ? checkGerman(q.word, _controller.text, soft: widget.soft)
          : checkRussian(q.word, _controller.text, soft: widget.soft);
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _result = res;
      if (res.accepted) {
        _correct++;
      } else {
        _wrong.add(q.word);
      }
    });
  }

  void _next() {
    setState(() {
      if (_index + 1 >= _questions.length) {
        _finished = true;
      } else {
        _index++;
        _result = null;
        _controller.clear();
      }
    });
    if (!_finished) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  void _insertChar(String ch) {
    final text = _controller.text;
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    _controller.value = TextEditingValue(
      text: text.replaceRange(start, end, ch),
      selection: TextSelection.collapsed(offset: start + ch.length),
    );
  }

  Widget _charRow() {
    const chars = ['ä', 'ö', 'ü', 'ß', 'Ä', 'Ö', 'Ü'];
    return ExcludeFocus(
      child: Material(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              for (final ch in chars)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => _insertChar(ch),
                      child: Text(ch, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _questionView(BuildContext context) {
    final theme = Theme.of(context);
    final q = _questions[_index];
    final res = _result;
    final answered = res != null;
    final accepted = res?.accepted ?? false;
    final note = res?.note;
    final ruToDe = q.direction == QuestionDirection.ruToDe;
    final prompt = ruToDe ? russianFull(q.word) : q.word.title;
    final correctText = ruToDe ? q.word.title : russianFull(q.word);
    final isLast = _index + 1 >= _questions.length;

    String? helper;
    if (ruToDe && q.word.pos == Pos.noun) {
      helper = 'Существительное пишите с артиклем: der / die / das';
    }

    Color? fill;
    if (answered) {
      fill = accepted ? Colors.green.withAlpha(45) : Colors.red.withAlpha(45);
    }

    return Column(
      children: [
        LinearProgressIndicator(
          value: (_index + (answered ? 1 : 0)) / _questions.length,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${_index + 1} / ${_questions.length}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        Text(
                          ruToDe ? 'Напишите по-немецки' : 'Напишите по-русски',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          prompt,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(q.word.pos.label, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                readOnly: answered,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                style: const TextStyle(fontSize: 20),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: ruToDe ? 'Ответ по-немецки' : 'Ответ по-русски',
                  helperText: helper,
                  filled: answered,
                  fillColor: fill,
                ),
              ),
              if (answered) ...[
                const SizedBox(height: 12),
                Text(
                  accepted ? 'Верно!' : 'Неверно',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: accepted ? Colors.green : theme.colorScheme.error,
                  ),
                ),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(note),
                  ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Правильный ответ',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            correctText,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          WordInfo(word: q.word, showHeader: false),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (ruToDe && !answered) _charRow(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: answered
                    ? SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _next,
                          child: Text(isLast ? 'Результат' : 'Дальше'),
                        ),
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _submit(giveUp: true),
                              child: const Text('Не знаю'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _submit,
                              child: const Text('Проверить'),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _resultView() {
    final weak = List<Word>.of(_wrong);
    return StudyResultView(
      headline: '$_correct из ${_questions.length}',
      subtitle: 'правильных ответов',
      weakTitle: 'Ошибки (${weak.length})',
      weak: weak,
      onRepeat: () => setState(() => _begin(weak)),
      onClose: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.soft ? 'Письмо (мягкая проверка)' : 'Письмо'),
      ),
      body: _finished ? _resultView() : _questionView(context),
    );
  }
}

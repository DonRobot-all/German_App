import 'dart:math';

import 'package:flutter/material.dart';

import '../checker.dart';
import '../models.dart';
import '../study.dart';
import '../tts.dart';
import 'study_screens.dart';

/// Глаголы, у которых заполнена хотя бы одна форма.
List<Word> verbFormWords(List<Word> words) => [
      for (final w in words)
        if (w.pos == Pos.verb &&
            (w.present3 != null || w.preterite != null || w.perfect != null))
          w,
    ];

class _FormField {
  _FormField(this.label, this.expected, this.hint);

  final String label;
  final String expected;
  final String hint;
  final TextEditingController controller = TextEditingController();
  final FocusNode focus = FocusNode();
  AnswerCheck? result;
}

/// Тренировка форм глаголов: по инфинитиву вписать Präsens (er/sie/es),
/// Präteritum и Perfekt.
class VerbFormsScreen extends StatefulWidget {
  const VerbFormsScreen({super.key, required this.words, required this.soft});

  final List<Word> words;
  final bool soft;

  @override
  State<VerbFormsScreen> createState() => _VerbFormsScreenState();
}

class _VerbFormsScreenState extends State<VerbFormsScreen> {
  late List<Word> _queue;
  final List<Word> _wrong = [];
  List<_FormField> _fields = [];
  int _index = 0;
  int _correct = 0;
  bool _checked = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _begin(widget.words);
  }

  @override
  void dispose() {
    _disposeFields();
    super.dispose();
  }

  void _disposeFields() {
    for (final f in _fields) {
      f.controller.dispose();
      f.focus.dispose();
    }
    _fields = [];
  }

  void _begin(List<Word> words) {
    _queue = List<Word>.of(words)..shuffle(Random());
    _wrong.clear();
    _index = 0;
    _correct = 0;
    _finished = false;
    _prepare();
  }

  void _prepare() {
    _disposeFields();
    final w = _queue[_index];
    _fields = [
      if (w.present3 != null)
        _FormField('Präsens, er/sie/es', w.present3!, 'er/sie/es …'),
      if (w.preterite != null)
        _FormField('Präteritum, er/sie/es', w.preterite!, 'er/sie/es …'),
      if (w.perfect != null) _FormField('Perfekt', w.perfect!, 'er/sie/es …'),
    ];
    _checked = false;
  }

  void _check({bool giveUp = false}) {
    if (_checked) return;
    var allOk = true;
    for (final f in _fields) {
      final res = giveUp
          ? const AnswerCheck(false)
          : checkForm(f.expected, f.controller.text, soft: widget.soft);
      f.result = res;
      if (!res.accepted) allOk = false;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _checked = true;
      if (allOk) {
        _correct++;
      } else {
        _wrong.add(_queue[_index]);
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

  void _insertChar(String ch) {
    _FormField? target;
    for (final f in _fields) {
      if (f.focus.hasFocus) target = f;
    }
    target ??= _fields.isEmpty ? null : _fields.first;
    if (target == null) return;
    final c = target.controller;
    final text = c.text;
    final sel = c.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    c.value = TextEditingValue(
      text: text.replaceRange(start, end, ch),
      selection: TextSelection.collapsed(offset: start + ch.length),
    );
    target.focus.requestFocus();
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

  Widget _fieldView(_FormField f, int i) {
    final res = f.result;
    final ok = res?.accepted ?? false;
    final note = res?.note;
    final last = i == _fields.length - 1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: f.controller,
            focusNode: f.focus,
            autofocus: i == 0,
            readOnly: _checked,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: last ? TextInputAction.done : TextInputAction.next,
            onSubmitted: (_) {
              if (last) _check();
            },
            style: const TextStyle(fontSize: 20),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: f.label,
              hintText: f.hint,
              filled: _checked,
              fillColor: _checked
                  ? (ok ? Colors.green.withAlpha(45) : Colors.red.withAlpha(45))
                  : null,
            ),
          ),
          if (_checked)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                ok
                    ? (note ?? 'Верно')
                    : 'Правильно: ${f.expected}${note == null ? '' : '\n$note'}',
                style: TextStyle(
                  color: ok ? Colors.green : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _questionView(BuildContext context) {
    final theme = Theme.of(context);
    final w = _queue[_index];
    final isLast = _index + 1 >= _queue.length;
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_index + (_checked ? 1 : 0)) / _queue.length,
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
                  padding: const EdgeInsets.all(20),
                  child: SizedBox(
                    width: double.infinity,
                    child: Column(
                      children: [
                        Text(
                          'Впишите формы глагола',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          w.german,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        SpeakButton(
                          key: ValueKey<String>('vf-$_index'),
                          text: w.german,
                        ),
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
              for (var i = 0; i < _fields.length; i++) _fieldView(_fields[i], i),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_checked) _charRow(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: _checked
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
                              onPressed: () => _check(giveUp: true),
                              child: const Text('Не знаю'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton(
                              onPressed: _check,
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
      headline: '$_correct из ${_queue.length}',
      subtitle: 'глаголов без ошибок во всех формах',
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
        title: Text(widget.soft ? 'Формы глаголов (мягко)' : 'Формы глаголов'),
      ),
      body: _finished ? _resultView() : _questionView(context),
    );
  }
}

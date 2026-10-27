import 'dart:math';

import 'package:flutter/material.dart';

import '../checker.dart';
import '../models.dart';
import '../settings.dart';
import '../study.dart';
import '../tts.dart';

/// Вопросы по «аспектам» слова: артикль, формы глагола, предлог.
///
/// Каждый виджет занимает весь экран под полосой прогресса (содержимое и
/// нижняя панель с кнопками). Он один раз сообщает результат через
/// [onAnswered], а кнопка «Дальше» вызывает [onNext]. Поэтому одни и те же
/// вопросы используются и в отдельных тренировках, и в умном повторении.
/// Чтобы состояние сбрасывалось, каждому вопросу давайте новый key.

List<Word> articleWords(List<Word> words) =>
    [for (final w in words) if (w.aspects.contains(kAspectArticle)) w];

List<Word> verbFormWords(List<Word> words) =>
    [for (final w in words) if (w.aspects.contains(kAspectForms)) w];

List<Word> prepVerbWords(List<Word> words) =>
    [for (final w in words) if (w.aspects.contains(kAspectPrep)) w];

/// Для диктовки подходит любое слово.
List<Word> dictationWords(List<Word> words) =>
    [for (final w in words) if (w.german.trim().isNotEmpty) w];

List<Word> wordsForAspect(String aspect, List<Word> words) =>
    [for (final w in words) if (w.aspects.contains(aspect)) w];

// ---------- Общие куски ----------

class _PromptCard extends StatelessWidget {
  const _PromptCard({
    required this.question,
    required this.title,
    required this.subtitle,
    this.badge,
    this.speakText,
  });

  final String question;
  final String title;
  final String subtitle;
  final String? badge;
  final String? speakText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Chip(
                    label: Text(badge!),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              Text(question, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (speakText != null)
                SpeakButton(key: ValueKey<String>('sp-$title'), text: speakText!),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.ok, this.text});

  final bool ok;
  final String? text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text ?? (ok ? 'Верно!' : 'Неверно'),
      textAlign: TextAlign.center,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: ok ? Colors.green : theme.colorScheme.error,
      ),
    );
  }
}

class _NextBar extends StatelessWidget {
  const _NextBar({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          width: double.infinity,
          child: FilledButton(onPressed: onPressed, child: Text(label)),
        ),
      ),
    );
  }
}

// ---------- Артикль ----------

class ArticleQuestion extends StatefulWidget {
  const ArticleQuestion({
    super.key,
    required this.word,
    required this.onAnswered,
    required this.onNext,
    required this.nextLabel,
    this.badge,
  });

  final Word word;
  final void Function(bool correct) onAnswered;
  final VoidCallback onNext;
  final String nextLabel;
  final String? badge;

  @override
  State<ArticleQuestion> createState() => _ArticleQuestionState();
}

class _ArticleQuestionState extends State<ArticleQuestion> {
  String? _picked;

  void _pick(String article) {
    if (_picked != null) return;
    final ok = article == widget.word.article;
    setState(() => _picked = article);
    widget.onAnswered(ok);
    if (AppSettings.instance.autoSpeak) {
      Speaker.instance.speak(widget.word.title);
    }
  }

  Color? _color(String a) {
    final picked = _picked;
    if (picked == null) return null;
    if (a == widget.word.article) return Colors.green.withAlpha(90);
    if (a == picked) return Colors.red.withAlpha(90);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.word;
    final answered = _picked != null;
    final ok = _picked == w.article;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PromptCard(
                badge: widget.badge,
                question: 'Какой артикль?',
                title: answered ? w.title : w.german,
                subtitle: russianFull(w),
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
                            backgroundColor: _color(a),
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
                _Verdict(
                  ok: ok,
                  text: ok ? null : 'Неверно, правильно: ${w.article}',
                ),
                if (w.pluralLine != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(w.pluralLine!, textAlign: TextAlign.center),
                  ),
              ],
            ],
          ),
        ),
        _NextBar(
          label: widget.nextLabel,
          onPressed: answered ? widget.onNext : null,
        ),
      ],
    );
  }
}

// ---------- Предлог ----------

class PrepQuestion extends StatefulWidget {
  const PrepQuestion({
    super.key,
    required this.word,
    required this.onAnswered,
    required this.onNext,
    required this.nextLabel,
    this.badge,
  });

  final Word word;
  final void Function(bool correct) onAnswered;
  final VoidCallback onNext;
  final String nextLabel;
  final String? badge;

  @override
  State<PrepQuestion> createState() => _PrepQuestionState();
}

class _PrepQuestionState extends State<PrepQuestion> {
  late final List<String> _options;
  String? _pickedPrep;
  String? _pickedCase;

  bool get _needsCase => widget.word.prepCase != null;
  bool get _answered =>
      _pickedPrep != null && (!_needsCase || _pickedCase != null);

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    final right = widget.word.prep!;
    final others = [
      for (final p in kPrepositions)
        if (p != right) p,
    ]..shuffle(rnd);
    _options = [right, ...others.take(5)]..shuffle(rnd);
  }

  void _pickPrep(String p) {
    if (_pickedPrep != null) return;
    setState(() => _pickedPrep = p);
    _maybeDone();
  }

  void _pickCase(String c) {
    if (_pickedPrep == null || _pickedCase != null) return;
    setState(() => _pickedCase = c);
    _maybeDone();
  }

  void _maybeDone() {
    if (!_answered) return;
    final w = widget.word;
    widget.onAnswered(
      _pickedPrep == w.prep && (!_needsCase || _pickedCase == w.prepCase),
    );
  }

  Color? _color(bool isRight, bool isPicked) {
    if (!_answered) return null;
    if (isRight) return Colors.green.withAlpha(90);
    if (isPicked) return Colors.red.withAlpha(90);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = widget.word;
    final answered = _answered;
    final ok = answered &&
        _pickedPrep == w.prep &&
        (!_needsCase || _pickedCase == w.prepCase);
    final full = w.prepCase == null ? w.german : '${w.german} + ${w.prepCase}.';
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PromptCard(
                badge: widget.badge,
                question: 'Какой предлог?',
                title: answered ? full : '${w.prepStem} …',
                subtitle: russianFull(w),
                speakText: answered ? w.german : null,
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
                          backgroundColor: _color(p == w.prep, p == _pickedPrep),
                        ),
                        onPressed:
                            _pickedPrep == null ? () => _pickPrep(p) : null,
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
                            onPressed:
                                _pickedCase == null ? () => _pickCase(c) : null,
                            child:
                                Text(c, style: const TextStyle(fontSize: 18)),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (answered) ...[
                const SizedBox(height: 16),
                _Verdict(ok: ok, text: ok ? null : 'Неверно. Правильно: $full'),
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
        _NextBar(
          label: widget.nextLabel,
          onPressed: answered ? widget.onNext : null,
        ),
      ],
    );
  }
}

// ---------- Формы глагола ----------

class _FormField {
  _FormField(this.label, this.expected);

  final String label;
  final String expected;
  final TextEditingController controller = TextEditingController();
  final FocusNode focus = FocusNode();
  AnswerCheck? result;
}

class FormsQuestion extends StatefulWidget {
  const FormsQuestion({
    super.key,
    required this.word,
    required this.soft,
    required this.onAnswered,
    required this.onNext,
    required this.nextLabel,
    this.badge,
  });

  final Word word;

  /// Мягкая проверка письма.
  final bool soft;
  final void Function(bool correct) onAnswered;
  final VoidCallback onNext;
  final String nextLabel;
  final String? badge;

  @override
  State<FormsQuestion> createState() => _FormsQuestionState();
}

class _FormsQuestionState extends State<FormsQuestion> {
  late final List<_FormField> _fields;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    final w = widget.word;
    _fields = [
      if (w.present3 != null) _FormField('Präsens, er/sie/es', w.present3!),
      if (w.preterite != null) _FormField('Präteritum, er/sie/es', w.preterite!),
      if (w.perfect != null) _FormField('Perfekt', w.perfect!),
    ];
  }

  @override
  void dispose() {
    for (final f in _fields) {
      f.controller.dispose();
      f.focus.dispose();
    }
    super.dispose();
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
    setState(() => _checked = true);
    widget.onAnswered(allOk);
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
              hintText: 'er/sie/es …',
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

  @override
  Widget build(BuildContext context) {
    final w = widget.word;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _PromptCard(
                badge: widget.badge,
                question: 'Впишите формы глагола',
                title: w.german,
                subtitle: russianFull(w),
                speakText: w.german,
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
                          onPressed: widget.onNext,
                          child: Text(widget.nextLabel),
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
}

// ---------- Диктовка ----------

class DictationQuestion extends StatefulWidget {
  const DictationQuestion({
    super.key,
    required this.word,
    required this.soft,
    required this.onAnswered,
    required this.onNext,
    required this.nextLabel,
    this.badge,
  });

  final Word word;

  /// Мягкая проверка письма.
  final bool soft;
  final void Function(bool correct) onAnswered;
  final VoidCallback onNext;
  final String nextLabel;
  final String? badge;

  @override
  State<DictationQuestion> createState() => _DictationQuestionState();
}

class _DictationQuestionState extends State<DictationQuestion> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  AnswerCheck? _result;
  bool _showHint = false;

  @override
  void initState() {
    super.initState();
    // Слово звучит сразу, как появился вопрос.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Speaker.instance.speak(widget.word.title);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _check({bool giveUp = false}) {
    if (_result != null) return;
    final AnswerCheck res;
    if (giveUp) {
      res = const AnswerCheck(false);
    } else {
      if (_controller.text.trim().isEmpty) return;
      res = checkGerman(widget.word, _controller.text, soft: widget.soft);
    }
    FocusScope.of(context).unfocus();
    setState(() => _result = res);
    widget.onAnswered(res.accepted);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = widget.word;
    final res = _result;
    final answered = res != null;
    final accepted = res?.accepted ?? false;
    final note = res?.note;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      if (widget.badge != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Chip(
                            label: Text(widget.badge!),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      Text(
                        'Послушайте и напишите по-немецки',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => Speaker.instance.speak(w.title),
                            icon: const Icon(Icons.volume_up),
                            label: const Text('Повторить'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => Speaker.instance
                                .speak(w.title, rateFactor: 0.6),
                            icon: const Icon(Icons.slow_motion_video),
                            label: const Text('Медленно'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (_showHint || answered)
                        Text(
                          russianFull(w),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        )
                      else
                        TextButton(
                          onPressed: () => setState(() => _showHint = true),
                          child: const Text('Показать перевод'),
                        ),
                    ],
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
                onSubmitted: (_) => _check(),
                style: const TextStyle(fontSize: 20),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Ответ по-немецки',
                  helperText: w.pos == Pos.noun
                      ? 'Существительное пишите с артиклем: der / die / das'
                      : null,
                  filled: answered,
                  fillColor: answered
                      ? (accepted
                          ? Colors.green.withAlpha(45)
                          : Colors.red.withAlpha(45))
                      : null,
                ),
              ),
              if (answered) ...[
                const SizedBox(height: 12),
                _Verdict(ok: accepted),
                if (note != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(note, textAlign: TextAlign.center),
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
                          Text('Правильный ответ',
                              style: theme.textTheme.bodySmall),
                          const SizedBox(height: 2),
                          Text(
                            w.title,
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (w.pluralLine != null) Text(w.pluralLine!),
                          if (w.verbFormsLine != null) Text(w.verbFormsLine!),
                          if (w.prepLine != null) Text(w.prepLine!),
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
              if (!answered) _charRow(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: answered
                    ? SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: widget.onNext,
                          child: Text(widget.nextLabel),
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
}

/// Вопрос нужного вида для [aspect].
Widget buildAspectQuestion({
  required String aspect,
  required Word word,
  required bool soft,
  required void Function(bool correct) onAnswered,
  required VoidCallback onNext,
  required String nextLabel,
  String? badge,
  Key? key,
}) {
  switch (aspect) {
    case kAspectArticle:
      return ArticleQuestion(
        key: key,
        word: word,
        onAnswered: onAnswered,
        onNext: onNext,
        nextLabel: nextLabel,
        badge: badge,
      );
    case kAspectDictation:
      return DictationQuestion(
        key: key,
        word: word,
        soft: soft,
        onAnswered: onAnswered,
        onNext: onNext,
        nextLabel: nextLabel,
        badge: badge,
      );
    case kAspectPrep:
      return PrepQuestion(
        key: key,
        word: word,
        onAnswered: onAnswered,
        onNext: onNext,
        nextLabel: nextLabel,
        badge: badge,
      );
    default:
      return FormsQuestion(
        key: key,
        word: word,
        soft: soft,
        onAnswered: onAnswered,
        onNext: onNext,
        nextLabel: nextLabel,
        badge: badge,
      );
  }
}

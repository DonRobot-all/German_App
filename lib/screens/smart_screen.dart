import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../checker.dart';
import '../db.dart';
import '../models.dart';
import '../srs.dart';
import '../study.dart';
import '../tts.dart';
import 'aspect_widgets.dart';
import 'study_screens.dart';

enum _Format { choice, written, aspect }

class _Task {
  const _Task({
    required this.item,
    required this.format,
    this.quiz,
    this.attempts = 0,
  });

  final ReviewItem item;
  final _Format format;

  /// Вопрос с вариантами (только для формата choice).
  final QuizQuestion? quiz;

  /// 0 — обычный вопрос, 1 и больше — повтор после ошибки в этой сессии.
  final int attempts;

  bool get isRetry => attempts > 0;
}

/// Сессия «Умное повторение»: ошибки, просроченные, давно не писавшиеся и
/// новые слова вперемешку. Вопросы бывают с вариантами и письменные.
class SmartSessionScreen extends StatefulWidget {
  const SmartSessionScreen({
    super.key,
    required this.items,
    required this.pool,
    required this.soft,
  });

  final List<ReviewItem> items;

  /// Все слова приложения (для подбора неверных вариантов).
  final List<Word> pool;

  /// Мягкая проверка письма.
  final bool soft;

  @override
  State<SmartSessionScreen> createState() => _SmartSessionScreenState();
}

class _SmartSessionScreenState extends State<SmartSessionScreen> {
  final Random _rnd = Random();
  final List<_Task> _queue = [];
  final List<Word> _wrongWords = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  _Task? _current;
  bool _aspectAnswered = false;
  int _seq = 0; // номер текущего вопроса (для автоозвучки)
  int _total = 0;
  int _done = 0;
  int _firstTry = 0;
  int _firstTryCorrect = 0;
  int? _selected;
  AnswerCheck? _result;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    for (final item in widget.items) {
      _queue.add(_makeTask(item));
    }
    _total = _queue.length;
    if (_queue.isEmpty) {
      _finished = true;
    } else {
      _current = _queue.removeAt(0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Выбирает формат вопроса: слова с низким уровнем чаще идут с вариантами,
  /// с высоким — письменно. «Давно не писали» всегда письменно.
  _Task _makeTask(ReviewItem item) {
    // Артикль, формы глагола и предлог: у них свои вопросы.
    if (item.aspect != null) {
      return _Task(item: item, format: _Format.aspect);
    }
    var format = _Format.choice;
    if (widget.pool.length < 2 ||
        item.reason == ReviewReason.stale ||
        item.level >= 4) {
      format = _Format.written;
    } else if (item.level >= 2 && _rnd.nextBool()) {
      format = _Format.written;
    }
    QuizQuestion? quiz;
    if (format == _Format.choice) {
      quiz = buildSingleQuestion(
        word: item.word,
        direction: item.direction,
        pool: widget.pool,
        random: _rnd,
      );
      if (quiz == null) format = _Format.written;
    }
    return _Task(item: item, format: format, quiz: quiz);
  }

  /// Записывает ответ, а при ошибке возвращает слово в очередь
  /// через 3–5 других карточек (не больше двух раз).
  /// Вызывается внутри setState.
  void _record(_Task t, bool correct) {
    final w = t.item.word;
    final key = t.item.progressDirection;
    // Навыки (артикль, формы, предлог) оцениваются как полноценный ответ.
    final written = t.format != _Format.choice;

    if (t.isRetry && correct) {
      unawaited(AppDb.instance.touchWritten(w.id, key));
    } else {
      unawaited(AppDb.instance.recordAnswer(
        w.id,
        key,
        correct: correct,
        written: written,
      ));
    }

    if (!t.isRetry) {
      _firstTry++;
      if (correct) _firstTryCorrect++;
    }
    _done++;

    if (!correct) {
      if (!_wrongWords.any((x) => x.id == w.id)) _wrongWords.add(w);
      if (t.attempts < 2) {
        final pos = min(_queue.length, 3 + _rnd.nextInt(3));
        _queue.insert(
          pos,
          _Task(
            item: t.item,
            format:
                t.format == _Format.aspect ? _Format.aspect : _Format.written,
            attempts: t.attempts + 1,
          ),
        );
        _total++;
      }
    }
  }

  void _answerChoice(int i) {
    final t = _current;
    if (t == null || _selected != null) return;
    final correct = i == t.quiz!.correctIndex;
    setState(() {
      _selected = i;
      _record(t, correct);
    });
  }

  void _submitWritten({bool giveUp = false}) {
    final t = _current;
    if (t == null || _result != null) return;
    final AnswerCheck res;
    if (giveUp) {
      res = const AnswerCheck(false);
    } else {
      if (_controller.text.trim().isEmpty) return;
      res = t.item.direction == QuestionDirection.ruToDe
          ? checkGerman(t.item.word, _controller.text, soft: widget.soft)
          : checkRussian(t.item.word, _controller.text, soft: widget.soft);
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _result = res;
      _record(t, res.accepted);
    });
  }

  void _next() {
    setState(() {
      if (_queue.isEmpty) {
        _finished = true;
        _current = null;
      } else {
        _current = _queue.removeAt(0);
        _seq++;
        _selected = null;
        _result = null;
        _aspectAnswered = false;
        _controller.clear();
      }
    });
    if (!_finished && _current?.format == _Format.written) {
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

  String _reasonLabel(_Task t) {
    if (t.isRetry) return 'Повторяем ошибку';
    switch (t.item.reason) {
      case ReviewReason.relearn:
        return 'Недавняя ошибка';
      case ReviewReason.overdue:
        return 'Пора повторить';
      case ReviewReason.stale:
        return 'Давно не писали';
      case ReviewReason.fresh:
        return 'Новое слово';
    }
  }

  // ---------- Виджеты ----------

  Widget _promptCard(BuildContext context, _Task t, String question, String prompt) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              Chip(
                label: Text(_reasonLabel(t)),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(height: 8),
              Text(question, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text(
                prompt,
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (t.item.direction == QuestionDirection.deToRu)
                SpeakButton(
                  key: ValueKey<String>('sp-$_seq'),
                  text: t.item.word.title,
                  autoPlay: true,
                ),
              const SizedBox(height: 4),
              Text(t.item.word.pos.label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(QuizQuestion q, int i) {
    final answered = _selected != null;
    final isCorrect = i == q.correctIndex;
    final isSelected = i == _selected;
    Color? bg;
    Color? fg;
    if (answered && isCorrect) {
      bg = Colors.green.shade700;
      fg = Colors.white;
    } else if (answered && isSelected) {
      bg = Colors.red.shade700;
      fg = Colors.white;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: bg,
            foregroundColor: fg,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          onPressed: () => _answerChoice(i),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  q.optionText(i),
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              if (answered && isCorrect) const Icon(Icons.check),
              if (answered && !isCorrect && isSelected) const Icon(Icons.close),
            ],
          ),
        ),
      ),
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

  Widget _verdict(BuildContext context, bool ok, String? note) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ok ? 'Верно!' : 'Неверно',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: ok ? Colors.green : theme.colorScheme.error,
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(note),
          ),
        if (!ok && _current != null && _current!.attempts < 2)
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text('Это слово вернётся через несколько карточек.'),
          ),
      ],
    );
  }

  Widget _choiceBody(BuildContext context, _Task t) {
    final q = t.quiz!;
    final answered = _selected != null;
    final correct = answered && _selected == q.correctIndex;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _promptCard(
          context,
          t,
          q.direction == QuestionDirection.ruToDe
              ? 'Как по-немецки?'
              : 'Как по-русски?',
          q.prompt,
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < q.options.length; i++) _option(q, i),
        if (answered) ...[
          const SizedBox(height: 4),
          _verdict(context, correct, null),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: WordInfo(
                  word: q.word,
                  speakOnShow: q.direction == QuestionDirection.ruToDe,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _writtenBody(BuildContext context, _Task t) {
    final theme = Theme.of(context);
    final w = t.item.word;
    final ruToDe = t.item.direction == QuestionDirection.ruToDe;
    final res = _result;
    final answered = res != null;
    final accepted = res?.accepted ?? false;
    final note = res?.note;
    final prompt = ruToDe ? russianFull(w) : w.title;
    final correctText = ruToDe ? w.title : russianFull(w);

    String? helper;
    if (ruToDe && w.pos == Pos.noun) {
      helper = 'Существительное пишите с артиклем: der / die / das';
    }
    Color? fill;
    if (answered) {
      fill = accepted ? Colors.green.withAlpha(45) : Colors.red.withAlpha(45);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _promptCard(
          context,
          t,
          ruToDe ? 'Напишите по-немецки' : 'Напишите по-русски',
          prompt,
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
          onSubmitted: (_) => _submitWritten(),
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
          _verdict(context, accepted, note),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Правильный ответ', style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      correctText,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    WordInfo(
                      word: w,
                      showHeader: false,
                      speakOnShow: ruToDe,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _bottomBar(_Task t) {
    final isChoice = t.format == _Format.choice;
    final answered = isChoice ? _selected != null : _result != null;
    final ruToDe = t.item.direction == QuestionDirection.ruToDe;
    final isLast = _queue.isEmpty;

    final Widget buttons;
    if (answered) {
      buttons = SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: _next,
          child: Text(isLast ? 'Результат' : 'Дальше'),
        ),
      );
    } else if (isChoice) {
      buttons = SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => _answerChoice(-1),
          child: const Text('Не знаю'),
        ),
      );
    } else {
      buttons = Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _submitWritten(giveUp: true),
              child: const Text('Не знаю'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: _submitWritten,
              child: const Text('Проверить'),
            ),
          ),
        ],
      );
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isChoice && ruToDe && !answered) _charRow(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: buttons,
          ),
        ],
      ),
    );
  }

  Widget _aspectBody(BuildContext context, _Task t) {
    return buildAspectQuestion(
      key: ValueKey<String>('asp-$_seq'),
      aspect: t.item.aspect!,
      word: t.item.word,
      soft: widget.soft,
      badge: '${_reasonLabel(t)} · ${aspectLabel(t.item.aspect!)}',
      nextLabel: _queue.isEmpty ? 'Результат' : 'Дальше',
      onNext: _next,
      onAnswered: (ok) {
        if (_aspectAnswered) return;
        setState(() {
          _aspectAnswered = true;
          _record(t, ok);
        });
      },
    );
  }

  Widget _sessionView(BuildContext context, _Task t) {
    final isAspect = t.format == _Format.aspect;
    return Column(
      children: [
        LinearProgressIndicator(
          value: (_done / _total).clamp(0.0, 1.0).toDouble(),
        ),
        Expanded(
          child: isAspect
              ? _aspectBody(context, t)
              : t.format == _Format.choice
                  ? _choiceBody(context, t)
                  : _writtenBody(context, t),
        ),
        // У вопросов-навыков своя нижняя панель.
        if (!isAspect) _bottomBar(t),
      ],
    );
  }

  Widget _resultView() {
    if (_firstTry == 0) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Сейчас повторять нечего.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final weak = List<Word>.of(_wrongWords);
    return StudyResultView(
      headline: '$_firstTryCorrect из $_firstTry',
      subtitle: 'правильно с первого раза',
      weakTitle: 'Ошибки (${weak.length}) вернутся в повторение',
      weak: weak,
      onClose: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _current;
    return Scaffold(
      appBar: AppBar(title: const Text('Умное повторение')),
      body: (_finished || t == null) ? _resultView() : _sessionView(context, t),
    );
  }
}

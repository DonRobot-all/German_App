import 'dart:math';

import 'package:flutter/material.dart';

import '../models.dart';
import '../study.dart';
import 'written_screen.dart';

// ======================================================================
// Настройка тренировки (нижняя панель)
// ======================================================================

Future<void> showStudySetup(
  BuildContext context, {
  required List<Word> words,
  required List<Word> pool,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _StudySetupSheet(
      rootContext: context,
      words: words,
      pool: pool,
    ),
  );
}

class _StudySetupSheet extends StatefulWidget {
  const _StudySetupSheet({
    required this.rootContext,
    required this.words,
    required this.pool,
  });

  final BuildContext rootContext;
  final List<Word> words;
  final List<Word> pool;

  @override
  State<_StudySetupSheet> createState() => _StudySetupSheetState();
}

class _StudySetupSheetState extends State<_StudySetupSheet> {
  StudyDirection _direction = StudyDirection.ruDe;
  int _size = 0; // 0 = все слова
  bool _soft = false; // false = строгая проверка письма

  List<Word> _session() {
    final list = List<Word>.of(widget.words)..shuffle();
    if (_size > 0 && list.length > _size) return list.take(_size).toList();
    return list;
  }

  void _startCards() {
    final session = _session();
    final root = widget.rootContext;
    final direction = _direction;
    Navigator.pop(context);
    Navigator.push(
      root,
      MaterialPageRoute<void>(
        builder: (_) => FlashcardsScreen(words: session, direction: direction),
      ),
    );
  }

  void _startQuiz() {
    final session = _session();
    final root = widget.rootContext;
    final direction = _direction;
    final pool = widget.pool;
    Navigator.pop(context);
    Navigator.push(
      root,
      MaterialPageRoute<void>(
        builder: (_) =>
            QuizScreen(words: session, pool: pool, direction: direction),
      ),
    );
  }

  void _startWritten() {
    final session = _session();
    final root = widget.rootContext;
    final direction = _direction;
    final soft = _soft;
    Navigator.pop(context);
    Navigator.push(
      root,
      MaterialPageRoute<void>(
        builder: (_) => WrittenScreen(
          words: session,
          direction: direction,
          soft: soft,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canQuiz = widget.pool.length >= 2;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Тренировка', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Направление', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<StudyDirection>(
              showSelectedIcon: false,
              segments: [
                for (final d in StudyDirection.values)
                  ButtonSegment<StudyDirection>(
                    value: d,
                    label: Text(d.label),
                  ),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 16),
            Text('Сколько слов', style: theme.textTheme.labelLarge),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment<int>(value: 10, label: Text('10')),
                ButtonSegment<int>(value: 20, label: Text('20')),
                ButtonSegment<int>(value: 0, label: Text('Все')),
              ],
              selected: {_size},
              onSelectionChanged: (s) => setState(() => _size = s.first),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Мягкая проверка письма'),
              subtitle: const Text(
                'ae/oe/ue вместо ä/ö/ü, любой регистр, опечатка в одну букву. '
                'Артикль обязателен всегда.',
              ),
              value: _soft,
              onChanged: (v) => setState(() => _soft = v),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _startCards,
              icon: const Icon(Icons.style_outlined),
              label: const Text('Карточки'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: canQuiz ? _startQuiz : null,
              icon: const Icon(Icons.quiz_outlined),
              label: const Text('Тест с вариантами ответа'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _startWritten,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Письменный ввод'),
            ),
            if (!canQuiz)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Для теста нужно минимум 2 слова.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Общие виджеты
// ======================================================================

/// Информация о слове: артикль, перевод, мн. число, формы глагола, пример.
class WordInfo extends StatelessWidget {
  const WordInfo({
    super.key,
    required this.word,
    this.showHeader = true,
    this.centered = false,
  });

  final Word word;
  final bool showHeader;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final align = centered ? TextAlign.center : TextAlign.start;
    final lines = <String>[
      if (word.pluralLine != null) word.pluralLine!,
      if (word.verbFormsLine != null) word.verbFormsLine!,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        if (showHeader) ...[
          Text(
            word.title,
            textAlign: align,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(russianFull(word), textAlign: align),
        ],
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(l, textAlign: align),
          ),
        if (word.example != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              word.example!,
              textAlign: align,
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
      ],
    );
  }
}

/// Итоги сессии.
class StudyResultView extends StatelessWidget {
  const StudyResultView({
    required this.headline,
    required this.subtitle,
    required this.weakTitle,
    required this.weak,
    required this.onRepeat,
    required this.onClose,
  });

  final String headline;
  final String subtitle;
  final String weakTitle;
  final List<Word> weak;
  final VoidCallback onRepeat;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        Text(
          headline,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(subtitle, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        if (weak.isNotEmpty) ...[
          Text(weakTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final w in weak)
            Card(
              child: ListTile(
                title: Text(
                  w.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(russianFull(w)),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: onRepeat,
            child: const Text('Повторить эти слова'),
          ),
        ] else
          Text(
            'Без ошибок!',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: onClose, child: const Text('Закрыть')),
      ],
    );
  }
}

// ======================================================================
// Тест с вариантами ответа
// ======================================================================

class QuizScreen extends StatefulWidget {
  const QuizScreen({
    super.key,
    required this.words,
    required this.pool,
    required this.direction,
  });

  final List<Word> words;
  final List<Word> pool;
  final StudyDirection direction;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late List<QuizQuestion> _questions;
  final List<Word> _wrong = [];
  int _index = 0;
  int? _selected;
  int _correct = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _begin(widget.words);
  }

  void _begin(List<Word> words) {
    _questions = buildQuiz(
      words: words,
      pool: widget.pool,
      direction: widget.direction,
    );
    _index = 0;
    _selected = null;
    _correct = 0;
    _wrong.clear();
    _finished = false;
  }

  void _answer(int i) {
    if (_selected != null) return;
    final q = _questions[_index];
    setState(() {
      _selected = i;
      if (i == q.correctIndex) {
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
        _selected = null;
      }
    });
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
          onPressed: () => _answer(i),
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

  Widget _questionView(BuildContext context) {
    final theme = Theme.of(context);
    final q = _questions[_index];
    final answered = _selected != null;
    final correct = answered && _selected == q.correctIndex;
    final isLast = _index + 1 >= _questions.length;

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
                          q.direction == QuestionDirection.ruToDe
                              ? 'Как по-немецки?'
                              : 'Как по-русски?',
                          style: theme.textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          q.prompt,
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
              for (var i = 0; i < q.options.length; i++) _option(q, i),
              if (answered) ...[
                const SizedBox(height: 4),
                Text(
                  correct ? 'Верно!' : 'Неверно',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: correct ? Colors.green : theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: WordInfo(word: q.word),
                    ),
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

  Widget _result() {
    final total = _questions.length;
    final weak = List<Word>.of(_wrong);
    return StudyResultView(
      headline: '$_correct из $total',
      subtitle: 'правильных ответов',
      weakTitle: 'Ошибки (${weak.length})',
      weak: weak,
      onRepeat: () => setState(() => _begin(weak)),
      onClose: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_questions.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Не удалось составить вопросы.\nДобавьте в набор больше слов.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (_finished) {
      body = _result();
    } else {
      body = _questionView(context);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Тест')),
      body: body,
    );
  }
}

// ======================================================================
// Карточки
// ======================================================================

class _Card {
  const _Card(this.word, this.direction);

  final Word word;
  final QuestionDirection direction;
}

class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({
    super.key,
    required this.words,
    required this.direction,
  });

  final List<Word> words;
  final StudyDirection direction;

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  late List<_Card> _cards;
  final List<Word> _unknown = [];
  int _index = 0;
  int _known = 0;
  bool _flipped = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _begin(widget.words);
  }

  void _begin(List<Word> words) {
    final rnd = Random();
    final list = List<Word>.of(words)..shuffle(rnd);
    _cards = [
      for (final w in list) _Card(w, pickDirection(widget.direction, rnd)),
    ];
    _index = 0;
    _known = 0;
    _flipped = false;
    _finished = false;
    _unknown.clear();
  }

  void _mark(bool known) {
    setState(() {
      if (known) {
        _known++;
      } else {
        _unknown.add(_cards[_index].word);
      }
      if (_index + 1 >= _cards.length) {
        _finished = true;
      } else {
        _index++;
        _flipped = false;
      }
    });
  }

  Widget _cardView(BuildContext context) {
    final theme = Theme.of(context);
    final card = _cards[_index];
    final ruToDe = card.direction == QuestionDirection.ruToDe;
    final frontText = ruToDe ? russianFull(card.word) : card.word.title;
    final backText = ruToDe ? card.word.title : russianFull(card.word);

    final Widget face;
    if (_flipped) {
      face = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            backText,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          WordInfo(word: card.word, showHeader: false, centered: true),
        ],
      );
    } else {
      face = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(card.word.pos.label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Text(
            frontText,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Text('Нажмите, чтобы перевернуть', style: theme.textTheme.bodySmall),
        ],
      );
    }

    return Column(
      children: [
        LinearProgressIndicator(value: _index / _cards.length),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  '${_index + 1} / ${_cards.length}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setState(() => _flipped = !_flipped),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Card(
                      key: ValueKey<String>('$_index-$_flipped'),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 300,
                          minWidth: double.infinity,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(child: face),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _flipped
                ? Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _mark(false),
                          child: const Text('Не знаю'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => _mark(true),
                          child: const Text('Знаю'),
                        ),
                      ),
                    ],
                  )
                : SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => setState(() => _flipped = true),
                      child: const Text('Показать ответ'),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _result() {
    final weak = List<Word>.of(_unknown);
    return StudyResultView(
      headline: '$_known из ${_cards.length}',
      subtitle: 'отмечено как «знаю»',
      weakTitle: 'Не знаю (${weak.length})',
      weak: weak,
      onRepeat: () => setState(() => _begin(weak)),
      onClose: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Карточки')),
      body: _finished ? _result() : _cardView(context),
    );
  }
}

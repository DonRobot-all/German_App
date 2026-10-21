import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../study.dart';
import 'study_screens.dart';

const int kMatchRoundSize = 6;

class _Tile {
  _Tile(this.word, this.text);

  final Word word;
  final String text;
  bool matched = false;
}

/// Игра «Сопоставление»: в каждом раунде 6 немецких слов и 6 переводов,
/// нужно как можно быстрее соединить пары. Ошибки добавляют штраф ко времени.
class MatchScreen extends StatefulWidget {
  const MatchScreen({super.key, required this.words});

  final List<Word> words;

  @override
  State<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends State<MatchScreen> {
  static const int _penaltySeconds = 2;

  final Random _rnd = Random();
  final Stopwatch _watch = Stopwatch();
  Timer? _ticker;
  Timer? _flashTimer;

  late List<List<Word>> _rounds;
  List<_Tile> _left = [];
  List<_Tile> _right = [];
  int _round = 0;
  int _mistakes = 0;
  final Set<String> _weakIds = {};
  final List<Word> _weak = [];
  late List<Word> _source;
  final Set<String> _roundWrong = {}; // слова, в которых ошиблись в этом раунде

  _Tile? _selected;
  bool _selectedIsLeft = true;
  _Tile? _flashA;
  _Tile? _flashB;
  bool _finished = false;
  int _roundsSeconds = 0; // время завершённых раундов

  @override
  void initState() {
    super.initState();
    _source = widget.words;
    _begin();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _flashTimer?.cancel();
    _watch.stop();
    super.dispose();
  }

  void _begin() {
    final list = List<Word>.of(_source)..shuffle(_rnd);
    _rounds = [];
    for (var i = 0; i < list.length; i += kMatchRoundSize) {
      final chunk = list.sublist(i, min(i + kMatchRoundSize, list.length));
      _rounds.add(chunk);
    }
    // Слишком короткий хвост (1–2 слова) добавляем к предыдущему раунду.
    if (_rounds.length > 1 && _rounds.last.length < 3) {
      final tail = _rounds.removeLast();
      _rounds.last.addAll(tail);
    }
    _round = 0;
    _mistakes = 0;
    _roundsSeconds = 0;
    _weak.clear();
    _weakIds.clear();
    _finished = false;
    _watch
      ..reset()
      ..start();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted && !_finished) setState(() {});
    });
    _startRound();
  }

  void _startRound() {
    final words = _rounds[_round];
    _left = [for (final w in words) _Tile(w, w.title)];
    _right = [for (final w in words) _Tile(w, russianShort(w))]..shuffle(_rnd);
    _roundWrong.clear();
    _selected = null;
    _flashA = null;
    _flashB = null;
  }

  int get _seconds => _watch.elapsed.inSeconds + _mistakes * _penaltySeconds;

  String _fmt(int s) {
    final m = s ~/ 60;
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  void _tap(_Tile tile, bool isLeft) {
    if (_finished || tile.matched) return;
    if (_flashA != null) return; // идёт подсветка ошибки
    final sel = _selected;
    if (sel == null || _selectedIsLeft == isLeft) {
      setState(() {
        _selected = tile;
        _selectedIsLeft = isLeft;
      });
      return;
    }
    if (identical(sel.word, tile.word)) {
      setState(() {
        sel.matched = true;
        tile.matched = true;
        _selected = null;
      });
      if (_left.every((t) => t.matched)) _roundDone();
      return;
    }
    // Ошибка.
    _mistakes++;
    _roundWrong..add(sel.word.id)..add(tile.word.id);
    if (_weakIds.add(sel.word.id)) _weak.add(sel.word);
    if (_weakIds.add(tile.word.id)) _weak.add(tile.word);
    setState(() {
      _flashA = sel;
      _flashB = tile;
      _selected = null;
    });
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      setState(() {
        _flashA = null;
        _flashB = null;
      });
    });
  }

  void _roundDone() {
    // Каждое слово раунда: верно, если не путали его ни с чем (узнавание DE→RU).
    for (final w in _rounds[_round]) {
      unawaited(AppDb.instance.recordAnswer(
        w.id,
        'de_ru',
        correct: !_roundWrong.contains(w.id),
        written: false,
      ));
    }
    if (_round + 1 >= _rounds.length) {
      _watch.stop();
      _ticker?.cancel();
      setState(() {
        _roundsSeconds = _seconds;
        _finished = true;
      });
    } else {
      setState(() {
        _round++;
        _startRound();
      });
    }
  }

  Widget _tileView(_Tile t, bool isLeft) {
    final theme = Theme.of(context);
    if (t.matched) return const SizedBox.shrink();
    final selected = identical(_selected, t);
    final flash = identical(_flashA, t) || identical(_flashB, t);
    Color bg = theme.colorScheme.surfaceContainerHighest;
    Color fg = theme.colorScheme.onSurface;
    if (selected) {
      bg = theme.colorScheme.primaryContainer;
      fg = theme.colorScheme.onPrimaryContainer;
    }
    if (flash) {
      bg = Colors.red.withAlpha(110);
    }
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _tap(t, isLeft),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              t.text,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 16,
                fontWeight: isLeft ? FontWeight.w600 : FontWeight.normal,
                color: fg,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _playView(BuildContext context) {
    final theme = Theme.of(context);
    final n = _left.length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Раунд ${_round + 1} / ${_rounds.length}',
                  style: theme.textTheme.bodyMedium),
              Text('Ошибок: $_mistakes', style: theme.textTheme.bodyMedium),
              Text(
                _fmt(_seconds),
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _tileView(_left[i], true),
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: _tileView(_right[i], false),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _resultView() {
    final weak = List<Word>.of(_weak);
    return StudyResultView(
      headline: _fmt(_roundsSeconds),
      subtitle: 'ошибок: $_mistakes (штраф $_penaltySeconds с за каждую)',
      weakTitle: 'Путались (${weak.length})',
      weak: weak,
      onRepeat: () => setState(() {
        if (weak.length >= 3) _source = weak;
        _begin();
      }),
      onClose: () => Navigator.pop(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Сопоставление')),
      body: _finished ? _resultView() : _playView(context),
    );
  }
}

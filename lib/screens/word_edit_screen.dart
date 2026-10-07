import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';

List<String> _splitTranslations(String s) => s
    .split(RegExp(r'[;,\n]'))
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

class WordEditScreen extends StatefulWidget {
  const WordEditScreen({super.key, required this.setId, this.word});

  final String setId;
  final Word? word;

  @override
  State<WordEditScreen> createState() => _WordEditScreenState();
}

class _WordEditScreenState extends State<WordEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();

  late Pos _pos;
  String? _article;
  bool _articleError = false;
  bool _saving = false;

  /// Поле, в которое вставляются кнопки ä ö ü ß.
  TextEditingController? _active;

  late final TextEditingController _german;
  late final TextEditingController _plural;
  late final TextEditingController _translations;
  late final TextEditingController _example;
  late final TextEditingController _note;
  late final TextEditingController _present3;
  late final TextEditingController _preterite;
  late final TextEditingController _perfect;

  bool get _isNew => widget.word == null;

  @override
  void initState() {
    super.initState();
    final w = widget.word;
    _pos = w?.pos ?? Pos.noun;
    _article = w?.article;
    _german = TextEditingController(text: w?.german ?? '');
    _plural = TextEditingController(text: w?.plural ?? '');
    _translations = TextEditingController(text: w?.translations.join('; ') ?? '');
    _example = TextEditingController(text: w?.example ?? '');
    _note = TextEditingController(text: w?.note ?? '');
    _present3 = TextEditingController(text: w?.present3 ?? '');
    _preterite = TextEditingController(text: w?.preterite ?? '');
    _perfect = TextEditingController(text: w?.perfect ?? '');
  }

  @override
  void dispose() {
    for (final c in [
      _german,
      _plural,
      _translations,
      _example,
      _note,
      _present3,
      _preterite,
      _perfect,
    ]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  String? _opt(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  void _clearAll() {
    for (final c in [
      _german,
      _plural,
      _translations,
      _example,
      _note,
      _present3,
      _preterite,
      _perfect,
    ]) {
      c.clear();
    }
    _formKey.currentState?.reset();
  }

  void _insertChar(String ch) {
    final c = _active;
    if (c == null) return;
    final text = c.text;
    final sel = c.selection;
    final start = sel.isValid ? sel.start : text.length;
    final end = sel.isValid ? sel.end : text.length;
    c.value = TextEditingValue(
      text: text.replaceRange(start, end, ch),
      selection: TextSelection.collapsed(offset: start + ch.length),
    );
  }

  Future<void> _save({bool addAnother = false}) async {
    if (_saving) return;
    final formOk = _formKey.currentState!.validate();

    var german = _german.text.trim();
    var article = _article;
    // Если ввели «der Tisch» целиком — разбираем артикль сами.
    if (_pos == Pos.noun) {
      final m = RegExp(r'^(der|die|das)\s+(.+)$', caseSensitive: false)
          .firstMatch(german);
      if (m != null) {
        article = m.group(1)!.toLowerCase();
        german = m.group(2)!.trim();
      }
    }
    final articleMissing = _pos == Pos.noun && article == null;
    setState(() => _articleError = articleMissing);
    if (!formOk || articleMissing) return;

    if (_pos == Pos.noun && german[0] != german[0].toUpperCase()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Существительные пишутся с большой буквы')),
      );
      return;
    }

    final isNoun = _pos == Pos.noun;
    final isVerb = _pos == Pos.verb;
    final word = Word(
      id: widget.word?.id ?? AppDb.instance.newId(),
      german: german,
      pos: _pos,
      article: isNoun ? article : null,
      plural: isNoun
          ? _opt(_plural)?.replaceFirst(
              RegExp(r'^die\s+', caseSensitive: false), '')
          : null,
      translations: _splitTranslations(_translations.text),
      example: _opt(_example),
      note: _opt(_note),
      present3: isVerb ? _opt(_present3) : null,
      preterite: isVerb ? _opt(_preterite) : null,
      perfect: isVerb ? _opt(_perfect) : null,
    );

    setState(() => _saving = true);
    await AppDb.instance.saveWord(word, widget.setId);
    if (!mounted) return;

    if (addAnother) {
      _clearAll();
      setState(() {
        _saving = false;
        _article = null;
        _articleError = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Добавлено: ${word.title}')),
      );
    } else {
      Navigator.pop(context);
    }
  }

  // ---------- Виджеты ----------

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    String? helper,
    int maxLines = 1,
    bool german = true,
    String? Function(String?)? validator,
    TextCapitalization capitalization = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Focus(
        onFocusChange: (focused) {
          if (focused && german) _active = c;
        },
        child: TextFormField(
          controller: c,
          maxLines: maxLines,
          textCapitalization: capitalization,
          validator: validator,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            helperText: helper,
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  Widget _charRow() {
    const chars = ['ä', 'ö', 'ü', 'ß', 'Ä', 'Ö', 'Ü'];
    return ExcludeFocus(
      child: Material(
        elevation: 3,
        child: SafeArea(
          top: false,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isNoun = _pos == Pos.noun;
    final isVerb = _pos == Pos.verb;
    final errorColor = Theme.of(context).colorScheme.error;

    final germanLabel = isNoun
        ? 'Слово (например, Tisch)'
        : isVerb
            ? 'Инфинитив (например, gehen)'
            : 'Немецкое слово';

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новое слово' : 'Редактирование'),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(),
            child: const Text('Сохранить'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final p in Pos.values)
                        ChoiceChip(
                          label: Text(p.label),
                          selected: _pos == p,
                          onSelected: (_) => setState(() {
                            _pos = p;
                            _articleError = false;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isNoun) ...[
                    Row(
                      children: [
                        for (final a in kArticles)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(a),
                              selected: _article == a,
                              onSelected: (_) => setState(() {
                                _article = a;
                                _articleError = false;
                              }),
                            ),
                          ),
                      ],
                    ),
                    if (_articleError)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text('Выберите артикль',
                            style: TextStyle(color: errorColor, fontSize: 12)),
                      ),
                    const SizedBox(height: 12),
                  ],
                  _field(
                    _german,
                    germanLabel,
                    helper: isNoun
                        ? 'Можно ввести сразу с артиклем: der Tisch'
                        : null,
                    capitalization: isNoun
                        ? TextCapitalization.words
                        : TextCapitalization.none,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Введите слово'
                        : null,
                  ),
                  if (isNoun)
                    _field(
                      _plural,
                      'Множественное число',
                      hint: 'Tische',
                      helper: 'Только форма, без артикля',
                    ),
                  if (isVerb) ...[
                    _field(_present3, 'Präsens, er/sie/es', hint: 'geht'),
                    _field(_preterite, 'Präteritum, er/sie/es', hint: 'ging'),
                    _field(_perfect, 'Perfekt', hint: 'ist gegangen'),
                  ],
                  _field(
                    _translations,
                    'Перевод',
                    german: false,
                    helper: 'Несколько вариантов — через запятую или «;»',
                    validator: (v) => _splitTranslations(v ?? '').isEmpty
                        ? 'Укажите перевод'
                        : null,
                  ),
                  _field(_example, 'Пример предложения (необязательно)',
                      maxLines: 2),
                  _field(_note, 'Заметка (необязательно)',
                      maxLines: 2, german: false),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _saving ? null : () => _save(),
                    child: const Text('Сохранить'),
                  ),
                  if (_isNew) ...[
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed:
                          _saving ? null : () => _save(addAnother: true),
                      child: const Text('Сохранить и добавить ещё'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _charRow(),
        ],
      ),
    );
  }
}

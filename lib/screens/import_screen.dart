import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db.dart';
import '../importer.dart';
import '../models.dart';

/// Импорт слов списком: вставить текст, посмотреть разбор, добавить в набор.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.setId});

  final String setId;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final TextEditingController _controller = TextEditingController();
  Set<String> _existing = <String>{};
  ImportParseResult? _parsed;
  List<DraftWord> _toAdd = [];
  int _skippedExisting = 0;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    final words = await AppDb.instance.listWords(widget.setId);
    if (!mounted) return;
    _existing = words.map(wordKey).toSet();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Буфер обмена пуст')),
      );
      return;
    }
    setState(() => _controller.text = text);
  }

  void _parse() {
    final parsed = parseWordList(_controller.text);
    final fresh =
        parsed.words.where((d) => !_existing.contains(d.key)).toList();
    setState(() {
      _parsed = parsed;
      _toAdd = fresh;
      _skippedExisting = parsed.words.length - fresh.length;
    });
  }

  Future<void> _save() async {
    if (_saving || _toAdd.isEmpty) return;
    setState(() => _saving = true);
    final words = [
      for (final d in _toAdd) d.toWord(AppDb.instance.newId()),
    ];
    await AppDb.instance.addWords(widget.setId, words);
    if (!mounted) return;
    Navigator.pop(context, words.length);
  }

  // ---------- Ввод текста ----------

  Widget _inputView(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Вставьте список слов: одно слово в строке. Слово и перевод '
                'разделяйте табуляцией, точкой с запятой или « - ».',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Примеры:\n'
                'der Tisch ; стол\n'
                'der Tisch, die Tische ; стол\n'
                'gehen, ging, ist gegangen ; идти\n'
                'Если русское слово стоит слева (как в Quizlet), столбцы '
                'поменяются местами сами. Из Quizlet: Экспорт → Копировать '
                'текст, затем вставьте сюда.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                minLines: 8,
                maxLines: 14,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'der Tisch ; стол\ndie Lampe ; лампа\ngehen ; идти',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _paste,
                    icon: const Icon(Icons.content_paste),
                    label: const Text('Вставить из буфера'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _controller.text.isEmpty
                        ? null
                        : () => setState(_controller.clear),
                    child: const Text('Очистить'),
                  ),
                ],
              ),
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
                onPressed: _controller.text.trim().isEmpty ? null : _parse,
                child: const Text('Разобрать'),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------- Просмотр результата ----------

  Widget _previewTile(BuildContext context, DraftWord d) {
    final theme = Theme.of(context);
    final extra = <String>[
      if (d.pluralLine != null) d.pluralLine!,
      if (d.verbFormsLine != null) d.verbFormsLine!,
    ];
    return Card(
      child: ListTile(
        title: Text(
          d.title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text([d.translations.join('; '), ...extra].join('\n')),
            for (final w in d.warnings)
              Text(
                '⚠ $w',
                style: TextStyle(color: theme.colorScheme.tertiary),
              ),
          ],
        ),
        trailing: Text(d.pos.label, style: theme.textTheme.bodySmall),
      ),
    );
  }

  Widget _previewView(BuildContext context, ImportParseResult parsed) {
    final theme = Theme.of(context);
    final summary = <String>[
      'Найдено слов: ${parsed.words.length}',
      if (_skippedExisting > 0) 'уже есть в наборе (пропустим): $_skippedExisting',
      if (parsed.duplicates > 0) 'повторы в списке (пропущены): ${parsed.duplicates}',
      if (parsed.errors.isNotEmpty) 'не удалось разобрать строк: ${parsed.errors.length}',
    ];
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(summary.join('\n'), style: theme.textTheme.bodyMedium),
              if (parsed.errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                for (final e in parsed.errors.take(10))
                  Text(
                    e,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                if (parsed.errors.length > 10)
                  Text('…и ещё ${parsed.errors.length - 10}'),
              ],
              const SizedBox(height: 12),
              if (_toAdd.isEmpty)
                const Text('Нет новых слов для добавления.')
              else
                for (final d in _toAdd) _previewTile(context, d),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => setState(() => _parsed = null),
                    child: const Text('Изменить текст'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: (_saving || _toAdd.isEmpty) ? null : _save,
                    child: Text(
                      _toAdd.isEmpty
                          ? 'Добавить'
                          : 'Добавить ${wordsCount(_toAdd.length)}',
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

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    return Scaffold(
      appBar: AppBar(title: const Text('Импорт слов')),
      body: parsed == null ? _inputView(context) : _previewView(context, parsed),
    );
  }
}

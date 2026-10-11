import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../db.dart';
import '../models.dart';
import '../importer.dart';
import 'import_screen.dart';
import 'study_screens.dart';
import 'word_edit_screen.dart';

class SetDetailScreen extends StatefulWidget {
  const SetDetailScreen({super.key, required this.set});

  final WordSet set;

  @override
  State<SetDetailScreen> createState() => _SetDetailScreenState();
}

class _SetDetailScreenState extends State<SetDetailScreen> {
  List<Word>? _words;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final words = await AppDb.instance.listWords(widget.set.id);
    if (!mounted) return;
    setState(() => _words = words);
  }

  Future<void> _openEditor([Word? word]) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => WordEditScreen(setId: widget.set.id, word: word),
      ),
    );
    await _load();
  }

  Future<void> _openImport() async {
    final added = await Navigator.push<int>(
      context,
      MaterialPageRoute<int>(
        builder: (_) => ImportScreen(setId: widget.set.id),
      ),
    );
    await _load();
    if (!mounted || added == null || added == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Добавлено: ${wordsCount(added)}')),
    );
  }

  Future<void> _export() async {
    final words = _words;
    if (words == null || words.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('В наборе пока нет слов')),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: exportWords(words)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Скопировано: ${wordsCount(words.length)}. '
          'Можно вставить в заметки, мессенджер или таблицу.',
        ),
      ),
    );
  }

  Future<void> _startStudy() async {
    final words = _words;
    if (words == null || words.isEmpty) return;
    final pool = await AppDb.instance.listAllWords();
    if (!mounted) return;
    await showStudySetup(context, words: words, pool: pool);
  }

  Future<bool> _confirmDelete(Word w) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить слово?'),
        content: Text(w.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final words = _words;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.set.name),
        actions: [
          if (words != null && words.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                onPressed: _startStudy,
                icon: const Icon(Icons.school_outlined),
                label: const Text('Учить'),
              ),
            ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'import') _openImport();
              if (v == 'export') _export();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'import', child: Text('Импорт списком')),
              PopupMenuItem(value: 'export', child: Text('Копировать набор')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Слово'),
      ),
      body: words == null
          ? const Center(child: CircularProgressIndicator())
          : words.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'В наборе пока нет слов.\nНажмите «Слово», чтобы добавить первое,\nили импортируйте списком через меню ⋮.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: words.length,
                  itemBuilder: (context, i) {
                    final w = words[i];
                    final extra = <String>[
                      if (w.pluralLine != null) w.pluralLine!,
                      if (w.verbFormsLine != null) w.verbFormsLine!,
                    ];
                    return Dismissible(
                      key: ValueKey(w.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => _confirmDelete(w),
                      onDismissed: (_) {
                        setState(() => _words!.removeWhere((x) => x.id == w.id));
                        AppDb.instance.deleteWord(w.id);
                      },
                      background: Container(
                        color: Theme.of(context).colorScheme.errorContainer,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        child: const Icon(Icons.delete_outline),
                      ),
                      child: ListTile(
                        title: Text(
                          w.title,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          [w.translations.join('; '), ...extra].join('\n'),
                        ),
                        isThreeLine: extra.isNotEmpty,
                        onTap: () => _openEditor(w),
                      ),
                    );
                  },
                ),
    );
  }
}

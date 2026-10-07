import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
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
      appBar: AppBar(title: Text(widget.set.name)),
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
                      'В наборе пока нет слов.\nНажмите «Слово», чтобы добавить первое.',
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

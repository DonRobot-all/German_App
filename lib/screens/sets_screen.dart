import 'dart:async';

import 'package:flutter/material.dart';

import '../db.dart';
import '../models.dart';
import '../reminders.dart';
import '../settings.dart';
import '../srs.dart';
import '../updater.dart';
import 'set_detail_screen.dart';
import 'settings_screen.dart';
import 'smart_screen.dart';
import 'stats_screen.dart';

class SetsScreen extends StatefulWidget {
  const SetsScreen({super.key});

  @override
  State<SetsScreen> createState() => _SetsScreenState();
}

class _SetsScreenState extends State<SetsScreen> with WidgetsBindingObserver {
  List<WordSet>? _sets;
  ReviewPlan? _plan;
  bool _soft = AppSettings.instance.softCheck; // false = строгая проверка
  UpdateInfo? _update;
  DateTime? _lastCheck;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    unawaited(_checkUpdate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// При возвращении в приложение проверяем обновления снова (не чаще раза в 2 минуты).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 2)) {
      return;
    }
    unawaited(_checkUpdate());
  }

  Future<void> _checkUpdate() async {
    _lastCheck = DateTime.now();
    final r = await checkForUpdate();
    if (!mounted || r.status != UpdateStatus.available) return;
    setState(() => _update = r.info);
  }

  Widget _updateCard(BuildContext context) {
    final u = _update;
    if (u == null) return const SizedBox.shrink();
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.system_update),
        title: Text('Доступна новая версия (сборка ${u.build})'),
        subtitle: const Text('Скачайте файл и нажмите «Установить».'),
        trailing: FilledButton(
          onPressed: () async {
            final ok = await openDownload(u);
            if (!ok && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Не удалось открыть ссылку')),
              );
            }
          },
          child: const Text('Обновить'),
        ),
      ),
    );
  }

  Future<void> _load() async {
    final sets = await AppDb.instance.listSets();
    final plan = await AppDb.instance.buildReviewPlan();
    if (!mounted) return;
    setState(() {
      _sets = sets;
      _plan = plan;
    });
    // Обновляем напоминания: учитываем, сколько слов ждёт и занимались ли сегодня.
    unawaited(refreshReminders());
  }

  Future<void> _openStats() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const StatsScreen()),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
    );
    if (!mounted) return;
    setState(() => _soft = AppSettings.instance.softCheck);
    await _load(); // размер сессии и «давно не писали» могли измениться
  }

  Future<void> _startSmart() async {
    // План пересобираем в момент нажатия: за время на экране сроки могли наступить.
    final plan = await AppDb.instance.buildReviewPlan();
    if (plan.items.isEmpty) {
      if (mounted) setState(() => _plan = plan);
      return;
    }
    final pool = await AppDb.instance.listAllWords();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            SmartSessionScreen(items: plan.items, pool: pool, soft: _soft),
      ),
    );
    await _load();
  }

  Widget _reviewCard(BuildContext context) {
    final plan = _plan;
    if (plan == null || plan.wordCount == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final toReview = plan.dueCount + plan.staleCount;

    final lines = <String>[
      'К повторению: $toReview',
      if (plan.staleCount > 0) 'из них давно не писали: ${plan.staleCount}',
      if (plan.newCount > 0) 'Новых слов: ${plan.newCount}',
    ];
    final String? waiting = (plan.items.isEmpty && plan.nextDue != null)
        ? 'Сейчас повторять нечего. Ближайшее повторение: '
            '${formatWhen(plan.nextDue!, DateTime.now())}'
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Умное повторение',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(lines.join('\n')),
            if (waiting != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(waiting),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Мягкая проверка письма'),
              value: _soft,
              onChanged: (v) => setState(() => _soft = v),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: plan.items.isEmpty ? null : _startSmart,
                icon: const Icon(Icons.bolt),
                label: Text('Повторить сейчас (${plan.items.length})'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editSet([WordSet? set]) async {
    final nameCtl = TextEditingController(text: set?.name ?? '');
    final descCtl = TextEditingController(text: set?.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(set == null ? 'Новый набор' : 'Изменить набор'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Название'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtl,
              textCapitalization: TextCapitalization.sentences,
              decoration:
                  const InputDecoration(labelText: 'Описание (необязательно)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtl.text.trim();
    final desc = descCtl.text.trim();
    if (set == null) {
      await AppDb.instance.createSet(name, desc);
    } else {
      await AppDb.instance.updateSet(set.id, name, desc);
    }
    await _load();
  }

  Future<void> _deleteSet(WordSet set) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить набор?'),
        content: Text('Набор «${set.name}» будет удалён.'),
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
    if (ok != true) return;
    await AppDb.instance.deleteSet(set.id);
    await _load();
  }

  Future<void> _open(WordSet set) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => SetDetailScreen(set: set)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sets = _sets;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Немецкие слова'),
        actions: [
          IconButton(
            tooltip: 'Статистика',
            icon: const Icon(Icons.bar_chart),
            onPressed: _openStats,
          ),
          IconButton(
            tooltip: 'Настройки',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editSet(),
        icon: const Icon(Icons.add),
        label: const Text('Набор'),
      ),
      body: sets == null
          ? const Center(child: CircularProgressIndicator())
          : sets.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Пока нет наборов.\nНажмите «Набор», чтобы создать первый.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: sets.length + 2,
                  itemBuilder: (context, i) {
                    if (i == 0) return _updateCard(context);
                    if (i == 1) return _reviewCard(context);
                    final s = sets[i - 2];
                    final sub = s.description.isEmpty
                        ? wordsCount(s.wordCount)
                        : '${s.description}\n${wordsCount(s.wordCount)}';
                    return Card(
                      child: ListTile(
                        title: Text(s.name),
                        subtitle: Text(sub),
                        isThreeLine: s.description.isNotEmpty,
                        onTap: () => _open(s),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            if (v == 'edit') _editSet(s);
                            if (v == 'delete') _deleteSet(s);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Изменить')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Удалить')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

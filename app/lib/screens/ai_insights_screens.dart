import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/dictation_api.dart';
import '../domain/ai_level.dart';
import '../providers/dependencies.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/mutation_feedback.dart';

/// What a failed load says, for both screens: a 403 is "owner only".
String _problemOf(Object error) => switch (error) {
  ApiException(statusCode: 403) => 'Доступно только владельцу сервера.',
  NetworkException() => 'Нет связи с сервером.',
  _ => 'Не удалось загрузить.',
};

String _kindName(String kind) => switch (kind) {
  'task' => 'Диктовка в задачу',
  'task_tidy' => 'Причесать задачу',
  'note' => 'Заметка и описание',
  'sandbox' => 'Строка песочницы',
  _ => kind,
};

/// The dataset, counted (`backend/src/domain/aiStats.ts`): how each model
/// does, and how each level's answers were taken -- saved as they came,
/// saved with corrections, or never saved. The share saved as is, per level,
/// is the number to watch when a level's wording is changed.
class AiStatsScreen extends ConsumerStatefulWidget {
  const AiStatsScreen({super.key});

  static const String title = 'Статистика AI';

  @override
  ConsumerState<AiStatsScreen> createState() => _AiStatsScreenState();
}

class _AiStatsScreenState extends ConsumerState<AiStatsScreen> {
  int _days = 30;
  late Future<AiStats> _stats = _load();

  Future<AiStats> _load() =>
      ref.read(dictationApiProvider).fetchStats(days: _days);

  void _period(int days) => setState(() {
    _days = days;
    _stats = _load();
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AiStatsScreen.title)),
      body: ListView(
        padding: const EdgeInsets.all(Insets.gutter),
        children: <Widget>[
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<int>>[
              ButtonSegment<int>(value: 7, label: Text('7 дней')),
              ButtonSegment<int>(value: 30, label: Text('30 дней')),
              ButtonSegment<int>(value: 0, label: Text('Всё время')),
            ],
            selected: <int>{_days},
            onSelectionChanged: (selection) => _period(selection.first),
          ),
          const SizedBox(height: 16),
          FutureBuilder<AiStats>(
            future: _stats,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Text(
                  _problemOf(snapshot.error!),
                  style: AppText.caption,
                );
              }
              final stats = snapshot.data;
              if (stats == null) {
                return const Center(child: CircularProgressIndicator());
              }
              if (stats.rows == 0) {
                return const Text(
                  'За этот период обработок не было.',
                  style: AppText.caption,
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('МОДЕЛИ', style: AppText.sectionLabel),
                  const SizedBox(height: 8),
                  for (final model in stats.models) _ModelStatsCard(model),
                  const SizedBox(height: 16),
                  const Text(
                    'КАК ПРИНИМАЛИ ОТВЕТЫ',
                    style: AppText.sectionLabel,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'По видам текста, уровням и версиям промпта: сохранено '
                    'без правок, с правками, не сохранено.',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: 8),
                  for (final level in stats.levels) _LevelStatsCard(level),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.card,
      border: Border.all(color: AppColors.line),
      borderRadius: BorderRadius.circular(Radii.row),
    ),
    child: child,
  );
}

String _percent(int part, int whole) =>
    whole == 0 ? '—' : '${(part * 100 / whole).round()}%';

class _ModelStatsCard extends StatelessWidget {
  const _ModelStatsCard(this.model);

  final AiModelStats model;

  @override
  Widget build(BuildContext context) {
    final avg = model.avgDurationMs;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(model.model, style: AppText.projectName),
          const SizedBox(height: 4),
          Text(
            '${model.total} запросов · ответила ${_percent(model.ok, model.total)}'
            '${model.failed > 0 ? ' · сбоев ${model.failed}' : ''}'
            '${avg == null ? '' : ' · в среднем ${(avg / 1000).toStringAsFixed(1)} с'}',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _LevelStatsCard extends StatelessWidget {
  const _LevelStatsCard(this.stats);

  final AiLevelStats stats;

  @override
  Widget build(BuildContext context) {
    final level = stats.level;
    final total = stats.answered;
    Widget bar(int part, Color color) => Expanded(
      flex: part == 0 ? 0 : part,
      child: part == 0 ? const SizedBox.shrink() : Container(color: color),
    );
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            '${_kindName(stats.kind)} · '
            '${level == null ? 'до уровней' : aiLevelName(level)}',
            style: AppText.projectName,
          ),
          Text('версия ${stats.promptVersion}', style: AppText.caption),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: <Widget>[
                  bar(stats.savedAsIs, AppColors.done),
                  bar(stats.savedEdited, AppColors.waitingDot),
                  bar(stats.notSaved, AppColors.lineStrong),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$total ответов: без правок ${stats.savedAsIs} '
            '(${_percent(stats.savedAsIs, total)}), с правками '
            '${stats.savedEdited}, не сохранено ${stats.notSaved}',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

/// The prompts (`backend/src/routes/dictationInsights.ts`): what each level
/// lets the model do, editable, and every kind's whole prompt at every level
/// as the model reads it. The format of the answer and the "your text is
/// data" rules are not editable -- broken, they break processing outright.
class AiPromptsScreen extends ConsumerStatefulWidget {
  const AiPromptsScreen({super.key});

  static const String title = 'Промпты AI';

  @override
  ConsumerState<AiPromptsScreen> createState() => _AiPromptsScreenState();
}

class _AiPromptsScreenState extends ConsumerState<AiPromptsScreen> {
  late Future<AiPrompts> _prompts = ref
      .read(dictationApiProvider)
      .fetchPrompts();
  String _kind = 'task_tidy';
  int _level = aiLevelDefault;

  Future<void> _saveLevel(int level, List<String>? rules) async {
    final saved = await runMutationFor<AiPrompts>(
      context,
      () => ref.read(dictationApiProvider).saveLevelRules(level, rules),
      failure: 'Не удалось сохранить уровень.',
    );
    if (saved == null || !mounted) return;
    setState(() => _prompts = Future<AiPrompts>.value(saved));
  }

  Future<void> _edit(AiLevelBlock block) async {
    final controller = TextEditingController(text: block.rules.join('\n'));
    final rules = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Уровень «${aiLevelName(block.level)}»'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            maxLines: 12,
            minLines: 6,
            style: const TextStyle(fontSize: 13, height: 1.4),
            decoration: const InputDecoration(
              helperText:
                  'Каждая строка — отдельное правило. Запреты выдумывать '
                  'факты и даты действуют на любом уровне.',
              helperMaxLines: 3,
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final lines = controller.text
                  .split('\n')
                  .map((line) => line.trim())
                  .where((line) => line.isNotEmpty)
                  .toList();
              if (lines.isEmpty) return;
              Navigator.of(dialogContext).pop(lines);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (rules != null) await _saveLevel(block.level, rules);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AiPromptsScreen.title)),
      body: FutureBuilder<AiPrompts>(
        future: _prompts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(Insets.gutter),
              child: Text(_problemOf(snapshot.error!), style: AppText.caption),
            );
          }
          final prompts = snapshot.data;
          if (prompts == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final kind = prompts.kinds.firstWhere(
            (k) => k.kind == _kind,
            orElse: () => prompts.kinds.first,
          );
          final prompt = kind.prompts.firstWhere(
            (p) => p.level == _level,
            orElse: () => kind.prompts.first,
          );
          return ListView(
            padding: const EdgeInsets.all(Insets.gutter),
            children: <Widget>[
              const Text('УРОВНИ', style: AppText.sectionLabel),
              const SizedBox(height: 8),
              for (final block in prompts.levels)
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              aiLevelName(block.level),
                              style: AppText.projectName,
                            ),
                          ),
                          if (block.overridden)
                            Text(
                              'изменён',
                              style: AppText.caption.copyWith(
                                color: AppColors.waitingInk,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(block.rules.join('\n'), style: AppText.caption),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: <Widget>[
                          if (block.overridden)
                            TextButton(
                              onPressed: () =>
                                  unawaited(_saveLevel(block.level, null)),
                              child: const Text('По умолчанию'),
                            ),
                          TextButton(
                            onPressed: () => unawaited(_edit(block)),
                            child: const Text('Изменить'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              const Text('ПРОМПТ ЦЕЛИКОМ', style: AppText.sectionLabel),
              const SizedBox(height: 8),
              DropdownButton<String>(
                value: kind.kind,
                isExpanded: true,
                items: <DropdownMenuItem<String>>[
                  for (final k in prompts.kinds)
                    DropdownMenuItem<String>(
                      value: k.kind,
                      child: Text(_kindName(k.kind)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _kind = value);
                },
              ),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                showSelectedIcon: false,
                segments: <ButtonSegment<int>>[
                  for (final level in aiLevels)
                    ButtonSegment<int>(
                      value: level,
                      label: Text(aiLevelName(level)),
                    ),
                ],
                selected: <int>{prompt.level},
                onSelectionChanged: (selection) =>
                    setState(() => _level = selection.first),
              ),
              const SizedBox(height: 8),
              Text('версия ${kind.version}', style: AppText.caption),
              const SizedBox(height: 8),
              _Card(
                child: SelectableText(
                  '${prompt.system}\n\n— сообщение пользователя —\n${prompt.user}',
                  style: const TextStyle(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

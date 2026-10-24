import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/outbox_overlay.dart';
import '../models/task_status.dart';
import '../providers/board_providers.dart';
import '../providers/outbox_providers.dart';
import '../storage/outbox_store.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'history_charts.dart' show HistoryHeading;
import 'mutation_feedback.dart';
import 'task_list.dart' show taskStatusLabel;

/// «Офлайн» in the history mode: what this device wrote with no network and
/// what became of it (the outbox, `outbox_providers.dart`).
///
/// Three groups, in the order they ask for attention: what still waits for a
/// network, what waits for a decision (an edit skipped because the field was
/// changed elsewhere, or one the server refused), and a week of what went --
/// green, so that "did it go?" has an answer to look at rather than a worry.
class OutboxHistoryView extends ConsumerWidget {
  const OutboxHistoryView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(outboxEntriesProvider).reversed.toList();
    final names = _projectNames(ref.watch(boardViewProvider));

    final waiting = entries.where((e) => e.isWaiting).toList();
    final decisions = entries.where((e) => e.needsDecision).toList();
    final settled = entries
        .where(
          (e) => e.state == OutboxState.sent || e.state == OutboxState.resolved,
        )
        .toList();

    OutboxEntryCard card(OutboxEntry entry) =>
        OutboxEntryCard(entry: entry, projectName: names[entry.projectId]);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 4, Insets.gutter, 24),
      children: <Widget>[
        if (entries.isEmpty)
          const _Quiet()
        else ...<Widget>[
          if (waiting.isNotEmpty) ...<Widget>[
            _Section(
              'Ждут связи · ${waiting.length}',
              action: TextButton.icon(
                onPressed: () => ref.read(outboxProvider.notifier).flush(),
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('Отправить сейчас'),
              ),
            ),
            for (final entry in waiting) card(entry),
          ],
          if (decisions.isNotEmpty) ...<Widget>[
            _Section('Требует решения · ${decisions.length}'),
            for (final entry in decisions) card(entry),
          ],
          if (settled.isNotEmpty) ...<Widget>[
            _Section('Отправлено · ${settled.length}'),
            for (final entry in settled) card(entry),
          ],
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              'история хранится на этом устройстве 7 дней',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
          ),
        ],
      ],
    );
  }

  static Map<String, String> _projectNames(BoardView view) => <String, String>{
    if (view is BoardReady)
      for (final row in view.projects) row.project.id: row.project.name,
  };
}

/// One entry: a line of history, or a question when it needs a decision.
class OutboxEntryCard extends ConsumerStatefulWidget {
  const OutboxEntryCard({required this.entry, this.projectName, super.key});

  final OutboxEntry entry;
  final String? projectName;

  @override
  ConsumerState<OutboxEntryCard> createState() => _OutboxEntryCardState();
}

class _OutboxEntryCardState extends ConsumerState<OutboxEntryCard> {
  /// A skipped edit opens to show both values. Closed by default: the list
  /// should read as a list first.
  bool _open = false;
  bool _confirmDiscard = false;

  OutboxEntry get entry => widget.entry;

  @override
  Widget build(BuildContext context) {
    final (icon, ink, fill, line, label) = switch (entry.state) {
      OutboxState.waiting => (
        Icons.cloud_upload_outlined,
        AppColors.muted,
        AppColors.background,
        AppColors.lineStrong,
        'ждёт связи',
      ),
      OutboxState.sent => (
        Icons.cloud_done_outlined,
        AppColors.done,
        AppColors.card,
        AppColors.line,
        'отправлено',
      ),
      OutboxState.skipped => (
        Icons.fast_forward_outlined,
        AppColors.waitingInk,
        AppColors.waitingFill,
        AppColors.waitingLine,
        'пропущено — изменено на другом устройстве',
      ),
      OutboxState.refused => (
        Icons.error_outline,
        AppColors.alarm,
        AppColors.card,
        AppColors.alarm.withValues(alpha: 0.3),
        'сервер не принял',
      ),
      OutboxState.resolved => (
        Icons.check,
        AppColors.muted,
        AppColors.card,
        AppColors.line,
        'оставлено как на сервере',
      ),
    };

    final at = entry.settledAt ?? entry.createdAt;
    final where = widget.projectName;
    final change = _changeLine(entry);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.card),
        onTap: entry.state == OutboxState.skipped
            ? () => setState(() => _open = !_open)
            : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 20, color: ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            <String>[_kindLabel(entry), ?where].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.chip.copyWith(color: ink),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _time(at),
                          style: AppText.chip.copyWith(color: AppColors.muted),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(entry.title, style: AppText.body),
                    if (change != null) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        change,
                        style: AppText.caption.copyWith(
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ],
                    if (entry.state != OutboxState.sent) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        entry.state == OutboxState.refused &&
                                entry.message != null
                            ? '$label: ${entry.message}'
                            : label,
                        style: AppText.caption.copyWith(color: ink),
                      ),
                    ],
                    if (entry.state == OutboxState.skipped && _open)
                      _conflict(),
                    if (entry.state == OutboxState.refused) _refusedActions(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _conflict() {
    final mine = _mineText(entry);
    final server = entry.serverTask == null
        ? null
        : _valuesText(entry, jsonWireValues(entry.serverTask!));

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _Value(
            label: 'Моё · с этого устройства',
            text: mine,
            fill: AppColors.waitingFill,
            line: AppColors.waitingLine,
          ),
          if (server != null) ...<Widget>[
            const SizedBox(height: 8),
            _Value(
              label: 'На сервере · действует',
              text: server,
              fill: AppColors.card,
              line: AppColors.lineStrong,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => runMutation(
                  context,
                  () => ref.read(outboxProvider.notifier).applyMine(entry),
                  failure: 'Не удалось сохранить на устройстве.',
                ),
                icon: const Icon(Icons.cloud_upload_outlined, size: 17),
                label: const Text('Применить моё'),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: mine));
                  if (!mounted) return;
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      const SnackBar(content: Text('Скопировано.')),
                    );
                },
                icon: const Icon(Icons.copy, size: 17),
                label: const Text('Скопировать'),
              ),
              TextButton(
                onPressed: () => runMutation(
                  context,
                  () => ref.read(outboxProvider.notifier).keepServer(entry),
                  failure: 'Не удалось сохранить на устройстве.',
                ),
                child: const Text('Оставить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _refusedActions() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: _confirmDiscard
            ? <Widget>[
                Text('Выбросить правку?', style: AppText.caption),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.alarm,
                  ),
                  onPressed: () => runMutation(
                    context,
                    () => ref.read(outboxProvider.notifier).discard(entry),
                    failure: 'Не удалось сохранить на устройстве.',
                  ),
                  child: const Text('Выбросить'),
                ),
                TextButton(
                  onPressed: () => setState(() => _confirmDiscard = false),
                  child: const Text('Нет'),
                ),
              ]
            : <Widget>[
                OutlinedButton.icon(
                  onPressed: () => runMutation(
                    context,
                    () => ref.read(outboxProvider.notifier).retry(entry),
                    failure: 'Не удалось сохранить на устройстве.',
                  ),
                  icon: const Icon(Icons.sync, size: 16),
                  label: const Text('Ещё раз'),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: AppColors.alarm),
                  onPressed: () => setState(() => _confirmDiscard = true),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('Выбросить'),
                ),
              ],
      ),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value({
    required this.label,
    required this.text,
    required this.fill,
    required this.line,
  });

  final String label;
  final String text;
  final Color fill;
  final Color line;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: AppText.chip.copyWith(color: AppColors.muted)),
          const SizedBox(height: 4),
          Text(text, style: AppText.body),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.label, {this.action});

  final String label;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 2),
      child: HistoryHeading(label: label, trailing: action),
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 48, 8, 0),
      child: Column(
        children: <Widget>[
          const Icon(
            Icons.cloud_done_outlined,
            size: 32,
            color: AppColors.done,
          ),
          const SizedBox(height: 12),
          Text('Всё отправлено', style: AppText.projectName),
          const SizedBox(height: 6),
          Text(
            'Задачи и правки, сделанные без сети, ждут здесь и уходят на '
            'сервер, когда связь появляется: при запуске, при возвращении в '
            'приложение и раз в полминуты.',
            textAlign: TextAlign.center,
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

// --- wording ----------------------------------------------------------------

const Map<String, String> _fieldLabel = <String, String>{
  'title': 'Название',
  'description': 'Описание',
  'categoryId': 'Категория',
  'status': 'Статус',
  'remindAt': 'Напоминание',
  'remindTime': 'Напоминание',
};

String _kindLabel(OutboxEntry entry) {
  if (entry.kind == OutboxKind.createTask) return 'Новая задача';
  final fields = <String>{for (final key in entry.body.keys) ?_fieldLabel[key]};
  return fields.isEmpty ? 'Правка' : fields.join(', ');
}

/// "Открыта → Сделано" for a status, the new text for a text field.
String? _changeLine(OutboxEntry entry) {
  if (entry.kind == OutboxKind.createTask) return null;
  final body = entry.body;
  if (body.containsKey('status')) {
    String name(Object? value) => value is String
        ? taskStatusLabel[TaskStatus.values.byName(value)] ?? value
        : '—';
    final was = entry.expected['status'];
    return was == null
        ? name(body['status'])
        : '${name(was)} → ${name(body['status'])}';
  }
  if (body.containsKey('title') && !body.containsKey('description')) {
    return null; // the title line above already is the change
  }
  return _mineText(entry);
}

/// What this device wanted, as text.
String _mineText(OutboxEntry entry) => _valuesText(entry, <String, Object?>{
  for (final field in outboxTaskFields)
    if (entry.body.containsKey(field)) field: entry.body[field],
});

/// [values] of the fields [entry] changes, one per line.
String _valuesText(OutboxEntry entry, Map<String, Object?> values) {
  final lines = <String>[
    for (final field in outboxTaskFields)
      if (entry.body.containsKey(field))
        switch (field) {
          'status' =>
            values[field] is String
                ? taskStatusLabel[TaskStatus.values.byName(
                        values[field]! as String,
                      )] ??
                      ''
                : '',
          'categoryId' => values[field] == null ? 'без категории' : 'другая',
          _ => (values[field] as String?) ?? '—',
        },
  ];
  return lines.where((line) => line.isNotEmpty).join('\n');
}

String _time(DateTime at) {
  final local = at.toLocal();
  final now = DateTime.now();
  final hm =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) return hm;
  return '${local.day.toString().padLeft(2, '0')}.'
      '${local.month.toString().padLeft(2, '0')} $hm';
}

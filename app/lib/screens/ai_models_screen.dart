import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../api/dictation_api.dart';
import '../providers/dictation_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/mutation_feedback.dart';

/// The server's list of preferred models (`backend/src/domain/modelRoster.ts`):
/// their order, which are on, how each has been doing, and a way back for one
/// its failures switched off.
///
/// Every change is saved at once, as the whole list -- the order is the
/// point of it, and a half-saved order means nothing. Only the owner may
/// change it; anyone else sees it read-only, and a 403 says why.
class AiModelsScreen extends ConsumerWidget {
  const AiModelsScreen({super.key});

  static const String title = 'Модели AI';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final models = ref.watch(aiModelsSettingProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(title),
        actions: <Widget>[
          if (models case AsyncData(:final value))
            IconButton(
              tooltip: 'Добавить модель',
              onPressed: () => unawaited(_add(context, ref, value)),
              icon: const Icon(Icons.add),
            ),
        ],
      ),
      body: switch (models) {
        AsyncData(:final value) => _list(context, ref, value),
        AsyncError(:final error) => Padding(
          padding: const EdgeInsets.all(Insets.gutter),
          child: Text(switch (error) {
            NetworkException() => 'Нет связи с сервером.',
            ApiException(statusCode: 503) =>
              'Разбор не настроен на сервере: нет ключа модели в .env.',
            _ => 'Не удалось получить список моделей.',
          }, style: AppText.caption),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  Widget _list(BuildContext context, WidgetRef ref, AiModels value) {
    final models = value.models;
    return ListView(
      padding: const EdgeInsets.all(Insets.gutter),
      children: <Widget>[
        Text(
          models.isEmpty
              ? 'Список пуст — работает модель сервера: '
                    '${value.fallbackModel ?? 'не задана'}. Добавьте модели, '
                    'чтобы задать порядок и запасные.'
              : 'Сначала спрашивается модель, ответившая последней; если '
                    'верхняя недавно сбоила — она и последняя ответившая '
                    'вместе. Три неудачи подряд — модель пропускается на час, '
                    'шесть за неделю — отключается до ручного включения.',
          style: AppText.caption,
        ),
        const SizedBox(height: 12),
        for (final (index, model) in models.indexed) ...<Widget>[
          _ModelRow(
            index: index,
            model: model,
            isFirst: index == 0,
            isLast: index == models.length - 1,
            onMove: (delta) =>
                _save(context, ref, _moved(models, index, delta)),
            onToggle: (on) => _save(context, ref, <AiModelEntry>[
              for (final (i, m) in models.indexed)
                i == index
                    ? m.edited(
                        name: m.name,
                        label: m.label,
                        baseUrl: m.baseUrl,
                        apiKeyEnv: m.apiKeyEnv,
                        enabled: on,
                      )
                    : m,
            ]),
            onEdit: () => unawaited(_edit(context, ref, models, index)),
            onReenable: model.id == null
                ? null
                : () => runMutation(
                    context,
                    () => ref
                        .read(aiModelsSettingProvider.notifier)
                        .reenable(model.id!),
                    failure: 'Не удалось включить модель.',
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  static List<AiModelEntry> _moved(
    List<AiModelEntry> models,
    int index,
    int delta,
  ) {
    final list = <AiModelEntry>[...models];
    final item = list.removeAt(index);
    list.insert((index + delta).clamp(0, list.length), item);
    return list;
  }

  Future<void> _save(
    BuildContext context,
    WidgetRef ref,
    List<AiModelEntry> models,
  ) => runMutation(
    context,
    () => ref.read(aiModelsSettingProvider.notifier).save(models),
    failure: 'Не удалось сохранить список моделей.',
  );

  Future<void> _add(BuildContext context, WidgetRef ref, AiModels value) async {
    final added = await showDialog<_ModelEdit>(
      context: context,
      builder: (_) => const _ModelDialog(),
    );
    if (added == null || added.delete || !context.mounted) return;
    await _save(context, ref, <AiModelEntry>[
      ...value.models,
      AiModelEntry(
        id: null,
        name: added.name,
        label: added.label,
        enabled: true,
        status: 'ok',
        baseUrl: added.baseUrl,
        apiKeyEnv: added.apiKeyEnv,
      ),
    ]);
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    List<AiModelEntry> models,
    int index,
  ) async {
    final edit = await showDialog<_ModelEdit>(
      context: context,
      builder: (_) => _ModelDialog(current: models[index]),
    );
    if (edit == null || !context.mounted) return;
    final list = <AiModelEntry>[...models];
    if (edit.delete) {
      list.removeAt(index);
    } else {
      list[index] = models[index].edited(
        name: edit.name,
        label: edit.label,
        baseUrl: edit.baseUrl,
        apiKeyEnv: edit.apiKeyEnv,
      );
    }
    await _save(context, ref, list);
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.index,
    required this.model,
    required this.isFirst,
    required this.isLast,
    required this.onMove,
    required this.onToggle,
    required this.onEdit,
    required this.onReenable,
  });

  final int index;
  final AiModelEntry model;
  final bool isFirst;
  final bool isLast;
  final ValueChanged<int> onMove;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback? onReenable;

  @override
  Widget build(BuildContext context) {
    final (statusText, statusColor) = switch (model.status) {
      'auto_disabled' => (
        'Отключена автоматически: ${model.autoDisabledReason ?? 'неудачи подряд'}',
        AppColors.alarm,
      ),
      'cooling_down' => (
        'Пропускается: ${model.consecutiveFailures} неудачи подряд',
        AppColors.waitingInk,
      ),
      'disabled' => ('Выключена', AppColors.muted),
      _ when model.consecutiveFailures > 0 => (
        'Работает, неудач подряд: ${model.consecutiveFailures}',
        AppColors.waitingInk,
      ),
      _ => ('Работает', AppColors.done),
    };
    final provider = <String>[
      model.name,
      if (model.baseUrl != null)
        Uri.tryParse(model.baseUrl!)?.host ?? model.baseUrl!,
      if (model.apiKeyEnv != null)
        model.keyPresent == false
            ? '${model.apiKeyEnv} — не задан на сервере'
            : model.apiKeyEnv!,
    ].join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('${index + 1}', style: AppText.numberSmall),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: onEdit,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(model.title, style: AppText.projectName),
                      const SizedBox(height: 2),
                      Text(provider, style: AppText.caption),
                      const SizedBox(height: 2),
                      Text(
                        statusText,
                        style: AppText.caption.copyWith(color: statusColor),
                      ),
                    ],
                  ),
                ),
              ),
              Switch(
                value: model.enabled,
                onChanged: model.status == 'auto_disabled' ? null : onToggle,
              ),
            ],
          ),
          Row(
            children: <Widget>[
              if (model.status == 'auto_disabled' && onReenable != null)
                TextButton.icon(
                  onPressed: onReenable,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Включить снова'),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Выше',
                onPressed: isFirst ? null : () => onMove(-1),
                icon: const Icon(Icons.arrow_upward, size: 20),
              ),
              IconButton(
                tooltip: 'Ниже',
                onPressed: isLast ? null : () => onMove(1),
                icon: const Icon(Icons.arrow_downward, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// What the dialog closed with: the fields, or "delete this one".
class _ModelEdit {
  const _ModelEdit({
    required this.name,
    this.label,
    this.baseUrl,
    this.apiKeyEnv,
    this.delete = false,
  });

  const _ModelEdit.delete() : this(name: '', delete: true);

  final String name;
  final String? label;
  final String? baseUrl;
  final String? apiKeyEnv;
  final bool delete;
}

class _ModelDialog extends StatefulWidget {
  const _ModelDialog({this.current});

  final AiModelEntry? current;

  @override
  State<_ModelDialog> createState() => _ModelDialogState();
}

class _ModelDialogState extends State<_ModelDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.current?.name ?? '',
  );
  late final TextEditingController _label = TextEditingController(
    text: widget.current?.label ?? '',
  );
  late final TextEditingController _baseUrl = TextEditingController(
    text: widget.current?.baseUrl ?? '',
  );
  late final TextEditingController _apiKeyEnv = TextEditingController(
    text: widget.current?.apiKeyEnv ?? '',
  );

  static final RegExp _envName = RegExp(r'^LLM_[A-Z0-9_]{1,60}$');

  @override
  void dispose() {
    _name.dispose();
    _label.dispose();
    _baseUrl.dispose();
    _apiKeyEnv.dispose();
    super.dispose();
  }

  String? get _envError {
    final value = _apiKeyEnv.text.trim();
    if (value.isEmpty || _envName.hasMatch(value)) return null;
    return 'Имя переменной из .env, начинается с LLM_';
  }

  String? get _urlError {
    final value = _baseUrl.text.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http')
        ? null
        : 'Адрес вида https://…/v1';
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && _envError == null && _urlError == null;

  String? _orNull(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.current == null ? 'Новая модель' : 'Модель'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: _name,
              autofocus: widget.current == null,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Модель у провайдера',
                hintText: 'deepseek-chat',
              ),
            ),
            TextField(
              controller: _label,
              decoration: const InputDecoration(
                labelText: 'Как называть в приложении',
                hintText: 'необязательно',
              ),
            ),
            TextField(
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Адрес провайдера',
                hintText: 'пусто — LLM_BASE_URL',
                errorText: _urlError,
              ),
            ),
            TextField(
              controller: _apiKeyEnv,
              textCapitalization: TextCapitalization.characters,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Переменная с ключом',
                hintText: 'пусто — LLM_API_KEY',
                helperText: 'Сам ключ хранится в .env на сервере.',
                errorText: _envError,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        if (widget.current != null)
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(const _ModelEdit.delete()),
            child: const Text('Удалить'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _valid
              ? () => Navigator.of(context).pop(
                  _ModelEdit(
                    name: _name.text.trim(),
                    label: _orNull(_label),
                    baseUrl: _orNull(_baseUrl),
                    apiKeyEnv: _orNull(_apiKeyEnv),
                  ),
                )
              : null,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

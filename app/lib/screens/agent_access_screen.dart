import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/agent_token_api.dart';
import '../api/api_exception.dart';
import '../providers/dependencies.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/mutation_feedback.dart';

/// `/agent-tokens` for this screen. Hand-written rather than generated: it is
/// used here and nowhere else.
final agentTokenApiProvider = Provider<AgentTokenApi>(
  (ref) => AgentTokenApi(ref.watch(apiClientProvider)),
);

/// The live tokens, re-read after every create and revoke.
final agentTokensProvider = FutureProvider.autoDispose<List<AgentToken>>(
  (ref) => ref.watch(agentTokenApiProvider).list(),
);

/// The address agents connect to: the API's own origin and `/mcp`. On the web
/// build the API is the page's origin, so an empty base means that.
String mcpUrlFor(String baseUrl) {
  var base = baseUrl.trim();
  if (base.isEmpty) base = Uri.base.origin;
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  return '$base/mcp';
}

/// The command that connects Claude Code, ready to paste.
String claudeMcpAddCommand(String mcpUrl, String token) =>
    'claude mcp add --transport http taskradar $mcpUrl '
    '--header "Authorization: Bearer $token"';

/// «Доступ для агентов (MCP)»: personal tokens for coding agents.
///
/// What a token opens is the MCP endpoint and nothing else
/// (`backend/src/lib/agentTokens.ts`): an agent can read projects, tasks,
/// notes and the inbox, change a task's status and text, and add tasks --
/// never delete anything. The plain token is shown once, right after it is
/// made, with the command to paste; the list afterwards shows only its first
/// characters.
class AgentAccessScreen extends ConsumerWidget {
  const AgentAccessScreen({super.key});

  static const String title = 'Доступ для агентов (MCP)';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = ref.watch(agentTokensProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(_create(context, ref)),
        icon: const Icon(Icons.add),
        label: const Text('Создать токен'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              12,
              Insets.gutter,
              96,
            ),
            children: <Widget>[
              const Text(
                'Токен даёт агенту (Claude Code и другим) доступ к TaskRadar '
                'по протоколу MCP: читать проекты, задачи, заметки и '
                'песочницу, менять статус и текст задач, добавлять задачи. '
                'Удалять агент ничего не может. Токен показывается один раз — '
                'сразу после создания.',
                style: AppText.caption,
              ),
              const SizedBox(height: 16),
              ...switch (tokens) {
                AsyncData(:final value) when value.isEmpty => <Widget>[
                  const Text('Токенов пока нет.', style: AppText.body),
                ],
                AsyncData(:final value) => <Widget>[
                  for (final token in value) ...<Widget>[
                    _TokenRow(
                      token: token,
                      onRevoke: () => unawaited(_revoke(context, ref, token)),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
                AsyncError(:final error) => <Widget>[
                  Text(switch (error) {
                    NetworkException() => 'Нет связи с сервером.',
                    _ => 'Не удалось получить список токенов.',
                  }, style: AppText.caption.copyWith(color: AppColors.alarm)),
                ],
                _ => <Widget>[const Center(child: CircularProgressIndicator())],
              },
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NameDialog(),
    );
    if (name == null || !context.mounted) return;
    final created = await runMutationFor(
      context,
      () => ref.read(agentTokenApiProvider).create(name: name),
      failure: 'Не удалось создать токен.',
    );
    ref.invalidate(agentTokensProvider);
    if (created == null || !context.mounted) return;
    final url = mcpUrlFor(ref.read(apiClientProvider).dio.options.baseUrl);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CreatedDialog(token: created.token, mcpUrl: url),
    );
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    AgentToken token,
  ) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отозвать токен?'),
        content: Text(
          'Агенты с токеном «${_label(token)}» сразу потеряют доступ. '
          'Вернуть его нельзя — только создать новый.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.alarm),
            child: const Text('Отозвать'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await runMutation(
      context,
      () => ref.read(agentTokenApiProvider).revoke(token.id),
      failure: 'Не удалось отозвать токен.',
    );
    ref.invalidate(agentTokensProvider);
  }
}

String _label(AgentToken token) {
  final name = token.name;
  return name == null || name.isEmpty ? 'без названия' : name;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _when(DateTime at) {
  final local = at.toLocal();
  return '${_two(local.day)}.${_two(local.month)}.${local.year} '
      '${_two(local.hour)}:${_two(local.minute)}';
}

class _TokenRow extends StatelessWidget {
  const _TokenRow({required this.token, required this.onRevoke});

  final AgentToken token;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final used = token.lastUsedAt;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: Row(
          children: <Widget>[
            const Icon(Icons.key_outlined, color: AppColors.muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(_label(token), style: AppText.body),
                  const SizedBox(height: 2),
                  Text(
                    '${token.prefix}… · создан ${_when(token.createdAt)}\n'
                    '${used == null ? 'ещё не использовался' : 'использован ${_when(used)}'}',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Отозвать',
              onPressed: onRevoke,
              icon: const Icon(Icons.block, color: AppColors.alarm),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks for an optional name. Pops the name ('' for none), or null on cancel.
class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый токен'),
      content: TextField(
        controller: _name,
        autofocus: true,
        maxLength: 60,
        decoration: const InputDecoration(
          labelText: 'Название (необязательно)',
          hintText: 'Например, «ноутбук»',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_name.text),
          child: const Text('Создать'),
        ),
      ],
    );
  }
}

/// The token, once, with the command to paste.
class _CreatedDialog extends StatelessWidget {
  const _CreatedDialog({required this.token, required this.mcpUrl});

  final String token;
  final String mcpUrl;

  @override
  Widget build(BuildContext context) {
    final command = claudeMcpAddCommand(mcpUrl, token);
    return AlertDialog(
      title: const Text('Токен создан'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Скопируйте его сейчас: больше он нигде не появится.',
              style: AppText.caption.copyWith(color: AppColors.alarm),
            ),
            const SizedBox(height: 12),
            _CopyBlock(
              label: 'Токен',
              value: token,
              copyLabel: 'Скопировать токен',
              copied: 'Токен скопирован',
            ),
            const SizedBox(height: 12),
            _CopyBlock(
              label: 'Команда для Claude Code',
              value: command,
              copyLabel: 'Скопировать команду',
              copied: 'Команда скопирована',
            ),
          ],
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}

class _CopyBlock extends StatelessWidget {
  const _CopyBlock({
    required this.label,
    required this.value,
    required this.copyLabel,
    required this.copied,
  });

  final String label;
  final String value;
  final String copyLabel;
  final String copied;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: AppText.caption),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: value));
              messenger
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text(copied)));
            },
            icon: const Icon(Icons.copy, size: 18),
            label: Text(copyLabel),
          ),
        ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_error_message.dart';
import '../domain/project_badge.dart';
import '../domain/task_age.dart';
import '../models/board_project.dart';
import '../models/inbox_item.dart';
import '../navigation/app_routes.dart';
import '../providers/archive_providers.dart';
import '../providers/board_providers.dart';
import '../providers/capture_queue_providers.dart';
import '../providers/inbox_providers.dart';
import '../providers/scope_providers.dart';
import '../storage/capture_queue_store.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/glance.dart';
import '../widgets/mode_navigation.dart';
import '../widgets/mutation_feedback.dart';
import '../widgets/project_name_dialog.dart';
import 'dictation_screen.dart';

/// The sandbox (F8, redrawn in F12): write it down now, sort it later.
///
/// ## What F12 changed, and why
///
/// The old screen was a one-line composer nailed to the top and a `ListTile`
/// per waiting line, each with a `PopupMenuButton` offering four actions. That
/// is two of the three complaints in one screen: the field showed two or three
/// words of a dictated sentence, and filing a line cost a menu, a dialog, a
/// scroll through every project and a tap -- four decisions to answer "куда
/// это".
///
/// Now:
///
/// - **The line being worked on is a text area, open and editable**, 19 px and
///   104 px tall. Correcting a misheard word is typing, not "Поправить текст…"
///   in a menu.
/// - **The projects are buttons under it.** One tap and the line is a task.
///   That is the whole screen: the pile is worked by reading a line and
///   pressing a name.
/// - **There is no composer.** Capture is the microphone, which lives in the
///   same corner as everywhere else, and typing a new line is the same field
///   the line above it uses.
///
/// ## What has not changed
///
/// Everything about the queue (F8.1). Lines captured with no signal live on
/// this device's disk, they are listed here with a mark saying so, and the one
/// thing they cannot do is be filed -- filing puts a task at a position in a
/// list another device may have changed, which is the conflict resolution the
/// product still defers.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  static const String title = 'Песочница';

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  /// Which line is open for editing. Null means "the oldest one", which is the
  /// right default: the pile is worked oldest first, because the line at risk
  /// of rotting is the one that has waited longest.
  String? _openId;

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider);
    final pending = ref.watch(pendingCapturesProvider);
    final items = inbox.value ?? const <InboxItem>[];

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _header(items.length + pending.length),
            Expanded(
              child: RefreshIndicator(
                // Flush first, then re-read. In that order because the natural
                // reason to pull down here is "I have signal now", and a
                // refresh that fetched the server's list before sending the
                // queue would show a pile missing the very lines the user is
                // waiting to see land.
                onRefresh: () async {
                  await ref.read(captureQueueProvider.notifier).flush();
                  await ref.read(inboxProvider.notifier).refresh();
                },
                child: _body(inbox, items, pending),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header(int total) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(4, 10, 16, 10),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Назад',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.chevron_left, size: 26),
            color: AppColors.ink,
          ),
          Expanded(child: Text(InboxScreen.title, style: AppText.screen)),
          // One dot per waiting line, capped. The count is the promise this
          // screen makes: a pile nobody is reminded of is a pile that rots.
          for (var i = 0; i < (total > 6 ? 6 : total); i++)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: SizedBox(
                width: 9,
                height: 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.alarm,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          if (total > 6)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('+${total - 6}', style: AppText.chip),
            ),
        ],
      ),
    );
  }

  Widget _body(
    AsyncValue<List<InboxItem>> inbox,
    List<InboxItem> items,
    List<PendingCapture> pending,
  ) {
    if (items.isEmpty && pending.isEmpty) {
      return _Filler(
        icon: inbox.hasError ? Icons.cloud_off : Icons.inbox_outlined,
        title: inbox.hasError
            ? 'Не удалось загрузить песочницу'
            : inbox.isLoading
            ? 'Загружаем песочницу…'
            : 'Песочница пуста',
        body: inbox.hasError
            ? describeApiError(inbox.error!)
            : 'Сюда попадает то, что записано на ходу, — одной строкой и без '
                  'выбора проекта. Кнопка внизу записывает голосом.',
      );
    }

    // The open line, resolved rather than trusted: the id may name a line that
    // has just been filed or thrown away, and a screen with nothing open would
    // look broken.
    final open = items.any((item) => item.id == _openId)
        ? _openId!
        : items.isEmpty
        ? null
        : items.first.id;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 14, Insets.gutter, 24),
      children: <Widget>[
        // A failed `GET /inbox` is a banner *over* the queued lines rather than
        // a screen instead of them: those lines are on this device's disk, and
        // what failed is reading the server's half.
        if (inbox.hasError && pending.isNotEmpty)
          _OfflineBanner(message: describeApiError(inbox.error!)),

        for (final item in items) ...<Widget>[
          if (item.id == open)
            _OpenLine(
              key: ValueKey<String>('open-${item.id}'),
              item: item,
              onFiled: () => setState(() => _openId = null),
            )
          else
            _ClosedLine(
              key: ValueKey<String>(item.id),
              item: item,
              onTap: () => setState(() => _openId = item.id),
            ),
          const SizedBox(height: 12),
        ],

        // Unsent **last**, and that is the honest order rather than the
        // attention-grabbing one. The pile is worked oldest first, and floating
        // a line captured thirty seconds ago above lines from yesterday would
        // reorder the queue by a property that has nothing to do with what
        // needs doing.
        for (final entry in pending) ...<Widget>[
          _PendingLine(entry: entry),
          const SizedBox(height: 12),
        ],

        if (items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.format_list_bulleted,
                  size: 18,
                  color: AppColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'строка становится задачей одним касанием проекта',
                    style: AppText.hint,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.gutter, 12, Insets.gutter, 18),
      child: Row(
        children: <Widget>[
          Expanded(child: Text('записать ещё', style: AppText.caption)),
          MicrophoneSquare(
            tooltip: 'Записать ещё',
            onPressed: () => unawaited(AppRoutes.openDictation(context)),
          ),
        ],
      ),
    );
  }
}

/// The line being worked on: editable, with the projects under it.
class _OpenLine extends ConsumerStatefulWidget {
  const _OpenLine({required this.item, required this.onFiled, super.key});

  final InboxItem item;
  final VoidCallback onFiled;

  @override
  ConsumerState<_OpenLine> createState() => _OpenLineState();
}

class _OpenLineState extends ConsumerState<_OpenLine> {
  late final TextEditingController _text = TextEditingController(
    text: widget.item.text,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// Saves an edit only if there is one.
  ///
  /// Called on the way into a project rather than on every keystroke or on a
  /// separate "Сохранить": the moment the line becomes a task is the only
  /// moment its text has to be right, and a correction that was typed and then
  /// filed must not be filed in its old wording.
  Future<bool> _commitEdit() async {
    final text = _text.text.trim();
    if (text.isEmpty || text == widget.item.text) return true;

    return runMutation(
      context,
      () => ref.read(inboxProvider.notifier).edit(widget.item, text),
      failure: 'Не удалось изменить строчку.',
    );
  }

  Future<void> _file(String projectId, String projectName) async {
    if (!await _commitEdit() || !mounted) return;

    final ok = await runMutation(
      context,
      () => ref
          .read(inboxProvider.notifier)
          .file(widget.item, projectId: projectId),
      success: 'Задача добавлена в «$projectName».',
      failure: 'Не удалось перенести в проект.',
    );
    if (ok) widget.onFiled();
  }

  /// "Задача, для которой проекта ещё нет" -- the second reason the sandbox
  /// exists.
  ///
  /// Two requests rather than a server-side "promote": creating a project is an
  /// operation that already exists and already lands in the right scope, and a
  /// combined endpoint would duplicate its rules on the server.
  Future<void> _fileIntoNew() async {
    if (!await _commitEdit() || !mounted) return;

    final name = await askForProjectName(
      context,
      title: 'Новый проект',
      confirmLabel: 'Создать',
      // The captured line is usually the project's name, or nearly.
      initialName: _text.text.trim(),
    );
    if (name == null || !mounted) return;

    final scopeId = ref.read(activeScopeProvider)?.id;
    final created = await runMutationFor(
      context,
      () => ref
          .read(projectLifecycleProvider.notifier)
          .create(name, scopeId: scopeId),
      failure: 'Не удалось создать проект.',
    );
    if (created == null || !mounted) return;

    await _file(created.id, created.name);
  }

  Future<void> _dictate() async {
    final text = await AppRoutes.openDictation(
      context,
      destination: const FieldDestination('в эту строку'),
    );
    if (text == null || text.isEmpty || !mounted) return;
    final combined = '${_text.text.trimRight()} $text'.trim();
    _text.value = TextEditingValue(
      text: combined,
      selection: TextSelection.collapsed(offset: combined.length),
    );
  }

  Future<void> _discard() async {
    // A plain yes/no: this is one sentence, typed recently, and the
    // type-the-name confirmation that guards deleting a project would be
    // theatre. It is still a confirmation, because the line cannot be
    // recovered.
    final confirmed = await confirmDestructive(
      context,
      title: 'Выбросить строчку?',
      message:
          '«${widget.item.text}» исчезнет насовсем — вернуть будет нельзя.',
      confirmLabel: 'Выбросить',
    );
    if (!confirmed || !mounted) return;

    final ok = await runMutation(
      context,
      () => ref.read(inboxProvider.notifier).discard(widget.item),
      failure: 'Не удалось выбросить строчку.',
    );
    if (ok) widget.onFiled();
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(boardViewProvider);
    final projects = view is BoardReady
        ? view.projects
        : const <BoardProject>[];
    final age = daysSince(widget.item.createdAt);
    // One colour per project across the whole board -- see
    // `assignProjectBadgeColors`. Two project buttons wearing one colour is the
    // failure the badge exists to prevent, and they sit side by side here.
    final badgeColours = assignProjectBadgeColors(
      projects.map((entry) => entry.project.name),
    );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.indigoLink, width: 1.5),
        borderRadius: BorderRadius.circular(Radii.panel),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 104,
            child: TextField(
              controller: _text,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              textCapitalization: TextCapitalization.sentences,
              style: AppText.sandboxField,
              decoration: const InputDecoration(
                filled: false,
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Что не забыть…',
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  age == null ? '' : 'записано ${formatDays(age)} назад',
                  style: AppText.caption,
                ),
              ),
              _SquareAction(
                icon: Icons.mic_none,
                tooltip: 'Договорить голосом',
                onTap: () => unawaited(_dictate()),
              ),
              const SizedBox(width: 8),
              _SquareAction(
                icon: Icons.delete_outline,
                tooltip: 'Выбросить строку',
                colour: AppColors.alarm,
                onTap: () => unawaited(_discard()),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: AppColors.lineFaint),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final entry in projects)
                _ProjectButton(
                  name: entry.project.name,
                  badgeColor: badgeColours[entry.project.name],
                  onTap: () =>
                      unawaited(_file(entry.project.id, entry.project.name)),
                ),
              _SquareAction(
                icon: Icons.add,
                tooltip: 'В новый проект',
                dashed: true,
                onTap: () => unawaited(_fileIntoNew()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A line waiting its turn: tap it to work on it.
class _ClosedLine extends StatelessWidget {
  const _ClosedLine({required this.item, required this.onTap, super.key});

  final InboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final age = daysSince(item.createdAt);

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(Radii.panel),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.panel),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(Radii.panel),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(item.text, style: AppText.sandboxLine),
                    if (age != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Text(
                        '${formatDays(age)} в песочнице',
                        style: AppText.caption,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.chevron_right, size: 20, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A line that is on this device and not on the server yet (F8.1).
///
/// The mark is not optional: without it, "записано" and "записано у меня в
/// кармане" look exactly the same, and the difference is the one the user needs
/// in order to decide whether it is safe to forget the thought.
class _PendingLine extends ConsumerWidget {
  const _PendingLine({required this.entry});

  final PendingCapture entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final failed = entry.failed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(Radii.panel),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            failed ? Icons.error_outline : Icons.schedule_send_outlined,
            size: 20,
            color: failed ? AppColors.alarm : AppColors.muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(entry.text, style: AppText.sandboxLine),
                const SizedBox(height: 6),
                Text(
                  failed
                      ? 'Сервер не принял строчку — попробуем ещё раз'
                      : 'Не отправлено — уедет, когда появится сеть',
                  style: AppText.caption.copyWith(
                    color: failed ? AppColors.alarm : AppColors.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SquareAction(
            icon: Icons.delete_outline,
            tooltip: 'Выбросить',
            colour: AppColors.alarm,
            onTap: () => unawaited(_discard(context, ref)),
          ),
        ],
      ),
    );
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Выбросить строчку?',
      message: '«${entry.text}» исчезнет насовсем — вернуть будет нельзя.',
      confirmLabel: 'Выбросить',
    );
    if (!confirmed || !context.mounted) return;

    await runMutation(
      context,
      () => ref.read(captureQueueProvider.notifier).discard(entry),
      failure: 'Не удалось убрать строчку из очереди.',
    );
  }
}

/// One project, as a 44 px button. One tap and the line above is a task in it.
class _ProjectButton extends StatelessWidget {
  const _ProjectButton({
    required this.name,
    required this.onTap,
    this.badgeColor,
  });

  final Color? badgeColor;

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(Radii.row),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.row),
        child: Container(
          height: Targets.minimum,
          constraints: const BoxConstraints(maxWidth: 220),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(Radii.row),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ProjectBadge(name: name, size: 20, color: badgeColor),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(color: AppColors.ink),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 44x44 bordered square: the size everything tappable on this screen is.
class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.colour = AppColors.ink,
    this.dashed = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color colour;

  /// Drawn with the lighter "add something" border. Flutter has no dashed
  /// border without a custom painter, and a painter for one 44 px square is
  /// more code than the difference is worth -- so it is the same square in the
  /// pale [AppColors.lineStrong] instead, which reads as the same "not a thing
  /// yet" hint.
  final bool dashed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: dashed ? Colors.transparent : AppColors.card,
        borderRadius: BorderRadius.circular(Radii.row),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.row),
          child: Container(
            width: Targets.minimum,
            height: Targets.minimum,
            decoration: BoxDecoration(
              border: Border.all(
                color: dashed ? AppColors.lineStrong : AppColors.line,
              ),
              borderRadius: BorderRadius.circular(Radii.row),
            ),
            child: Icon(
              icon,
              size: 21,
              color: dashed ? AppColors.muted : colour,
            ),
          ),
        ),
      ),
    );
  }
}

class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.waitingFill,
        border: Border.all(color: AppColors.waitingLine),
        borderRadius: BorderRadius.circular(Radii.row),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.cloud_off, size: 18, color: AppColors.waitingInk),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Показано только то, что записано на этом устройстве. $message',
              style: AppText.hint.copyWith(color: AppColors.waitingInk),
            ),
          ),
          TextButton(
            onPressed: () => ref.read(inboxProvider.notifier).refresh(),
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
  }
}

class _Filler extends StatelessWidget {
  const _Filler({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(icon, size: 40, color: AppColors.lineStrong),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppText.projectName,
                  ),
                  const SizedBox(height: 8),
                  Text(body, textAlign: TextAlign.center, style: AppText.hint),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

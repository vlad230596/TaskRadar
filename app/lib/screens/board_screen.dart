import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_exception.dart';
import '../models/board_project.dart';
import '../providers/board_providers.dart';
import '../providers/session_provider.dart';
import '../widgets/project_card.dart';
import 'notification_bench_screen.dart';

/// The board: every active project, one card each, top to bottom.
///
/// ## Why a vertical list and not columns
///
/// The original picture of this product (`../../../README.md`) is a wide board
/// where a column is a project. That is the **F6** layout, for the desktop
/// target, and it is deliberately not built here: on a phone, fifteen
/// horizontal columns means fifteen horizontal swipes to answer "what is
/// happening", which is the one thing this screen exists to answer in a single
/// vertical scroll.
///
/// F6 adds the wide layout next to this one; the card is already a separate
/// widget so that the columns can reuse it.
class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    /*
     * Watched for its lifetime, not its value (it has none).
     *
     * `boardReminderBridge` is what turns a refreshed board into an updated
     * alarm queue. It is `keepAlive`, but a Riverpod provider that nobody
     * subscribes to is never *created*, so something has to be the first
     * subscriber -- and the board screen is the right one: it is the signed-in
     * home, mounted for as long as the app is in use, and the bridge is
     * keepAlive so it outlives any navigation away from here.
     *
     * F4 gives reminders a real owner (a settings screen plus the workmanager
     * task) and this line moves there.
     */
    ref.watch(boardReminderBridgeProvider);

    final view = ref.watch(boardViewProvider);
    final refreshing = view is BoardReady && view.isRefreshing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('TaskRadar'),
        // A hairline at the top edge rather than a spinner over the content:
        // a background refresh must not hide the board that is already
        // readable, which is the entire point of drawing the cache first.
        bottom: refreshing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
        actions: [
          IconButton(
            // TEMPORARY (F1/F2). The bench is still the only way to check the
            // notification stack on a device; it goes away with F4.
            tooltip: NotificationBenchScreen.title,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationBenchScreen(),
              ),
            ),
            icon: const Icon(Icons.notifications_active_outlined),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(boardProvider.notifier).refresh(),
        child: switch (view) {
          BoardLoading() => const _Message(
            icon: null,
            title: 'Загружаем доску…',
            body:
                'Если это первый запуск на этом устройстве, локального снимка '
                'ещё нет и приходится ждать сервер.',
          ),

          BoardUnavailable(:final error) => _Message(
            icon: Icons.cloud_off,
            title: 'Не удалось загрузить доску',
            body:
                '${describeBoardError(error)}\n\nЛокального снимка тоже нет — '
                'показать нечего. Потяните вниз или нажмите «Повторить».',
            action: _RetryButton(),
          ),

          BoardReady() => _BoardList(view: view),
        },
      ),
    );
  }
}

/// Turns an [ApiException] into something a person can act on.
///
/// The distinction that matters is the one [NetworkException] exists for: "your
/// phone cannot reach the server" and "the server answered with an error" have
/// completely different next steps, and collapsing them into "ошибка" is how
/// users end up rebooting routers over a 500.
String describeBoardError(Object error) => switch (error) {
  NetworkException() => 'Нет связи с сервером.',
  ApiException(:final statusCode, :final message) =>
    'Сервер ответил ошибкой $statusCode: $message',
  _ => error.toString(),
};

class _BoardList extends ConsumerWidget {
  const _BoardList({required this.view});

  final BoardReady view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return CustomScrollView(
      // Without this the list does not scroll when it is shorter than the
      // viewport, and a pull-to-refresh on a two-project board does nothing.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (view.isStale || view.refreshError != null)
          SliverToBoxAdapter(child: _StaleBanner(view: view)),

        if (view.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              icon: Icons.inbox_outlined,
              title: 'Проектов пока нет',
              body:
                  'Активных проектов на доске нет. Создание проекта появится '
                  'на F3 — пока их заводит старый веб-клиент.',
              scrollable: false,
            ),
          )
        else
          SliverList.builder(
            itemCount: view.projects.length,
            itemBuilder: (context, index) {
              final entry = view.projects[index];
              return ProjectCard(
                key: ValueKey<String>(entry.project.id),
                entry: entry,
                onTap: () => _openProject(context, entry),
              );
            },
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  /// F3 replaces this with the project screen. Until then a tap has to *say*
  /// that, rather than do nothing -- a card that looks tappable and silently
  /// is not reads as a bug.
  void _openProject(BuildContext context, BoardProject entry) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('«${entry.project.name}» — экран проекта будет на F3'),
        ),
      );
  }
}

/// "You are looking at the past, and here is how far into it."
///
/// The plan asks for this explicitly: a cached board that silently looks like a
/// live one is worse than no cache, because the user acts on yesterday's state
/// believing it is today's.
class _StaleBanner extends ConsumerWidget {
  const _StaleBanner({required this.view});

  final BoardReady view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final failed = view.refreshError != null;

    final background = failed
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final foreground = failed
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;

    final lines = <String>[
      if (failed) describeBoardError(view.refreshError!),
      if (view.isStale)
        'Показан локальный снимок от ${formatUpdatedAt(view.updatedAt)}.'
      else
        'Данные от ${formatUpdatedAt(view.updatedAt)}.',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failed ? Icons.cloud_off : Icons.history,
                size: 18,
                color: foreground,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  failed ? 'Не удалось обновить' : 'Данные из кэша',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            lines.join(' '),
            style: theme.textTheme.bodySmall?.copyWith(color: foreground),
          ),
          if (failed) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: _RetryButton(foreground: foreground),
            ),
          ],
        ],
      ),
    );
  }
}

class _RetryButton extends ConsumerWidget {
  const _RetryButton({this.foreground});

  final Color? foreground;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return TextButton.icon(
      onPressed: () => ref.read(boardProvider.notifier).refresh(),
      icon: const Icon(Icons.refresh, size: 18),
      label: const Text('Повторить'),
      style: foreground == null
          ? null
          : TextButton.styleFrom(foregroundColor: foreground),
    );
  }
}

/// A centred block of text that still fills the viewport, so that
/// pull-to-refresh works on top of it.
class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
    this.scrollable = true,
  });

  /// Null draws a progress indicator instead — the loading state.
  final IconData? icon;
  final String title;
  final String body;
  final Widget? action;

  /// True when this is the direct child of the [RefreshIndicator] and therefore
  /// has to be the scrollable itself (otherwise the gesture never starts).
  /// False inside a [SliverFillRemaining], which is already inside one.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon == null)
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(strokeWidth: 3),
            )
          else
            Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );

    if (!scrollable) return Center(child: content);

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// "сегодня в 09:12" / "вчера в 21:40" / "14.09 в 08:05".
///
/// Relative wording for the two days that matter and an absolute date beyond
/// them: the question the user is answering is "is this stale enough to
/// distrust?", and "вчера" answers it instantly while "15.09" needs a moment of
/// arithmetic. Everything here is local wall-clock, which is the only clock the
/// reader has.
String formatUpdatedAt(DateTime updatedAt, {DateTime? now}) {
  final local = updatedAt.toLocal();
  final today = (now ?? DateTime.now()).toLocal();

  final time =
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';

  final date = DateTime(local.year, local.month, local.day);
  final midnight = DateTime(today.year, today.month, today.day);
  final days = midnight.difference(date).inDays;

  return switch (days) {
    0 => 'сегодня в $time',
    1 => 'вчера в $time',
    _ =>
      '${local.day.toString().padLeft(2, '0')}.'
          '${local.month.toString().padLeft(2, '0')} в $time',
  };
}

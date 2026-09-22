import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../navigation/app_routes.dart';
import '../providers/session_provider.dart';
import '../providers/shell_providers.dart';
import '../widgets/adaptive_layout.dart';
import '../widgets/mode_navigation.dart';
import 'history_screen.dart';
import 'plan_screen.dart';
import 'scopes_screen.dart';
import 'work_screen.dart';

/// The signed-in home: three modes, one microphone, and nothing else at this
/// level (F12).
///
/// ## Why the modes are swapped here rather than pushed
///
/// `app.dart` explains why being signed in is a switch on `home` rather than a
/// route, and this is the same argument one level down. The three modes are
/// three answers to "что сейчас на экране", exactly one is true at a time, and
/// none of them is somewhere you came *from*. Pushed as routes they would fill
/// the back stack with modes nobody thinks of as history, and restoring the
/// last-used mode at startup would mean synthesising a navigation stack instead
/// of reading an integer.
///
/// Everything below a mode -- a project, a task, the sandbox, the dictation
/// screen -- is still a real route pushed on top of this, exactly as F3
/// arranged. So the back button has one meaning everywhere: leave this
/// sub-screen. It never changes mode.
///
/// ## Why the content is kept alive across a switch
///
/// [IndexedStack] rather than a `switch` returning one child. Switching to the
/// work mode and back must not re-run the planning mode's build from scratch,
/// lose its scroll position, or -- worse -- drop the last listener on
/// `boardViewProvider` for one frame and make an auto-disposed provider under
/// it rebuild. The cost is that all three modes are built once; the two stubs
/// are a `Column`, and F13's will be lists over data that is already in
/// memory.
class ShellScreen extends ConsumerWidget {
  const ShellScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(shellModeProvider);
    final wide = isWideLayout(context);

    final content = IndexedStack(
      index: AppMode.values.indexOf(mode),
      children: const <Widget>[PlanScreen(), WorkScreen(), HistoryScreen()],
    );

    final header = switch (mode) {
      AppMode.plan => const PlanHeader(),
      AppMode.work => const WorkHeader(),
      AppMode.history => const HistoryHeader(),
    };

    if (wide) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ModeRail(
              current: mode,
              onSelect: (value) =>
                  ref.read(shellModeProvider.notifier).select(value),
              onDictate: () => AppRoutes.openDictation(context),
              onSettings: () => AppRoutes.openSettings(context),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[header, Expanded(child: content)],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[header, Expanded(child: content)],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: ModeBar(
          current: mode,
          onSelect: (value) =>
              ref.read(shellModeProvider.notifier).select(value),
          onDictate: () => AppRoutes.openDictation(context),
        ),
      ),
    );
  }
}

/// The way to the archive, the scopes, the settings and the way out.
///
/// ## Why this exists when the reference pages have no such button
///
/// `design/reference/Main.html` shows a phone header with a title, a scope pill
/// and the layout toggle -- and nothing else. On the desktop the rail carries a
/// settings cog; on the phone the reference simply does not say where settings
/// live, because none of the five screens it specifies is settings.
///
/// They still have to be reachable: the archive, the scope manager, the speech
/// model's download and "Выйти" are all behind them, and a personal tool whose
/// only route to signing out is reinstalling is not a shipped app. So one 44 px
/// overflow at the end of the header, which is the smallest thing that can hold
/// four rare actions, and which was the same control the old board screen used
/// for exactly the same four.
class ShellOverflowButton extends ConsumerWidget {
  const ShellOverflowButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<_ShellAction>(
      tooltip: 'Ещё',
      icon: const Icon(Icons.more_vert, size: 21),
      position: PopupMenuPosition.under,
      onSelected: (action) {
        switch (action) {
          case _ShellAction.archive:
            AppRoutes.openArchive(context);
          case _ShellAction.scopes:
            AppRoutes.openScopes(context);
          case _ShellAction.settings:
            AppRoutes.openSettings(context);
          case _ShellAction.signOut:
            ref.read(sessionProvider.notifier).signOut();
        }
      },
      itemBuilder: (_) => const <PopupMenuEntry<_ShellAction>>[
        PopupMenuItem<_ShellAction>(
          value: _ShellAction.archive,
          child: ListTile(
            leading: Icon(Icons.inventory_2_outlined),
            title: Text('Архив'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_ShellAction>(
          value: _ShellAction.scopes,
          child: ListTile(
            leading: Icon(Icons.workspaces_outline),
            title: Text(ScopesScreen.title),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem<_ShellAction>(
          value: _ShellAction.settings,
          child: ListTile(
            leading: Icon(Icons.settings_outlined),
            title: Text('Настройки'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuDivider(),
        // Last, and behind a divider, because it is next to nothing worth an
        // accidental tap.
        PopupMenuItem<_ShellAction>(
          value: _ShellAction.signOut,
          child: ListTile(
            leading: Icon(Icons.logout),
            title: Text('Выйти'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

enum _ShellAction { archive, scopes, settings, signOut }

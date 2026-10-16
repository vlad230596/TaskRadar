import 'package:flutter/material.dart';

/// Back with typed, unsaved text asks first.
///
/// The rule the Android Back checks (`tests/android/`) hold every screen to:
///
/// 1. Back with the keyboard up only closes the keyboard -- the platform does
///    that before the app sees anything, and the text stays;
/// 2. Back with nothing to lose leaves at once -- a dialog in front of every
///    read-only Back trains people to dismiss it without reading;
/// 3. Back with something to lose asks "Выйти без сохранения?" with
///    «Остаться», «Выйти» and, where the screen can save, «Сохранить».
///
/// Before this widget only the note editor followed rule 3; the task screen,
/// the dictation screen, "Причесать" and the open sandbox line dropped the
/// text without a word.
///
/// [isDirty] is read on every change of [listenable] (the text controllers),
/// so only the [PopScope] rebuilds per keystroke, not the screen. The caller's
/// own rebuilds re-read it as well, which covers state that is not a
/// controller (a recording in progress).
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard({
    required this.isDirty,
    required this.message,
    required this.child,
    this.listenable,
    this.onSave,
    super.key,
  });

  final bool Function() isDirty;

  /// What will be lost, in one sentence.
  final String message;

  final Listenable? listenable;

  /// Offered as «Сохранить» when given. Returns whether the route should be
  /// left afterwards: false when the save failed (its own snackbar says why)
  /// or when the save has already closed the screen itself.
  final Future<bool> Function()? onSave;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable ?? const _Never(),
      builder: (context, child) => PopScope<Object?>(
        canPop: !isDirty(),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _confirm(context);
        },
        child: child!,
      ),
      child: child,
    );
  }

  Future<void> _confirm(BuildContext context) async {
    // The field keeps focus after the keyboard's own Back, and a closing
    // dialog hands focus back to it -- which brought the keyboard up again
    // after «Остаться», a step the user had just undone. Two Backs mean "I am
    // done typing"; the field is one tap away if they were not.
    FocusManager.instance.primaryFocus?.unfocus();
    final choice = await showDialog<_Leave>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти без сохранения?'),
        content: Text(message),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Остаться'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_Leave.discard),
            child: const Text('Выйти'),
          ),
          if (onSave != null)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_Leave.save),
              child: const Text('Сохранить'),
            ),
        ],
      ),
    );
    if (!context.mounted) return;

    switch (choice) {
      case _Leave.discard:
        Navigator.of(context).pop();
      case _Leave.save:
        if (await onSave!() && context.mounted) Navigator.of(context).pop();
      case null:
        break;
    }
  }
}

enum _Leave { save, discard }

class _Never implements Listenable {
  const _Never();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

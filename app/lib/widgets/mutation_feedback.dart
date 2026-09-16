import 'package:flutter/material.dart';

import '../api/api_error_message.dart';

/// Runs a write and says so out loud when it fails.
///
/// ## Why failures are shouted rather than swallowed
///
/// `flutter-migration-plan.md` is categorical: the local cache is read-only,
/// **every write requires the network**, and there is no operation queue. An
/// optimistic update is therefore a prediction with a one-round-trip lifetime,
/// not an offline edit -- and the honest ending for a prediction that turned out
/// wrong is "your change did not happen, here is why", not a silent revert.
///
/// A silent revert is the specific failure mode worth naming: the row snaps back
/// to its old state, which looks exactly like a UI bug, so the user tries again,
/// and again, with no idea that their phone is on a captive-portal Wi-Fi. The
/// message is what turns that into one readable sentence.
///
/// The notifier does the rolling back (it owns the "before" state); this only
/// reports. Returns whether the write succeeded, for callers that want to close
/// an editor only on success.
Future<bool> runMutation(
  BuildContext context,
  Future<void> Function() action, {
  required String failure,
}) async {
  // Resolved before the await: after it, this widget may be gone and looking up
  // an ancestor through a dead element is the `use_build_context_synchronously`
  // crash. The messenger itself belongs to the Scaffold above, which outlives
  // the row being edited.
  final messenger = ScaffoldMessenger.of(context);

  try {
    await action();
    return true;
  } catch (error) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text('$failure ${describeApiError(error)}')),
      );
    return false;
  }
}

/// "Удалить задачу?" -- a yes/no the user cannot undo.
///
/// Both deletes in this screen are permanent server-side (`DELETE /tasks/:id`
/// and `DELETE /notes/:id` remove the row, there is no soft delete and no
/// undo), so both go through here. The React client used `window.confirm` for
/// the same reason.
Future<bool> confirmDestructive(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Удалить',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return confirmed ?? false;
}

/// A confirmation that cannot be given by reflex: the user has to type the thing
/// back (F4).
///
/// ## Why deleting a project does not get the ordinary dialog
///
/// [confirmDestructive] is right for a task or a note -- one line of text, lost
/// in one tap, re-typed in five seconds. Deleting a project takes its tasks and
/// its notes with it: months of the context this whole tool exists to preserve
/// (`../../README.md`), gone, with nothing on the server to restore from. A
/// yes/no in front of that is not a confirmation, it is a speed bump that a
/// person walking to the kitchen will clear without reading -- "ок/отмена на
/// автомате" is the exact failure being designed against.
///
/// Typing the name changes what the dialog measures. A yes/no asks "are you
/// sure", which is a question about a mood; this asks "which project", which is
/// a question about a fact, and it cannot be answered correctly by a mis-tap or
/// by the wrong row being open. It also costs nothing in the common case,
/// because the common case is not deleting a project at all -- that is what the
/// archive is for, and it is one tap away in the same list.
///
/// Trimmed and case-insensitive: the point is proving you know which project
/// this is, not proving you can reproduce capitalisation.
Future<bool> confirmByTyping(
  BuildContext context, {
  required String title,
  required String message,
  required String expected,
  required String fieldLabel,
  String confirmLabel = 'Удалить навсегда',
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _TypedConfirmationDialog(
      title: title,
      message: message,
      expected: expected,
      fieldLabel: fieldLabel,
      confirmLabel: confirmLabel,
    ),
  );

  return confirmed ?? false;
}

class _TypedConfirmationDialog extends StatefulWidget {
  const _TypedConfirmationDialog({
    required this.title,
    required this.message,
    required this.expected,
    required this.fieldLabel,
    required this.confirmLabel,
  });

  final String title;
  final String message;
  final String expected;
  final String fieldLabel;
  final String confirmLabel;

  @override
  State<_TypedConfirmationDialog> createState() =>
      _TypedConfirmationDialogState();
}

class _TypedConfirmationDialogState extends State<_TypedConfirmationDialog> {
  final TextEditingController _controller = TextEditingController();

  bool get _matches =>
      _controller.text.trim().toLowerCase() ==
      widget.expected.trim().toLowerCase();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            // Not autofocused. A keyboard appearing over the paragraph that
            // explains what is about to be destroyed defeats the paragraph.
            decoration: InputDecoration(
              labelText: widget.fieldLabel,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_matches) Navigator.of(context).pop(true);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          // Disabled rather than hidden: a hidden button reads as a broken
          // dialog, a disabled one reads as "there is one more thing to do".
          onPressed: _matches ? () => Navigator.of(context).pop(true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

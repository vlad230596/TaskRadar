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

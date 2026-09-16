import 'package:flutter/material.dart';

/// Asks for a project's name -- the new one, or a corrected one.
///
/// One dialog for creating and for renaming, because `POST /projects` and
/// `PATCH /projects/:id` take the same single field with the same validation
/// (`createProjectSchema` *is* `updateProjectSchema`, `backend/src/schemas.ts`).
/// Two dialogs would be two places for the trim rule and the disabled-button
/// rule to drift apart.
///
/// Returns the typed name, already trimmed, or null if the user backed out.
/// An empty name never comes back: the confirm button stays disabled instead of
/// a validation message, because the empty field is already the whole message
/// and the server would refuse it anyway.
Future<String?> askForProjectName(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
  String hint = 'Название проекта',
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NameDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      hint: hint,
    ),
  );
}

/// The same question about a scope (F7).
///
/// The same dialog, not a copy of it: "name this thing, non-empty, trimmed" is
/// one rule, and the parts that are easy to get subtly wrong -- disposing the
/// controller only when the dialog is actually gone, pre-selecting the old name
/// so a rename is one gesture, keeping the confirm button disabled instead of
/// showing a validation message -- are exactly the parts nobody wants two
/// copies of. Only the wording differs.
Future<String?> askForScopeName(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String initialName = '',
}) {
  return askForProjectName(
    context,
    title: title,
    confirmLabel: confirmLabel,
    initialName: initialName,
    hint: 'Работа, Дача, Личное…',
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.confirmLabel,
    required this.initialName,
    required this.hint,
  });

  final String title;
  final String confirmLabel;
  final String initialName;
  final String hint;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  )..selection = TextSelection(
    // Pre-selected, so a rename can be typed over in one gesture. The name is
    // usually being replaced rather than edited -- and when it is being edited,
    // one tap puts the caret where the user wants it.
    baseOffset: 0,
    extentOffset: widget.initialName.length,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: widget.hint,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

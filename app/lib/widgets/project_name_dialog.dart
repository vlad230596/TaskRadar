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
    builder: (_) => _ProjectNameDialog(
      title: title,
      confirmLabel: confirmLabel,
      initialName: initialName,
      hint: hint,
    ),
  );
}

class _ProjectNameDialog extends StatefulWidget {
  const _ProjectNameDialog({
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
  State<_ProjectNameDialog> createState() => _ProjectNameDialogState();
}

class _ProjectNameDialogState extends State<_ProjectNameDialog> {
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

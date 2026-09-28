import 'package:flutter/material.dart';

import '../api/dictation_api.dart';
import '../navigation/app_routes.dart';
import '../screens/dictation_screen.dart';
import '../theme/tokens.dart';
import 'dictation.dart';

/// A microphone next to a field that is not on one of F12's redrawn screens.
///
/// ## Why this exists at all, given that the microphone lives in one place
///
/// It does live in one place -- the shell's fourth navigation item -- and that
/// is where dictation is *started* from. What the rule is about is the button:
/// there is exactly one kind of it, it is the only indigo thing, and pressing
/// any of them opens the same full-screen recorder. It is not about there being
/// literally one on the whole device; the task screen and the sandbox each have
/// one in the same corner for the same reason.
///
/// This is that same button at 44 px, for the places F12 did not redraw: the
/// note editor and the note composer. They keep dictation because taking it
/// away would be a regression, and they get it through the same screen as
/// everything else -- so there is still no second gesture, no press-and-hold,
/// and no inline recording panel anywhere in the app. (The "name this project"
/// dialog had one too; F15 took it away -- see `project_name_dialog.dart`.)
///
/// When those screens are redesigned this widget should go with them.
class DictateInto extends StatelessWidget {
  const DictateInto({
    required this.controller,
    this.label = 'в это поле',
    this.separator = ' ',
    this.tooltip = 'Продиктовать',
    this.kind = ParseKind.note,
    super.key,
  });

  /// What "Разобрать" on the dictation screen makes of the words -- see
  /// [FieldDestination.kind].
  final ParseKind kind;

  /// The field the words are appended to.
  final TextEditingController controller;

  /// What the dictation screen's chip says the destination is.
  final String label;

  /// What separates the dictated text from what is already there. A newline for
  /// a Markdown body, where two dictated chunks are two thoughts and running
  /// them into one paragraph is the one thing that would make the result worse
  /// than typing it.
  final String separator;

  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      constraints: const BoxConstraints(
        minWidth: Targets.minimum,
        minHeight: Targets.minimum,
      ),
      color: AppColors.indigo,
      icon: const Icon(Icons.mic_none, size: 22),
      onPressed: () async {
        final result = await AppRoutes.openDictation(
          context,
          destination: FieldDestination(label, kind: kind),
        );
        // One field, one text: a note or a line comes back as words. A
        // task's two fields ([FieldTaskText]) are the task screen's own
        // business, and a field here has nowhere to put the second.
        final text = switch (result) {
          FieldWords(:final text) => text,
          FieldTaskText(:final title, :final description) => <String>[
            title,
            ?description,
          ].join(separator),
          null => '',
        };
        if (text.isEmpty) return;
        appendDictated(controller, text: text, separator: separator);
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../ai_tidy.dart';

/// The task editor's look: the dictation screen's dark family (task-editor
/// spec, section 8), so creating, editing and reviewing a dictation read as
/// one place. A local [Theme] over the editor, never the app's own theme --
/// the task list under the compact sheet stays light.
abstract final class EditorColors {
  static const Color background = AppColors.voiceBackground;
  static const Color well = AppColors.voiceWell;
  static const Color line = AppColors.voiceLine;
  static const Color ink = AppColors.voiceInk;
  static const Color muted = AppColors.voiceMuted;
  static const Color bright = AppColors.voiceBright;
  static const Color focus = AppColors.voiceLevelHigh;

  /// A recognised token in the text: the focus colour at 30 %.
  static const Color tokenFill = Color(0x4D6C79E8);

  /// "Блокер", lit on the dark surface.
  static const Color blocked = AppColors.waitingDotOnInk;

  /// "Сделано", lightened so it reads on the dark surface.
  static const Color done = Color(0xFF7FD1A8);

  /// A reminder whose moment has gone by.
  static const Color past = Color(0xFFFF8C70);
}

/// The editor's type: the review screen's sizes.
abstract final class EditorText {
  /// The title: 22/600, as the review screen's "НАЗВАНИЕ".
  static final TextStyle title = AppText.dictated.copyWith(
    fontSize: 22,
    fontWeight: FontWeight.w600,
    height: 1.3,
  );

  /// The description and every other body line: 17.
  static final TextStyle body = AppText.dictated.copyWith(
    fontSize: 17,
    height: 1.4,
  );

  /// The header: "Новая задача" / "Задача".
  static final TextStyle header = AppText.screenTight.copyWith(
    color: EditorColors.ink,
  );

  /// A chip's label.
  static const TextStyle chip = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    color: EditorColors.bright,
  );

  /// Small print under a control.
  static const TextStyle note = TextStyle(
    fontFamily: AppFonts.text,
    fontWeight: FontWeight.w500,
    fontSize: 13,
    color: EditorColors.muted,
  );
}

/// The width from which the editor opens as a 560 px dialog instead of a
/// sheet or a page (spec, section 1).
const double kEditorDialogBreakpoint = 720;

/// The dialog's width on a wide window.
const double kEditorDialogWidth = 560;

/// The theme the editor is drawn in: the dictation screen's, plus the sheets
/// and menus opened from it.
final ThemeData editorTheme = voiceTheme.copyWith(
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: AppColors.railActive,
    surfaceTintColor: Colors.transparent,
    modalBackgroundColor: AppColors.railActive,
    dragHandleColor: EditorColors.muted,
    showDragHandle: true,
  ),
  listTileTheme: const ListTileThemeData(
    iconColor: EditorColors.bright,
    textColor: EditorColors.ink,
  ),
  iconTheme: const IconThemeData(color: EditorColors.bright),
  dividerColor: EditorColors.line,
  snackBarTheme: buildAppTheme().snackBarTheme,
);

/// Light status-bar icons over the dark editor -- see the same note in
/// `dictation_screen.dart`.
const SystemUiOverlayStyle editorOverlayStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
  systemNavigationBarColor: AppColors.voiceBackground,
  systemNavigationBarIconBrightness: Brightness.light,
);

/// "Добавить" / "Сохранить": white on the dark screen, 76 px (56 with the
/// keyboard up), the review screen's "Готово".
class EditorPrimaryButton extends StatelessWidget {
  const EditorPrimaryButton({
    required this.label,
    required this.onPressed,
    this.icon = Icons.check,
    this.compact = false,
    this.onLongPress,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: compact ? 56 : Targets.finishDictation,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.card,
          foregroundColor: AppColors.voiceBackground,
          disabledBackgroundColor: EditorColors.line,
          disabledForegroundColor: EditorColors.muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.large),
          ),
          textStyle: AppText.action.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 19,
          ),
        ),
        onPressed: onPressed,
        onLongPress: onLongPress,
        icon: Icon(icon, size: 24),
        label: Text(label),
      ),
    );
  }
}

/// A secondary action beside or under the primary one: outlined in the
/// editor's line colour.
class EditorSecondaryButton extends StatelessWidget {
  const EditorSecondaryButton({
    required this.onPressed,
    this.label,
    this.icon,
    this.tooltip,
    this.height = 52,
    this.width,
    super.key,
  });

  final String? label;
  final IconData? icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final double height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      backgroundColor: Colors.transparent,
      foregroundColor: EditorColors.bright,
      side: const BorderSide(color: EditorColors.line, width: 1.5),
      padding: this.label == null ? EdgeInsets.zero : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.large),
      ),
      textStyle: AppText.action.copyWith(fontWeight: FontWeight.w600),
    );
    final label = this.label;
    final Widget button = label == null
        ? OutlinedButton(
            style: style,
            onPressed: onPressed,
            child: Icon(icon, size: 24),
          )
        : icon == null
        ? OutlinedButton(
            style: style,
            onPressed: onPressed,
            child: Text(label),
          )
        : OutlinedButton.icon(
            style: style,
            onPressed: onPressed,
            icon: Icon(icon, size: 20),
            label: Text(label),
          );
    final sized = SizedBox(height: height, width: width, child: button);
    final tooltip = this.tooltip;
    return tooltip == null ? sized : Tooltip(message: tooltip, child: sized);
  }
}

/// A section's caps label: "ОПИСАНИЕ", "СПИСОК · 2/5" -- the review screen's
/// [TidyLabel], with room on the right for the section's own controls.
class EditorSectionLabel extends StatelessWidget {
  const EditorSectionLabel(this.text, {this.trailing, super.key});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailing = this.trailing;
    if (trailing == null) return TidyLabel(text);
    return Row(
      children: <Widget>[
        Expanded(child: TidyLabel(text)),
        trailing,
      ],
    );
  }
}

/// A small pill inside a card: "Причесать", the microphone. 30 px drawn,
/// 44 px caught (see `Targets.minimum`).
class EditorPill extends StatelessWidget {
  const EditorPill({
    required this.icon,
    required this.onTap,
    this.label,
    this.tooltip,
    this.accent = false,
    super.key,
  });

  final IconData icon;
  final String? label;
  final String? tooltip;
  final VoidCallback onTap;

  /// The microphone: the one indigo control, as everywhere in the app.
  final bool accent;

  static const double _height = 30;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    final tooltip = this.tooltip;
    final ink = accent ? AppColors.onInk : EditorColors.bright;

    final pill = Material(
      color: accent ? AppColors.indigo : Colors.transparent,
      shape: StadiumBorder(
        side: accent
            ? BorderSide.none
            : const BorderSide(color: EditorColors.line),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: _height,
          width: label == null ? _height + 6 : null,
          child: label == null
              ? Icon(icon, size: 17, color: ink)
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(icon, size: 14, color: ink),
                      const SizedBox(width: 5),
                      Text(
                        label,
                        style: EditorText.chip.copyWith(
                          fontSize: 12.5,
                          color: ink,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );

    final hit = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: (Targets.minimum - _height) / 2,
        ),
        child: pill,
      ),
    );
    return tooltip == null ? hit : Tooltip(message: tooltip, child: hit);
  }
}

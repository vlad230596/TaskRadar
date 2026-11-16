import 'package:flutter/widgets.dart';

/// The app's [TextEditingController]: the same, except for how the word the
/// keyboard is still composing is marked.
///
/// ## Why not the framework's underline
///
/// While a predictive keyboard (Gboard, Samsung, Yandex) is composing a word,
/// Flutter marks that word with `TextDecoration.underline` and no
/// `decorationColor` ([TextEditingController.buildTextSpan]). On the owner's
/// Android phone that underline came out as an *invisible line that erases
/// part of a letter*: a band one pixel thick, 1.5 px under the baseline (the
/// Golos `post` table: underline position -75, thickness 50 per 1000), the
/// colour of the background, cutting through every descender of the word
/// being typed -- the tail of "у" in "буквы". It came and went with the
/// composing region, which is why it "sometimes appears": it is there while a
/// word is being typed and gone after the space.
///
/// So the composing word is marked by a faint tint *behind* it instead. A
/// span's background is painted before its glyphs, so whatever the engine
/// does with it, it cannot cover a letter; an underline is painted after
/// them and can.
///
/// Every text field in the app uses this (or [SmartTextController], which
/// extends it). A new field should too: `ImeTextController()` in place of
/// `TextEditingController()`.
class ImeTextController extends TextEditingController {
  ImeTextController({super.text});

  /// The tint behind the composing word: the field's own ink, faint, so it
  /// reads on the dark capture screen and on a light dialog alike.
  static TextStyle composingStyle(TextStyle? style) => TextStyle(
    backgroundColor: (style?.color ?? const Color(0xFF808080)).withValues(
      alpha: 0.16,
    ),
  );

  /// Whether [value]'s composing region is one to mark, under the same rules
  /// as the framework's [TextEditingController.buildTextSpan].
  bool showsComposing(bool withComposing) =>
      withComposing &&
      value.isComposingRangeValid &&
      !value.composing.isCollapsed;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!showsComposing(withComposing)) {
      return TextSpan(style: style, text: text);
    }
    final composing = value.composing;
    return TextSpan(
      style: style,
      children: <TextSpan>[
        TextSpan(text: composing.textBefore(text)),
        TextSpan(
          style: composingStyle(style),
          text: composing.textInside(text),
        ),
        TextSpan(text: composing.textAfter(text)),
      ],
    );
  }
}

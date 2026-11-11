import 'package:flutter/material.dart';

import '../../domain/smart_tokens.dart';
import 'editor_theme.dart';

/// A text field's controller that knows what is recognised in its text
/// (task-editor spec, section 2): the date, `#проект` and `/категория`
/// tokens of `domain/smart_tokens.dart`, and the links.
///
/// ## What it does on every edit
///
/// 1. Keeps the dismissed ranges («Не дата», Backspace after a token, the
///    scan on opening an existing task) aligned with the text
///    ([shiftRangesForEdit]).
/// 2. Re-parses the text ([parseSmartTokens]) *before* listeners hear of the
///    change, so a listener always reads tokens of the text it is told about.
/// 3. Draws the tokens and links in [buildTextSpan]: an active token is a
///    filled highlight, an ambiguous one a dotted underline, a link a plain
///    underline. A dismissed piece is ordinary text.
///
/// ## Backspace after a token
///
/// As in Todoist: the first Backspace with the caret right after an active
/// token only un-recognises it (the text stays), the second one erases a
/// character. Detected in the [value] setter, which is where `EditableText`
/// writes every keystroke.
///
/// The controller holds no values: what a token *means* to the task is the
/// editor's business (the chips, `screens/task_editor_screen.dart`).
class SmartTextController extends TextEditingController {
  SmartTextController({
    super.text,
    SmartContext Function()? contextFor,
    DateTime Function()? clock,
    this.recognise = true,
  }) : _contextFor = contextFor ?? _noContext,
       _clock = clock ?? DateTime.now {
    _parse(super.value.text);
  }

  static SmartContext _noContext() => const SmartContext();

  final SmartContext Function() _contextFor;
  final DateTime Function() _clock;

  /// False for a field that only underlines links (the description): tokens
  /// are read from the title alone, which is the text they are cut from.
  final bool recognise;

  List<SmartRange> _dismissed = const <SmartRange>[];
  List<SmartToken> _tokens = const <SmartToken>[];
  List<LinkSpan> _links = const <LinkSpan>[];

  /// Every token in the text, resolved or not, sorted by start.
  List<SmartToken> get tokens => _tokens;

  /// The tokens that assign a value now.
  Iterable<SmartToken> get activeTokens =>
      _tokens.where((token) => token.isResolved);

  /// The links in the text.
  List<LinkSpan> get links => _links;

  /// The ranges the user said are not tokens.
  List<SmartRange> get dismissed => _dismissed;

  /// The token of [kind], resolved or not, or null.
  SmartToken? tokenOf(TokenKind kind) {
    for (final token in _tokens) {
      if (token.kind == kind) return token;
    }
    return null;
  }

  /// The resolved token of [kind], or null.
  SmartToken? activeOf(TokenKind kind) {
    final token = tokenOf(kind);
    return token != null && token.isResolved ? token : null;
  }

  /// The token under [offset], strictly inside it (a caret at either edge is
  /// typing next to the token, not touching it).
  SmartToken? tokenAt(int offset) {
    for (final token in _tokens) {
      if (token.start < offset && offset < token.end) return token;
    }
    return null;
  }

  /// The link under [offset], edges included.
  LinkSpan? linkAt(int offset) {
    for (final link in _links) {
      if (link.start <= offset && offset <= link.end) return link;
    }
    return null;
  }

  /// The text with the active tokens cut out, for saving.
  String get strippedText => stripTokens(text, activeTokens).trim();

  /// «Не дата»: [token]'s piece becomes plain text, and stays so in this
  /// position.
  void dismiss(SmartToken token) {
    _dismissed = <SmartRange>[..._dismissed, token.range];
    _parse(text);
    notifyListeners();
  }

  /// Every token of [kind] dismissed -- the chip of that kind was changed by
  /// hand, so the text no longer speaks for it.
  void dismissKind(TokenKind kind) {
    final token = tokenOf(kind);
    if (token != null) dismiss(token);
  }

  /// Marks everything recognisable in the text as dismissed: an existing
  /// task's text, written before this feature, must not silently move its
  /// reminder (spec, "Источник правды").
  void dismissAll() {
    if (!recognise) return;
    _dismissed = <SmartRange>[
      ..._dismissed,
      ...findAllTokenRanges(text, now: _clock(), ctx: _contextFor()),
    ];
    _parse(text);
    notifyListeners();
  }

  /// Sets [text] as the field's whole content, with nothing dismissed --
  /// what a task opened for editing or a cleared field starts from.
  void reset(String text) {
    _dismissed = const <SmartRange>[];
    final same = text == this.text;
    value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (same) {
      _parse(text);
      notifyListeners();
    }
  }

  /// Re-reads the context (the projects or categories arrived, or the
  /// selected project changed) and parses again.
  void refresh() {
    final before = _tokens;
    _parse(text);
    if (!_sameTokens(before, _tokens)) notifyListeners();
  }

  /// Replaces `[start, end)` with [replacement] -- picking one of an
  /// ambiguous token's candidates writes its full name into the text.
  void replaceRange(int start, int end, String replacement) {
    final next = text.replaceRange(start, end, replacement);
    value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + replacement.length,
      ),
    );
  }

  @override
  set value(TextEditingValue newValue) {
    final old = super.value;
    if (old.text == newValue.text) {
      super.value = newValue;
      return;
    }

    final swallowed = _backspaceAfterToken(old, newValue);
    if (swallowed != null) {
      _dismissed = <SmartRange>[..._dismissed, swallowed.range];
      _parse(old.text);
      // The text stays as it was; listeners hear that the token went.
      notifyListeners();
      return;
    }

    _dismissed = shiftRangesForEdit(_dismissed, old.text, newValue.text);
    _parse(newValue.text);
    super.value = newValue;
  }

  /// The active token a single Backspace right after it would bite into.
  SmartToken? _backspaceAfterToken(
    TextEditingValue old,
    TextEditingValue next,
  ) {
    if (!recognise) return null;
    final selection = old.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    final caret = selection.baseOffset;
    if (caret <= 0 || next.text.length != old.text.length - 1) return null;
    if (next.text !=
        old.text.substring(0, caret - 1) + old.text.substring(caret)) {
      return null;
    }
    for (final token in activeTokens) {
      if (token.end == caret) return token;
    }
    return null;
  }

  void _parse(String text) {
    _links = findLinks(text);
    _tokens = recognise
        ? parseSmartTokens(
            text,
            now: _clock(),
            ctx: _withDismissed(_contextFor()),
          )
        : const <SmartToken>[];
  }

  SmartContext _withDismissed(SmartContext context) => SmartContext(
    projects: context.projects,
    categories: context.categories,
    dismissed: <SmartRange>[...context.dismissed, ..._dismissed],
  );

  static bool _sameTokens(List<SmartToken> a, List<SmartToken> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    if (_tokens.isEmpty && _links.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final composing = value.composing;
    final showComposing =
        withComposing &&
        composing.isValid &&
        !composing.isCollapsed &&
        composing.end <= text.length;

    // Every place the look can change, then one span per piece between them.
    final cuts = <int>{0, text.length};
    for (final token in _tokens) {
      if (token.end <= text.length) cuts.addAll(<int>[token.start, token.end]);
    }
    for (final link in _links) {
      if (link.end <= text.length) cuts.addAll(<int>[link.start, link.end]);
    }
    if (showComposing) cuts.addAll(<int>[composing.start, composing.end]);
    final points = cuts.toList()..sort();

    final children = <TextSpan>[];
    for (var i = 0; i + 1 < points.length; i++) {
      final start = points[i];
      final end = points[i + 1];
      if (start >= end) continue;

      TextStyle piece = const TextStyle();
      final decorations = <TextDecoration>[];
      TextDecorationStyle? decorationStyle;

      for (final token in _tokens) {
        if (token.start <= start && end <= token.end) {
          if (token.isResolved) {
            piece = piece.copyWith(
              backgroundColor: EditorColors.tokenFill,
              color: token.past ? EditorColors.past : EditorColors.bright,
            );
          } else {
            decorations.add(TextDecoration.underline);
            decorationStyle = TextDecorationStyle.dotted;
          }
        }
      }
      for (final link in _links) {
        if (link.start <= start && end <= link.end) {
          decorations.add(TextDecoration.underline);
          piece = piece.copyWith(color: EditorColors.bright);
        }
      }
      if (showComposing &&
          composing.start <= start &&
          end <= composing.end) {
        decorations.add(TextDecoration.underline);
      }
      if (decorations.isNotEmpty) {
        piece = piece.copyWith(
          decoration: TextDecoration.combine(decorations),
          decorationStyle: decorationStyle,
          decorationColor: EditorColors.bright,
        );
      }

      children.add(TextSpan(text: text.substring(start, end), style: piece));
    }

    return TextSpan(style: style, children: children);
  }
}

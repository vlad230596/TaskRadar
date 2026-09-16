import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Renders a note's markdown source.
///
/// ## Which package, and why
///
/// `flutter-migration-plan.md` names `flutter_markdown_plus`, and that is what
/// this uses. The reason is in the name: `flutter_markdown` was the Flutter
/// team's own package and is **discontinued**, and `flutter_markdown_plus` is
/// the maintained fork of exactly that code -- same widget names, same
/// `MarkdownStyleSheet`, same `markdown` parser underneath. See `pubspec.yaml`
/// for why the version resolves against this SDK where several newer packages
/// do not.
///
/// ## Why the whole renderer is one small widget
///
/// So that there is exactly one place where a note turns into pixels. The note
/// list draws a clipped preview and the editor draws a full-height view, and if
/// each reached for `MarkdownBody` itself they would drift into two different
/// typographies for the same text -- and the editor's preview would stop being a
/// preview of what the list shows.
///
/// It also gives the markdown itself a test seam: asserting that `# Заголовок`
/// renders as the text `Заголовок` (and *not* as the literal `# Заголовок`) is a
/// one-line widget test against this class, and it is the only test that can
/// tell "markdown is being rendered" from "markdown is being printed".
class NoteMarkdown extends StatelessWidget {
  const NoteMarkdown({
    required this.content,
    this.selectable = false,
    super.key,
  });

  /// Raw markdown source, as stored. Never empty-able server-side (a `Note`'s
  /// `content` is a non-null column whose empty value is `""`), so the empty
  /// case is a real one and is handled here rather than by every caller.
  final String content;

  /// Whether the rendered text can be selected and copied. On for the editor's
  /// preview -- half of why a note exists is to copy a command out of it -- and
  /// off in the list, where a long-press selecting text would fight with the tap
  /// that opens the note.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (content.trim().isEmpty) {
      return Text(
        'Пусто',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return MarkdownBody(
      data: content,
      selectable: selectable,
      // Markdown's own rule is that a single newline is *not* a line break, and
      // that is wrong for these notes: they are written in a plain multi-line
      // text field, as lists of half-sentences, by someone who pressed Enter
      // because they meant a new line. Without this, "жду кабель\nспросить
      // завтра" renders as one run-on line, which reads as a rendering bug.
      softLineBreak: true,
      styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
        // The default fromTheme puts headlineSmall-sized text on `#`, which in
        // a note preview is bigger than the note's own title. Scaled down so
        // that a heading inside a note stays subordinate to it.
        h1: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        h2: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        h3: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        // No trailing gap after the last block: the card supplies its own
        // padding, and the sheet's default leaves a dead strip at the bottom.
        blockSpacing: 6,
        code: theme.textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
      ),
    );
  }
}

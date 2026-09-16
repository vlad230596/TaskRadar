import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/widgets/note_markdown.dart';

/// The notes are markdown, and this is the only test that can tell markdown
/// being *rendered* from markdown being *printed*.
///
/// That distinction is not academic: a note viewer that shows `# Контекст` and
/// `**важно**` verbatim looks like a plain-text field with stray punctuation,
/// which is precisely what the product does not want -- `../../README.md` calls
/// the notes "markdown-заметки" and they are the project's body.
void main() {
  Future<void> pumpNote(WidgetTester tester, String content) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: NoteMarkdown(content: content)),
        ),
      ),
    );
  }

  testWidgets('a heading renders as text, not as its source', (tester) async {
    await pumpNote(tester, '# Контекст проекта\n\nОбычный абзац.');

    expect(find.text('Контекст проекта'), findsOneWidget);
    expect(find.text('Обычный абзац.'), findsOneWidget);

    // The failure this catches: the renderer silently degrading to a Text.
    expect(find.textContaining('# Контекст'), findsNothing);
  });

  testWidgets('emphasis is consumed, and the words survive', (tester) async {
    await pumpNote(tester, 'это **важно** и *очень*');

    // The markers are gone from the rendered string; the words are not. Asserted
    // through the rendered rich text rather than `find.text`, because emphasis
    // splits a paragraph into spans.
    final rendered = _renderedText(tester);
    expect(rendered, contains('важно'));
    expect(rendered, contains('очень'));
    expect(rendered, isNot(contains('**')));
    expect(rendered, isNot(contains('*очень*')));
  });

  testWidgets('a list becomes list items', (tester) async {
    await pumpNote(tester, '- жду кабель\n- позвонить Петру\n- потом плитка');

    expect(find.text('жду кабель'), findsOneWidget);
    expect(find.text('позвонить Петру'), findsOneWidget);
    expect(find.text('потом плитка'), findsOneWidget);
    expect(find.textContaining('- жду'), findsNothing);
  });

  testWidgets('a single newline is a line break', (tester) async {
    // Markdown's own rule would join these into one line. For a note typed in a
    // plain multi-line field that is wrong -- the Enter was meant -- which is
    // what `softLineBreak` is set for.
    await pumpNote(tester, 'жду кабель\nспросить завтра');

    final body = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(body.softLineBreak, isTrue);

    final rendered = _renderedText(tester);
    expect(rendered, contains('жду кабель'));
    expect(rendered, contains('спросить завтра'));
  });

  testWidgets('a fenced code block keeps its text', (tester) async {
    await pumpNote(tester, 'команда:\n\n```\nnpm run dev\n```');

    expect(find.textContaining('npm run dev'), findsWidgets);
    expect(find.textContaining('```'), findsNothing);
  });

  testWidgets('an empty note says so instead of rendering nothing', (
    tester,
  ) async {
    // "" is a real, reachable value: `createNoteSchema` defaults `content` to it,
    // so every note created from the inline field starts here. A blank card
    // would read as a broken renderer.
    await pumpNote(tester, '');
    expect(find.text('Пусто'), findsOneWidget);

    await pumpNote(tester, '   \n  ');
    expect(find.text('Пусто'), findsOneWidget);
  });

  testWidgets('selectable is off by default and on when asked', (tester) async {
    await pumpNote(tester, 'текст');
    expect(
      tester.widget<MarkdownBody>(find.byType(MarkdownBody)).selectable,
      isFalse,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: NoteMarkdown(content: 'текст', selectable: true)),
      ),
    );
    expect(
      tester.widget<MarkdownBody>(find.byType(MarkdownBody)).selectable,
      isTrue,
    );
  });
}

/// Every piece of text the renderer produced, concatenated.
///
/// `find.text` matches a whole `Text` widget's data, which emphasis and soft
/// breaks split into spans -- so a "the markers are gone" assertion has to look
/// at the flattened output instead.
String _renderedText(WidgetTester tester) {
  final parts = <String>[];

  for (final widget in tester.allWidgets) {
    if (widget is RichText) {
      parts.add(widget.text.toPlainText());
    } else if (widget is Text) {
      parts.add(widget.data ?? widget.textSpan?.toPlainText() ?? '');
    }
  }

  return parts.join('\n');
}

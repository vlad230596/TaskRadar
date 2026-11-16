import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/editor/smart_text_controller.dart';
import 'package:taskradar/widgets/ime_text_controller.dart';

/// The word a keyboard is composing must not be underlined: on the owner's
/// phone the framework's underline came out as an invisible band that cut
/// the descenders of the word ("у" in "буквы"). See [ImeTextController].
///
/// A test cannot see pixels the way the phone's GPU draws them, so it pins
/// the cause instead: no span of a field's text carries an underline while a
/// word is composed, the composed word is marked from behind, and every
/// field in `lib/` gets the controller that does this.
void main() {
  const style = AppText.dictated;

  List<TextSpan> spansOf(TextSpan root) {
    final out = <TextSpan>[];
    root.visitChildren((span) {
      if (span is TextSpan) out.add(span);
      return true;
    });
    return out;
  }

  /// The style each character is drawn with, merged down the tree.
  Iterable<(String, TextStyle)> pieces(TextSpan root) sync* {
    Iterable<(String, TextStyle)> walk(
      TextSpan span,
      TextStyle inherited,
    ) sync* {
      final here = inherited.merge(span.style);
      if (span.text case final text? when text.isNotEmpty) yield (text, here);
      for (final child in span.children ?? const <InlineSpan>[]) {
        if (child is TextSpan) yield* walk(child, here);
      }
    }

    yield* walk(root, const TextStyle());
  }

  Future<TextSpan> composedSpan(
    WidgetTester tester,
    TextEditingController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            autofocus: true,
            maxLines: null,
            style: style,
          ),
        ),
      ),
    );
    await tester.pump();
    // What the field actually lays out and paints, not what the controller
    // would build if asked: `EditableText` decides `withComposing` itself.
    final editable = tester.allRenderObjects.whereType<RenderEditable>().single;
    return editable.text! as TextSpan;
  }

  const text = 'стирает часть буквы';
  final composed = TextEditingValue(
    text: text,
    selection: const TextSelection.collapsed(offset: text.length),
    composing: TextRange(start: text.indexOf('буквы'), end: text.length),
  );

  testWidgets('a composed word is tinted behind, not underlined', (
    tester,
  ) async {
    final controller = ImeTextController()..value = composed;
    final span = await composedSpan(tester, controller);

    for (final s in spansOf(span)) {
      final decoration = s.style?.decoration;
      expect(
        decoration == null || decoration == TextDecoration.none,
        isTrue,
        reason: 'no underline may cross the letters being typed',
      );
    }
    final word = pieces(span).singleWhere((p) => p.$1 == 'буквы').$2;
    expect(word.backgroundColor, isNotNull);
    expect(word.backgroundColor!.a, lessThan(0.5));
    expect(word.color, style.color);
    final rest = pieces(span).firstWhere((p) => p.$1.startsWith('стирает')).$2;
    expect(rest.backgroundColor, isNull);
  });

  testWidgets('the task editor\'s controller marks it the same way', (
    tester,
  ) async {
    // A link in the text takes SmartTextController past the plain path and
    // into its own span builder.
    const linked = 'см. https://example.com и буквы';
    final controller = SmartTextController(text: linked, recognise: false)
      ..value = TextEditingValue(
        text: linked,
        selection: const TextSelection.collapsed(offset: linked.length),
        composing: TextRange(
          start: linked.indexOf('буквы'),
          end: linked.length,
        ),
      );
    final span = await composedSpan(tester, controller);

    final word = pieces(span).singleWhere((p) => p.$1 == 'буквы').$2;
    expect(word.decoration, anyOf(isNull, TextDecoration.none));
    expect(word.backgroundColor, isNotNull);
    // The link keeps its underline: it is not being typed.
    final link = pieces(span).singleWhere((p) => p.$1.contains('https')).$2;
    expect(link.decoration, TextDecoration.underline);
  });

  test('every field in lib/ uses ImeTextController', () {
    final offenders = <String>[];
    final construction = RegExp(r'(?<![\w.])TextEditingController\(');
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (!line.startsWith('//') && construction.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'construct ImeTextController instead: the framework controller '
          'underlines the word being typed, and that underline cut letters '
          'on the phone',
    );
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/overflow_fade_text.dart';

/// A clipped title has to say that it was clipped (F15): a fade over the last
/// visible line, and "ещё N строк" under it.
void main() {
  Future<void> pump(WidgetTester tester, String text, {int maxLines = 3}) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 200,
              child: OverflowFadeText(
                text,
                maxLines: maxLines,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }

  final long = List<String>.filled(40, 'слово').join(' ');

  testWidgets('text that fits is drawn plainly', (tester) async {
    await pump(tester, 'Купить лампочки');

    expect(find.text('Купить лампочки'), findsOneWidget);
    expect(find.textContaining('ещё'), findsNothing);
    expect(find.byType(ShaderMask), findsNothing);
  });

  testWidgets('text that does not fit fades and counts what is hidden', (
    tester,
  ) async {
    await pump(tester, long);

    final title = tester.widget<Text>(find.text(long));
    expect(title.maxLines, 3);
    expect(find.byType(ShaderMask), findsOneWidget);
    expect(find.textContaining(RegExp(r'^ещё \d+ строк')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the count follows maxLines', (tester) async {
    await pump(tester, long);
    final atThree = _hidden(tester);

    await pump(tester, long, maxLines: 5);
    expect(_hidden(tester), atThree - 2);
  });

  test('the Russian plural has three forms', () {
    expect(linesWord(1), 'строка');
    expect(linesWord(2), 'строки');
    expect(linesWord(4), 'строки');
    expect(linesWord(5), 'строк');
    expect(linesWord(11), 'строк');
    expect(linesWord(12), 'строк');
    expect(linesWord(21), 'строка');
    expect(linesWord(22), 'строки');
    expect(linesWord(25), 'строк');
  });
}

int _hidden(WidgetTester tester) {
  final hint = tester.widget<Text>(find.textContaining(RegExp(r'^ещё \d+')));
  return int.parse(RegExp(r'\d+').firstMatch(hint.data!)!.group(0)!);
}

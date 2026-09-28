import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/screens/plan_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/mode_title.dart';

import 'support/acceptance_fonts.dart';
import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_settings_store.dart';

/// A mode's name never breaks inside the word.
///
/// With the test's fallback font every glyph is a square and the widths mean
/// nothing, so the real Unbounded is loaded: "Планирование" at 375 px is a
/// question about *that* face's metrics.
void main() {
  setUpAll(loadAcceptanceFonts);

  /// One line of the mode style is ~1.2 of its size; two lines would be ~2.4.
  void expectOneLine(WidgetTester tester, String text, {double scale = 1}) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
    expect(
      paragraph.size.height,
      lessThan(AppText.mode.fontSize! * scale * 1.8),
    );
  }

  Future<void> pumpPlanHeader(
    WidgetTester tester, {
    double width = 375,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final backend = FakeBackend()..alwaysRespond(<dynamic>[]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 812),
              textScaler: TextScaler.linear(textScale),
            ),
            child: const Scaffold(body: SafeArea(child: PlanHeader())),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('"Планирование" is one line in the plan header at 375 px', (
    tester,
  ) async {
    await pumpPlanHeader(tester);

    expect(tester.takeException(), isNull);
    expectOneLine(tester, 'Планирование');
    // ...and inside the header, not under its buttons.
    final title = tester.getRect(find.byType(ModeTitle));
    expect(title.right, lessThanOrEqualTo(375 - 16));
  });

  testWidgets('with large system text it scales down instead of wrapping', (
    tester,
  ) async {
    await pumpPlanHeader(tester, width: 320, textScale: 1.4);

    expect(tester.takeException(), isNull);
    expectOneLine(tester, 'Планирование', scale: 1.4);
    final rendered = tester.getRect(find.text('Планирование'));
    final slot = tester.getRect(find.byType(ModeTitle));
    // The FittedBox scaled it: the word's painted width is the slot's.
    expect(rendered.width, lessThanOrEqualTo(slot.width + 0.5));
  });

  testWidgets('ModeTitle in a narrow slot scales, never breaks the word', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 90, child: ModeTitle('Планирование')),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expectOneLine(tester, 'Планирование');
    expect(tester.getRect(find.text('Планирование')).width, lessThan(91));
  });
}

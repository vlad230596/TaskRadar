import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/screens/archive_screen.dart';
import 'package:taskradar/screens/inbox_screen.dart';
import 'package:taskradar/screens/pick_screen.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/screens/scopes_screen.dart';
import 'package:taskradar/screens/settings_screen.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/screens/task_editor_screen.dart';
import 'package:taskradar/widgets/glance.dart';

import 'support/acceptance_fonts.dart';
import 'support/layout_bench.dart';

/// Ничего не вылезает за свои границы — на каждом ключевом экране, на
/// телефонах от 320 до 412 dp и на планшете/десктопе, при крупном шрифте
/// системы.
///
/// Владелец прислал снимок, где точки «В работе» уходили за край тёмной
/// полоски, а на плитках проектов точки наезжали на «58 д» и срезали вторую
/// строку задачи пополам. Ни одно из этого не было ошибкой Flutter в релизе —
/// поэтому кроме ошибок переполнения [LayoutBench.pumpAndAudit] проверяет
/// геометрию сам (см. `support/layout_audit.dart`).
///
/// Шрифты — настоящие (`loadAcceptanceFonts`): тестовый шрифт по умолчанию
/// другой ширины, и на нём тесно было бы не там, где у владельца.
void main() {
  setUpAll(loadAcceptanceFonts);

  const sizes = <String, Size>{
    '320x568': Size(320, 568),
    '360x740': Size(360, 740),
    '393x851': Size(393, 851),
    '412x915': Size(412, 915),
    '800x1280': Size(800, 1280),
    '1440x900': Size(1440, 900),
  };
  const scales = <double>[1.0, 1.3, 1.6, 2.0];

  final screens = <String, _Screen>{
    'plan list': _Screen(
      (_) => const ShellScreen(),
      prepare: (b) => b.settings
        ..appMode = 'plan'
        ..planLayout = 'list',
    ),
    'plan tiles, all scopes': _Screen(
      (_) => const ShellScreen(),
      prepare: (b) => b.settings
        ..appMode = 'plan'
        ..planLayout = 'tiles',
    ),
    'plan tiles, one scope': _Screen(
      (_) => const ShellScreen(),
      singleScope: true,
      prepare: (b) => b.settings
        ..appMode = 'plan'
        ..planLayout = 'tiles',
    ),
    'work': _Screen(
      (_) => const ShellScreen(),
      prepare: (b) => b.settings.appMode = 'work',
    ),
    'history': _Screen(
      (_) => const ShellScreen(),
      prepare: (b) => b.settings.appMode = 'history',
    ),
    'project': _Screen((b) => ProjectScreen(projectId: b.homeProjectId)),
    'project notes': _Screen(
      (b) => ProjectScreen(projectId: b.homeProjectId),
      then: (tester) async {
        final tab = find.textContaining('Заметки');
        if (tab.evaluate().isNotEmpty) await tester.tap(tab.first);
      },
    ),
    'task editor': _Screen(
      (b) => TaskEditor(projectId: b.homeProjectId, taskId: b.richTaskId),
    ),
    'inbox': _Screen((_) => const InboxScreen()),
    'pick': _Screen((_) => const PickScreen()),
    'archive': _Screen((_) => const ArchiveScreen()),
    'scopes': _Screen((_) => const ScopesScreen()),
    'settings': _Screen((_) => const SettingsScreen()),
  };

  for (final MapEntry(key: name, value: screen) in screens.entries) {
    group(name, () {
      for (final MapEntry(key: sizeName, value: size) in sizes.entries) {
        for (final scale in scales) {
          // Wide windows are mouse-and-keyboard: a large system font there is
          // a browser zoom, which the matrix covers well enough at 1.3.
          if (size.width >= 800 && scale > 1.3) continue;

          testWidgets('$sizeName @ ${scale}x', (tester) async {
            final bench = LayoutBench(singleScope: screen.singleScope);
            screen.prepare?.call(bench);
            final problems = await bench.pumpAndAudit(
              tester,
              screen.build(bench),
              size: size,
              textScale: scale,
              then: screen.then,
            );
            expect(
              problems,
              isEmpty,
              reason:
                  '$name at $sizeName, text ${scale}x:\n'
                  '${problems.join('\n---\n')}',
            );
          });
        }
      }
    });
  }

  // The owner's screenshot, checked by name rather than only through the
  // generic audit: a 412 dp phone, the system font at 130 %, the planning
  // board as tiles, fifteen tasks in the working set.
  group('the screenshot', () {
    for (final scale in <double>[1.0, 1.3, 1.6]) {
      for (final width in <double>[360, 412]) {
        testWidgets('tiles at ${width.toInt()} dp @ ${scale}x', (tester) async {
          final bench = LayoutBench();
          bench.settings
            ..appMode = 'plan'
            ..planLayout = 'tiles';
          final problems = await bench.pumpAndAudit(
            tester,
            const ShellScreen(),
            size: Size(width, 915),
            textScale: scale,
            check: _screenshotChecks,
          );
          expect(problems, isEmpty, reason: problems.join('\n'));
        });
      }
    }
  });
}

/// The dots on each tile end before its age label, and the dots of the
/// "В работе" strip stay inside the strip and clear of its chevron.
List<String> _screenshotChecks(WidgetTester tester) {
  final problems = <String>[];
  Rect rectOf(Element e) {
    final box = e.renderObject! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  final strips = find.byType(TaskDots).evaluate().toList();
  if (strips.isEmpty) problems.add('no TaskDots on the board');
  for (final strip in strips) {
    final card = find.ancestor(
      of: find.byWidget(strip.widget),
      matching: find.byType(Material),
    );
    final cardRect = rectOf(card.first.evaluate().first);
    final age = find.descendant(
      of: card.first,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Text && RegExp(r'^\d+ (д|нед|мес|г)').hasMatch(w.data ?? ''),
      ),
    );
    final dots = find.descendant(
      of: find.byWidget(strip.widget),
      matching: find.byType(Container),
    );
    for (final dot in dots.evaluate()) {
      final r = rectOf(dot);
      if (!cardRect.contains(r.topLeft) || !cardRect.contains(r.bottomRight)) {
        problems.add('a dot at $r is outside its tile $cardRect');
      }
      for (final label in age.evaluate()) {
        final l = rectOf(label);
        if (r.overlaps(l)) problems.add('a dot at $r overlaps the age at $l');
      }
    }
  }

  final bar = find.ancestor(
    of: find.text('В работе'),
    matching: find.byType(Material),
  );
  final barRect = rectOf(bar.first.evaluate().first);
  final chevron = rectOf(
    find
        .descendant(of: bar.first, matching: find.byIcon(Icons.chevron_right))
        .evaluate()
        .first,
  );
  final amber = find.descendant(
    of: bar.first,
    matching: find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).shape == BoxShape.circle,
    ),
  );
  if (amber.evaluate().isEmpty) problems.add('no dots in the strip');
  for (final dot in amber.evaluate()) {
    final r = rectOf(dot);
    if (r.right > chevron.left) {
      problems.add('a strip dot at $r runs into the chevron at $chevron');
    }
    if (r.right > barRect.right) {
      problems.add('a strip dot at $r is outside the strip $barRect');
    }
  }
  return problems;
}

class _Screen {
  const _Screen(
    this.build, {
    this.prepare,
    this.then,
    this.singleScope = false,
  });

  final Widget Function(LayoutBench bench) build;
  final void Function(LayoutBench bench)? prepare;
  final Future<void> Function(WidgetTester tester)? then;
  final bool singleScope;
}

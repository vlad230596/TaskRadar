import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/checklist_item.dart';
import 'package:taskradar/theme/tokens.dart';
import 'package:taskradar/widgets/editor/checklist_section.dart';

/// The task editor's checklist section (`design/task-editor-spec.md` §6,
/// WP5), driven the way the editor drives it: a parent that holds the list
/// and passes every `onChanged` back.
void main() {
  ChecklistItem item(String id, String text, {bool done = false}) =>
      ChecklistItem(id: id, text: text, done: done);

  late List<ChecklistItem> list;
  late List<String> toggled;
  late int changes;

  setUp(() {
    toggled = <String>[];
    changes = 0;
  });

  Future<void> pump(
    WidgetTester tester,
    List<ChecklistItem> initial, {
    bool withToggle = false,
    bool enabled = true,
  }) async {
    list = initial;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: AppColors.voiceBackground,
          body: StatefulBuilder(
            builder: (context, setState) => ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                ChecklistSection(
                  items: list,
                  enabled: enabled,
                  onChanged: (next) => setState(() {
                    changes++;
                    list = next;
                  }),
                  onToggle: withToggle ? toggled.add : null,
                ),
                TextButton(
                  key: const ValueKey<String>('start'),
                  onPressed: () =>
                      setState(() => list = ChecklistSection.withNewItem(list)),
                  child: const Text('Список'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder field(String id) =>
      find.byKey(ValueKey<String>('checklist-field-$id'));

  EditableText editable(WidgetTester tester, String id) => tester.widget(
    find.descendant(of: field(id), matching: find.byType(EditableText)),
  );

  String progress(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const ValueKey<String>('checklist-progress')))
      .data!;

  testWidgets('an empty list draws nothing; the chip starts one with the '
      'caret in it', (tester) async {
    await pump(tester, const <ChecklistItem>[]);
    expect(
      find.byKey(const ValueKey<String>('checklist-section')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey<String>('start')));
    await tester.pump();
    await tester.pump();

    expect(list, hasLength(1));
    expect(list.single.text, '');
    expect(editable(tester, list.single.id).focusNode.hasFocus, isTrue);
    expect(progress(tester), 'СПИСОК · 0/0');
  });

  testWidgets('Enter adds the next item and moves the caret there, like a '
      'shopping list', (tester) async {
    await pump(tester, const <ChecklistItem>[]);
    await tester.tap(find.byKey(const ValueKey<String>('start')));
    await tester.pump();
    await tester.pump();

    final first = list.single.id;
    await tester.enterText(field(first), 'молоко');
    await tester.enterText(field(first), 'молоко\n');
    await tester.pump();
    await tester.pump();

    expect(list.map((i) => i.text), <String>['молоко', '']);
    final second = list[1].id;
    expect(editable(tester, second).focusNode.hasFocus, isTrue);

    await tester.enterText(field(second), 'хлеб');
    await tester.pump();
    expect(list.map((i) => i.text), <String>['молоко', 'хлеб']);
    expect(progress(tester), 'СПИСОК · 0/2');
  });

  testWidgets('Enter in the middle splits the item at the caret', (
    tester,
  ) async {
    await pump(tester, <ChecklistItem>[item('aaaaaaaa', 'молокохлеб')]);
    await tester.enterText(field('aaaaaaaa'), 'молоко\nхлеб');
    await tester.pump();
    await tester.pump();

    expect(list.map((i) => i.text), <String>['молоко', 'хлеб']);
    expect(list.first.id, 'aaaaaaaa');
    expect(editable(tester, list[1].id).focusNode.hasFocus, isTrue);
    expect(editable(tester, list[1].id).controller.selection.baseOffset, 0);
  });

  testWidgets('Enter in an empty item ends the list there', (tester) async {
    await pump(tester, <ChecklistItem>[
      item('aaaaaaaa', 'молоко'),
      item('bbbbbbbb', ''),
    ]);
    await tester.showKeyboard(field('bbbbbbbb'));
    await tester.enterText(field('bbbbbbbb'), '\n');
    await tester.pump();

    expect(list.map((i) => i.text), <String>['молоко']);
  });

  testWidgets('a pasted list becomes one item per line, markers cut off', (
    tester,
  ) async {
    await pump(tester, <ChecklistItem>[item('aaaaaaaa', '')]);
    await tester.enterText(
      field('aaaaaaaa'),
      '- молоко\n* хлеб\n\n• сыр\n1. яйца\n2) масло',
    );
    await tester.pump();
    await tester.pump();

    expect(list.map((i) => i.text), <String>[
      'молоко',
      'хлеб',
      'сыр',
      'яйца',
      'масло',
    ]);
    expect(list.first.id, 'aaaaaaaa');
    expect(list.map((i) => i.id).toSet(), hasLength(5));
    expect(editable(tester, list.last.id).focusNode.hasFocus, isTrue);
  });

  testWidgets('ticking an item reports the ticked list; done items stay in '
      'place, struck through', (tester) async {
    await pump(tester, <ChecklistItem>[
      item('aaaaaaaa', 'молоко'),
      item('bbbbbbbb', 'хлеб'),
    ]);
    expect(progress(tester), 'СПИСОК · 0/2');

    await tester.tap(
      find.byKey(const ValueKey<String>('checklist-box-aaaaaaaa')),
    );
    await tester.pumpAndSettle();

    expect(list.first.done, isTrue);
    expect(list.map((i) => i.id), <String>['aaaaaaaa', 'bbbbbbbb']);
    expect(progress(tester), 'СПИСОК · 1/2');
    expect(
      editable(tester, 'aaaaaaaa').style.decoration,
      TextDecoration.lineThrough,
    );
    expect(toggled, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey<String>('checklist-box-aaaaaaaa')),
    );
    await tester.pumpAndSettle();
    expect(list.first.done, isFalse);
  });

  testWidgets('an existing task: a tick also goes to onToggle, at once', (
    tester,
  ) async {
    await pump(tester, <ChecklistItem>[
      item('aaaaaaaa', 'молоко'),
    ], withToggle: true);

    await tester.tap(
      find.byKey(const ValueKey<String>('checklist-box-aaaaaaaa')),
    );
    await tester.pumpAndSettle();

    expect(toggled, <String>['aaaaaaaa']);
    expect(list.single.done, isTrue);
    // A tick alone is not an unsaved edit.
    expect(
      ChecklistSection.differsInContent(list, <ChecklistItem>[
        item('aaaaaaaa', 'молоко'),
      ]),
      isFalse,
    );
  });

  testWidgets('the remove button of the focused row removes it', (
    tester,
  ) async {
    await pump(tester, <ChecklistItem>[
      item('aaaaaaaa', 'молоко'),
      item('bbbbbbbb', 'хлеб'),
    ]);
    expect(
      find.byKey(const ValueKey<String>('checklist-remove-bbbbbbbb')),
      findsNothing,
    );
    await tester.showKeyboard(field('bbbbbbbb'));
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('checklist-remove-bbbbbbbb')),
    );
    await tester.pump();
    await tester.pump();

    expect(list.map((i) => i.id), <String>['aaaaaaaa']);
    expect(editable(tester, 'aaaaaaaa').focusNode.hasFocus, isTrue);
  });

  testWidgets('swiping a row away removes it', (tester) async {
    await pump(tester, <ChecklistItem>[
      item('aaaaaaaa', 'молоко'),
      item('bbbbbbbb', 'хлеб'),
    ]);
    await tester.drag(
      find.byKey(const ValueKey<String>('checklist-box-aaaaaaaa')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(list.map((i) => i.id), <String>['bbbbbbbb']);
  });

  testWidgets('Backspace in an empty item removes it and goes up', (
    tester,
  ) async {
    await pump(tester, <ChecklistItem>[
      item('aaaaaaaa', 'молоко'),
      item('bbbbbbbb', ''),
    ]);
    await tester.showKeyboard(field('bbbbbbbb'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    await tester.pump();

    expect(list.map((i) => i.id), <String>['aaaaaaaa']);
    expect(editable(tester, 'aaaaaaaa').focusNode.hasFocus, isTrue);
  });

  testWidgets('a blank item left behind goes away; the section with it', (
    tester,
  ) async {
    await pump(tester, const <ChecklistItem>[]);
    await tester.tap(find.byKey(const ValueKey<String>('start')));
    await tester.pump();
    await tester.pump();
    expect(list, hasLength(1));

    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    await tester.pump();

    expect(list, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('checklist-section')),
      findsNothing,
    );
  });

  testWidgets('"+ пункт" adds an empty item with the caret', (tester) async {
    await pump(tester, <ChecklistItem>[item('aaaaaaaa', 'молоко')]);
    await tester.tap(find.byKey(const ValueKey<String>('checklist-add')));
    await tester.pump();
    await tester.pump();

    expect(list, hasLength(2));
    expect(editable(tester, list.last.id).focusNode.hasFocus, isTrue);
  });

  testWidgets('dragging the handle reorders', (tester) async {
    await pump(tester, <ChecklistItem>[
      item('aaaaaaaa', 'молоко'),
      item('bbbbbbbb', 'хлеб'),
      item('cccccccc', 'сыр'),
    ]);
    final handle = find.descendant(
      of: find.byKey(const ValueKey<String>('aaaaaaaa')),
      matching: find.byIcon(Icons.drag_indicator),
    );
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 15));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    expect(list.first.id, isNot('aaaaaaaa'));
    expect(list.map((i) => i.id).toSet(), <String>{
      'aaaaaaaa',
      'bbbbbbbb',
      'cccccccc',
    });
  });

  testWidgets('the menu removes the ticked items, or the whole list', (
    tester,
  ) async {
    await pump(tester, <ChecklistItem>[
      item('aaaaaaaa', 'молоко', done: true),
      item('bbbbbbbb', 'хлеб'),
    ]);
    await tester.tap(find.byKey(const ValueKey<String>('checklist-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Убрать отмеченные'));
    await tester.pumpAndSettle();
    expect(list.map((i) => i.id), <String>['bbbbbbbb']);

    await tester.tap(find.byKey(const ValueKey<String>('checklist-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить список'));
    await tester.pumpAndSettle();
    expect(list, isEmpty);
    expect(
      find.byKey(const ValueKey<String>('checklist-section')),
      findsNothing,
    );
  });

  testWidgets('read-only: no ticking, no menu, no adding', (tester) async {
    await pump(tester, <ChecklistItem>[
      item('aaaaaaaa', 'молоко'),
    ], enabled: false);
    await tester.tap(
      find.byKey(const ValueKey<String>('checklist-box-aaaaaaaa')),
    );
    await tester.pumpAndSettle();
    expect(changes, 0);
    expect(find.byKey(const ValueKey<String>('checklist-menu')), findsNothing);
    expect(find.byKey(const ValueKey<String>('checklist-add')), findsNothing);
  });

  testWidgets('a list changed by the editor shows the new texts', (
    tester,
  ) async {
    await pump(tester, <ChecklistItem>[item('aaaaaaaa', 'молоко')]);
    // The parent replaces the list (e.g. the saved row came back).
    final state = tester.state<State<StatefulWidget>>(
      find.byType(StatefulBuilder),
    );
    // ignore: invalid_use_of_protected_member
    state.setState(() => list = <ChecklistItem>[item('aaaaaaaa', 'кефир')]);
    await tester.pump();
    expect(editable(tester, 'aaaaaaaa').controller.text, 'кефир');
  });

  group('helpers', () {
    test('forSave trims, drops blanks, clamps to 500', () {
      final saved = ChecklistSection.forSave(<ChecklistItem>[
        item('aaaaaaaa', '  молоко '),
        item('bbbbbbbb', '   '),
        item('cccccccc', 'x' * 600, done: true),
      ]);
      expect(saved.map((i) => i.id), <String>['aaaaaaaa', 'cccccccc']);
      expect(saved.first.text, 'молоко');
      expect(saved.last.text, hasLength(500));
      expect(saved.last.done, isTrue);
    });

    test(
      'differsInContent: text, order and membership count, ticks do not',
      () {
        final saved = <ChecklistItem>[
          item('aaaaaaaa', 'молоко'),
          item('bbbbbbbb', 'хлеб'),
        ];
        expect(ChecklistSection.differsInContent(saved, saved), isFalse);
        expect(
          ChecklistSection.differsInContent(<ChecklistItem>[
            item('aaaaaaaa', 'молоко', done: true),
            item('bbbbbbbb', 'хлеб'),
            item('cccccccc', ' '),
          ], saved),
          isFalse,
        );
        expect(
          ChecklistSection.differsInContent(saved.reversed.toList(), saved),
          isTrue,
        );
        expect(
          ChecklistSection.differsInContent(<ChecklistItem>[
            item('aaaaaaaa', 'кефир'),
            item('bbbbbbbb', 'хлеб'),
          ], saved),
          isTrue,
        );
        expect(
          ChecklistSection.differsInContent(const <ChecklistItem>[], null),
          isFalse,
        );
        expect(ChecklistSection.differsInContent(saved, null), isTrue);
      },
    );

    test('splitLines cuts markers and blank lines', () {
      expect(
        ChecklistSection.splitLines('- a\r\n[ ] b\n[x] c\n\n  10. d\n☐ e\nf'),
        <String>['a', 'b', 'c', 'd', 'e', 'f'],
      );
    });
  });

  group('ChecklistProgressBadge', () {
    Future<void> badge(WidgetTester tester, List<ChecklistItem>? items) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: ChecklistProgressBadge(items: items)),
          ),
        );

    testWidgets('nothing without a checklist', (tester) async {
      await badge(tester, null);
      expect(find.byType(Text), findsNothing);
      await badge(tester, const <ChecklistItem>[]);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('"2/3", green once complete', (tester) async {
      await badge(tester, <ChecklistItem>[
        item('aaaaaaaa', 'a', done: true),
        item('bbbbbbbb', 'b', done: true),
        item('cccccccc', 'c'),
      ]);
      expect(find.text('2/3'), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);

      await badge(tester, <ChecklistItem>[item('aaaaaaaa', 'a', done: true)]);
      expect(find.text('1/1'), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('1/1')).style!.color,
        AppColors.done,
      );
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/task_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/theme/tokens.dart';
import 'package:taskradar/widgets/ai_tidy.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_history_backend.dart';
import 'support/fake_project_backend.dart';

/// The task screen as variant A draws it: a field that sizes to its text, the
/// chips under it, one "Взять в работу" button, a 38 px status control and a
/// folded note.
///
/// What the screen *writes* (title, note, status, delete) is covered by
/// `project_screen_test.dart`, and the life-of-task block by
/// `task_life_test.dart`; this file checks the layout and the new controls.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late String projectId;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    FakeHistoryBackend(backend);
    projectId = server.addProject(name: 'Дом', id: 'prj_dom');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpTask(
    WidgetTester tester,
    String taskId, {
    TidyText? onTidy,
  }) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
          deviceTimeZoneNameProvider.overrideWith(
            (ref) async => 'Europe/Moscow',
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TaskScreen(
            projectId: projectId,
            taskId: taskId,
            onTidy: onTidy,
          ),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  Finder titleField() => find.byType(TextField).first;

  testWidgets('the field sizes to its text, two lines at the least', (
    tester,
  ) async {
    final short = server.addTask(projectId: projectId, title: 'Купить');
    await pumpTask(tester, short);

    final field = tester.widget<TextField>(titleField());
    expect(field.style?.fontSize, 16.5);
    expect(field.minLines, 2);
    expect(field.maxLines, isNull);
    expect(field.expands, isFalse);

    // Two lines of 16.5 px, not the old 252 px box.
    final shortHeight = tester.getSize(titleField()).height;
    expect(shortHeight, lessThan(80));

    // ...and a long one grows rather than scrolling inside itself.
    await tester.enterText(titleField(), 'Посмотреть, почему не работает ' * 8);
    await tester.pump();
    expect(tester.getSize(titleField()).height, greaterThan(shortHeight));
    expect(tester.takeException(), isNull);
  });

  testWidgets('"Причесать" is always there, beside the microphone', (
    tester,
  ) async {
    final id = server.addTask(projectId: projectId, title: 'купить кабель');
    await pumpTask(tester, id);

    expect(find.text('Причесать'), findsOneWidget);
    // The microphone moved from the bottom bar into the card; the bar is only
    // "Сохранить" now.
    expect(find.byTooltip('Дописать голосом'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Сохранить'), findsOneWidget);
  });

  testWidgets('"Причесать" rewrites the title and the note through the hook', (
    tester,
  ) async {
    final id = server.addTask(projectId: projectId, title: 'купить кабель');
    TaskText? seen;
    await pumpTask(
      tester,
      id,
      onTidy: (current) async {
        seen = current;
        return (title: 'Купить кабель', description: 'Два метра.');
      },
    );

    await tester.tap(find.text('Причесать'));
    await settle(tester);

    expect(seen, (title: 'купить кабель', description: null));
    expect(
      tester.widget<TextField>(titleField()).controller!.text,
      'Купить кабель',
    );
    // The description is half the answer, so the note unfolds to show it.
    expect(find.text('Два метра.'), findsOneWidget);
  });

  testWidgets(
    '"Причесать" in the app: the model, as task_tidy, from the text',
    (tester) async {
      final id = server.addTask(
        projectId: projectId,
        title: 'ну купить кабель',
        description: 'два метра',
      );
      final parses = <Map<String, dynamic>>[];
      backend.on('POST', '/dictation/parse', (match) {
        parses.add(match.body);
        return sseResponse(<String>[
          sseEvent('accepted'),
          sseEvent('result', <String, dynamic>{
            'title': 'Купить кабель',
            'description': 'Длина два метра.',
          }),
        ]);
      });
      await pumpTask(tester, id);

      await tester.tap(find.text('Причесать'));
      await settle(tester);
      expect(parses.single['kind'], 'task_tidy');
      // One source: the title, then the note.
      expect(parses.single['text'], 'ну купить кабель\nдва метра');

      await tester.tap(find.text('Готово'));
      await settle(tester);

      expect(
        tester.widget<TextField>(titleField()).controller!.text,
        'Купить кабель',
      );
      await settle(tester);
      expect(find.byType(AiTidyScreen), findsNothing);
      expect(
        find.widgetWithText(TextField, 'Длина два метра.'),
        findsOneWidget,
      );
      // Not saved behind the user's back: "Сохранить" does that.
      expect(server.tasks.single['title'], 'ну купить кабель');
    },
  );

  testWidgets('"Взять в работу" takes the task, then offers the way back', (
    tester,
  ) async {
    final id = server.addTask(projectId: projectId, title: 'Вентилятор');
    await pumpTask(tester, id);

    final take = find.widgetWithText(OutlinedButton, 'Взять в работу');
    expect(take, findsOneWidget);
    expect(tester.getSize(take).height, 48);

    await tester.tap(take);
    await settle(tester);

    expect(server.tasks.single['focusedAt'], isNotNull);
    final drop = find.widgetWithText(
      FilledButton,
      'В работе · убрать из набора',
    );
    expect(drop, findsOneWidget);
    expect(
      tester.widget<FilledButton>(drop).style?.backgroundColor?.resolve({}),
      AppColors.indigo,
    );

    await tester.tap(drop);
    await settle(tester);

    expect(server.tasks.single['focusedAt'], isNull);
    expect(find.text('Взять в работу'), findsOneWidget);
  });

  testWidgets('the status control says "Открыта", not "В очереди"', (
    tester,
  ) async {
    final id = server.addTask(projectId: projectId, title: 'Вентилятор');
    await pumpTask(tester, id);

    expect(find.text('Открыта'), findsOneWidget);
    expect(find.text('Блокер'), findsOneWidget);
    expect(find.text('Сделано'), findsOneWidget);
    expect(find.text('В очереди'), findsNothing);
    expect(find.textContaining('очеред'), findsNothing);

    expect(tester.getSize(find.text('Открыта')).height, lessThan(38));

    await tester.tap(find.text('Сделано'));
    await settle(tester);
    expect(server.tasks.single['status'], 'done');
  });

  testWidgets('a note is a labelled block at 14 px', (tester) async {
    final id = server.addTask(
      projectId: projectId,
      title: 'Вентилятор',
      description: 'Щиток в коридоре',
    );
    await pumpTask(tester, id);

    expect(find.text('ЗАМЕТКА'), findsOneWidget);
    final note = tester.widget<TextField>(find.byType(TextField).last);
    expect(note.controller!.text, 'Щиток в коридоре');
    expect(note.style?.fontSize, 14);
  });

  testWidgets('the life of the task is one line until asked', (tester) async {
    final id = server.addTask(projectId: projectId, title: 'Вентилятор');
    await pumpTask(tester, id);

    // No journal for this task: the whole life belongs to "open".
    expect(find.textContaining(RegExp(r'^открыта \d+ дн')), findsOneWidget);
    expect(find.text('ЖИЗНЬ ЗАДАЧИ'), findsNothing);
  });

  testWidgets('everything fits a 375 px phone without overflow', (
    tester,
  ) async {
    final id = server.addTask(
      projectId: projectId,
      title: 'Посмотреть, почему не работает вентилятор в туалете',
      status: 'blocked',
      description: 'Щиток в коридоре, автомат второй слева.',
    );
    await pumpTask(tester, id, onTidy: (text) async => text);

    expect(tester.takeException(), isNull);
    // The 16 px gutter.
    expect(tester.getTopLeft(find.byType(TextField).first).dx, greaterThan(16));
  });
}

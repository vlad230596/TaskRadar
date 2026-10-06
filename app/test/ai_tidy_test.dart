import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/api_exception.dart';
import 'package:taskradar/api/dictation_api.dart';
import 'package:taskradar/models/note.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/project_providers.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/note_editor_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/widgets/ai_tidy.dart';
import 'package:taskradar/widgets/project_name_dialog.dart';
import 'package:taskradar/widgets/tidy_progress.dart';

import 'support/fake_backend.dart';

/// "Причесать" (F15): the tidy screen every entry point but the dictation
/// screen opens, the note editor as one of those entry points, and the one
/// text field that has no AI at all.
///
/// ## What is pinned here
///
/// The rule the whole feature rests on: the model works from the source --
/// the text as it was, or as corrected by hand in "Исходник" -- and never from
/// its own previous answer. "Разобрать заново" sends the source again, and
/// "Как надиктовано" hands the source back.
void main() {
  late FakeBackend backend;
  late List<Map<String, dynamic>> parses;

  /// Each request is answered with the next of these, the last one repeated.
  late List<Map<String, dynamic>> answers;

  setUp(() {
    backend = FakeBackend();
    parses = <Map<String, dynamic>>[];
    answers = <Map<String, dynamic>>[];
    backend.on('POST', '/dictation/parse', (match) {
      parses.add(match.body);
      // No answer set: the model fails, as the server says it.
      if (answers.isEmpty) {
        return sseResponse(<String>[
          sseEvent('accepted'),
          sseEvent('error', <String, dynamic>{
            'code': 'model_failed',
            'message': 'Dictation model did not answer',
          }),
        ]);
      }
      final answer = answers[(parses.length - 1).clamp(0, answers.length - 1)];
      return sseResponse(<String>[
        sseEvent('accepted', <String, dynamic>{'kind': match.body['kind']}),
        sseEvent('model_started', <String, dynamic>{'model': 'm'}),
        sseEvent('model_done', <String, dynamic>{'durationMs': 300}),
        sseEvent('validated'),
        sseEvent('result', answer),
      ]);
    });
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpHost(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          deviceTimeZoneNameProvider.overrideWith(
            (ref) async => 'Europe/Moscow',
          ),
        ],
        child: MaterialApp(theme: buildAppTheme(), home: home),
      ),
    );
    await settle(tester);
  }

  group('the tidy screen', () {
    TidyOutcome? outcome;
    var closed = false;

    Future<void> open(
      WidgetTester tester, {
      ParseKind kind = ParseKind.note,
      String source = 'ну значит гвозди и краска',
      String? noteTitle,
      List<TidyProject> projects = const <TidyProject>[],
    }) async {
      outcome = null;
      closed = false;
      await pumpHost(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  outcome = await openAiTidy(
                    context,
                    kind: kind,
                    source: source,
                    noteTitle: noteTitle,
                    projects: projects,
                  );
                  closed = true;
                },
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('открыть'));
      await settle(tester);
    }

    testWidgets('starts at once, from the source, and shows the answer', (
      tester,
    ) async {
      answers.add(<String, dynamic>{
        'title': null,
        'content': '- гвозди\n- краска',
      });

      await open(tester, noteTitle: 'Дача');

      expect(parses.single, <String, dynamic>{
        'text': 'ну значит гвозди и краска',
        'timeZone': 'Europe/Moscow',
        'kind': 'note',
        'noteTitle': 'Дача',
      });
      expect(find.text('Результат AI'), findsOneWidget);
      expect(find.text('- гвозди\n- краска'), findsOneWidget);
      expect(find.byType(TidyProgressCard), findsNothing);
    });

    testWidgets('"Исходник" shows the source, and back', (tester) async {
      answers.add(<String, dynamic>{'content': 'Гвозди и краска.'});
      await open(tester);

      await tester.tap(find.text('Исходник'));
      await settle(tester);
      expect(find.text('ну значит гвозди и краска'), findsOneWidget);
      expect(find.text(tidySourceHint), findsOneWidget);
      expect(find.text('Гвозди и краска.'), findsNothing);

      await tester.tap(find.text('Результат AI'));
      await settle(tester);
      expect(find.text('Гвозди и краска.'), findsOneWidget);
    });

    testWidgets('"Разобрать заново" runs from the source, never the answer', (
      tester,
    ) async {
      answers
        ..add(<String, dynamic>{'content': 'Гвозди и краска.'})
        ..add(<String, dynamic>{'content': 'Гвозди, краска и кисти.'});
      await open(tester);

      // Once as it is: the answer is not fed back in.
      await tester.tap(find.text('Разобрать заново'));
      await settle(tester);
      expect(parses[1]['text'], 'ну значит гвозди и краска');

      // Then with the source corrected by hand.
      await tester.tap(find.text('Исходник'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('tidy-source')),
        'гвозди краска и кисти',
      );
      await tester.tap(find.text('Разобрать заново'));
      await settle(tester);

      expect(parses.map((body) => body['text']), <String>[
        'ну значит гвозди и краска',
        'ну значит гвозди и краска',
        'гвозди краска и кисти',
      ]);
      expect(find.text('Гвозди, краска и кисти.'), findsOneWidget);
    });

    testWidgets('"Как надиктовано" hands back the source, corrected', (
      tester,
    ) async {
      answers.add(<String, dynamic>{'content': 'Гвозди и краска.'});
      await open(tester);

      await tester.tap(find.text('Исходник'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('tidy-source')),
        'гвозди и белая краска',
      );
      await tester.tap(find.text('Как надиктовано'));
      await settle(tester);

      expect(closed, isTrue);
      expect(outcome, isA<TidyKeptSource>());
      expect(outcome!.source, 'гвозди и белая краска');
    });

    testWidgets('"Готово" hands back the answer with the corrections in it', (
      tester,
    ) async {
      answers.add(<String, dynamic>{
        'title': 'Позвонить в сервис',
        'description': 'Про колодки.',
        'parseId': 'dp-7',
      });
      await open(
        tester,
        kind: ParseKind.taskTidy,
        source: 'позвонить в сервис',
      );

      expect(find.text('НАЗВАНИЕ'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Про колодки.'),
        'Про колодки и масло.',
      );
      await tester.tap(find.text('Готово'));
      await settle(tester);

      final accepted = outcome! as TidyAccepted;
      final task = accepted.result as TidiedTask;
      expect(task.title, 'Позвонить в сервис');
      expect(task.description, 'Про колодки и масло.');
      expect(task.parseId, 'dp-7');
    });

    testWidgets('a sandbox line: the suggested project is one tap', (
      tester,
    ) async {
      answers.add(<String, dynamic>{
        'text': 'Купить краску',
        'projectId': 'prj_1',
        'projectName': 'Дача',
      });
      await open(
        tester,
        kind: ParseKind.sandbox,
        source: 'купить краску',
        projects: const <TidyProject>[
          (id: 'prj_1', name: 'Дача'),
          (id: 'prj_2', name: 'Дом'),
        ],
      );

      expect(find.text('Другой проект'), findsOneWidget);
      await tester.tap(find.text('В «Дача»'));
      await settle(tester);

      final accepted = outcome! as TidyAccepted;
      expect(accepted.projectId, 'prj_1');
      expect((accepted.result as TidiedLine).text, 'Купить краску');
    });

    testWidgets('a sandbox line carries its task shape, unless corrected', (
      tester,
    ) async {
      final answer = <String, dynamic>{
        'text': 'Купить краску, белую',
        'title': 'Купить краску',
        'description': 'Белую.',
        'projectId': 'prj_1',
        'projectName': 'Дача',
        'parseId': 'dp-8',
      };
      answers.add(answer);
      await open(
        tester,
        kind: ParseKind.sandbox,
        source: 'купить краску белую',
        projects: const <TidyProject>[(id: 'prj_1', name: 'Дача')],
      );
      await tester.tap(find.text('В «Дача»'));
      await settle(tester);

      final line = (outcome! as TidyAccepted).result as TidiedLine;
      expect(line.hasTaskShape, isTrue);
      expect((line.title, line.description), ('Купить краску', 'Белую.'));
      expect(line.parseId, 'dp-8');

      // Corrected by hand: the split was of other words, so it goes.
      await open(
        tester,
        kind: ParseKind.sandbox,
        source: 'купить краску белую',
        projects: const <TidyProject>[(id: 'prj_1', name: 'Дача')],
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Купить краску, белую'),
        'Купить краску, синюю',
      );
      await tester.tap(find.text('В «Дача»'));
      await settle(tester);
      final edited = (outcome! as TidyAccepted).result as TidiedLine;
      expect(edited.hasTaskShape, isFalse);
      expect(edited.title, 'Купить краску, синюю');
      expect(edited.parseId, 'dp-8');
    });

    testWidgets('an invented date: the answer, with an amber note naming it', (
      tester,
    ) async {
      answers.add(<String, dynamic>{
        'title': 'Созвон с Петей',
        'description': 'В 3.00, обсудить смету.',
        'warnings': <Map<String, dynamic>>[
          <String, dynamic>{'kind': 'invented_date', 'token': '3.00'},
        ],
      });
      await open(
        tester,
        kind: ParseKind.taskTidy,
        source: 'созвон с петей в три ноль обсудить смету',
      );

      expect(
        find.text(
          'AI добавил «3.00», которого не было в тексте — проверь',
          findRichText: true,
        ),
        findsOneWidget,
      );
      // The token is marked, not just named.
      final note = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('tidy-warning')),
          matching: find.byType(Text),
        ),
      );
      final marked = <String>[];
      note.textSpan!.visitChildren((span) {
        if (span is TextSpan && span.style?.backgroundColor != null) {
          marked.add(span.text ?? '');
        }
        return true;
      });
      expect(marked, <String>['«3.00»']);

      // Taking it is the user's call, and "Исходник" is one tap away.
      await tester.tap(find.text('Готово'));
      await settle(tester);
      expect(
        ((outcome! as TidyAccepted).result as TidiedTask).description,
        'В 3.00, обсудить смету.',
      );
    });

    test('warnings are read leniently: none, or only the well-formed', () {
      expect(TidyWarning.listFrom(null), isEmpty);
      expect(TidyWarning.listFrom('invented_date'), isEmpty);
      final read = TidyWarning.listFrom(<dynamic>[
        <String, dynamic>{'kind': 'invented_date', 'token': 'завтра'},
        <String, dynamic>{'kind': 'invented_date'},
        <String, dynamic>{'kind': 'invented_date', 'token': ''},
        42,
      ]);
      expect(read.map((w) => (w.kind, w.token)), <(String, String)>[
        ('invented_date', 'завтра'),
      ]);
    });

    testWidgets('a sandbox line: or another project, picked from the list', (
      tester,
    ) async {
      answers.add(<String, dynamic>{
        'text': 'Купить краску',
        'projectId': null,
      });
      await open(
        tester,
        kind: ParseKind.sandbox,
        source: 'купить краску',
        projects: const <TidyProject>[(id: 'prj_2', name: 'Дом')],
      );

      expect(find.text('Проект не угадан'), findsOneWidget);
      await tester.tap(find.text('Другой проект'));
      await settle(tester);
      await tester.tap(find.text('Дом').last);
      await settle(tester);

      expect((outcome! as TidyAccepted).projectId, 'prj_2');
    });

    testWidgets('a failure keeps the source and offers "Повторить"', (
      tester,
    ) async {
      await open(tester);

      expect(
        find.text('Модель не ответила — попробуйте ещё раз.'),
        findsOneWidget,
      );
      expect(find.text('Повторить'), findsOneWidget);
      expect(find.text('ну значит гвозди и краска'), findsOneWidget);
      // Nothing to accept yet.
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Готово'))
            .onPressed,
        isNull,
      );
    });
  });

  group('the note editor', () {
    Note note({String title = 'Дача', String content = 'ну гвозди краска'}) =>
        Note(
          id: 'note_1',
          projectId: 'prj_1',
          title: title,
          content: content,
          createdAt: '2026-09-20T10:00:00.000Z',
          updatedAt: '2026-09-20T10:00:00.000Z',
        );

    testWidgets('"Причесать" tidies the body as a note, into the draft', (
      tester,
    ) async {
      answers.add(<String, dynamic>{
        'title': null,
        'content': '- гвозди\n- краска',
      });
      await pumpHost(
        tester,
        NoteEditorScreen(projectId: 'prj_1', note: note()),
      );

      await tester.tap(find.byTooltip('Причесать'));
      await settle(tester);
      expect(parses.single['kind'], 'note');
      expect(parses.single['noteTitle'], 'Дача');
      await tester.tap(find.text('Готово'));
      await settle(tester);

      expect(find.byType(NoteEditorScreen), findsOneWidget);
      expect(find.text('- гвозди\n- краска'), findsOneWidget);
      // A draft, not a save: the user says "Сохранить" as for any edit.
      expect(find.text('Заметка · не сохранено'), findsOneWidget);
    });

    testWidgets('saved, the answer takes its record along (F15)', (
      tester,
    ) async {
      final json = <String, dynamic>{
        'id': 'note_1',
        'projectId': 'prj_1',
        'title': 'Дача',
        'content': 'ну гвозди краска',
        'createdAt': '2026-09-20T10:00:00.000Z',
        'updatedAt': '2026-09-20T10:00:00.000Z',
      };
      final patches = <Map<String, dynamic>>[];
      backend
        ..on(
          'GET',
          '/projects/prj_1/notes',
          (_) => jsonResponse(<dynamic>[json]),
        )
        ..on('PATCH', '/notes/note_1', (match) {
          patches.add(match.body);
          return jsonResponse(<String, dynamic>{...json, ...match.body});
        });
      answers.add(<String, dynamic>{
        'title': null,
        'content': '- гвозди\n- краска',
        'parseId': 'dp-9',
      });
      await pumpHost(
        tester,
        // The project's notes loaded underneath, as in the app: the editor
        // is opened from the list, and saves through it.
        Consumer(
          builder: (context, ref, _) {
            ref.watch(projectNotesProvider('prj_1'));
            return NoteEditorScreen(projectId: 'prj_1', note: note());
          },
        ),
      );

      await tester.tap(find.byTooltip('Причесать'));
      await settle(tester);
      await tester.tap(find.text('Готово'));
      await settle(tester);
      await tester.tap(find.byTooltip('Сохранить'));
      await settle(tester);

      expect(patches.single, <String, dynamic>{
        'content': '- гвозди\n- краска',
        'dictationParseId': 'dp-9',
      });
    });

    testWidgets('an empty body has nothing to tidy', (tester) async {
      await pumpHost(
        tester,
        NoteEditorScreen(
          projectId: 'prj_1',
          note: note(content: ''),
        ),
      );
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byIcon(Icons.auto_awesome_outlined),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('the project-name dialog', () {
    testWidgets('has neither a microphone nor "Причесать"', (tester) async {
      await pumpHost(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => askForProjectName(
                  context,
                  title: 'Новый проект',
                  confirmLabel: 'Создать',
                ),
                child: const Text('открыть'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('открыть'));
      await settle(tester);

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.byIcon(Icons.mic_none)),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.byTooltip('Продиктовать')),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.textContaining('Причесать')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.byIcon(Icons.auto_awesome_outlined),
        ),
        findsNothing,
      );
    });
  });

  group('tidyFailureMessage', () {
    test('names the daily limit when the server refuses with 429', () {
      expect(
        tidyFailureMessage(ApiException(429, 'Daily AI request limit reached')),
        contains('лимит'),
      );
    });

    test('sends the user to Settings when the model was retired', () {
      // The stream's `error` event: the class at the top.
      final fromStream = ApiException(502, 'Dictation model did not answer', {
        'code': 'model_failed',
        'cause': 'model_not_found',
        'model': 'vendor/old:free',
      });
      expect(
        tidyFailureMessage(fromStream),
        'Модель «vendor/old:free» недоступна у провайдера — выберите другую '
        'в Настройках.',
      );

      // The JSON reply: the same, under `details`.
      final fromJson = ApiException(502, 'Dictation model did not answer', {
        'error': 'UpstreamModelError',
        'details': {'cause': 'model_not_found'},
      });
      expect(tidyFailureMessage(fromJson), startsWith('Модель недоступна'));
    });

    test('names an empty account and a rate limit', () {
      ApiException failed(String cause) =>
          ApiException(502, 'x', {'code': 'model_failed', 'cause': cause});
      expect(tidyFailureMessage(failed('no_credits')), contains('средства'));
      expect(tidyFailureMessage(failed('rate_limited')), contains('минуту'));
    });

    test('falls back for a class it does not know', () {
      expect(
        tidyFailureMessage(
          ApiException(502, 'x', {'code': 'model_failed', 'cause': 'new_one'}),
        ),
        'Модель не ответила — попробуйте ещё раз.',
      );
    });

    test('keeps "Модель не ответила" for other server errors', () {
      expect(
        tidyFailureMessage(ApiException(502, 'Bad gateway')),
        'Модель не ответила — попробуйте ещё раз.',
      );
    });
  });
}

import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/attachments/clipboard_image.dart';
import 'package:taskradar/attachments/compress.dart';
import 'package:taskradar/domain/outbox_overlay.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/attachment_providers.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/screens/task_editor_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/theme/tokens.dart';
import 'package:taskradar/voice/voice_model.dart';
import 'package:taskradar/widgets/ai_tidy.dart';
import 'package:taskradar/storage/outbox_store.dart';
import 'package:taskradar/widgets/editor/attachment_strip.dart';
import 'package:taskradar/widgets/editor/checklist_section.dart';
import 'package:taskradar/widgets/editor/editor_theme.dart';
import 'package:taskradar/widgets/editor/smart_text_controller.dart';
import 'package:taskradar/widgets/editor/task_draft.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_capture_queue_store.dart';
import 'support/fake_history_backend.dart';
import 'support/fake_outbox_store.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_voice.dart';

/// The task editor (task-editor spec, WP4): one screen to create and to edit
/// a task. The first half is the old task screen's capabilities, carried
/// over; the second is what is new -- creating with a reminder and a
/// category, recognition in the text, the compact sheet.
///
/// What the list writes from its rows is `project_screen_test.dart`; the
/// reminder's day and time pickers are `blocker_reminder_screen_test.dart`;
/// the life-of-task block `task_life_test.dart`.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeOutboxStore outbox;
  late String projectId;
  late _FakeQueue pictures;
  late _FakeClipboard clipboard;

  // A real 1x1 PNG: what a pasted screenshot looks like to the editor.
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  /// 15:00 on Wednesday 11 November 2026: «завтра» is the 12th.
  DateTime clock() => DateTime(2026, 11, 11, 15);

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    outbox = FakeOutboxStore();
    FakeHistoryBackend(backend);
    pictures = _FakeQueue();
    clipboard = _FakeClipboard();
    projectId = server.addProject(name: 'Дом', id: 'prj_dom');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  List<Override> overrides({bool voice = false}) => [
    apiClientProvider.overrideWithValue(backend.client),
    boardSnapshotStoreProvider.overrideWithValue(FakeBoardSnapshotStore()),
    outboxStoreProvider.overrideWithValue(outbox),
    deviceTimeZoneNameProvider.overrideWith((ref) async => 'Europe/Moscow'),
    attachmentQueueProvider.overrideWithValue(pictures),
    imageEncoderProvider.overrideWithValue(null),
    clipboardImageReaderProvider.overrideWithValue(clipboard),
    if (voice) ...[
      voiceRecorderProvider.overrideWithValue(FakeVoiceRecorder()),
      speechRecognizerProvider.overrideWithValue(
        FakeSpeechRecognizer()..text = 'и переходник',
      ),
      voiceModelInstallationProvider.overrideWith(_ReadyModel.new),
      captureQueueStoreProvider.overrideWithValue(FakeCaptureQueueStore()),
    ],
  ];

  void phone(WidgetTester tester, {Size size = const Size(375, 812)}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// An existing task's editor as the home page.
  Future<void> pumpTask(
    WidgetTester tester,
    String taskId, {
    TidyText? onTidy,
    bool voice = false,
  }) async {
    phone(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(voice: voice),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: TaskEditor(
            projectId: projectId,
            taskId: taskId,
            onTidy: onTidy,
            clock: clock,
          ),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  /// A host page with a button that opens [open] -- so that leaving the
  /// editor can be seen.
  Future<void> pumpHost(
    WidgetTester tester,
    void Function(BuildContext context) open, {
    Size size = const Size(375, 812),
  }) async {
    phone(tester, size: size);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: MaterialApp(
          theme: buildAppTheme(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => open(context),
                  child: const Text('открыть'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('открыть'));
    await settle(tester);
  }

  /// A new task's editor, full height, pushed over the host.
  Future<void> pumpNew(WidgetTester tester, {TaskDraft? prefill}) =>
      pumpHost(
        tester,
        (context) => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => TaskEditor(
              projectId: projectId,
              prefill: prefill,
              clock: clock,
            ),
          ),
        ),
      );

  Finder titleField() => find.byType(TextField).first;

  SmartTextController titleController(WidgetTester tester) =>
      tester.widget<TextField>(titleField()).controller!
          as SmartTextController;

  Finder chip(String tooltip) => find.byTooltip(tooltip);

  Finder chipText(String tooltip, String text) =>
      find.descendant(of: chip(tooltip), matching: find.text(text));

  group('an existing task: what the old task screen did', () {
    testWidgets('the title field sizes to its text, two lines at the least', (
      tester,
    ) async {
      final short = server.addTask(projectId: projectId, title: 'Купить');
      await pumpTask(tester, short);

      final field = tester.widget<TextField>(titleField());
      expect(field.style?.fontSize, 22);
      expect(field.minLines, 2);
      expect(field.maxLines, isNull);
      expect(field.expands, isFalse);

      final shortHeight = tester.getSize(titleField()).height;
      // Two lines of 22 px, not a fixed box.
      expect(shortHeight, lessThan(90));

      await tester.enterText(titleField(), 'Посмотреть, почему не работает ' * 8);
      await tester.pump();
      expect(tester.getSize(titleField()).height, greaterThan(shortHeight));
      expect(tester.takeException(), isNull);
    });

    testWidgets('"Причесать" beside the microphone; "Сохранить" only with an '
        'edit', (tester) async {
      final id = server.addTask(projectId: projectId, title: 'купить кабель');
      await pumpTask(tester, id);

      expect(find.text('Причесать'), findsOneWidget);
      expect(find.byTooltip('Дописать голосом'), findsOneWidget);
      // Nothing to save yet: everything else on the screen writes at once.
      expect(find.widgetWithText(FilledButton, 'Сохранить'), findsNothing);

      await tester.enterText(titleField(), 'купить кабель HDMI');
      await tester.pump();
      expect(find.widgetWithText(FilledButton, 'Сохранить'), findsOneWidget);
    });

    testWidgets('"Причесать" is offered only while there is text', (
      tester,
    ) async {
      final id = server.addTask(projectId: projectId, title: 'купить кабель');
      await pumpTask(tester, id);

      await tester.enterText(titleField(), '   ');
      await tester.pump();
      expect(find.text('Причесать'), findsNothing);
      expect(find.byTooltip('Дописать голосом'), findsOneWidget);

      await tester.tap(find.text('+ Описание'));
      await tester.pump();
      expect(find.text('Причесать'), findsNothing);

      final noteField = find.widgetWithText(
        TextField,
        'Кто, что, к какому сроку…',
      );
      await tester.enterText(noteField, 'два метра');
      await tester.pump();
      // The description's own, and the title's (both fields together).
      expect(find.text('Причесать'), findsNWidgets(2));

      await tester.enterText(noteField, '');
      await tester.pump();
      expect(find.text('Причесать'), findsNothing);

      await tester.enterText(titleField(), 'к');
      await tester.pump();
      expect(find.text('Причесать'), findsOneWidget);
    });

    testWidgets('"Причесать" rewrites the title and the description', (
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
      expect(titleController(tester).text, 'Купить кабель');
      expect(find.text('Два метра.'), findsOneWidget);
    });

    testWidgets('"Причесать" in the app: the model, as task_tidy', (
      tester,
    ) async {
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

      await tester.tap(find.text('Причесать').first);
      await settle(tester);
      expect(parses.single['kind'], 'task_tidy');
      expect(parses.single['text'], 'ну купить кабель\nдва метра');

      await tester.tap(find.text('Готово'));
      await settle(tester);

      expect(titleController(tester).text, 'Купить кабель');
      await settle(tester);
      expect(find.byType(AiTidyScreen), findsNothing);
      expect(find.widgetWithText(TextField, 'Длина два метра.'), findsOneWidget);
      // Not saved behind the user's back.
      expect(server.tasks.single['title'], 'ну купить кабель');
    });

    testWidgets('"Причесать", saved: one PATCH of both fields, with the record', (
      tester,
    ) async {
      final id = server.addTask(projectId: projectId, title: 'ну купить кабель');
      backend.on('POST', '/dictation/parse', (match) {
        return sseResponse(<String>[
          sseEvent('accepted'),
          sseEvent('result', <String, dynamic>{
            'title': 'Купить кабель',
            'description': null,
            'parseId': 'dp-11',
          }),
        ]);
      });
      await pumpTask(tester, id);

      await tester.tap(find.text('Причесать'));
      await settle(tester);
      await tester.tap(find.text('Готово'));
      await settle(tester);
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await settle(tester);

      expect(server.patches.single.body, <String, dynamic>{
        'title': 'Купить кабель',
        'description': null,
        'dictationParseId': 'dp-11',
      });
      expect(server.tasks.single['title'], 'Купить кабель');
    });

    testWidgets('"Причесать" on the description alone, as a note', (
      tester,
    ) async {
      final id = server.addTask(
        projectId: projectId,
        title: 'Купить кабель',
        description: 'ну два метра наверно',
      );
      final parses = <Map<String, dynamic>>[];
      backend.on('POST', '/dictation/parse', (match) {
        parses.add(match.body);
        return sseResponse(<String>[
          sseEvent('accepted'),
          sseEvent('result', <String, dynamic>{
            'title': null,
            'content': 'Длина два метра.',
            'parseId': 'dp-21',
          }),
        ]);
      });
      await pumpTask(tester, id);

      expect(find.text('Причесать'), findsNWidgets(2));
      await tester.tap(find.text('Причесать').last);
      await settle(tester);
      expect(parses.single['kind'], 'note');
      expect(parses.single['text'], 'ну два метра наверно');

      await tester.tap(find.text('Готово'));
      await settle(tester);
      await settle(tester);

      expect(titleController(tester).text, 'Купить кабель');
      expect(find.widgetWithText(TextField, 'Длина два метра.'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await settle(tester);
      expect(server.patches.single.body, <String, dynamic>{
        'title': 'Купить кабель',
        'description': 'Длина два метра.',
        'dictationParseId': 'dp-21',
      });
    });

    testWidgets('the description microphone appends the words', (
      tester,
    ) async {
      final id = server.addTask(
        projectId: projectId,
        title: 'Купить кабель',
        description: 'Два метра',
      );
      backend.on('POST', '/dictation/parse', (match) {
        return sseResponse(<String>[
          sseEvent('accepted'),
          sseEvent('result', <String, dynamic>{'content': 'Что-то другое'}),
        ]);
      });
      await pumpTask(tester, id, voice: true);

      await tester.tap(find.byTooltip('Дописать в описание голосом'));
      await settle(tester);
      await tester.tap(find.text('Готово'));
      await settle(tester);
      await tester.tap(find.text('Разобрать'));
      await settle(tester);
      await tester.tap(find.text('Как надиктовано'));
      await settle(tester);
      await tester.tap(find.text('Готово'));
      await settle(tester);
      await settle(tester);

      expect(titleController(tester).text, 'Купить кабель');
      expect(
        find.widgetWithText(TextField, 'Два метра\nи переходник'),
        findsOneWidget,
      );
    });

    group('dictating into the task', () {
      Future<void> dictateAndTidy(
        WidgetTester tester,
        String id,
        Map<String, dynamic> answer,
        List<Map<String, dynamic>> parses,
      ) async {
        backend.on('POST', '/dictation/parse', (match) {
          parses.add(match.body);
          return sseResponse(<String>[
            sseEvent('accepted'),
            sseEvent('result', answer),
          ]);
        });
        await pumpTask(tester, id, voice: true);

        await tester.tap(find.byTooltip('Дописать голосом'));
        await settle(tester);
        await tester.tap(find.text('Готово'));
        await settle(tester);
      }

      testWidgets('"Разобрать": from the task and the words, fills both', (
        tester,
      ) async {
        final id = server.addTask(
          projectId: projectId,
          title: 'Купить кабель',
          description: 'Два метра',
        );
        final parses = <Map<String, dynamic>>[];
        await dictateAndTidy(tester, id, <String, dynamic>{
          'title': 'Купить кабель и переходник',
          'description': 'Кабель два метра.',
          'parseId': 'dp-12',
        }, parses);

        await tester.tap(find.text('Разобрать'));
        await settle(tester);
        expect(parses.single['kind'], 'task_tidy');
        expect(parses.single['text'], 'Купить кабель\nДва метра\nи переходник');
        await tester.tap(find.text('Готово'));
        await settle(tester);
        await settle(tester);

        expect(titleController(tester).text, 'Купить кабель и переходник');
        expect(
          find.widgetWithText(TextField, 'Кабель два метра.'),
          findsOneWidget,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
        await settle(tester);
        expect(server.patches.single.body, <String, dynamic>{
          'title': 'Купить кабель и переходник',
          'description': 'Кабель два метра.',
          'dictationParseId': 'dp-12',
        });
      });

      testWidgets('"Как надиктовано": the words appended to the title', (
        tester,
      ) async {
        final id = server.addTask(projectId: projectId, title: 'Купить кабель');
        final parses = <Map<String, dynamic>>[];
        await dictateAndTidy(tester, id, <String, dynamic>{
          'title': 'Что-то другое',
        }, parses);

        await tester.tap(find.text('Разобрать'));
        await settle(tester);
        await tester.tap(find.text('Как надиктовано'));
        await settle(tester);
        await tester.tap(find.text('Готово'));
        await settle(tester);
        await settle(tester);

        expect(titleController(tester).text, 'Купить кабель и переходник');
        await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
        await settle(tester);
        expect(
          server.patches.single.body.containsKey('dictationParseId'),
          isFalse,
        );
      });
    });

    testWidgets('"Взять в работу" takes the task, then offers the way back', (
      tester,
    ) async {
      final id = server.addTask(projectId: projectId, title: 'Вентилятор');
      await pumpTask(tester, id);

      final take = find.widgetWithText(OutlinedButton, 'Взять в работу');
      await tester.ensureVisible(take);
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

    testWidgets('the status control: Открыта / Блокер / Сделано', (
      tester,
    ) async {
      final id = server.addTask(projectId: projectId, title: 'Вентилятор');
      await pumpTask(tester, id);

      expect(find.text('Открыта'), findsOneWidget);
      expect(find.text('Блокер'), findsOneWidget);
      expect(find.text('Сделано'), findsOneWidget);
      expect(find.textContaining('очеред'), findsNothing);

      await tester.ensureVisible(find.text('Сделано'));
      await tester.tap(find.text('Сделано'));
      await settle(tester);
      expect(server.tasks.single['status'], 'done');
      // A done task has no reminder to set.
      expect(chip('Напоминание'), findsNothing);
    });

    testWidgets('the description is a labelled block at 17 px', (
      tester,
    ) async {
      final id = server.addTask(
        projectId: projectId,
        title: 'Вентилятор',
        description: 'Щиток в коридоре',
      );
      await pumpTask(tester, id);

      expect(find.text('ОПИСАНИЕ'), findsOneWidget);
      final note = tester.widget<TextField>(find.byType(TextField).last);
      expect(note.controller!.text, 'Щиток в коридоре');
      expect(note.style?.fontSize, 17);
    });

    testWidgets('the life of the task is one line until asked', (
      tester,
    ) async {
      final id = server.addTask(projectId: projectId, title: 'Вентилятор');
      await pumpTask(tester, id);

      expect(
        find.textContaining(RegExp(r'^открыта \d+ (день|дн)')),
        findsOneWidget,
      );
      expect(find.text('ЖИЗНЬ ЗАДАЧИ'), findsNothing);
    });

    group('the AI mark', () {
      String addProcessed() {
        final id = server.addTask(
          projectId: projectId,
          title: 'Купить кабель',
          description: 'Два метра.',
        );
        server.tasks.last.addAll(<String, dynamic>{
          'aiSource': 'ну купить кабель два метра',
          'aiKind': 'task',
          'aiResult': <String, dynamic>{
            'title': 'Купить кабель',
            'description': 'Два метра.',
          },
        });
        return id;
      }

      testWidgets('opens the AI screen on the saved answer, asking nothing', (
        tester,
      ) async {
        final parses = <Map<String, dynamic>>[];
        backend.on('POST', '/dictation/parse', (match) {
          parses.add(match.body);
          return sseResponse(<String>[sseEvent('accepted')]);
        });
        await pumpTask(tester, addProcessed());

        await tester.tap(find.text('AI'));
        await settle(tester);

        expect(find.byType(AiTidyScreen), findsOneWidget);
        expect(parses, isEmpty);
        expect(
          find.descendant(
            of: find.byType(AiTidyScreen),
            matching: find.widgetWithText(TextField, 'Купить кабель'),
          ),
          findsOneWidget,
        );
        expect(find.text('Как надиктовано'), findsOneWidget);
      });

      testWidgets('"Как надиктовано" puts the source back', (tester) async {
        await pumpTask(tester, addProcessed());

        await tester.tap(find.text('AI'));
        await settle(tester);
        await tester.tap(find.text('Как надиктовано'));
        await settle(tester);

        expect(titleController(tester).text, 'ну купить кабель два метра');
        expect(find.text('AI'), findsNothing);

        await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
        await settle(tester);
        expect(
          server.patches.every((patch) => !patch.body.containsKey('aiClear')),
          isTrue,
        );
        expect(server.tasks.single['aiSource'], 'ну купить кабель два метра');
      });

      testWidgets('"Причесать" works from the source, not from the answer', (
        tester,
      ) async {
        final parses = <Map<String, dynamic>>[];
        backend.on('POST', '/dictation/parse', (match) {
          parses.add(match.body);
          return sseResponse(<String>[sseEvent('accepted')]);
        });
        await pumpTask(tester, addProcessed());

        await tester.tap(find.text('Причесать').first);
        await settle(tester);
        expect(parses.single['text'], 'ну купить кабель два метра');
      });

      testWidgets('edited by hand after AI, "Причесать" keeps the edit', (
        tester,
      ) async {
        final parses = <Map<String, dynamic>>[];
        backend.on('POST', '/dictation/parse', (match) {
          parses.add(match.body);
          return sseResponse(<String>[sseEvent('accepted')]);
        });
        await pumpTask(tester, addProcessed());

        await tester.enterText(titleField(), 'Купить кабель и вилку');
        await tester.tap(find.text('Причесать').first);
        await settle(tester);
        expect(parses.single['text'], 'Купить кабель и вилку\nДва метра.');
      });
    });

    testWidgets('everything fits a 375 px phone without overflow', (
      tester,
    ) async {
      final id = server.addTask(
        projectId: projectId,
        title: 'Посмотреть, почему не работает вентилятор в туалете',
        status: 'blocked',
        description: 'Щиток в коридоре, автомат второй слева.',
        remindAt: '2026-11-20T00:00:00.000Z',
        remindTime: '10:30',
      );
      await pumpTask(tester, id, onTidy: (text) async => text);

      expect(tester.takeException(), isNull);
      expect(tester.getTopLeft(titleField()).dx, greaterThan(16));
    });

    group('the ⋯ menu', () {
      testWidgets('"Удалить задачу" asks first, then deletes and leaves', (
        tester,
      ) async {
        final id = server.addTask(projectId: projectId, title: 'Лишняя');
        await pumpHost(
          tester,
          (context) =>
              AppRoutes.openTask(context, projectId: projectId, taskId: id),
        );

        await tester.tap(find.byTooltip('Ещё'));
        await settle(tester);
        await tester.tap(find.text('Удалить задачу'));
        await settle(tester);
        expect(find.text('Удалить задачу?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
        await settle(tester);

        expect(server.tasks, isEmpty);
        expect(find.byType(TaskEditor), findsNothing);
      });

      testWidgets('"Вернуть в песочницу" asks, unfiles and leaves', (
        tester,
      ) async {
        final id = server.addTask(projectId: projectId, title: 'Не сюда');
        await pumpHost(
          tester,
          (context) =>
              AppRoutes.openTask(context, projectId: projectId, taskId: id),
        );

        await tester.tap(find.byTooltip('Ещё'));
        await settle(tester);
        await tester.tap(find.text('Вернуть в песочницу'));
        await settle(tester);
        expect(find.text('Вернуть в песочницу?'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, 'Вернуть'));
        await settle(tester);

        expect(server.tasks, isEmpty);
        expect(server.inbox.single['text'], 'Не сюда');
        expect(find.byType(TaskEditor), findsNothing);
      });
    });

    group('«Перенести в проект…»', () {
      Future<void> pumpPushed(WidgetTester tester, String taskId) => pumpHost(
        tester,
        (context) =>
            AppRoutes.openTask(context, projectId: projectId, taskId: taskId),
      );

      testWidgets('the project chip offers the other live projects, and the '
          'task leaves for the one picked', (tester) async {
        server.addProject(name: 'Дача', id: 'prj_dacha');
        server.addProject(
          name: 'Старое',
          id: 'prj_old',
          archivedAt: FakeProjectBackend.archivedAtStamp,
        );
        server.addTask(projectId: 'prj_dacha', title: 'Скосить траву');
        final id = server.addTask(projectId: projectId, title: 'Покрасить забор');
        await pumpPushed(tester, id);

        await tester.tap(find.byTooltip('Перенести в проект…'));
        await settle(tester);

        expect(find.text('Перенести в проект'), findsOneWidget);
        final sheet = find.byType(BottomSheet);
        expect(
          find.descendant(of: sheet, matching: find.text('Дача')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: sheet, matching: find.text('Дом')),
          findsNothing,
        );
        expect(
          find.descendant(of: sheet, matching: find.text('Старое')),
          findsNothing,
        );

        await tester.tap(find.descendant(of: sheet, matching: find.text('Дача')));
        await settle(tester);
        await settle(tester);

        final moved = server.tasks.singleWhere((t) => t['id'] == id);
        expect(moved['projectId'], 'prj_dacha');
        expect(find.text('Задача перенесена в «Дача».'), findsOneWidget);
        expect(find.byType(TaskEditor), findsNothing);
        expect(find.text('открыть'), findsOneWidget);
      });

      testWidgets('closing the sheet moves nothing', (tester) async {
        server.addProject(name: 'Дача', id: 'prj_dacha');
        final id = server.addTask(projectId: projectId, title: 'Покрасить забор');
        await pumpPushed(tester, id);

        await tester.tap(find.byTooltip('Перенести в проект…'));
        await settle(tester);
        await tester.tapAt(const Offset(187, 40));
        await settle(tester);

        expect(server.tasks.single['projectId'], projectId);
        expect(find.byType(TaskEditor), findsOneWidget);
        expect(
          backend.requests.where((r) => r.path.endsWith('/move')),
          isEmpty,
        );
      });

      testWidgets('with no other project, says how to get one', (tester) async {
        final id = server.addTask(projectId: projectId, title: 'Покрасить забор');
        await pumpPushed(tester, id);

        await tester.tap(find.byTooltip('Перенести в проект…'));
        await settle(tester);

        expect(find.textContaining('Других проектов нет'), findsOneWidget);
      });
    });
  });

  group('an existing task: recognition and chips', () {
    testWidgets('text saved before this feature is not re-applied', (
      tester,
    ) async {
      final id = server.addTask(
        projectId: projectId,
        title: 'Позвонить в пятницу в 10',
      );
      await pumpTask(tester, id);

      // Scanned once on opening, everything found dismissed.
      expect(titleController(tester).activeTokens, isEmpty);
      expect(chipText('Напоминание', '+ Напомнить'), findsOneWidget);

      await tester.enterText(titleField(), 'Позвонить в пятницу в 10 маме');
      await tester.pump();
      expect(titleController(tester).activeTokens, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await settle(tester);
      // Only the title: no reminder moved behind the user's back.
      expect(server.patches.single.body, <String, dynamic>{
        'title': 'Позвонить в пятницу в 10 маме',
      });
    });

    testWidgets('a date typed now fills the chip, and is cut out on save', (
      tester,
    ) async {
      final id = server.addTask(projectId: projectId, title: 'Позвонить');
      await pumpTask(tester, id);

      await tester.enterText(titleField(), 'Позвонить завтра в 10');
      await tester.pump();
      expect(chipText('Напоминание', 'Завтра, 10:00'), findsOneWidget);
      // Not written yet: the text and what it says wait for "Сохранить".
      expect(server.patches, isEmpty);

      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await settle(tester);

      expect(server.tasks.single['title'], 'Позвонить');
      expect(server.patches.single.body, <String, dynamic>{
        'remindAt': '2026-11-12',
        'remindTime': '10:00',
      });
    });

    testWidgets('the reminder chip writes at once', (tester) async {
      final id = server.addTask(projectId: projectId, title: 'Позвонить');
      await pumpTask(tester, id);

      await tester.tap(find.text('+ Напомнить'));
      await settle(tester);
      expect(find.text('Когда напомнить'), findsOneWidget);
      await tester.tap(find.text('Завтра утром'));
      await settle(tester);

      expect(server.patches.single.body, <String, dynamic>{
        'remindAt': '2026-11-12',
        'remindTime': '09:00',
      });
      expect(chipText('Напоминание', 'Завтра, 09:00'), findsOneWidget);

      // The cross takes it off, also at once.
      await tester.tap(find.byTooltip('Убрать напоминание'));
      await settle(tester);
      expect(server.patches.last.body, <String, dynamic>{'remindAt': null});
      expect(find.text('+ Напомнить'), findsOneWidget);
    });
  });

  group('a new task', () {
    testWidgets('a date, a category and a project typed into the title', (
      tester,
    ) async {
      server.addProject(name: 'Дача', id: 'prj_dacha');
      final shopping = server.addCategory(projectId: 'prj_dacha', name: 'Покупки');
      await pumpNew(tester);

      expect(find.text('Новая задача'), findsOneWidget);
      expect(chipText('Проект задачи', 'Дом'), findsOneWidget);

      await tester.enterText(
        titleField(),
        'Купить семена завтра в 10 #дача /пок',
      );
      await settle(tester);

      final tokens = titleController(tester).activeTokens.toList();
      expect(tokens, hasLength(3));
      expect(chipText('Напоминание', 'Завтра, 10:00'), findsOneWidget);
      expect(chipText('Проект задачи', 'Дача'), findsOneWidget);
      expect(chipText('Категория', 'Покупки'), findsOneWidget);

      // Highlighted in the field: the active pieces have the token fill.
      final span = titleController(tester).buildTextSpan(
        context: tester.element(titleField()),
        withComposing: false,
      );
      final lit = <String>[
        for (final child in span.children!.cast<TextSpan>())
          if (child.style?.backgroundColor == EditorColors.tokenFill)
            child.text!,
      ];
      expect(lit, <String>['завтра в 10', '#дача', '/пок']);

      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);

      final row = server.tasks.single;
      expect(row['projectId'], 'prj_dacha');
      // Cut out of the title: the values live in the task's fields.
      expect(row['title'], 'Купить семена');
      expect(row['remindAt'], '2026-11-12');
      expect(row['remindTime'], '10:00');
      expect(row['categoryId'], shopping);
      expect(find.byType(TaskEditor), findsNothing);
      // Said, because the task went to a list that is not the one open.
      expect(find.text('Задача добавлена в «Дача».'), findsOneWidget);
    });

    testWidgets('a tap on the highlight: «Не дата» keeps the words as text', (
      tester,
    ) async {
      await pumpNew(tester);

      await tester.enterText(titleField(), 'Купить корм завтра в 10');
      await settle(tester);
      final token = titleController(tester).activeTokens.single;

      final editable = tester.allRenderObjects
          .whereType<RenderEditable>()
          .first;
      final caret = editable.getLocalRectForCaret(
        TextPosition(offset: token.start + 3),
      );
      await tester.tapAt(editable.localToGlobal(caret.center));
      await settle(tester);

      expect(find.text('Не дата'), findsOneWidget);
      expect(find.text('Изменить…'), findsOneWidget);
      await tester.tap(find.text('Не дата'));
      await settle(tester);

      expect(titleController(tester).activeTokens, isEmpty);
      expect(chipText('Напоминание', '+ Напомнить'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);
      expect(server.tasks.single['title'], 'Купить корм завтра в 10');
      expect(server.tasks.single['remindAt'], isNull);
    });

    testWidgets('Backspace after a token un-recognises it first', (
      tester,
    ) async {
      await pumpNew(tester);
      final controller = titleController(tester);

      const text = 'Купить корм завтра';
      controller.value = const TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      await tester.pump();
      expect(controller.activeTokens, hasLength(1));
      expect(chipText('Напоминание', 'Завтра'), findsOneWidget);

      // The first Backspace: the text stays, the token goes.
      controller.value = TextEditingValue(
        text: text.substring(0, text.length - 1),
        selection: const TextSelection.collapsed(offset: text.length - 1),
      );
      await tester.pump();
      expect(controller.text, text);
      expect(controller.activeTokens, isEmpty);
      expect(chipText('Напоминание', '+ Напомнить'), findsOneWidget);

      // The second one erases.
      controller.value = TextEditingValue(
        text: text.substring(0, text.length - 1),
        selection: const TextSelection.collapsed(offset: text.length - 1),
      );
      await tester.pump();
      expect(controller.text, 'Купить корм завтр');
    });

    testWidgets('erasing a token gives back the value from before it', (
      tester,
    ) async {
      await pumpNew(tester);

      // A reminder set by hand...
      await tester.tap(find.text('+ Напомнить'));
      await settle(tester);
      await tester.tap(find.text('Через неделю'));
      await settle(tester);
      expect(chipText('Напоминание', '18.11'), findsOneWidget);

      // ...overridden by a typed date while it is there...
      await tester.enterText(titleField(), 'Позвонить завтра');
      await tester.pump();
      expect(chipText('Напоминание', 'Завтра'), findsOneWidget);

      // ...and back when the date is erased.
      await tester.enterText(titleField(), 'Позвонить');
      await tester.pump();
      expect(chipText('Напоминание', '18.11'), findsOneWidget);
    });

    testWidgets('a reminder and a category set by hand go with the create', (
      tester,
    ) async {
      final kitchen = server.addCategory(projectId: projectId, name: 'Кухня');
      await pumpNew(tester);

      // The description is open from the start on a new task.
      expect(find.text('ОПИСАНИЕ'), findsOneWidget);
      await tester.enterText(titleField(), 'Смеситель');
      await tester.enterText(find.byType(TextField).last, 'Хром, не латунь');

      await tester.tap(find.text('+ Напомнить'));
      await settle(tester);
      await tester.tap(find.text('Завтра утром'));
      await settle(tester);

      // The row scrolls sideways; the category is its last chip.
      await tester.ensureVisible(find.text('Без категории'));
      await tester.tap(find.text('Без категории'));
      await settle(tester);
      await tester.tap(find.text('Кухня'));
      await settle(tester);
      expect(chipText('Категория', 'Кухня'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);

      final row = server.tasks.single;
      expect(row['title'], 'Смеситель');
      expect(row['description'], 'Хром, не латунь');
      expect(row['remindAt'], '2026-11-12');
      expect(row['remindTime'], '09:00');
      expect(row['categoryId'], kitchen);
      expect(row['status'], 'pending');
    });

    testWidgets('«Список» opens a checklist that goes with the create', (
      tester,
    ) async {
      await pumpNew(tester);
      await tester.enterText(titleField(), 'Купить к ужину');

      await tester.ensureVisible(find.text('Список'));
      await tester.tap(find.text('Список'));
      await settle(tester);
      expect(find.text('Список'), findsNothing);

      final item = find.descendant(
        of: find.byType(ChecklistSection),
        matching: find.byType(TextField),
      );
      await tester.enterText(item.first, 'Хлеб');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);

      final checklist = server.tasks.single['checklist'] as List<dynamic>;
      expect(checklist.map((i) => (i as Map)['text']), <String>['Хлеб']);
    });

    testWidgets('an empty checklist item is not sent', (tester) async {
      await pumpNew(tester);
      await tester.enterText(titleField(), 'Без списка');
      await tester.ensureVisible(find.text('Список'));
      await tester.tap(find.text('Список'));
      await settle(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);

      expect(server.tasks.single['checklist'], isNull);
    });

    testWidgets('a new task can be created as a blocker, never as done', (
      tester,
    ) async {
      await pumpNew(tester);

      expect(find.text('Открыта'), findsOneWidget);
      expect(find.text('Сделано'), findsNothing);
      await tester.enterText(titleField(), 'Жду кабель');
      await tester.ensureVisible(find.text('Блокер'));
      await tester.tap(find.text('Блокер'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);

      expect(server.tasks.single['status'], 'blocked');
    });

    testWidgets('an ambiguous #… offers the projects it could be', (
      tester,
    ) async {
      server.addProject(name: 'Дача', id: 'prj_dacha');
      await pumpNew(tester);

      await tester.enterText(titleField(), 'Полить грядки #д');
      await settle(tester);
      expect(find.text('#Дом'), findsOneWidget);
      expect(find.text('#Дача'), findsOneWidget);

      await tester.tap(find.text('#Дача'));
      await settle(tester);
      expect(titleController(tester).text, 'Полить грядки #Дача');
      expect(chipText('Проект задачи', 'Дача'), findsOneWidget);
    });

    testWidgets('the project chip picks another project', (tester) async {
      server.addProject(name: 'Дача', id: 'prj_dacha');
      await pumpNew(tester);

      await tester.tap(find.byTooltip('Проект задачи'));
      await settle(tester);
      await tester.tap(find.widgetWithText(ListTile, 'Дача'));
      await settle(tester);

      await tester.enterText(titleField(), 'Полить грядки');
      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);
      expect(server.tasks.single['projectId'], 'prj_dacha');
    });

    testWidgets('a prefill from dictation: text, AI reminder and the record', (
      tester,
    ) async {
      await pumpNew(
        tester,
        prefill: const TaskDraft(
          title: 'Купить кабель',
          description: 'Два метра',
          remindAt: '2026-11-20',
          remindTime: '18:00',
          parseId: 'dp-31',
        ),
      );

      expect(titleController(tester).text, 'Купить кабель');
      expect(find.widgetWithText(TextField, 'Два метра'), findsOneWidget);
      expect(chipText('Напоминание', '20.11, 18:00'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);

      final create = backend.requests.singleWhere(
        (r) => r.method == 'POST' && r.path == '/projects/$projectId/tasks',
      );
      final body = create.data as Map<String, dynamic>;
      expect(body['title'], 'Купить кабель');
      expect(body['remindAt'], '2026-11-20');
      expect(body['remindTime'], '18:00');
      expect(body['dictationParseId'], 'dp-31');
    });

    testWidgets('nothing typed: Back leaves, nothing created', (tester) async {
      await pumpNew(tester);
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(TaskEditor), findsNothing);
      expect(server.tasks, isEmpty);
    });
  });

  group('the compact sheet («+ Задача»)', () {
    Future<void> openSheet(WidgetTester tester, {Size? size}) => pumpHost(
      tester,
      (context) => AppRoutes.openNewTask(context, projectId: projectId),
      size: size ?? const Size(375, 812),
    );

    testWidgets('title, chips and "Добавить"; expanding keeps the text', (
      tester,
    ) async {
      await openSheet(tester);

      expect(find.byType(TaskEditor), findsOneWidget);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('+ Напомнить'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Добавить'), findsOneWidget);
      // Compact: no sections yet.
      expect(find.text('ОПИСАНИЕ'), findsNothing);

      await tester.enterText(titleField(), 'Позвонить электрику');
      await tester.tap(find.byTooltip('Развернуть'));
      await settle(tester);

      expect(find.text('ОПИСАНИЕ'), findsOneWidget);
      expect(titleController(tester).text, 'Позвонить электрику');

      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);
      expect(server.tasks.single['title'], 'Позвонить электрику');
      expect(find.byType(TaskEditor), findsNothing);
    });

    testWidgets('"Добавить и ещё" keeps the sheet open, empty', (
      tester,
    ) async {
      await openSheet(tester);

      await tester.enterText(titleField(), 'Первая');
      await tester.tap(find.byTooltip('Добавить и ещё'));
      await settle(tester);
      await tester.enterText(titleField(), 'Вторая');
      await tester.tap(find.byTooltip('Добавить и ещё'));
      await settle(tester);

      expect(server.titlesInOrder(projectId), <String>['Первая', 'Вторая']);
      expect(find.byType(TaskEditor), findsOneWidget);
      expect(titleController(tester).text, isEmpty);
      expect(find.text('Задача добавлена в «Дом».'), findsOneWidget);
    });

    testWidgets('typed text: the scrim asks before throwing it away', (
      tester,
    ) async {
      await openSheet(tester);
      await tester.enterText(titleField(), 'Позвонить электрику');
      await settle(tester);

      await tester.tapAt(const Offset(187, 10));
      await settle(tester);
      expect(find.text('Новая задача не будет создана.'), findsOneWidget);
    });

    testWidgets('a wide window: a 560 px dialog instead', (tester) async {
      await openSheet(tester, size: const Size(1280, 900));

      expect(find.byType(TaskEditorDialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.getSize(find.byType(TaskEditor)).width, 560);
    });
  });

  group('pictures in the editor', () {
    final desktop = TargetPlatformVariant.only(TargetPlatform.windows);

    Future<void> pressCtrlV(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settle(tester);
    }

    testWidgets(
      'Ctrl+V of a screenshot in the compact sheet: expands, shows the draft, '
      'uploads it after «Добавить»',
      (tester) async {
        clipboard.image = png;
        await pumpHost(
          tester,
          (context) => AppRoutes.openNewTask(context, projectId: projectId),
        );
        expect(find.text('ОПИСАНИЕ'), findsNothing);

        await tester.showKeyboard(titleField());
        await pressCtrlV(tester);

        // Expanded, so the picture is in view; the title took no text.
        expect(find.text('ОПИСАНИЕ'), findsOneWidget);
        expect(find.byType(AttachmentTile), findsOneWidget);
        expect(titleController(tester).text, isEmpty);
        expect(pictures.added, isEmpty);

        // No title: the task cannot be created, but the picture is not
        // thrown away either.
        await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
        await settle(tester);
        expect(find.byType(TaskEditor), findsOneWidget);
        expect(find.byType(AttachmentTile), findsOneWidget);
        expect(
          find.textContaining('без этого задачу не создать'),
          findsOneWidget,
        );
        expect(server.tasks, isEmpty);

        await tester.enterText(titleField(), 'Ошибка на экране оплаты');
        await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
        await settle(tester);

        final id = server.tasks.single['id'] as String;
        expect(pictures.added, <String>[id]);
        expect(pictures.files.single.mimeType, 'image/png');
        expect(find.byType(TaskEditor), findsNothing);
      },
      variant: desktop,
    );

    testWidgets(
      'a new task with only a picture asks before it is closed',
      (tester) async {
        clipboard.image = png;
        await pumpNew(tester);
        await tester.showKeyboard(titleField());
        await pressCtrlV(tester);
        expect(find.byType(AttachmentTile), findsOneWidget);

        await tester.tap(find.byTooltip('Закрыть'));
        await settle(tester);
        expect(find.text('Выйти без сохранения?'), findsOneWidget);
        expect(find.text('Новая задача не будет создана.'), findsOneWidget);
      },
      variant: desktop,
    );

    testWidgets('an empty new task still closes on «Добавить» quietly', (
      tester,
    ) async {
      await pumpNew(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Добавить'));
      await settle(tester);
      expect(find.byType(TaskEditor), findsNothing);
    });

    testWidgets(
      'Ctrl+V in an existing task uploads at once; text still pastes',
      (tester) async {
        final taskId = server.addTask(
          projectId: projectId,
          title: 'Сломан вход',
        );
        await pumpTask(tester, taskId);
        await tester.showKeyboard(titleField());

        clipboard.image = png;
        await pressCtrlV(tester);
        expect(pictures.added, <String>[taskId]);
        expect(titleController(tester).text, 'Сломан вход');

        // Text on the clipboard goes to the field as before.
        clipboard.image = null;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => switch (call.method) {
            'Clipboard.getData' => <String, Object?>{'text': ' в подъезд'},
            'Clipboard.hasStrings' => <String, Object?>{'value': true},
            _ => null,
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final controller = titleController(tester);
        controller.selection = TextSelection.collapsed(
          offset: controller.text.length,
        );
        await pressCtrlV(tester);
        expect(titleController(tester).text, 'Сломан вход в подъезд');
        expect(pictures.added, hasLength(1));
      },
      variant: desktop,
    );

    testWidgets('the Android keyboard inserts a picture into either field', (
      tester,
    ) async {
      await pumpNew(tester);
      // Title and description both take keyboard pictures.
      final configs = <ContentInsertionConfiguration>[
        for (final field in tester.widgetList<TextField>(
          find.byType(TextField),
        ))
          ?field.contentInsertionConfiguration,
      ];
      expect(configs, hasLength(2));
      expect(configs.first.allowedMimeTypes, contains('image/png'));

      configs.first.onContentInserted(
        KeyboardInsertedContent(
          mimeType: 'image/png',
          uri: 'content://keyboard/1',
          data: png,
        ),
      );
      await settle(tester);
      expect(find.byType(AttachmentTile), findsOneWidget);

      // A GIF (not a type the server takes) is ignored.
      configs.last.onContentInserted(
        KeyboardInsertedContent(
          mimeType: 'image/gif',
          uri: 'content://keyboard/2',
          data: Uint8List.fromList(<int>[0x47, 0x49, 0x46]),
        ),
      );
      await settle(tester);
      expect(find.byType(AttachmentTile), findsOneWidget);
    });
  });
}

class _FakeQueue implements AttachmentQueue {
  final List<String> added = <String>[];
  final List<XFile> files = <XFile>[];

  @override
  Future<PendingAttachment> add(
    String taskIdOrLocal,
    XFile file, {
    String? projectId,
    String? title,
  }) async {
    added.add(taskIdOrLocal);
    files.add(file);
    return PendingAttachment(
      entry: OutboxEntry(
        key: 'k${added.length}',
        kind: OutboxKind.uploadAttachment,
        projectId: projectId ?? 'p',
        title: title ?? '',
        body: const <String, Object?>{},
        createdAt: DateTime.utc(2026),
      ),
      state: PendingAttachmentState.waiting,
    );
  }

  @override
  Future<List<PendingAttachment>> addAll(
    String taskIdOrLocal,
    List<XFile> files, {
    String? projectId,
    String? title,
  }) async => <PendingAttachment>[
    for (final file in files)
      await add(taskIdOrLocal, file, projectId: projectId, title: title),
  ];

  @override
  Future<void> discard(PendingAttachment pending) async {}

  @override
  Future<void> remove(Task task, String attachmentId) async {}

  @override
  Future<void> retry(PendingAttachment pending) async {}
}

class _FakeClipboard implements ClipboardImageReader {
  Uint8List? image;

  @override
  Future<Uint8List?> readImage() async => image;
}

class _ReadyModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => VoiceModelReady(fakeInstalledModel());
}

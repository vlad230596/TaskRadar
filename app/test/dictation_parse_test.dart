import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/screens/dictation_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/voice/voice_model.dart';

import 'support/fake_backend.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_voice.dart';

/// "Разобрать" on the dictation screen (F14), and the keyboard on a phone.
///
/// ## What is pinned here
///
/// Transparency. Nothing reaches the model unless "Разобрать" is pressed; its
/// answer is on screen, editable, before "Готово" saves it; and a failure is
/// said under the words rather than swallowed. The version before this one
/// tidied silently inside "Готово", and the task that landed in the project
/// was not the text the user had last seen.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late List<Map<String, dynamic>> parseBodies;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    server.addProject(name: 'Дом', id: 'prj_1');
    parseBodies = <Map<String, dynamic>>[];
  });

  void modelAnswers(Map<String, dynamic> body, {int statusCode = 200}) {
    backend.on('POST', '/dictation/parse', (match) {
      parseBodies.add(match.body);
      return jsonResponse(body, statusCode: statusCode);
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Opens the screen aimed at [destination] over a host screen, and stops the
  /// recording: the fake recogniser has heard "Купить кабель".
  Future<void> dictate(
    WidgetTester tester, {
    DictationDestination destination = const ProjectDestination(
      projectId: 'prj_1',
      name: 'Дом',
    ),
  }) async {
    // A phone: the size the keyboard bug was seen at.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          voiceRecorderProvider.overrideWithValue(FakeVoiceRecorder()),
          speechRecognizerProvider.overrideWithValue(FakeSpeechRecognizer()),
          voiceModelInstallationProvider.overrideWith(_ReadyModel.new),
          deviceTimeZoneNameProvider.overrideWith(
            (ref) async => 'Europe/Moscow',
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          // A screen underneath, as in the app: the dictation screen pops when
          // it has saved, and the snackbar is shown on whatever is left.
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push<String>(
                    MaterialPageRoute<String>(
                      builder: (_) => DictationScreen(destination: destination),
                    ),
                  ),
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

    await tester.tap(find.text('Готово'));
    await settle(tester);
  }

  /// The body of the one `POST /projects/:id/tasks` the screen sent.
  Map<String, dynamic> createBody() =>
      backend.requests
              .singleWhere(
                (r) => r.method == 'POST' && r.path == '/projects/prj_1/tasks',
              )
              .data
          as Map<String, dynamic>;

  Future<void> tidy(WidgetTester tester) async {
    await tester.tap(find.text('Разобрать'));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester) async {
    await tester.tap(find.text('Готово'));
    await settle(tester);
  }

  group('"Разобрать"', () {
    testWidgets('nothing goes to the model unless it is pressed', (
      tester,
    ) async {
      modelAnswers(<String, dynamic>{'title': 'Не должно понадобиться'});

      await dictate(tester);
      expect(find.text('Разобрать'), findsOneWidget);
      await save(tester);

      expect(parseBodies, isEmpty);
      expect(server.tasks.single['title'], 'Купить кабель');
      expect(find.text('Задача добавлена в «Дом».'), findsOneWidget);
    });

    testWidgets('shows the proposal, and saves what is on screen', (
      tester,
    ) async {
      modelAnswers(<String, dynamic>{
        'title': 'Купить кабель USB-C',
        'description': 'Два метра',
        'remindDate': null,
        'remindTime': null,
        'parseId': 'dp-1',
      });

      await dictate(tester);
      await tidy(tester);

      expect(parseBodies, <Map<String, dynamic>>[
        <String, dynamic>{'text': 'Купить кабель', 'timeZone': 'Europe/Moscow'},
      ]);
      expect(find.text('Разобрано — можно править'), findsOneWidget);
      expect(find.text('Купить кабель USB-C'), findsOneWidget);
      expect(find.text('Два метра'), findsOneWidget);
      // Nothing saved yet: the proposal is a proposal.
      expect(server.tasks, isEmpty);

      // A correction made here is what lands, not the model's wording.
      await tester.enterText(
        find.widgetWithText(TextField, 'Купить кабель USB-C'),
        'Заказать кабель USB-C',
      );
      await save(tester);

      // The server's record of the parse is linked to the task, so what was
      // kept becomes the label the prompt is later scored against.
      expect(createBody()['dictationParseId'], 'dp-1');

      expect(server.tasks.single, <String, dynamic>{
        ...server.tasks.single,
        'title': 'Заказать кабель USB-C',
        'description': 'Два метра',
        'status': 'pending',
        'remindAt': null,
      });
    });

    testWidgets('a proposed reminder makes a blocked task with that date', (
      tester,
    ) async {
      modelAnswers(<String, dynamic>{
        'title': 'Купить кабель',
        'description': null,
        'remindDate': '2026-09-25',
        'remindTime': '10:00',
      });

      await dictate(tester);
      await tidy(tester);
      expect(find.text('Напомнить 25.09 · задача будет ждать'), findsOneWidget);
      await save(tester);

      expect(server.tasks.single['status'], 'blocked');
      // The calendar date, not an instant -- see `ProjectApi.updateTask`.
      expect(server.tasks.single['remindAt'], '2026-09-25');
      expect(
        find.text('Задача добавлена в «Дом», напомню 25.09.'),
        findsOneWidget,
      );
    });

    testWidgets('the reminder can be taken off and the rest kept', (
      tester,
    ) async {
      modelAnswers(<String, dynamic>{
        'title': 'Купить кабель',
        'description': 'Два метра',
        'remindDate': '2026-09-25',
        'remindTime': null,
      });

      await dictate(tester);
      await tidy(tester);
      await tester.tap(find.byTooltip('Без напоминания'));
      await settle(tester);
      await save(tester);

      expect(server.tasks.single['status'], 'pending');
      expect(server.tasks.single['remindAt'], isNull);
      expect(server.tasks.single['description'], 'Два метра');
    });

    testWidgets('"Как надиктовано" goes back to the words', (tester) async {
      modelAnswers(<String, dynamic>{
        'title': 'Купить кабель USB-C',
        'parseId': 'dp-2',
      });

      await dictate(tester);
      await tidy(tester);
      await tester.tap(find.text('Как надиктовано'));
      await settle(tester);
      await save(tester);

      expect(server.tasks.single['title'], 'Купить кабель');
      // The raw words are not an answer the model gave: no label.
      expect(createBody().containsKey('dictationParseId'), isFalse);
    });

    testWidgets('no model on the server: said, and the words stay', (
      tester,
    ) async {
      modelAnswers(<String, dynamic>{
        'error': 'DictationUnavailableError',
        'message': 'Dictation parsing is not configured',
      }, statusCode: 503);

      await dictate(tester);
      await tidy(tester);

      expect(find.text('Разбор не настроен на сервере.'), findsOneWidget);
      expect(find.text('Купить кабель'), findsOneWidget);

      await save(tester);
      expect(server.tasks.single['title'], 'Купить кабель');
    });

    testWidgets('no network: said, and the words stay', (tester) async {
      backend.failingPaths.add('/dictation/parse');

      await dictate(tester);
      await tidy(tester);

      expect(
        find.text('Нет связи с сервером — можно сохранить как есть.'),
        findsOneWidget,
      );
      expect(find.text('Купить кабель'), findsOneWidget);
    });

    testWidgets('the model failing: said, so it can be tried again', (
      tester,
    ) async {
      modelAnswers(<String, dynamic>{
        'error': 'UpstreamModelError',
        'message': 'Dictation model did not answer',
      }, statusCode: 502);

      await dictate(tester);
      await tidy(tester);

      expect(
        find.text('Модель не ответила — попробуйте ещё раз.'),
        findsOneWidget,
      );
      expect(find.text('Разобрать'), findsOneWidget);
    });

    testWidgets('not offered for the sandbox', (tester) async {
      await dictate(tester, destination: const SandboxDestination());
      expect(find.text('Разобрать'), findsNothing);
    });
  });

  group('the keyboard on a phone', () {
    testWidgets('leaves the words most of what is left of the screen', (
      tester,
    ) async {
      await dictate(tester);

      // The keyboard of a typical phone at 390x844.
      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      await settle(tester);

      // It was 66 px -- two lines of 25 px text, the rest scrolled out of
      // sight -- because the meter's reserved space and "Отменить" kept theirs.
      final field = tester.getRect(find.byType(TextField));
      expect(field.height, greaterThan(200));
      expect(field.bottom, lessThanOrEqualTo(844 - 330));
      expect(find.text('Отменить'), findsNothing);
      expect(find.text('Готово'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the proposal scrolls instead of overflowing', (tester) async {
      modelAnswers(<String, dynamic>{
        'title': 'Купить кабель USB-C для монитора в кабинете',
        'description': List<String>.filled(12, '- пункт списка').join('\n'),
        'remindDate': '2026-09-25',
        'remindTime': null,
      });

      await dictate(tester);
      await tidy(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 330);
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Готово'), findsOneWidget);
    });
  });
}

class _ReadyModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => VoiceModelReady(fakeInstalledModel());
}

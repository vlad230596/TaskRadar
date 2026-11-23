import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/goal.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/note_editor_screen.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/theme/tokens.dart';
import 'package:taskradar/widgets/note_list.dart';

import 'support/fake_board_snapshot_store.dart';
import 'support/fake_ideas_backend.dart';
import 'support/fake_notification_gateway.dart';

/// Ideas (`design/goals-ideas-spec.md`, §7): the former notes, with their
/// goals and «Сделать задачей».
void main() {
  group('splitIdeaText', () {
    test('the first line is the title, the rest the text', () {
      expect(splitIdeaText('Статья\nпро диктовку\nи модели'), (
        'Статья',
        'про диктовку\nи модели',
      ));
    });

    test('one line is a title with no text', () {
      expect(splitIdeaText('  Статья про диктовку  '), (
        'Статья про диктовку',
        '',
      ));
    });

    test('a very long first line is cut at a word, the rest moves down', () {
      final words = List<String>.filled(40, 'слово').join(' ');
      final (title, text) = splitIdeaText(words);
      expect(title.length, lessThanOrEqualTo(121));
      expect(title, endsWith('…'));
      expect(text, isNotEmpty);
    });
  });

  group('ideaPreview', () {
    test('strips headings, list marks, emphasis and links', () {
      expect(
        ideaPreview(
          '# Что помнить\n\n- ключи у **соседей**\n'
          '- [Recorder](https://x.y) и `код`',
        ),
        'Что помнить ключи у соседей Recorder и код',
      );
    });

    test('an empty text has no preview', () {
      expect(ideaPreview('  \n '), '');
    });
  });

  test('goalsOfIdea: the goals that keep the idea', () {
    GoalView goal(String id, List<String> ideas) => GoalView(
      id: id,
      contourId: 'c',
      title: id,
      state: GoalState.slot,
      position: 1,
      createdAt: '2026-11-01T00:00:00.000Z',
      ideas: <GoalIdea>[
        for (final idea in ideas)
          GoalIdea(id: idea, title: idea, projectId: 'p', projectName: 'P'),
      ],
    );
    final goals = <GoalView>[
      goal('g1', <String>['n1']),
      goal('g2', <String>['n2', 'n1']),
      goal('g3', <String>[]),
    ];
    expect(goalsOfIdea(goals, 'n1').map((g) => g.id), <String>['g1', 'g2']);
    expect(goalsOfIdea(goals, 'n9'), isEmpty);
  });

  group('the ideas tab', () {
    late FakeIdeasBackend server;

    setUp(() => server = FakeIdeasBackend());

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    Future<void> pumpIdeas(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(server.backend.client),
            boardSnapshotStoreProvider.overrideWithValue(
              FakeBoardSnapshotStore(),
            ),
            notificationGatewayProvider.overrideWithValue(
              FakeNotificationGateway(),
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: const ProjectScreen(projectId: FakeIdeasBackend.projectId),
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Идеи · 3'));
      await settle(tester);
    }

    testWidgets('newest first, with goal chips or «Связать с целью»', (
      tester,
    ) async {
      await pumpIdeas(tester);

      final titles = <String>[
        'Статья: диктовка без облака',
        'Доклад на митапе про Flutter-виджеты на Android',
        'Серия коротких постов «как я веду задачи»',
      ];
      final tops = <double>[
        for (final title in titles) tester.getTopLeft(find.text(title)).dy,
      ];
      expect(tops, orderedEquals(<double>[...tops]..sort()));

      // The active contour is «Работа» (first, no schedules): its goal's chip
      // is bright, the other contour's muted.
      final bright = tester.widget<IdeaGoalChip>(
        find.widgetWithText(IdeaGoalChip, 'Первая публикация'),
      );
      expect(bright.bright, isTrue);
      final muted = tester.widget<IdeaGoalChip>(
        find.widgetWithText(IdeaGoalChip, 'Положение на рынке труда'),
      );
      expect(muted.bright, isFalse);
      // No goals: the link offer instead.
      expect(find.text('Связать с целью'), findsOneWidget);
      expect(find.text('Сделать задачей'), findsNWidgets(3));
      // Three ideas: no hint line any more.
      expect(find.textContaining('Мысль, которая может стать'), findsNothing);
      // The composer is gone, the bar is there.
      expect(find.byType(TextField), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Идея'), findsOneWidget);
      expect(find.byTooltip('Продиктовать идею'), findsOneWidget);
      expect(find.byTooltip('Задача голосом'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Сделать задачей» offline: says the network is needed and '
        'keeps the idea', (tester) async {
      await pumpIdeas(tester);
      server.offline.add('/to-task');

      await tester.tap(find.text('Сделать задачей').first);
      await settle(tester);

      expect(find.textContaining('Нужна сеть'), findsOneWidget);
      expect(server.notes, hasLength(3));
      expect(find.text('Статья: диктовка без облака'), findsOneWidget);
    });

    testWidgets(
      '«Сделать задачей» online: the idea leaves, «Открыть» offered',
      (tester) async {
        await pumpIdeas(tester);

        await tester.tap(find.text('Сделать задачей').first);
        await settle(tester);

        expect(server.tasks.single['title'], 'Статья: диктовка без облака');
        expect(find.text('Статья: диктовка без облака'), findsNothing);
        expect(find.text('Теперь это задача в «Публикации»'), findsOneWidget);
        expect(find.text('Открыть'), findsOneWidget);
        // Fewer than three now: the hint is back.
        expect(
          find.textContaining('Мысль, которая может стать'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the idea screen is dark and offers its actions', (
      tester,
    ) async {
      await pumpIdeas(tester);

      await tester.tap(find.text('Статья: диктовка без облака'));
      await settle(tester);

      expect(find.byType(NoteEditorScreen), findsOneWidget);
      final scaffold = tester.widget<Scaffold>(
        find.descendant(
          of: find.byType(NoteEditorScreen),
          matching: find.byType(Scaffold),
        ),
      );
      expect(scaffold.backgroundColor, AppColors.voiceBackground);
      expect(find.text('Публикации'), findsOneWidget);
      expect(find.text('ЦЕЛИ'), findsOneWidget);
      expect(find.text('Первая публикация'), findsOneWidget);
      expect(find.text('Сделать задачей'), findsOneWidget);
      expect(find.text('Связать с целью'), findsOneWidget);

      // An edit swaps the actions for «Сохранить».
      await tester.enterText(find.byType(TextField).first, 'Статья');
      await settle(tester);
      expect(find.text('Сохранить'), findsOneWidget);
      expect(find.text('Сделать задачей'), findsNothing);
    });
  });
}

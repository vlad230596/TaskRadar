import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/project_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/domain/reminders.dart';
import 'package:taskradar/domain/today_view.dart';
import 'package:taskradar/widgets/today/date_sheet.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// The gesture this product exists for, at the widget level:
/// "блокер → выбрал дату → дата наступила → видно → снял".
///
/// The date picker is a real `showDatePicker`, driven the way a person drives
/// it, because the interesting part is not that a callback fires but **which
/// day ends up in the request body** -- and that is exactly where a timezone
/// off-by-one hides.
///
/// ## Where the controls moved in F12
///
/// The date used to be set from a 30 px text button inside a task row. It is
/// now a full-width row on the task screen, for the same reason everything else
/// moved there: a row is 56 px and has to hold a title, and the controls that
/// were squeezed in beside it were the ones nobody could hit.
///
/// What did **not** move is the chaining rule -- blocking a task with no date
/// offers the picker immediately -- because that is a rule about the product,
/// not about a screen. It is now in `setTaskStatus`, shared by the row and the
/// task screen, and it is exercised here from the row.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeBoardSnapshotStore snapshots;
  late FakeNotificationGateway gateway;
  late String projectId;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    snapshots = FakeBoardSnapshotStore();
    gateway = FakeNotificationGateway();
    projectId = server.addProject(name: 'Дача', id: 'prj_1');
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  Future<void> pumpProject(WidgetTester tester) async {
    // Tall enough that the date picker's dialog and the task row are both
    // reachable without scrolling.
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(snapshots),
          notificationGatewayProvider.overrideWithValue(gateway),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: ProjectScreen(projectId: projectId),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  /// Opens one task on its own screen, which is where the date lives.
  Future<void> openTask(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await settle(tester);
  }

  /// The task editor's «Дата» chip (today-history-spec §7): its sheet.
  Future<void> openDateSheet(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Дата'));
    await tester.pumpAndSettle();
  }

  /// Taps a day of the date sheet's month -- a tap applies and closes.
  ///
  /// Tapping a number rather than typing: the number is what a person taps,
  /// and the whole risk being tested is that the day they see is not the
  /// day that gets sent.
  Future<void> pickDay(WidgetTester tester, int dayOfMonth) async {
    await tester.tap(
      find
          .descendant(
            of: find.byType(DateSheet),
            matching: find.text('$dayOfMonth'),
          )
          .first,
    );
    await settle(tester);
  }

  /// The date chip's words, inside the chip.
  Finder chip(String text) =>
      find.descendant(of: find.byTooltip('Дата'), matching: find.text(text));

  /// The time chip's words.
  Finder timeChip(String text) => find.descendant(
    of: find.byTooltip('Время — пуш в это время'),
    matching: find.text(text),
  );

  String today() => calendarDateForApi(DateTime.now());

  String dayAt(int offsetDays) =>
      calendarDateForApi(DateTime.now().add(Duration(days: offsetDays)));

  /// The chip's words for a date [offsetDays] from today.
  String label(int offsetDays) =>
      formatTaskDate(dayAt(offsetDays), null, today())!.capitalized;

  /// `remindAt` as the server stores it, [offsetDays] from today.
  String storedRemindAt(int offsetDays) => '${dayAt(offsetDays)}T00:00:00.000Z';

  group('setting a date', () {
    testWidgets('a dateless blocker says so on the row', (tester) async {
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
      );
      await pumpProject(tester);

      // Not silence: a blocker with no date is a task that will never ask
      // again, and the row is where that is noticed.
      expect(find.textContaining('без даты'), findsOneWidget);
    });

    testWidgets('picking a day sends that calendar day, and the chip shows it', (
      tester,
    ) async {
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
      );
      await pumpProject(tester);
      await openTask(tester, 'Жду кабель');

      await openDateSheet(tester);
      expect(find.text('Когда этим заняться'), findsOneWidget);
      // No time step behind the day: a date alone is the common case.
      await pickDay(tester, DateTime.now().day);

      final patch = server.patches.last;
      expect(patch.body['remindTime'], isNull);
      expect(
        patch.body['remindAt'],
        today(),
        reason: 'a bare calendar date, not an instant',
      );
      expect(chip('Сегодня'), findsOneWidget);
      expect(find.text('Пуш в это время. Без времени — без пуша.'), findsNothing);
    });

    testWidgets('a time is its own step after the day, and goes with it', (
      tester,
    ) async {
      server.addTask(projectId: projectId, title: 'Позвонить');
      await pumpProject(tester);
      await openTask(tester, 'Позвонить');
      // No time without a date.
      expect(find.text('+ Время'), findsNothing);

      await openDateSheet(tester);
      await pickDay(tester, DateTime.now().day);
      await tester.tap(find.text('+ Время'));
      await tester.pumpAndSettle();
      expect(find.text('Пуш в это время. Без времени — без пуша.'), findsOneWidget);
      await tester.tap(find.text('15:00'));
      await settle(tester);

      expect(server.patches.last.body, <String, dynamic>{
        'remindAt': today(),
        'remindTime': '15:00',
      });
      expect(timeChip('15:00'), findsOneWidget);
    });

    testWidgets('the time can be taken off, keeping the day', (tester) async {
      server.addTask(
        projectId: projectId,
        title: 'Позвонить',
        remindAt: storedRemindAt(2),
        remindTime: '14:30',
      );
      await pumpProject(tester);
      await openTask(tester, 'Позвонить');
      expect(chip(label(2)), findsOneWidget);
      expect(timeChip('14:30'), findsOneWidget);

      await tester.tap(find.byTooltip('Убрать время'));
      await settle(tester);

      expect(server.patches.last.body, <String, dynamic>{
        'remindAt': dayAt(2),
        'remindTime': null,
      });
      expect(timeChip('14:30'), findsNothing);
      expect(timeChip('+ Время'), findsOneWidget);
      expect(chip(label(2)), findsOneWidget);
    });

    testWidgets('a day-only date offers to add a time, not remove one', (
      tester,
    ) async {
      server.addTask(
        projectId: projectId,
        title: 'Позвонить',
        remindAt: storedRemindAt(2),
      );
      await pumpProject(tester);
      await openTask(tester, 'Позвонить');
      expect(find.byTooltip('Убрать время'), findsNothing);

      await tester.tap(find.text('+ Время'));
      await tester.pumpAndSettle();
      expect(find.text('Убрать время'), findsNothing);
      await tester.tap(find.text('9:00'));
      await settle(tester);

      expect(server.patches.last.body, <String, dynamic>{
        'remindAt': dayAt(2),
        'remindTime': '09:00',
      });
    });

    testWidgets('closing the time sheet changes nothing', (tester) async {
      server.addTask(
        projectId: projectId,
        title: 'Позвонить',
        remindAt: storedRemindAt(2),
        remindTime: '14:30',
      );
      await pumpProject(tester);
      await openTask(tester, 'Позвонить');
      await tester.tap(find.text('14:30'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Закрыть').last);
      await settle(tester);

      expect(server.patches, isEmpty);
      expect(timeChip('14:30'), findsOneWidget);
    });

    testWidgets('changing the day keeps the time', (tester) async {
      server.addTask(
        projectId: projectId,
        title: 'Позвонить',
        remindAt: storedRemindAt(2),
        remindTime: '14:30',
      );
      await pumpProject(tester);
      await openTask(tester, 'Позвонить');
      await openDateSheet(tester);
      // The sheet says so.
      expect(find.text('Время 14:30 сохранится'), findsOneWidget);
      await tester.tap(find.text('Завтра'));
      await settle(tester);

      expect(server.patches.last.body, <String, dynamic>{
        'remindAt': dayAt(1),
        'remindTime': '14:30',
      });
    });

    testWidgets('changing an existing date opens on the day already set', (
      tester,
    ) async {
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: storedRemindAt(3),
      );
      await pumpProject(tester);

      // The row carries the date read-only -- a blocker's date is when to
      // check...
      final rowLabel = formatTaskDate(dayAt(3), null, today())!.text;
      expect(find.textContaining('проверить $rowLabel'), findsOneWidget);

      // ...and the task screen is where it is changed.
      await openTask(tester, 'Жду кабель');
      await openDateSheet(tester);

      // The sheet holds the stored calendar day rather than one either side
      // of it -- which is what `DateTime.parse(...).toLocal()` would have
      // produced west of UTC.
      expect(tester.widget<DateSheet>(find.byType(DateSheet)).current, dayAt(3));
    });

    testWidgets('closing the date sheet changes nothing', (tester) async {
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
      );
      await pumpProject(tester);
      await openTask(tester, 'Жду кабель');

      await openDateSheet(tester);
      await tester.tap(find.byTooltip('Закрыть').last);
      await settle(tester);

      expect(server.patches, isEmpty);
      expect(find.text('+ Дата'), findsOneWidget);
    });
  });

  group('clearing a date', () {
    testWidgets(
      'sends an explicit null and the chip goes back to offering one',
      (tester) async {
        server.addTask(
          projectId: projectId,
          title: 'Жду кабель',
          status: 'blocked',
          remindAt: storedRemindAt(3),
        );
        await pumpProject(tester);
        await openTask(tester, 'Жду кабель');

        await tester.tap(find.byTooltip('Снять дату'));
        await settle(tester);

        expect(server.patches.last.body.containsKey('remindAt'), isTrue);
        expect(server.patches.last.body['remindAt'], isNull);
        expect(find.text('+ Дата'), findsOneWidget);
      },
    );

    testWidgets('one cross takes the time with the date', (tester) async {
      server.addTask(
        projectId: projectId,
        title: 'Позвонить',
        remindAt: storedRemindAt(3),
        remindTime: '14:30',
      );
      await pumpProject(tester);
      await openTask(tester, 'Позвонить');

      await tester.tap(find.byTooltip('Снять дату'));
      await settle(tester);

      expect(server.patches.last.body, <String, dynamic>{'remindAt': null});
      expect(find.text('+ Дата'), findsOneWidget);
      expect(find.text('+ Время'), findsNothing);
    });

    testWidgets('«Снять дату» in the sheet does the same', (tester) async {
      server.addTask(
        projectId: projectId,
        title: 'Позвонить',
        remindAt: storedRemindAt(3),
      );
      await pumpProject(tester);
      await openTask(tester, 'Позвонить');
      await openDateSheet(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Снять дату'));
      await settle(tester);

      expect(server.patches.last.body, <String, dynamic>{'remindAt': null});
    });

    testWidgets('no confirmation dialog in front of it', (tester) async {
      // Deliberate: the date is one tap from being set again and the task is
      // untouched, so a dialog would make the frequent correction as heavy as
      // the rare destruction.
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: storedRemindAt(3),
      );
      await pumpProject(tester);
      await openTask(tester, 'Жду кабель');

      await tester.tap(find.byTooltip('Снять дату'));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);

      // Let the PATCH finish: dio arms a receive-timeout timer per request, and
      // flutter_test fails a test that leaves one pending.
      await settle(tester);
    });
  });

  /// The chain of «blocking a task» still uses the Material pickers: the day,
  /// then the time («Без времени» unless [time]).
  Future<void> pickChainDay(
    WidgetTester tester,
    int dayOfMonth, {
    bool time = false,
  }) async {
    await tester.tap(find.text('$dayOfMonth').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Во сколько напомнить'), findsOneWidget);
    await tester.tap(find.text(time ? 'Готово' : 'Без времени'));
    await settle(tester);
  }

  group('blocking a task', () {
    testWidgets('offers the date immediately, as one gesture', (tester) async {
      server.addTask(projectId: projectId, title: 'Жду кабель');
      await pumpProject(tester);

      // From the row: a long press on the status circle is the three-way
      // choice. The chaining rule lives in `setTaskStatus`, so it applies here
      // and on the task screen alike.
      await tester.longPress(find.byTooltip('Отметить сделанной'));
      await settle(tester);
      await tester.tap(find.text('Блокер').last);
      await settle(tester);

      // Without this the app fills up with dateless blockers -- tasks that are
      // stuck and will never say so again.
      expect(find.text('Когда напомнить'), findsOneWidget);

      final today = DateTime.now();
      await pickChainDay(tester, today.day);

      expect(server.patches, hasLength(2));
      expect(server.patches[0].body['status'], 'blocked');
      expect(
        server.patches[1].body['remindAt'],
        '${_pad4(today.year)}-${_pad2(today.month)}-${_pad2(today.day)}',
      );
    });

    testWidgets('the task screen chains it the same way', (tester) async {
      // Two screens, one rule. A copy of the rule in each is a copy that drifts.
      server.addTask(projectId: projectId, title: 'Жду кабель');
      await pumpProject(tester);
      await openTask(tester, 'Жду кабель');

      await tester.tap(find.text('Блокер'));
      await settle(tester);

      expect(find.text('Когда напомнить'), findsOneWidget);
    });

    testWidgets('cancelling leaves a legitimate dateless blocker', (
      tester,
    ) async {
      server.addTask(projectId: projectId, title: 'Жду кабель');
      await pumpProject(tester);

      await tester.longPress(find.byTooltip('Отметить сделанной'));
      await settle(tester);
      await tester.tap(find.text('Блокер').last);
      await settle(tester);
      await tester.tap(find.text('Отмена'));
      await settle(tester);

      // "blocked, and I do not know when" is a real answer, not a mistake.
      expect(server.patches, hasLength(1));
      expect(server.patches.single.body['status'], 'blocked');
      expect(find.textContaining('без даты'), findsOneWidget);
    });

    testWidgets('a task that already has a date is not asked again', (
      tester,
    ) async {
      // Re-blocking a task whose date survived from before: nothing to ask.
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: storedRemindAt(5),
      );
      await pumpProject(tester);

      await tester.longPress(find.byTooltip('Блокер — снять'));
      await settle(tester);
      await tester.tap(find.text('Открыта').last);
      await settle(tester);

      expect(find.text('Когда напомнить'), findsNothing);
      // Leaving `blocked` clears the date -- F3's rule, unchanged.
      expect(server.patches.single.body['remindAt'], isNull);
    });
  });

  group('a date is visible on the row', () {
    testWidgets('a blocker dated today says «проверить сегодня»', (
      tester,
    ) async {
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
        remindAt: storedRemindAt(0),
      );
      server.addTask(
        projectId: projectId,
        title: 'Ждём плитку',
        status: 'blocked',
        remindAt: storedRemindAt(4),
      );
      await pumpProject(tester);

      // A blocker's date is when to check (today-decisions, 6).
      expect(find.textContaining('проверить сегодня'), findsOneWidget);
      final soon = formatTaskDate(dayAt(4), null, today())!.text;
      expect(find.textContaining('проверить $soon'), findsOneWidget);
      // No more «пора»: the date label says the day.
      expect(find.textContaining('пора'), findsNothing);
    });

    testWidgets('an open task shows its date on the row, without "ждёт"', (
      tester,
    ) async {
      server.addTask(
        projectId: projectId,
        title: 'Обычная',
        remindAt: storedRemindAt(2),
      );
      await pumpProject(tester);

      final label = formatTaskDate(dayAt(2), null, today())!.text;
      expect(find.textContaining(label), findsWidgets);
      expect(find.textContaining('без даты'), findsNothing);
      expect(find.textContaining('ждёт'), findsNothing);
    });

    testWidgets('a task that is not blocked can be given a date', (
      tester,
    ) async {
      server.addTask(projectId: projectId, title: 'Обычная');
      await pumpProject(tester);
      await openTask(tester, 'Обычная');

      await openDateSheet(tester);
      await pickDay(tester, DateTime.now().day);

      expect(server.tasks.single['status'], 'pending');
      expect(server.patches.last.body['remindAt'], today());
      expect(chip('Сегодня'), findsOneWidget);
    });
  });
}

String _pad2(int value) => value.toString().padLeft(2, '0');

String _pad4(int value) => value.toString().padLeft(4, '0');

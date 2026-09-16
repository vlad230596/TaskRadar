import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/screens/project_screen.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';

/// The gesture this whole iteration exists for, at the widget level (F4):
/// "блокер → выбрал дату → дата наступила → видно → снял".
///
/// The date picker is a real `showDatePicker`, driven the way a person drives
/// it, because the interesting part is not that a callback fires but **which
/// day ends up in the request body** -- and that is exactly where a timezone
/// off-by-one hides.
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
          home: ProjectScreen(projectId: projectId),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
  }

  /// `remindAt` as the server stores it, [offsetDays] from today.
  String storedRemindAt(int offsetDays) {
    final day = DateTime.now().add(Duration(days: offsetDays));
    return '${_pad4(day.year)}-${_pad2(day.month)}-${_pad2(day.day)}'
        'T00:00:00.000Z';
  }

  /// Picks a day in the open date picker by tapping its day-of-month cell, then
  /// confirming.
  ///
  /// Tapping a number rather than typing into the input: the number is what a
  /// person taps, and the whole risk being tested is that the day they see is
  /// not the day that gets sent.
  Future<void> pickDay(WidgetTester tester, int dayOfMonth) async {
    await tester.tap(find.text('$dayOfMonth').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово'));
    await settle(tester);
  }

  group('setting a date on a blocker', () {
    testWidgets('a dateless blocker offers the picker in words', (
      tester,
    ) async {
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
      );
      await pumpProject(tester);

      // Not the F3 placeholder ("дата появится на F4"), and not silence: a
      // blocker with no date is a task that will never ask again, so the row
      // says what to do about it.
      expect(find.text('напомнить…'), findsOneWidget);
    });

    testWidgets('picking a day sends that calendar day, and the row shows it', (
      tester,
    ) async {
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
      );
      await pumpProject(tester);

      await tester.tap(find.text('напомнить…'));
      await tester.pumpAndSettle();
      expect(find.text('Когда напомнить'), findsOneWidget);

      // The picker opens on today; pick today, which is always selectable
      // (`firstDate` is today, because a past reminder can never fire).
      final today = DateTime.now();
      await pickDay(tester, today.day);

      final patch = server.patches.last;
      expect(patch.body.keys, <String>['remindAt']);
      expect(
        patch.body['remindAt'],
        '${_pad4(today.year)}-${_pad2(today.month)}-${_pad2(today.day)}',
        reason: 'a bare calendar date, not an instant',
      );

      // Dated today, so the row is the loud "act on this" variant.
      expect(find.textContaining('Напомнить · '), findsOneWidget);
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

      final chosen = DateTime.now().add(const Duration(days: 3));
      expect(
        find.text('Ждём до ${_pad2(chosen.day)}.${_pad2(chosen.month)}'),
        findsOneWidget,
      );

      await tester.tap(find.textContaining('Ждём до'));
      await tester.pumpAndSettle();

      // The picker's own header is the proof it opened on the stored day rather
      // than one day either side of it -- which is what
      // `DateTime.parse(...).toLocal()` would have produced west of UTC.
      expect(find.byType(DatePickerDialog), findsOneWidget);
      final dialog = tester.widget<DatePickerDialog>(
        find.byType(DatePickerDialog),
      );
      expect(
        dialog.initialDate,
        DateTime(chosen.year, chosen.month, chosen.day),
      );
    });

    testWidgets('cancelling the picker changes nothing', (tester) async {
      server.addTask(
        projectId: projectId,
        title: 'Жду кабель',
        status: 'blocked',
      );
      await pumpProject(tester);

      await tester.tap(find.text('напомнить…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await settle(tester);

      expect(server.patches, isEmpty);
      expect(find.text('напомнить…'), findsOneWidget);
    });
  });

  group('clearing a date', () {
    testWidgets(
      'sends an explicit null and the row goes back to offering one',
      (tester) async {
        server.addTask(
          projectId: projectId,
          title: 'Жду кабель',
          status: 'blocked',
          remindAt: storedRemindAt(3),
        );
        await pumpProject(tester);

        await tester.tap(find.byTooltip('Убрать дату напоминания'));
        await settle(tester);

        expect(server.patches.last.body.containsKey('remindAt'), isTrue);
        expect(server.patches.last.body['remindAt'], isNull);
        expect(find.text('напомнить…'), findsOneWidget);
      },
    );

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

      await tester.tap(find.byTooltip('Убрать дату напоминания'));
      await tester.pump();

      expect(find.byType(AlertDialog), findsNothing);

      // Let the PATCH finish: dio arms a receive-timeout timer per request, and
      // flutter_test fails a test that leaves one pending.
      await settle(tester);
    });
  });

  group('blocking a task', () {
    testWidgets('offers the date immediately, as one gesture', (tester) async {
      server.addTask(projectId: projectId, title: 'Жду кабель');
      await pumpProject(tester);

      await tester.tap(find.byTooltip('Статус: Ожидает'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Блокер').last);
      await settle(tester);

      // Without this the app fills up with dateless blockers -- tasks that are
      // stuck and will never say so again.
      expect(find.text('Когда напомнить'), findsOneWidget);

      final today = DateTime.now();
      await pickDay(tester, today.day);

      expect(server.patches, hasLength(2));
      expect(server.patches[0].body['status'], 'blocked');
      expect(
        server.patches[1].body['remindAt'],
        '${_pad4(today.year)}-${_pad2(today.month)}-${_pad2(today.day)}',
      );
    });

    testWidgets('cancelling leaves a legitimate dateless blocker', (
      tester,
    ) async {
      server.addTask(projectId: projectId, title: 'Жду кабель');
      await pumpProject(tester);

      await tester.tap(find.byTooltip('Статус: Ожидает'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Блокер').last);
      await settle(tester);
      await tester.tap(find.text('Отмена'));
      await settle(tester);

      // "blocked, and I do not know when" is a real answer, not a mistake.
      expect(server.patches, hasLength(1));
      expect(server.patches.single.body['status'], 'blocked');
      expect(find.text('напомнить…'), findsOneWidget);
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

      await tester.tap(find.byTooltip('Статус: Блокер'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ожидает').last);
      await settle(tester);

      expect(find.text('Когда напомнить'), findsNothing);
      // Leaving `blocked` clears the date -- F3's rule, unchanged.
      expect(server.patches.single.body['remindAt'], isNull);
    });
  });

  group('a due date is visible', () {
    testWidgets('today reads as "Напомнить", a future day as "Ждём до"', (
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

      expect(find.textContaining('Напомнить · '), findsOneWidget);
      expect(find.textContaining('Ждём до '), findsOneWidget);
    });

    testWidgets('a non-blocked task has no reminder line at all', (
      tester,
    ) async {
      // The date is only meaningful while the task is waiting on something, and
      // `remindersFromBoard` arms nothing for any other status -- an input here
      // would be an input whose value does nothing.
      server.addTask(
        projectId: projectId,
        title: 'Обычная',
        remindAt: storedRemindAt(2),
      );
      await pumpProject(tester);

      expect(find.text('напомнить…'), findsNothing);
      expect(find.textContaining('Ждём до'), findsNothing);
    });
  });
}

String _pad2(int value) => value.toString().padLeft(2, '0');

String _pad4(int value) => value.toString().padLeft(4, '0');

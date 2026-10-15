import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/project_providers.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/screens/shell_screen.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/voice/voice_model.dart';

import 'support/fake_backend.dart';
import 'support/fake_board_snapshot_store.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_project_backend.dart';
import 'support/fake_settings_store.dart';
import 'support/fake_voice.dart';

/// The alarm queue follows the board whatever is on screen.
///
/// A reminder set on the phone in a project or a task -- a route pushed over
/// the shell -- was never armed: the only subscriber of `boardReminderBridge`
/// was a `ref.watch` in the planning screen, and Riverpod pauses a covered
/// route's subscriptions. Found on a real phone whose OS alarm queue had
/// nothing for two reminders that never fired.
void main() {
  late FakeBackend backend;
  late FakeProjectBackend server;
  late FakeNotificationGateway gateway;

  setUp(() {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    gateway = FakeNotificationGateway();

    // The work mode's own reads; what they answer is not what this is about.
    backend.on('GET', '/history', (_) => jsonResponse(_emptyHistory()));

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (MethodCall call) async =>
              call.method == 'getLocalTimezone' ? 'Europe/Moscow' : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        );
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          boardSnapshotStoreProvider.overrideWithValue(
            FakeBoardSnapshotStore(),
          ),
          notificationGatewayProvider.overrideWithValue(gateway),
          settingsStoreProvider.overrideWithValue(FakeSettingsStore()),
          voiceRecorderProvider.overrideWithValue(FakeVoiceRecorder()),
          speechRecognizerProvider.overrideWithValue(FakeSpeechRecognizer()),
          voiceModelInstallationProvider.overrideWith(_ReadyModel.new),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const ShellScreen(),
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(ShellScreen)));
  }

  /// A date a week from now, as the date picker hands it over.
  String nextWeek() {
    final day = DateTime.now().add(const Duration(days: 7));
    return '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
  }

  /// Sets a reminder on the one task the way the task screen does, and lets
  /// the write, the board splice and the resync finish.
  Future<void> remind(
    WidgetTester tester,
    ProviderContainer container,
    String projectId,
  ) async {
    await tester.runAsync(() async {
      container.listen(projectTasksProvider(projectId), (_, _) {});
      final task = (await container.read(
        projectTasksProvider(projectId).future,
      )).single;
      await container
          .read(projectTasksProvider(projectId).notifier)
          .setRemindAt(task, nextWeek(), time: '08:15');
    });
    await settle(tester);
    await tester.runAsync(() => container.read(reminderSyncProvider.future));
    await settle(tester);
  }

  // Not the bug that was found -- `IndexedStack` keeps hidden modes ticking --
  // but the other way the planning screen can be off screen.
  testWidgets('a reminder set while the work mode is shown is armed', (
    tester,
  ) async {
    final projectId = server.addProject(name: 'Школа');
    server.addTask(projectId: projectId, title: 'Забрать документы');

    final container = await pumpShell(tester);
    await tester.tap(find.text('Работа'));
    await settle(tester);
    expect(gateway.scheduleCalls, isEmpty);

    await remind(tester, container, projectId);

    expect(gateway.scheduleCalls, hasLength(1));
    final fireAt = gateway.scheduleCalls.single.fireAt;
    expect((fireAt.hour, fireAt.minute), (8, 15));
  });

  testWidgets('a reminder set under a pushed route is armed', (tester) async {
    final projectId = server.addProject(name: 'Почта');
    server.addTask(projectId: projectId, title: 'Сделать сохранялку');

    final container = await pumpShell(tester);
    // Anything opaque over the shell: the dictation screen, a task, a project.
    appNavigatorKeyOf(
      tester,
    ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
    // Past the page transition, after which the shell is offstage.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ShellScreen), findsNothing);

    await remind(tester, container, projectId);

    expect(gateway.scheduleCalls, hasLength(1));
  });
}

NavigatorState appNavigatorKeyOf(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator));

Map<String, dynamic> _emptyHistory() => <String, dynamic>{
  'range': '7d',
  'from': null,
  'to': DateTime.now().toUtc().toIso8601String(),
  'closedByDay': <dynamic>[],
  'closedTotal': 0,
  'projects': <dynamic>[],
  'stale': <dynamic>[],
};

class _ReadyModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => VoiceModelReady(fakeInstalledModel());
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/reminder_schedule.dart';
import 'package:taskradar/notifications/notification_gateway.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/screens/notification_bench_screen.dart';
import 'package:taskradar/screens/settings_screen.dart';

import 'support/fake_backend.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';
import 'support/fake_voice.dart';

/// The settings screen (F4): the one real setting, and the diagnostic that
/// explains why reminders might not be arriving.
void main() {
  late FakeNotificationGateway gateway;
  late FakeSettingsStore settings;
  late FakeVoiceModelStore voiceModels;
  late FakeBackend backend;

  /// What `GET /dictation/model` answers, and every `PUT` body received. The
  /// fake stores like the server does: the default by name is "no choice".
  Map<String, dynamic>? dictationModel;
  late List<Map<String, dynamic>> modelPuts;

  setUp(() {
    backend = FakeBackend();
    dictationModel = <String, dynamic>{
      'model': 'stealth/space-bunny-alpha',
      'defaultModel': 'stealth/space-bunny-alpha',
      'override': null,
    };
    modelPuts = <Map<String, dynamic>>[];
    backend.on('GET', '/dictation/model', (match) {
      final body = dictationModel;
      return body == null
          ? jsonResponse(<String, dynamic>{
              'error': 'DictationUnavailableError',
              'message': 'Dictation parsing is not configured',
            }, statusCode: 503)
          : jsonResponse(body);
    });
    backend.on('PUT', '/dictation/model', (match) {
      modelPuts.add(match.body);
      final chosen = match.body['model'] as String?;
      final fallback = dictationModel!['defaultModel'] as String;
      dictationModel = <String, dynamic>{
        'model': chosen ?? fallback,
        'defaultModel': fallback,
        'override': chosen,
      };
      return jsonResponse(dictationModel);
    });

    gateway = FakeNotificationGateway();
    settings = FakeSettingsStore();
    voiceModels = FakeVoiceModelStore();

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

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(backend.client),
          notificationGatewayProvider.overrideWithValue(gateway),
          settingsStoreProvider.overrideWithValue(settings),
          voiceModelStoreProvider.overrideWithValue(voiceModels),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the reminder hour', () {
    testWidgets('shows the default when nothing has been saved', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text('09:00'), findsOneWidget);
      expect(find.textContaining('по местному времени'), findsOneWidget);
    });

    testWidgets('shows the saved hour, not the default', (tester) async {
      settings.time = const ReminderTime(7, 30);
      await pumpSettings(tester);

      expect(find.text('07:30'), findsOneWidget);
      expect(find.text('09:00'), findsNothing);
    });

    testWidgets('picking a new hour saves it', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Время утреннего напоминания'));
      await tester.pumpAndSettle();
      expect(find.text('Когда напоминать'), findsOneWidget);

      // The dial is awkward to drive; the keyboard entry mode is the same code
      // path for the value that matters.
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, '6');
      await tester.enterText(fields.last, '45');
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      expect(settings.writes, <ReminderTime>[const ReminderTime(6, 45)]);
      expect(find.text('06:45'), findsOneWidget);
    });

    testWidgets('a failed save is reported without losing the choice', (
      tester,
    ) async {
      await pumpSettings(tester);
      settings.writeFailure = StateError('disk full');

      await tester.tap(find.text('Время утреннего напоминания'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.keyboard_outlined));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.first, '6');
      await tester.enterText(fields.last, '45');
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      // Applied (the alarms are re-armed at the hour the user asked for) and
      // said out loud (it will not survive a restart).
      expect(find.text('06:45'), findsOneWidget);
      expect(find.textContaining('сохранить его не удалось'), findsOneWidget);
    });
  });

  group('permissions', () {
    testWidgets('a denial is the loud case, because it is the silent one', (
      tester,
    ) async {
      // A denied POST_NOTIFICATIONS breaks reminders with no error anywhere:
      // scheduling succeeds, the alarm fires, the OS drops the notification.
      gateway.permissionState = const NotificationPermissionState(
        notificationsEnabled: false,
        canScheduleExactAlarms: false,
      );
      await pumpSettings(tester);

      expect(find.textContaining('Уведомления запрещены'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_off), findsOneWidget);
    });

    testWidgets('missing exact alarms is a degradation, said as one', (
      tester,
    ) async {
      gateway.permissionState = const NotificationPermissionState(
        notificationsEnabled: true,
        canScheduleExactAlarms: false,
      );
      await pumpSettings(tester);

      expect(find.textContaining('может опоздать на часы'), findsOneWidget);
    });

    testWidgets('all granted says so plainly', (tester) async {
      await pumpSettings(tester);

      expect(
        find.text('Уведомления и точные будильники разрешены.'),
        findsOneWidget,
      );
    });

    testWidgets('a platform with no permission model says that instead', (
      tester,
    ) async {
      gateway.support = NotificationSupport.windows;
      await pumpSettings(tester);

      expect(find.text('Разрешения'), findsOneWidget);
      expect(find.textContaining('не входит в приёмку F1'), findsOneWidget);
    });
  });

  testWidgets('the F1 bench is reachable from here', (tester) async {
    // It stays because NOTIFICATIONS-CHECKLIST.md is still the only way to
    // answer "did the alarm survive the night on this phone".
    await pumpSettings(tester);

    await tester.tap(find.text(NotificationBenchScreen.title));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationBenchScreen), findsOneWidget);
  });

  /// The speech model (F9). A quarter of a gigabyte is a decision, so it is
  /// presented as one.
  group('the speech model', () {
    testWidgets('offers the download with the size in it', (tester) async {
      await pumpSettings(tester);

      // The number before the decision, not after it: downloading 163 MB on
      // whatever connection somebody happens to be on is how an app gets
      // uninstalled.
      expect(find.textContaining('163 МБ'), findsOneWidget);
      expect(find.text('Скачать'), findsOneWidget);
    });

    testWidgets('downloading it ends in "готов"', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Скачать'));
      await tester.pumpAndSettle();

      expect(voiceModels.installCount, 1);
      expect(find.text('Голосовой ввод готов'), findsOneWidget);
      expect(find.text('Удалить'), findsOneWidget);
    });

    testWidgets('a failed download says why, and offers another go', (
      tester,
    ) async {
      voiceModels.installFailure = Exception('диск полон');
      await pumpSettings(tester);

      await tester.tap(find.text('Скачать'));
      await tester.pumpAndSettle();

      // "Не удалось" with no reason is useless for something that can fail on
      // the network, on disk space, or on a file the archive did not contain.
      expect(find.textContaining('диск полон'), findsOneWidget);
      expect(find.text('Ещё раз'), findsOneWidget);
    });

    testWidgets('an installed model says what it costs and can be deleted', (
      tester,
    ) async {
      voiceModels.present = true;
      await pumpSettings(tester);

      expect(find.text('Голосовой ввод готов'), findsOneWidget);
      expect(find.textContaining('236 МБ'), findsOneWidget);
      // The privacy claim is on screen, not just in a design document.
      expect(find.textContaining('никуда не отправляется'), findsOneWidget);

      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Удалить'));
      await tester.pumpAndSettle();

      expect(voiceModels.removeCount, 1);
      expect(find.text('Голосовой ввод'), findsOneWidget);
    });
  });

  group('the dictation model (F14)', () {
    testWidgets('shows the model in use, and that it is the default', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text('Модель разбора диктовки'), findsOneWidget);
      expect(
        find.text('stealth/space-bunny-alpha · по умолчанию с сервера'),
        findsOneWidget,
      );
    });

    testWidgets('a model typed here is saved, and said to be chosen here', (
      tester,
    ) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Модель разбора диктовки'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' qwen/qwen3-14b ');
      await tester.pump();
      await tester.tap(find.text('Сохранить'));
      await tester.pumpAndSettle();

      expect(modelPuts, <Map<String, dynamic>>[
        <String, dynamic>{'model': 'qwen/qwen3-14b'},
      ]);
      expect(
        find.text(
          'qwen/qwen3-14b · выбрана здесь, '
          'по умолчанию stealth/space-bunny-alpha',
        ),
        findsOneWidget,
      );
    });

    testWidgets('"По умолчанию" goes back to the server\'s model', (
      tester,
    ) async {
      dictationModel = <String, dynamic>{
        'model': 'qwen/qwen3-14b',
        'defaultModel': 'stealth/space-bunny-alpha',
        'override': 'qwen/qwen3-14b',
      };
      await pumpSettings(tester);

      await tester.tap(find.text('Модель разбора диктовки'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('По умолчанию'));
      await tester.pumpAndSettle();

      expect(modelPuts, <Map<String, dynamic>>[
        <String, dynamic>{'model': null},
      ]);
      expect(
        find.text('stealth/space-bunny-alpha · по умолчанию с сервера'),
        findsOneWidget,
      );
    });

    testWidgets('no model on the server: said, with nothing to edit', (
      tester,
    ) async {
      dictationModel = null;
      await pumpSettings(tester);

      expect(
        find.text('Разбор не настроен на сервере: нет ключа модели в .env.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Модель разбора диктовки'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}

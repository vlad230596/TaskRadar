import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/geofence_plan.dart';
import 'package:taskradar/geofence/location_access.dart';
import 'package:taskradar/models/task_location.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/geofence_providers.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/screens/settings_screen.dart';
import 'package:taskradar/widgets/editor/location_picker.dart';
import 'package:taskradar/widgets/editor/place_tile.dart';
import 'package:taskradar/widgets/editor/sections.dart';

import 'support/fake_backend.dart';
import 'support/fake_geofence.dart';
import 'support/fake_notification_gateway.dart';
import 'support/fake_settings_store.dart';
import 'support/fake_voice.dart';

/// Place reminders on screen: the settings switch with its permission flow,
/// the editor's place section, and the map picker (WP7).
void main() {
  late FakeGeofenceGateway geofences;
  late FakeLocationAccess access;
  late MemoryGeofenceStore store;
  late FakeSettingsStore settings;
  late FakeNotificationGateway notifications;

  setUp(() {
    geofences = FakeGeofenceGateway();
    access = FakeLocationAccess(level: LocationAccessLevel.denied);
    store = MemoryGeofenceStore();
    settings = FakeSettingsStore();
    notifications = FakeNotificationGateway();
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

  List<Override> overrides() => <Override>[
    apiClientProvider.overrideWithValue(FakeBackend().client),
    notificationGatewayProvider.overrideWithValue(notifications),
    settingsStoreProvider.overrideWithValue(settings),
    voiceModelStoreProvider.overrideWithValue(FakeVoiceModelStore()),
    geofenceGatewayProvider.overrideWithValue(geofences),
    locationAccessProvider.overrideWithValue(access),
    geofenceStoreProvider.overrideWithValue(store),
  ];

  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(),
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Switch placeSwitch(WidgetTester tester) =>
      tester.widget<Switch>(find.byType(Switch));

  group('settings: «Напоминания по месту»', () {
    testWidgets('is hidden where zones are not supported', (tester) async {
      geofences.supported = false;
      await pumpSettings(tester);
      expect(find.text('Напоминания по месту'), findsNothing);
    });

    testWidgets('is off by default', (tester) async {
      await pumpSettings(tester);
      expect(find.text('Напоминания по месту'), findsOneWidget);
      expect(placeSwitch(tester).value, isFalse);
    });

    testWidgets('foreground, then «всегда» turns it on', (tester) async {
      access.requestAnswers.addAll(<LocationAccessLevel>[
        LocationAccessLevel.whileInUse,
        LocationAccessLevel.always,
      ]);
      await pumpSettings(tester);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.textContaining('два разрешения'), findsOneWidget);
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();

      expect(find.text('Ещё одно разрешение'), findsOneWidget);
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      expect(access.requests, 2);
      expect(settings.placeReminders, isTrue);
      expect(placeSwitch(tester).value, isTrue);
      expect(find.textContaining('Отслеживается мест: 0'), findsOneWidget);
    });

    testWidgets('a refusal is explained and the switch stays off', (
      tester,
    ) async {
      access.requestAnswers.add(LocationAccessLevel.deniedForever);
      await pumpSettings(tester);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();

      expect(find.text('Нет доступа к геопозиции'), findsOneWidget);
      await tester.tap(find.text('Открыть настройки'));
      await tester.pumpAndSettle();

      expect(access.settingsOpened, 1);
      expect(settings.placeReminders, isNull);
      expect(placeSwitch(tester).value, isFalse);
    });

    testWidgets('«только во время использования» is not enough', (
      tester,
    ) async {
      access.level = LocationAccessLevel.whileInUse;
      await pumpSettings(tester);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продолжить'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Открыть'));
      await tester.pumpAndSettle();

      expect(find.textContaining('«во время использования»'), findsOneWidget);
      await tester.tap(find.text('Понятно'));
      await tester.pumpAndSettle();
      expect(settings.placeReminders, isNull);
      expect(placeSwitch(tester).value, isFalse);
    });

    testWidgets('cancelling the explanation asks nothing', (tester) async {
      await pumpSettings(tester);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(access.requests, 0);
      expect(placeSwitch(tester).value, isFalse);
    });

    testWidgets('switching off removes every zone', (tester) async {
      settings.placeReminders = true;
      access.level = LocationAccessLevel.always;
      final zone = PlannedGeofence(
        taskId: 'a',
        taskTitle: 'Купить',
        lat: 55.7,
        lng: 37.6,
        radius: 200,
      );
      geofences.zones[zone.id] = zone;
      store.zones = <String, PlannedGeofence>{zone.id: zone};
      await pumpSettings(tester);
      expect(placeSwitch(tester).value, isTrue);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(settings.placeReminders, isFalse);
      expect(geofences.zones, isEmpty);
      expect(store.zones, isEmpty);
    });

    testWidgets('on without background access says so', (tester) async {
      settings.placeReminders = true;
      access.level = LocationAccessLevel.whileInUse;
      await pumpSettings(tester);
      expect(find.textContaining('нет доступа к геопозиции в фоне'),
          findsOneWidget);
    });
  });

  group('PlaceTile', () {
    Future<void> pumpTile(
      WidgetTester tester, {
      TaskLocation? value,
      required ValueChanged<TaskLocation?> onChanged,
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            home: Scaffold(
              body: PlaceTile(value: value, onChanged: onChanged),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('empty: offers to add a place', (tester) async {
      await pumpTile(tester, onChanged: (_) {});
      expect(find.text('Напомнить по месту'), findsOneWidget);
    });

    testWidgets('shows the place, its status, and removes it', (tester) async {
      TaskLocation? changed = const TaskLocation(lat: 1, lng: 1);
      await pumpTile(
        tester,
        value: const TaskLocation(lat: 55.7, lng: 37.6, label: 'Аптека'),
        onChanged: (value) => changed = value,
      );
      expect(find.text('Аптека'), findsOneWidget);
      expect(find.textContaining('Радиус 200 м'), findsOneWidget);
      // The setting is off by default: the tile says the zone will not fire.
      expect(find.textContaining('выключены'), findsOneWidget);

      await tester.tap(find.byTooltip('Убрать место'));
      expect(changed, isNull);
    });

    testWidgets('says «только на телефоне» off Android', (tester) async {
      geofences.supported = false;
      await pumpTile(
        tester,
        value: const TaskLocation(lat: 55.7, lng: 37.6),
        onChanged: (_) {},
      );
      expect(find.text('Срабатывает только на телефоне'), findsOneWidget);
    });
  });

  group('editor slots', () {
    testWidgets('the chip and the section follow EditorExtras.location', (
      tester,
    ) async {
      final extras = EditorExtras();
      addTearDown(extras.dispose);
      EditorSectionScope scope() => EditorSectionScope(
        projectId: 'prj_1',
        task: null,
        extras: extras,
        expanded: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: extras,
                builder: (context, _) => Column(
                  children: <Widget>[
                    ...EditorSlots.chips(scope(), onOpen: () {}),
                    EditorSlots.location(scope()),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Место'), findsOneWidget); // the chip only
      expect(find.byType(PlaceTile), findsNothing);

      extras.location = const TaskLocation(lat: 55.7, lng: 37.6, label: 'Рынок');
      await tester.pumpAndSettle();
      expect(find.text('Рынок'), findsNWidgets(2)); // chip + section
      expect(find.byType(PlaceTile), findsOneWidget);

      await tester.tap(find.byTooltip('Убрать место').last);
      await tester.pumpAndSettle();
      expect(extras.location, isNull);
      expect(find.byType(PlaceTile), findsNothing);
    });
  });

  group('LocationPickerScreen', () {
    testWidgets('returns the centre, radius and label', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      access.level = LocationAccessLevel.always;
      access.position = (lat: 59.93, lng: 30.33);
      TaskLocation? result;

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<TaskLocation>(
                    MaterialPageRoute<TaskLocation>(
                      builder: (_) => LocationPickerScreen(
                        initial: const TaskLocation(
                          lat: 55.75,
                          lng: 37.61,
                          label: 'Магазин',
                        ),
                        tileProvider: _BlankTiles(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('© участники OpenStreetMap'), findsOneWidget);
      expect(find.byType(CircleLayer), findsOneWidget);
      expect(find.text('200 м'), findsWidgets);

      // Drag the slider to the far right: 1000 m.
      final slider = find.byType(Slider);
      await tester.drag(slider, const Offset(2000, 0));
      await tester.pumpAndSettle();
      expect(find.text('1000 м'), findsWidgets);

      // «Моё место» moves the pin.
      await tester.tap(find.text('Моё место'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  ');
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.radius, 1000);
      expect(result!.lat, closeTo(59.93, 1e-6));
      expect(result!.lng, closeTo(30.33, 1e-6));
      expect(result!.label, 'Место');
    });
  });
}

/// Tiles without the network: a 1×1 transparent PNG for every tile.
class _BlankTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_transparentPng);
}

final Uint8List _transparentPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

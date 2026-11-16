import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/dependencies.dart';
import 'package:taskradar/providers/reminder_providers.dart';
import 'package:taskradar/providers/voice_providers.dart';
import 'package:taskradar/theme/app_theme.dart';
import 'package:taskradar/voice/voice_model.dart';

import 'fake_backend.dart';
import 'fake_board_snapshot_store.dart';
import 'fake_capture_queue_store.dart';
import 'fake_history_backend.dart';
import 'fake_notification_gateway.dart';
import 'fake_project_backend.dart';
import 'fake_settings_store.dart';
import 'fake_voice.dart';
import 'layout_audit.dart';

/// Стенд для проверки вёрстки: данные «как у владельца, только хуже».
///
/// Длинные русские названия, проекты на двадцать задач (полоска точек длиннее
/// любой карточки), полтора десятка задач в работе, трёхзначные возрасты и
/// счётчики, второе пространство с длинным именем. Экраны, которые на
/// аккуратных данных приёмки (`zz_capture_*`) выглядят хорошо, на этих
/// показывают, где им тесно.
class LayoutBench {
  LayoutBench({this.singleScope = false}) {
    backend = FakeBackend();
    server = FakeProjectBackend(backend);
    history = FakeHistoryBackend(backend);
    _seed();
  }

  /// Одно пространство — тогда плитки складывают песочницу в сетку первой
  /// плиткой; с двумя доска делится по пространствам.
  final bool singleScope;

  late final FakeBackend backend;
  late final FakeProjectBackend server;
  late final FakeHistoryBackend history;
  final FakeSettingsStore settings = FakeSettingsStore();

  late final String homeProjectId;
  late final String richTaskId;

  static const List<String> _titles = <String>[
    'Посмотреть, почему не работает вентилятор в туалете. Позвонить в УК и '
        'спросить, чей это участок.',
    'Купить лампочки',
    'Заказать крючки для полок в ванной и заодно держатель для полотенец',
    'Обеспечить доступ к полке в кладовке',
    'Заменить болт на кухне в раковине, который подтекает уже вторую неделю',
    'Посмотреть статус Мишиной сим-карточки у оператора',
    'Выложить резюме прямо сегодня, пока не передумал',
    'Посмотреть лампочку дневного света в машине — мигает при запуске',
    'Записать Мишу к врачу',
    'Переклеить обои в коридоре',
    'Электроснабжение-дачного-участка-с-переоформлением-договора',
    'Разобрать антресоль',
  ];

  String _title(int i) => _titles[i % _titles.length];

  static const List<String> _statuses = <String>[
    'done',
    'done',
    'pending',
    'done',
    'blocked',
    'pending',
    'done',
    'pending',
  ];

  void _seed() {
    final second = singleScope
        ? 'scope_main'
        : server.addScope(
            name: 'Дача, гараж и всё, что за городом и не помещается',
            id: 'scope_dacha',
          );

    var focusedLeft = 15;
    String project(
      String name, {
      required int tasks,
      String scope = 'scope_main',
      int? notes,
      String createdAt = '2026-09-20T09:00:00.000Z',
      String? id,
    }) {
      final pid = server.addProject(
        name: name,
        id: id,
        scopeId: scope,
        createdAt: createdAt,
      );
      if (notes != null) server.projects[pid]!['noteCount'] = notes;
      for (var i = 0; i < tasks; i++) {
        server.addTask(
          projectId: pid,
          title: _title(i + name.length),
          status: _statuses[i % _statuses.length],
          focused: i % 3 == 2 && focusedLeft-- > 0,
        );
      }
      return pid;
    }

    homeProjectId = project('Дом', tasks: 22, notes: 3, id: 'prj_dom');
    project('Семья', tasks: 14, notes: 128);
    project('Машина', tasks: 4, createdAt: '2026-08-01T09:00:00.000Z');
    project('Личное', tasks: 9, notes: 1);
    project(
      'Ремонт квартиры на Профсоюзной улице после затопления соседями',
      tasks: 31,
      notes: 12,
      createdAt: '2025-01-15T09:00:00.000Z',
    );
    project('Пусто', tasks: 0);
    project('Дача', tasks: 18, scope: second);
    project(
      'Гараж и всё, что в нём лежит с прошлого года',
      tasks: 7,
      scope: second,
    );

    for (final name in <String>[
      'Старый ремонт балкона, который так и не закончили в прошлом году',
      'Отпуск',
    ]) {
      final pid = server.addProject(
        name: name,
        archivedAt: FakeProjectBackend.archivedAtStamp,
      );
      for (var i = 0; i < 9; i++) {
        server.addTask(projectId: pid, title: _title(i), status: 'done');
      }
    }

    final category = server.addCategory(
      projectId: homeProjectId,
      name: 'Сантехника и электрика в ванной',
    );
    richTaskId = server.addTask(
      projectId: homeProjectId,
      id: 'tsk_rich',
      title:
          'Посмотреть, почему не работает вентилятор в туалете. Позвонить в '
          'УК и спросить, чей это участок, и записать номер заявки.',
      description:
          'Вентилятор гудит, но не тянет. Номер УК — на двери подъезда. '
          'https://example.com/a/very/long/link/that/does/not/break/anywhere',
      status: 'blocked',
      remindAt: '2026-12-24T00:00:00.000Z',
      remindTime: '14:30',
      categoryId: category,
      focused: true,
      checklist: <Map<String, dynamic>>[
        for (var i = 0; i < 6; i++)
          <String, dynamic>{
            'id': 'item0000000$i',
            'text': i.isEven
                ? 'Проверить автомат в щитке, второй слева в верхнем ряду'
                : 'Снять решётку',
            'done': i < 2,
          },
      ],
      location: <String, dynamic>{
        'lat': 55.75,
        'lng': 37.61,
        'radius': 150,
        'label': 'Управляющая компания «Жилищник района Черёмушки»',
      },
    );
    server.addAttachment(taskId: richTaskId, bytes: _png);
    server.addAttachment(taskId: richTaskId, bytes: _png);
    history.events[richTaskId] = history.sampleJournal(richTaskId);

    for (var i = 0; i < 4; i++) {
      server.addNote(
        projectId: homeProjectId,
        title: 'Заметка про счётчики воды и показания за ${i + 1} квартал',
        content: 'Холодная 123, горячая 45. ' * 6,
      );
    }

    for (var i = 0; i < 14; i++) {
      server.addInboxItem(text: _title(i * 5 + 1));
    }

    history.history = history.historyJson(
      closedByDay: const <int>[13, 0, 41, 2, 0, 128, 1],
      stale: <Map<String, dynamic>>[
        for (var i = 0; i < 6; i++)
          history.staleJson(
            id: 'st$i',
            title: _title(i),
            projectName: i.isEven
                ? 'Ремонт квартиры на Профсоюзной улице после затопления'
                : 'Дом',
            status: i == 0 ? TaskStatus.blocked : TaskStatus.pending,
            ageDays: 400 + i,
            pendingDays: 300,
            blockedDays: 100 + i,
            focusedDaysAgo: i == 1 ? 2 : null,
          ),
      ],
      projects: <Map<String, dynamic>>[
        history.projectMovementJson(
          name: 'Ремонт квартиры на Профсоюзной улице после затопления',
          opened: 123,
          closed: 456,
        ),
        history.projectMovementJson(name: 'Дом', opened: 6, closed: 2),
        history.projectMovementJson(name: 'Семья', opened: 1000, closed: 999),
      ],
    );
  }

  /// Pumps [home] at [size] (logical px) with [textScale], settles it, and
  /// returns every layout problem: Flutter errors raised meanwhile plus what
  /// [auditWhileScrolling] finds.
  Future<List<String>> pumpAndAudit(
    WidgetTester tester,
    Widget home, {
    required Size size,
    required double textScale,
    Future<void> Function(WidgetTester tester)? then,

    /// Screen-specific geometry checks, run on the settled screen before it
    /// is scrolled; each string it returns is a problem. May be async (to
    /// take a picture of the screen, say).
    FutureOr<List<String>> Function(WidgetTester tester)? check,
  }) async {
    const dpr = 3.0;
    tester.view.physicalSize = size * dpr;
    tester.view.devicePixelRatio = dpr;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final found = <String>[];
    final errors = await captureLayoutErrors(() async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            apiClientProvider.overrideWithValue(backend.client),
            boardSnapshotStoreProvider.overrideWithValue(
              FakeBoardSnapshotStore(),
            ),
            captureQueueStoreProvider.overrideWithValue(
              FakeCaptureQueueStore(),
            ),
            notificationGatewayProvider.overrideWithValue(
              FakeNotificationGateway(),
            ),
            settingsStoreProvider.overrideWithValue(settings),
            deviceTimeZoneNameProvider.overrideWith(
              (ref) async => 'Europe/Moscow',
            ),
            voiceRecorderProvider.overrideWithValue(FakeVoiceRecorder()),
            speechRecognizerProvider.overrideWithValue(FakeSpeechRecognizer()),
            voiceModelInstallationProvider.overrideWith(_ReadyModel.new),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildAppTheme(),
            home: home,
            onGenerateRoute: AppRoutes.onGenerateRoute,
          ),
        ),
      );
      await _settle(tester);
      if (then != null) {
        await then(tester);
        await _settle(tester);
      }
      if (check != null) found.addAll(await check(tester));
      found.addAll(await auditWhileScrolling(tester));
      // Unmount inside the capture: a dispose-time error is a finding too.
      await tester.pumpWidget(const SizedBox.shrink());
      // Let one-shot timers the screens started (debounces, retries) run out.
      await tester.pump(const Duration(minutes: 1));
    });
    return <String>[...errors, ...found];
  }

  static Future<void> _settle(WidgetTester tester) async {
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }
}

class _ReadyModel extends VoiceModelInstallation {
  @override
  VoiceModelState build() => VoiceModelReady(fakeInstalledModel());
}

/// A real 1x1 PNG, so a picture that does get decoded is not an error.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

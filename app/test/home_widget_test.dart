import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/project_badge.dart';
import 'package:taskradar/home_widget/home_widget_gateway.dart';
import 'package:taskradar/home_widget/home_widget_snapshot.dart';
import 'package:taskradar/models/focus_task.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/providers/focus_providers.dart';
import 'package:taskradar/providers/home_widget_providers.dart';
import 'package:taskradar/providers/notification_link_providers.dart';
import 'package:taskradar/widgets/home_widget_scope.dart';

/// The Android home-screen widget «В работе»: the snapshot the app pushes to
/// it, the channel it is pushed over, and the scope that decides when.
///
/// The native side (Kotlin, `android/app/src/main/kotlin/.../widget/`) has no
/// tests here; it is compiled by `flutter build apk` and reads exactly the JSON
/// these tests pin down.
void main() {
  FocusTask row(
    String id, {
    required String project,
    String? projectName,
    String title = 'Задача',
    TaskStatus status = TaskStatus.pending,
  }) => FocusTask(
    id: id,
    projectId: project,
    title: title,
    description: null,
    status: status,
    position: 1,
    remindAt: null,
    createdAt: '2026-11-01T09:00:00.000Z',
    updatedAt: '2026-11-01T09:00:00.000Z',
    focusedAt: '2026-11-01T09:00:00.000Z',
    project: FocusProject(id: project, name: projectName ?? project),
  );

  final at = DateTime.utc(2026, 11, 11, 9, 40);

  group('buildHomeWidgetSnapshot', () {
    test('groups by project, in the order of each project\'s first task', () {
      final snapshot = buildHomeWidgetSnapshot(<FocusTask>[
        row('t1', project: 'p_home', projectName: 'Дом'),
        row('t2', project: 'p_tr', projectName: 'TaskRadar'),
        row('t3', project: 'p_home', projectName: 'Дом'),
        row('t4', project: 'p_family', projectName: 'Семья'),
        row('t5', project: 'p_tr', projectName: 'TaskRadar'),
      ], updatedAt: at);

      expect(snapshot.projects.map((p) => p.name), <String>[
        'Дом',
        'TaskRadar',
        'Семья',
      ]);
      expect(
        snapshot.projects.map((p) => p.tasks.map((t) => t.id).toList()),
        <List<String>>[
          <String>['t1', 't3'],
          <String>['t2', 't5'],
          <String>['t4'],
        ],
      );
    });

    test('counts per project and in total', () {
      final snapshot = buildHomeWidgetSnapshot(<FocusTask>[
        row('a', project: 'p1'),
        row('b', project: 'p2'),
        row('c', project: 'p1'),
        row('d', project: 'p1'),
      ], updatedAt: at);

      expect(snapshot.projects.map((p) => p.count), <int>[3, 1]);
      expect(snapshot.total, 4);
      expect(snapshot.toJson()['total'], 4);
      expect(
        (snapshot.toJson()['projects']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .map((p) => p['count']),
        <int>[3, 1],
      );
    });

    test('keeps the server order inside a project, blocked tasks included', () {
      final snapshot = buildHomeWidgetSnapshot(<FocusTask>[
        row(
          'z',
          project: 'p',
          title: 'Позже взятая',
          status: TaskStatus.blocked,
        ),
        row('a', project: 'p', title: 'Ещё одна'),
      ], updatedAt: at);

      final tasks = snapshot.projects.single.tasks;
      expect(tasks.map((t) => t.id), <String>['z', 'a']);
      expect(tasks.map((t) => t.blocked), <bool>[true, false]);
    });

    test('an empty set is a signed-in snapshot with no projects', () {
      final snapshot = buildHomeWidgetSnapshot(
        const <FocusTask>[],
        updatedAt: at,
      );

      expect(snapshot.signedIn, isTrue);
      expect(snapshot.projects, isEmpty);
      expect(snapshot.total, 0);
    });

    test('trims titles and names a blank one', () {
      final snapshot = buildHomeWidgetSnapshot(<FocusTask>[
        row('a', project: 'p', title: '  Купить кабель  '),
        row('b', project: 'p', title: '   '),
      ], updatedAt: at);

      expect(snapshot.projects.single.tasks.map((t) => t.title), <String>[
        'Купить кабель',
        'Без названия',
      ]);
    });

    test('gives the projects on the widget distinct badge colours', () {
      final names = <String>['Публикации', 'Дом', 'TaskRadar', 'Семья'];
      final snapshot = buildHomeWidgetSnapshot(<FocusTask>[
        for (final (i, name) in names.indexed)
          row('t$i', project: 'p$i', projectName: name),
      ], updatedAt: at);

      final expected = assignProjectBadgeColors(names);
      for (final project in snapshot.projects) {
        expect(project.badgeColor, expected[project.name]!.toARGB32());
        expect(project.badgeLetter, projectBadgeLetter(project.name));
      }
      expect(snapshot.projects.map((p) => p.badgeColor).toSet(), hasLength(4));
    });

    test('carries where the data came from', () {
      final cached = buildHomeWidgetSnapshot(
        <FocusTask>[row('a', project: 'p')],
        updatedAt: at,
        fromCache: true,
      );
      expect(cached.fromCache, isTrue);
      expect(cached.toJson()['updatedAt'], at.millisecondsSinceEpoch);
    });
  });

  group('serialization', () {
    test('round-trips through JSON', () {
      final snapshot = buildHomeWidgetSnapshot(
        <FocusTask>[
          row('t1', project: 'p1', projectName: 'Дом', title: 'Окна'),
          row(
            't2',
            project: 'p2',
            projectName: 'TaskRadar',
            title: 'Виджет',
            status: TaskStatus.blocked,
          ),
        ],
        updatedAt: at,
        fromCache: true,
      );

      final back = HomeWidgetSnapshot.decode(snapshot.encode());

      expect(back.updatedAt, at);
      expect(back.fromCache, isTrue);
      expect(back.signedIn, isTrue);
      expect(back.total, 2);
      expect(back.projects.map((p) => p.id), <String>['p1', 'p2']);
      expect(back.projects.last.tasks.single.title, 'Виджет');
      expect(back.projects.last.tasks.single.blocked, isTrue);
      expect(back.projects.last.tasks.single.projectId, 'p2');
      expect(
        back.projects.first.badgeColor,
        snapshot.projects.first.badgeColor,
      );
      expect(back.encode(), snapshot.encode());
    });

    test('pins the wire format the Kotlin reader expects', () {
      final json =
          jsonDecode(
                buildHomeWidgetSnapshot(<FocusTask>[
                  row('t1', project: 'p1', projectName: 'Дом', title: 'Окна'),
                ], updatedAt: at).encode(),
              )
              as Map<String, Object?>;

      expect(json.keys, <String>[
        'v',
        'updatedAt',
        'fromCache',
        'signedIn',
        'total',
        'projects',
      ]);
      expect(json['v'], HomeWidgetSnapshot.schemaVersion);
      final project =
          (json['projects']! as List<Object?>).single! as Map<String, Object?>;
      expect(project.keys, <String>[
        'id',
        'name',
        'count',
        'badge',
        'letter',
        'tasks',
      ]);
      // ARGB with the alpha byte set: Kotlin reads it with optLong().toInt().
      expect(project['badge'], isA<int>());
      expect((project['badge']! as int) >> 24, 0xFF);
      final task =
          (project['tasks']! as List<Object?>).single! as Map<String, Object?>;
      expect(task, <String, Object?>{
        'id': 't1',
        'projectId': 'p1',
        'title': 'Окна',
        'blocked': false,
      });
    });

    test('the signed-out snapshot has no tasks and says so', () {
      final json = HomeWidgetSnapshot.signedOut(at: at).toJson();
      expect(json['signedIn'], isFalse);
      expect(json['projects'], isEmpty);
      expect(json['total'], 0);
    });

    test('refuses another schema rather than guessing', () {
      expect(
        () => HomeWidgetSnapshot.decode('{"v": 99, "projects": []}'),
        throwsFormatException,
      );
    });
  });

  group('HomeWidgetAction.fromMap', () {
    test('reads a task tap and a refresh', () {
      expect(
        HomeWidgetAction.fromMap(<Object?, Object?>{
          'action': 'openTask',
          'taskId': 't1',
          'projectId': 'p1',
        }),
        const HomeWidgetOpenTask(taskId: 't1', projectId: 'p1'),
      );
      expect(
        HomeWidgetAction.fromMap(<Object?, Object?>{'action': 'refresh'}),
        const HomeWidgetRefresh(),
      );
    });

    test('ignores what it does not understand', () {
      expect(HomeWidgetAction.fromMap(null), isNull);
      expect(
        HomeWidgetAction.fromMap(<Object?, Object?>{'action': 'x'}),
        isNull,
      );
      expect(
        HomeWidgetAction.fromMap(<Object?, Object?>{'action': 'openTask'}),
        isNull,
      );
    });
  });

  group('MethodChannelHomeWidgetGateway', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(MethodChannelHomeWidgetGateway.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    tearDown(() => messenger.setMockMethodCallHandler(channel, null));

    test('publishes the JSON and takes the pending action', () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        if (call.method == 'takeAction') {
          return <String, String>{'action': 'openTask', 'taskId': 't9'};
        }
        return null;
      });

      final gateway = MethodChannelHomeWidgetGateway();
      await gateway.publish('{"v":1}');
      final action = await gateway.takeAction();

      expect(calls.map((c) => c.method), <String>['publish', 'takeAction']);
      expect(calls.first.arguments, '{"v":1}');
      expect(action, const HomeWidgetOpenTask(taskId: 't9'));
    });

    test('never throws when the platform side is missing', () async {
      final gateway = MethodChannelHomeWidgetGateway();
      await gateway.publish('{}');
      expect(await gateway.takeAction(), isNull);
    });
  });

  group('HomeWidgetScope', () {
    testWidgets('publishes the set, follows changes, and opens a tapped task', (
      tester,
    ) async {
      final gateway = _RecordingGateway();
      final link = _RecordingLink();
      final focus = _FakeFocusSet(<FocusTask>[
        row('t1', project: 'p1', projectName: 'Дом'),
        row('t2', project: 'p1', projectName: 'Дом'),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeWidgetGatewayProvider.overrideWithValue(gateway),
            focusSetProvider.overrideWith(() => focus),
            notificationLinkProvider.overrideWith(() => link),
          ],
          child: const HomeWidgetScope(child: SizedBox()),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(gateway.published, isNotEmpty);
      var last = HomeWidgetSnapshot.decode(gateway.published.last);
      expect(last.total, 2);
      expect(last.fromCache, isFalse);

      // A task leaves the set: the widget follows.
      focus.set(<FocusTask>[row('t2', project: 'p1', projectName: 'Дом')]);
      await tester.pump();
      last = HomeWidgetSnapshot.decode(gateway.published.last);
      expect(last.projects.single.tasks.single.id, 't2');

      // A tap on the widget, while the app is alive.
      gateway.actions.add(
        const HomeWidgetOpenTask(taskId: 't2', projectId: 'p1'),
      );
      gateway.listener!();
      await tester.pump();
      expect(link.opened, <String>['t2']);

      // Leaving the signed-in half tells the widget.
      await tester.pumpWidget(const SizedBox());
      expect(gateway.listener, isNull);
      expect(
        HomeWidgetSnapshot.decode(gateway.published.last).signedIn,
        isFalse,
      );
    });

    testWidgets('does nothing at all where there is no widget', (tester) async {
      final focus = _FakeFocusSet(<FocusTask>[row('t1', project: 'p1')]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeWidgetGatewayProvider.overrideWithValue(
              const UnsupportedHomeWidgetGateway(),
            ),
            focusSetProvider.overrideWith(() => focus),
          ],
          child: const HomeWidgetScope(child: SizedBox()),
        ),
      );
      await tester.pump();
      expect(focus.built, isFalse);
    });
  });
}

class _RecordingGateway implements HomeWidgetGateway {
  final List<String> published = <String>[];
  final List<HomeWidgetAction> actions = <HomeWidgetAction>[];
  VoidCallback? listener;

  @override
  bool get supported => true;

  @override
  Future<void> publish(String snapshotJson) async =>
      published.add(snapshotJson);

  @override
  Future<HomeWidgetAction?> takeAction() async =>
      actions.isEmpty ? null : actions.removeAt(0);

  @override
  void setActionListener(VoidCallback? listener) => this.listener = listener;
}

class _FakeFocusSet extends FocusSet {
  _FakeFocusSet(this._initial);

  final List<FocusTask> _initial;
  bool built = false;

  @override
  Future<List<FocusTask>> build() async {
    built = true;
    return _initial;
  }

  void set(List<FocusTask> rows) => state = AsyncData(rows);

  @override
  Future<void> syncQuietly() async {}
}

class _RecordingLink extends NotificationLink {
  final List<String> opened = <String>[];

  @override
  Future<void> open(String taskId) async => opened.add(taskId);
}

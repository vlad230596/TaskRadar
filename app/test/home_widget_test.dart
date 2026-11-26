import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/project_badge.dart';
import 'package:taskradar/home_widget/home_widget_gateway.dart';
import 'package:taskradar/home_widget/home_widget_snapshot.dart';
import 'package:taskradar/domain/today_view.dart';
import 'package:taskradar/models/focus_task.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/providers/shell_providers.dart';
import 'package:taskradar/providers/today_providers.dart';
import 'package:taskradar/models/goal.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/navigation/app_routes.dart';
import 'package:taskradar/providers/focus_providers.dart';
import 'package:taskradar/providers/goal_providers.dart';
import 'package:taskradar/providers/home_widget_providers.dart';
import 'package:taskradar/providers/notification_link_providers.dart';
import 'package:taskradar/screens/dictation_screen.dart';
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
        'goals',
      ]);
      expect(json['v'], HomeWidgetSnapshot.schemaVersion);
      expect(json['goals'], isEmpty);
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
      expect(
        HomeWidgetAction.fromMap(<Object?, Object?>{'action': 'dictate'}),
        const HomeWidgetDictate(),
      );
      expect(
        HomeWidgetAction.fromMap(<Object?, Object?>{
          'action': 'takeStep',
          'taskId': 's1',
        }),
        const HomeWidgetTakeStep(taskId: 's1'),
      );
      expect(
        HomeWidgetAction.fromMap(<Object?, Object?>{'action': 'takeStep'}),
        isNull,
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

  group('the «Сегодня» row', () {
    DayTask day(
      String id, {
      TaskStatus status = TaskStatus.pending,
      String? time,
      String date = '2026-11-27',
      String? doneAt,
    }) => DayTask(
      task: Task(
        id: id,
        projectId: 'p1',
        title: 'Задача $id',
        description: null,
        status: status,
        position: 1000,
        remindAt: '${date}T00:00:00.000Z',
        remindTime: time,
        doneAt: doneAt,
        createdAt: '2026-11-01T00:00:00.000Z',
        updatedAt: '2026-11-01T00:00:00.000Z',
        isCurrent: false,
      ),
      projectName: 'Дом',
    );

    DayView view({
      List<DayTask> today = const <DayTask>[],
      int done = 0,
      int tail = 0,
    }) => DayView(
      date: '2026-11-27',
      today: today,
      doneToday: <DayTask>[
        for (var i = 0; i < done; i++)
          day('d$i', status: TaskStatus.done, doneAt: '2026-11-27T07:00:00Z'),
      ],
      tail: <DayTask>[
        for (var i = 0; i < tail; i++) day('old$i', date: '2026-11-20'),
      ],
    );

    final noon = DateTime(2026, 11, 27, 12);

    test('counts N of M and names the nearest timed task ahead', () {
      final row = buildHomeWidgetToday(
        view(
          today: <DayTask>[
            day('a', time: '09:30'),
            day('b', time: '15:00'),
            day('c', time: '18:00'),
            day('d'),
          ],
          done: 3,
        ),
        now: noon,
      );
      expect(row.done, 3);
      expect(row.total, 7);
      expect(row.time, '15:00');
      expect(row.title, 'Задача b');
      expect(row.visible, isTrue);
    });

    test('with every time gone by, the nearest passed one', () {
      final row = buildHomeWidgetToday(
        view(
          today: <DayTask>[
            day('a', time: '09:30'),
            day('b', time: '11:00'),
          ],
        ),
        now: noon,
      );
      expect(row.time, '11:00');
      expect(row.title, 'Задача b');
    });

    test('no timed task: no second line', () {
      final row = buildHomeWidgetToday(
        view(today: <DayTask>[day('a')], done: 1),
        now: noon,
      );
      expect(row.time, isNull);
      expect(row.title, isNull);
    });

    test('an empty day is hidden -- unless the tail waits', () {
      expect(buildHomeWidgetToday(view(), now: noon).visible, isFalse);
      final tail = buildHomeWidgetToday(view(tail: 14), now: noon);
      expect(tail.visible, isTrue);
      expect(tail.total, 0);
      expect(tail.tail, 14);
    });

    test('round-trips and pins the wire format; older snapshots have none', () {
      final snapshot = buildHomeWidgetSnapshot(
        const <FocusTask>[],
        updatedAt: DateTime.utc(2026, 11, 27, 9),
        today: const HomeWidgetToday(
          done: 3,
          total: 7,
          tail: 2,
          time: '15:00',
          title: 'Встретить курьера',
        ),
      );
      final json = jsonDecode(snapshot.encode()) as Map<String, dynamic>;
      expect(json['today'], <String, dynamic>{
        'done': 3,
        'total': 7,
        'tail': 2,
        'time': '15:00',
        'title': 'Встретить курьера',
      });
      expect(
        HomeWidgetSnapshot.decode(snapshot.encode()).today,
        snapshot.today,
      );

      final older = buildHomeWidgetSnapshot(
        const <FocusTask>[],
        updatedAt: DateTime.utc(2026, 11, 27, 9),
      );
      expect(jsonDecode(older.encode()), isNot(contains('today')));
      expect(HomeWidgetSnapshot.decode(older.encode()).today, isNull);
    });

    test('a tap on the row is «open Работа»', () {
      expect(
        HomeWidgetAction.fromMap(<Object?, Object?>{'action': 'openWork'}),
        const HomeWidgetOpenWork(),
      );
    });

    testWidgets('the scope publishes the row and a tap opens «Работа»', (
      tester,
    ) async {
      final gateway = _RecordingGateway();
      final focus = _FakeFocusSet(<FocusTask>[row('t1', project: 'p1')]);
      final container = ProviderContainer(
        overrides: [
          homeWidgetGatewayProvider.overrideWithValue(gateway),
          focusSetProvider.overrideWith(() => focus),
          ..._noGoals.take(2),
          dayViewProvider.overrideWithValue(
            view(today: <DayTask>[day('a', time: '23:59')], done: 1),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const HomeWidgetScope(child: SizedBox()),
        ),
      );
      await tester.pump();
      await tester.pump();

      final today = HomeWidgetSnapshot.decode(gateway.published.last).today;
      expect(today?.done, 1);
      expect(today?.total, 2);
      expect(today?.time, '23:59');

      gateway.actions.add(const HomeWidgetOpenWork());
      gateway.listener!();
      await tester.pump();
      await tester.pump();
      expect(container.read(shellModeProvider), AppMode.work);
    });
  });

  group('goal rows', () {
    test('only the active contour\'s goals in slots, in their order', () {
      final rows = buildHomeWidgetGoals(
        <GoalView>[
          _goal('g1', contour: 'work', step: 's1', done: 2, total: 5),
          _goal('g2', contour: 'home', step: 's2'),
          _goal('g3', contour: 'work', state: GoalState.bench, step: 's3'),
          _goal('g4', contour: 'work'),
          _goal('g5', contour: 'work', step: 's5', expired: true),
        ],
        activeContourId: 'work',
        setIds: <String>{'s5'},
      );

      expect(rows.map((row) => row.goalId), <String>['g1', 'g4', 'g5']);
      expect(rows[0].stepId, 's1');
      expect(rows[0].stepTitle, 'Шаг s1');
      expect(rows[0].stepProjectId, 'p1');
      expect((rows[0].done, rows[0].total), (2, 5));
      expect(rows[0].inWork, isFalse);
      // No step: «Обсудить», no take button.
      expect(rows[1].stepId, isNull);
      expect(rows[1].stepTitle, isNull);
      // The window ran out; the step is already in the set.
      expect(rows[2].expired, isTrue);
      expect(rows[2].inWork, isTrue);
    });

    test('no active contour known: no goal rows', () {
      expect(
        buildHomeWidgetGoals(
          <GoalView>[_goal('g1', contour: 'work', step: 's1')],
          activeContourId: null,
          setIds: const <String>{},
        ),
        isEmpty,
      );
    });

    test('round-trip and pin the goal row wire format', () {
      final snapshot = buildHomeWidgetSnapshot(
        <FocusTask>[row('t1', project: 'p1')],
        updatedAt: at,
        goals: const <HomeWidgetGoal>[
          HomeWidgetGoal(
            goalId: 'g1',
            title: 'Новое поколение TaskRadar',
            done: 2,
            total: 5,
            stepId: 's1',
            stepTitle: 'Спроектировать экран целей',
            stepProjectId: 'p1',
          ),
          HomeWidgetGoal(goalId: 'g2', title: 'Отпуск', done: 0, total: 0),
        ],
      );
      final json = jsonDecode(snapshot.encode()) as Map<String, Object?>;
      final goal =
          (json['goals']! as List<Object?>).first! as Map<String, Object?>;
      expect(goal, <String, Object?>{
        'goalId': 'g1',
        'title': 'Новое поколение TaskRadar',
        'done': 2,
        'total': 5,
        'stepId': 's1',
        'stepTitle': 'Спроектировать экран целей',
        'stepProjectId': 'p1',
        'expired': false,
        'inWork': false,
      });
      // The widget's count is the set, not the goal rows.
      expect(json['total'], 1);

      final back = HomeWidgetSnapshot.decode(snapshot.encode());
      expect(back.goals, snapshot.goals);
    });

    test('a snapshot from an older app reads as no goals', () {
      final old = HomeWidgetSnapshot.decode(
        '{"v": 1, "updatedAt": 0, "fromCache": false, "signedIn": true, '
        '"total": 0, "projects": []}',
      );
      expect(old.goals, isEmpty);
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
            ..._noGoals,
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

    testWidgets('the microphone opens the dictation screen', (tester) async {
      final gateway = _RecordingGateway();
      final focus = _FakeFocusSet(<FocusTask>[row('t1', project: 'p1')]);
      final pushed = <String?>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeWidgetGatewayProvider.overrideWithValue(gateway),
            focusSetProvider.overrideWith(() => focus),
            ..._noGoals,
          ],
          child: MaterialApp(
            home: const HomeWidgetScope(child: SizedBox()),
            onGenerateRoute: (settings) {
              pushed.add(settings.name);
              return MaterialPageRoute<FieldDictation?>(
                settings: settings,
                builder: (_) => const SizedBox(),
              );
            },
          ),
        ),
      );
      await tester.pump();

      gateway.actions.add(const HomeWidgetDictate());
      gateway.listener!();
      await tester.pump();
      await tester.pump();

      expect(pushed, <String?>[AppRoutes.dictation]);
    });

    testWidgets('publishes the active contour\'s set and goal steps, and '
        'takes a step from the widget', (tester) async {
      final gateway = _RecordingGateway();
      final focus = _FakeFocusSet(<FocusTask>[
        row(
          't1',
          project: 'p1',
          projectName: 'Дом',
        ).copyWith(focusContourId: 'work'),
        row(
          't2',
          project: 'p1',
          projectName: 'Дом',
        ).copyWith(focusContourId: 'home'),
      ]);
      final goals = _FakeGoals(<GoalView>[
        _goal('g1', contour: 'work', step: 's1', done: 1, total: 3),
        _goal('g2', contour: 'home', step: 's2'),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            homeWidgetGatewayProvider.overrideWithValue(gateway),
            focusSetProvider.overrideWith(() => focus),
            goalsProvider.overrideWith(() => goals),
            contoursProvider.overrideWith(_FakeContours.new),
            dayViewProvider.overrideWithValue(null),
          ],
          child: const HomeWidgetScope(child: SizedBox()),
        ),
      );
      await tester.pump();
      await tester.pump();

      var last = HomeWidgetSnapshot.decode(gateway.published.last);
      // Only the active contour («work», the first) -- its set and its goal.
      expect(last.total, 1);
      expect(last.projects.single.tasks.single.id, 't1');
      expect(last.goals.single.goalId, 'g1');
      expect(last.goals.single.stepId, 's1');
      expect(last.goals.single.inWork, isFalse);

      // The take button on the widget.
      gateway.actions.add(const HomeWidgetTakeStep(taskId: 's1'));
      gateway.listener!();
      await tester.pump();
      await tester.pump();
      expect(focus.takenSteps, <String>['s1']);

      // The goals change: the widget follows.
      goals.set(<GoalView>[
        _goal('g1', contour: 'work', step: 's3', done: 2, total: 3),
      ]);
      await tester.pump();
      last = HomeWidgetSnapshot.decode(gateway.published.last);
      expect(last.goals.single.stepId, 's3');
      expect(last.goals.single.done, 2);
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

  final List<String> takenSteps = <String>[];

  @override
  Future<void> takeStep(GoalTask step) async => takenSteps.add(step.id);

  @override
  Future<void> syncQuietly() async {}
}

class _RecordingLink extends NotificationLink {
  final List<String> opened = <String>[];

  @override
  Future<void> open(String taskId) async => opened.add(taskId);
}

GoalView _goal(
  String id, {
  required String contour,
  GoalState state = GoalState.slot,
  String? step,
  int done = 0,
  int total = 1,
  bool expired = false,
}) => GoalView(
  id: id,
  contourId: contour,
  title: 'Цель $id',
  state: state,
  windowExpired: expired,
  position: 1000,
  createdAt: '2026-11-01T09:00:00.000Z',
  nextStep: step == null
      ? null
      : GoalTask(
          id: step,
          title: 'Шаг $step',
          status: TaskStatus.pending,
          projectId: 'p1',
          projectName: 'Дом',
        ),
  progress: GoalProgress(done: done, total: total),
);

class _FakeGoals extends Goals {
  _FakeGoals(this._initial);

  final List<GoalView> _initial;

  @override
  Future<List<GoalView>> build() async => _initial;

  void set(List<GoalView> rows) => state = AsyncData(rows);

  @override
  Future<void> syncQuietly() async {}
}

class _FakeContours extends Contours {
  @override
  Future<ContourList> build() async => const ContourList(
    contours: <Contour>[
      Contour(id: 'work', name: 'Работа', position: 1000),
      Contour(id: 'home', name: 'Личное', position: 2000),
    ],
  );
}

/// Goals and contours that never touch the network: none of either, which
/// is what an app talking to a server from before goals sees.
final _noGoals = [
  goalsProvider.overrideWith(() => _FakeGoals(const <GoalView>[])),
  contoursProvider.overrideWith(_NoContours.new),
  dayViewProvider.overrideWithValue(null),
];

class _NoContours extends Contours {
  @override
  Future<ContourList> build() async => const ContourList(contours: <Contour>[]);
}

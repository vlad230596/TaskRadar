import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/goals.dart';
import 'package:taskradar/models/goal.dart';
import 'package:taskradar/models/task_status.dart';

/// The pure rules of goals and contours (design/goals-ideas-contract.md):
/// active-contour resolution and the manual switch's `until`, the crown, the
/// warm age, and when taking a task into work becomes a duel.
void main() {
  // 23.11.2026 is a Monday, 28.11 a Saturday.
  final monday10 = DateTime(2026, 11, 23, 10, 0); // Mon
  final monday20 = DateTime(2026, 11, 23, 20, 0);
  final saturday10 = DateTime(2026, 11, 28, 10, 0); // Sat

  const weekdays = ContourSchedule(
    days: <int>[1, 2, 3, 4, 5],
    from: '09:00',
    to: '19:00',
  );
  const weekend = ContourSchedule(
    days: <int>[6, 7],
    from: '08:00',
    to: '22:00',
  );

  const work = Contour(
    id: 'work',
    name: 'Работа',
    position: 1000,
    schedule: weekdays,
  );
  const home = Contour(
    id: 'home',
    name: 'Личное',
    position: 2000,
    schedule: weekend,
  );
  const plain = Contour(id: 'plain', name: 'Основной', position: 500);

  group('resolveActiveContour', () {
    test('a manual choice with no end wins', () {
      final active = resolveActiveContour(
        const <Contour>[work, home],
        const ActiveContourChoice(contourId: 'home'),
        monday10,
      );
      expect(active?.id, 'home');
    });

    test('a manual choice wins until its until, then the schedule', () {
      final choice = ActiveContourChoice(
        contourId: 'home',
        until: DateTime(2026, 11, 23, 12).toUtc().toIso8601String(),
      );
      expect(
        resolveActiveContour(const <Contour>[work, home], choice, monday10)?.id,
        'home',
      );
      expect(
        resolveActiveContour(
          const <Contour>[work, home],
          choice,
          DateTime(2026, 11, 23, 13),
        )?.id,
        'work',
      );
    });

    test('a choice of a contour that is gone falls through', () {
      final active = resolveActiveContour(
        const <Contour>[work, home],
        const ActiveContourChoice(contourId: 'deleted'),
        saturday10,
      );
      expect(active?.id, 'home');
    });

    test('the first contour by position whose schedule covers now', () {
      expect(
        resolveActiveContour(
          const <Contour>[home, work],
          const ActiveContourChoice(),
          monday10,
        )?.id,
        'work',
      );
      expect(
        resolveActiveContour(
          const <Contour>[work, home],
          const ActiveContourChoice(),
          saturday10,
        )?.id,
        'home',
      );
    });

    test('overlapping schedules: the higher in the list wins', () {
      const everyday = ContourSchedule(
        days: <int>[1, 2, 3, 4, 5, 6, 7],
        from: '00:00',
        to: '23:59',
      );
      const always = Contour(
        id: 'always',
        name: 'Всегда',
        position: 3000,
        schedule: everyday,
      );
      expect(
        resolveActiveContour(
          const <Contour>[always, work],
          const ActiveContourChoice(),
          monday10,
        )?.id,
        'work',
      );
    });

    test('nothing covers now: the first by position', () {
      expect(
        resolveActiveContour(
          const <Contour>[work, home, plain],
          const ActiveContourChoice(),
          monday20,
        )?.id,
        'plain',
      );
    });

    test('the end of a span is not inside it', () {
      expect(scheduleCovers(weekdays, DateTime(2026, 11, 23, 19, 0)), isFalse);
      expect(scheduleCovers(weekdays, DateTime(2026, 11, 23, 9, 0)), isTrue);
      expect(scheduleCovers(weekdays, DateTime(2026, 11, 23, 18, 59)), isTrue);
    });

    test('an empty list resolves to nothing', () {
      expect(
        resolveActiveContour(
          const <Contour>[],
          const ActiveContourChoice(),
          monday10,
        ),
        isNull,
      );
    });
  });

  group('nextScheduleChange (the until of a manual switch)', () {
    test('no schedules: null, the choice lasts until switched again', () {
      expect(
        nextScheduleChange(<Contour>[
          plain,
          work.copyWith(schedule: null),
        ], monday10),
        isNull,
      );
    });

    test('inside a span: its end', () {
      expect(
        nextScheduleChange(const <Contour>[work, home], monday10),
        DateTime(2026, 11, 23, 19, 0),
      );
    });

    test('after the span: the next start that changes the answer', () {
      expect(
        nextScheduleChange(const <Contour>[work, home], monday20),
        DateTime(2026, 11, 24, 9, 0),
      );
    });

    test('Friday evening: Saturday morning, when «Личное» starts', () {
      expect(
        nextScheduleChange(const <Contour>[
          work,
          home,
        ], DateTime(2026, 11, 27, 20, 0)),
        DateTime(2026, 11, 28, 8, 0),
      );
    });

    test('an edge that changes nothing is skipped', () {
      // Two contours with the same span: at 19:00 the answer goes from
      // «work» to none -- but the overlapping one starting at 9:00 inside
      // work's span changes nothing and is not the answer.
      const overlap = Contour(
        id: 'overlap',
        name: 'Ещё',
        position: 3000,
        schedule: ContourSchedule(
          days: <int>[1, 2, 3, 4, 5],
          from: '12:00',
          to: '13:00',
        ),
      );
      expect(
        nextScheduleChange(const <Contour>[work, overlap], monday10),
        DateTime(2026, 11, 23, 19, 0),
      );
    });
  });

  group('isManualChoice', () {
    test('set and not expired', () {
      expect(
        isManualChoice(
          const <Contour>[work, home],
          const ActiveContourChoice(contourId: 'home'),
          monday10,
        ),
        isTrue,
      );
      expect(
        isManualChoice(
          const <Contour>[work, home],
          const ActiveContourChoice(),
          monday10,
        ),
        isFalse,
      );
    });
  });

  group('crown', () {
    const ref = TaskGoalRef(id: 'g1', title: 'Цель', contourId: 'work');
    const other = TaskGoalRef(id: 'g2', title: 'Другая', contourId: 'home');

    test('no goals: no crown', () {
      expect(crownLevel(const <TaskGoalRef>[], 'work'), CrownLevel.none);
    });

    test('a goal of the active contour: bright', () {
      expect(
        crownLevel(const <TaskGoalRef>[other, ref], 'work'),
        CrownLevel.bright,
      );
    });

    test('goals of other contours only: muted', () {
      expect(crownLevel(const <TaskGoalRef>[other], 'work'), CrownLevel.muted);
    });

    test('contours unknown: any goal is bright', () {
      expect(crownLevel(const <TaskGoalRef>[other], null), CrownLevel.bright);
    });
  });

  group('warm age', () {
    test('only a task in a working set or with a crown', () {
      expect(mayWarmAge(inWorkingSet: false, crowned: false), isFalse);
      expect(mayWarmAge(inWorkingSet: true, crowned: false), isTrue);
      expect(mayWarmAge(inWorkingSet: false, crowned: true), isTrue);
    });
  });

  group('duel', () {
    GoalView goal(
      String id, {
      String contourId = 'work',
      GoalState state = GoalState.slot,
      String? stepId = 's1',
      bool expired = false,
    }) {
      final step = stepId == null
          ? null
          : GoalTask(
              id: stepId,
              title: 'Шаг $stepId',
              status: TaskStatus.pending,
              projectId: 'p',
              projectName: 'P',
            );
      return GoalView(
        id: id,
        contourId: contourId,
        title: 'Цель $id',
        state: state,
        position: 1000,
        createdAt: '2026-11-01T10:00:00.000Z',
        windowExpired: expired,
        tasks: <GoalTask>[?step],
        nextStep: step,
      );
    }

    List<GoalView> duel({
      String taskId = 't',
      List<TaskGoalRef> taskGoals = const <TaskGoalRef>[],
      String? active = 'work',
      required List<GoalView> goals,
      Set<String> inSet = const <String>{},
      int? setSize,
    }) => duelGoals(
      taskId: taskId,
      taskGoals: taskGoals,
      activeContourId: active,
      goals: goals,
      activeSetIds: inSet,
      setSize: setSize ?? inSet.length,
      setLimit: 5,
    );

    test('a slotted goal of the active contour with a step not in the set', () {
      final result = duel(goals: <GoalView>[goal('g1')]);
      expect(result.map((g) => g.id), <String>['g1']);
    });

    test('no duel when the task has a goal of the active contour', () {
      expect(
        duel(
          taskGoals: const <TaskGoalRef>[
            TaskGoalRef(id: 'g9', title: 'x', contourId: 'work'),
          ],
          goals: <GoalView>[goal('g1')],
        ),
        isEmpty,
      );
    });

    test('a crown of another contour still duels', () {
      expect(
        duel(
          taskGoals: const <TaskGoalRef>[
            TaskGoalRef(id: 'g9', title: 'x', contourId: 'home'),
          ],
          goals: <GoalView>[goal('g1')],
        ),
        hasLength(1),
      );
    });

    test('no duel when the step is already in the set', () {
      expect(
        duel(goals: <GoalView>[goal('g1')], inSet: const <String>{'s1'}),
        isEmpty,
      );
    });

    test(
      'no duel for goals without a step, on the bench, elsewhere, expired',
      () {
        expect(
          duel(
            goals: <GoalView>[
              goal('g1', stepId: null),
              goal('g2', state: GoalState.bench),
              goal('g3', contourId: 'home'),
              goal('g4', expired: true),
            ],
          ),
          isEmpty,
        );
      },
    );

    test('no duel when the set is full', () {
      expect(duel(goals: <GoalView>[goal('g1')], setSize: 5), isEmpty);
    });

    test('no duel when contours are unknown', () {
      expect(duel(active: null, goals: <GoalView>[goal('g1')]), isEmpty);
    });

    test('taking the step itself is not a duel', () {
      expect(duel(taskId: 's1', goals: <GoalView>[goal('g1')]), isEmpty);
    });

    test('several goals: all offered, in order', () {
      final result = duel(
        goals: <GoalView>[
          goal('g1'),
          goal('g2', stepId: 's2'),
        ],
      );
      expect(result.map((g) => g.id), <String>['g1', 'g2']);
    });
  });

  group('window labels', () {
    final now = DateTime(2026, 11, 24, 12, 0);

    test('days left, and the clock in the last day', () {
      expect(
        windowLeftLabel(
          now.add(const Duration(days: 3, hours: 2)).toUtc().toIso8601String(),
          now: now,
        ),
        'ещё 3 д',
      );
      expect(
        windowLeftLabel(
          DateTime(2026, 11, 24, 18, 30).toUtc().toIso8601String(),
          now: now,
        ),
        'до 18:30',
      );
    });

    test('expired: yesterday, days ago', () {
      expect(
        windowExpiredLabel(
          DateTime(2026, 11, 23, 9).toUtc().toIso8601String(),
          now: now,
        ),
        'Окно вышло вчера',
      );
      expect(
        windowExpiredLabel(
          DateTime(2026, 11, 21, 9).toUtc().toIso8601String(),
          now: now,
        ),
        'Окно вышло 3 д назад',
      );
    });

    test('schedule descriptions', () {
      expect(describeSchedule(weekdays), 'пн–пт · 9:00–19:00');
      expect(describeSchedule(null), 'без расписания');
      expect(describeDays(const <int>[6, 7]), 'сб, вс');
      expect(describeDays(const <int>[1, 3, 4, 5]), 'пн, ср–пт');
    });

    test('the toast after a manual switch', () {
      expect(
        manualSwitchToast('Личное', DateTime(2026, 11, 30, 9), now: now),
        'Личное — до пн 9:00',
      );
      expect(manualSwitchToast('Личное', null), 'Личное — пока не переключите');
    });
  });
}

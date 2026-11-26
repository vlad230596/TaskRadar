import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/today_view.dart';
import 'package:taskradar/models/board_project.dart';
import 'package:taskradar/models/project.dart';
import 'package:taskradar/models/scope.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_status.dart';
import 'package:taskradar/models/today_history.dart';

/// The client's mirror of `backend/src/domain/today.ts` -- the same cases.
void main() {
  const today = '2026-11-27';

  Task task(
    String id, {
    TaskStatus status = TaskStatus.pending,
    String? date,
    String? time,
    String? doneAt,
    double position = 1000,
    String projectId = 'p1',
  }) => Task(
    id: id,
    projectId: projectId,
    title: id,
    description: null,
    status: status,
    position: position,
    remindAt: date == null ? null : '${date}T00:00:00.000Z',
    remindTime: time,
    doneAt: doneAt,
    createdAt: '2026-11-01T10:00:00.000Z',
    updatedAt: '2026-11-01T10:00:00.000Z',
    isCurrent: false,
  );

  DayTask placed(Task t, {int scope = 0, int project = 0, String? scopeId}) =>
      DayTask(
        task: t,
        projectName: 'P',
        scopeId: scopeId ?? 's$scope',
        scopeName: 'S$scope',
        scopeOrder: scope,
        projectOrder: project,
      );

  // A local instant on [day] at [hour] -- `doneAt` is compared by local day.
  String localAt(String day, int hour) {
    final p = day.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2], hour).toUtc().toIso8601String();
  }

  group('dayViewOf', () {
    test('splits open tasks into today and the tail; ignores the rest', () {
      final view = dayViewOf(<DayTask>[
        placed(task('today', date: today)),
        placed(task('blocked-today', status: TaskStatus.blocked, date: today)),
        placed(task('yesterday', date: '2026-11-26')),
        placed(task('tomorrow', date: '2026-11-28')),
        placed(task('undated')),
      ], today);

      expect(view.today.map((t) => t.id), <String>['today', 'blocked-today']);
      expect(view.tail.map((t) => t.id), <String>['yesterday']);
      expect(view.doneToday, isEmpty);
      expect(view.total, 2);
      expect(view.doneCount, 0);
    });

    test('done today counts only dated today or earlier, closed today', () {
      final view = dayViewOf(<DayTask>[
        placed(
          task(
            'done-dated-today',
            status: TaskStatus.done,
            date: today,
            doneAt: localAt(today, 11),
          ),
        ),
        placed(
          task(
            'done-tail',
            status: TaskStatus.done,
            date: '2026-11-20',
            doneAt: localAt(today, 9),
          ),
        ),
        // Dated next week, closed early: not part of today's «N из M».
        placed(
          task(
            'done-early',
            status: TaskStatus.done,
            date: '2026-12-03',
            doneAt: localAt(today, 10),
          ),
        ),
        // No date: in «Сделано», never in «Сегодня» (answer 5).
        placed(
          task('done-undated', status: TaskStatus.done, doneAt: localAt(today, 8)),
        ),
        // Closed yesterday.
        placed(
          task(
            'done-yesterday',
            status: TaskStatus.done,
            date: '2026-11-26',
            doneAt: localAt('2026-11-26', 20),
          ),
        ),
        placed(task('open', date: today)),
      ], today);

      expect(view.doneToday.map((t) => t.id), <String>[
        'done-tail',
        'done-dated-today',
      ]);
      expect(view.total, 3);
      expect(view.doneCount, 2);
    });

    test('today: by scope, timed first by time, then board order', () {
      final view = dayViewOf(<DayTask>[
        placed(task('home-free', date: today), scope: 1),
        placed(task('work-free-2', date: today, position: 2000)),
        placed(task('work-15', date: today, time: '15:00')),
        placed(task('home-9', date: today, time: '09:00'), scope: 1),
        placed(task('work-free-1', date: today, position: 1000)),
        placed(task('work-10', date: today, time: '10:00'), project: 3),
      ], today);

      expect(view.today.map((t) => t.id), <String>[
        'work-10',
        'work-15',
        'work-free-1',
        'work-free-2',
        'home-9',
        'home-free',
      ]);
      final groups = view.groups;
      expect(groups.map((g) => g.scopeId), <String>['s0', 's1']);
      expect(groups.first.tasks, hasLength(4));
    });

    test('the tail: oldest date first, then board order', () {
      final view = dayViewOf(<DayTask>[
        placed(task('b', date: '2026-11-25', position: 2000)),
        placed(task('c', date: '2026-11-26')),
        placed(task('a', date: '2026-11-25', position: 1000)),
        placed(task('old', date: '2026-10-01'), project: 5),
      ], today);
      expect(view.tail.map((t) => t.id), <String>['old', 'a', 'b', 'c']);
    });
  });

  group('isLater', () {
    test('open and dated after today + horizon', () {
      expect(isLater(task('x', date: '2026-12-07'), today, 10), isFalse);
      expect(isLater(task('x', date: '2026-12-08'), today, 10), isTrue);
      expect(
        isLater(task('x', date: '2026-12-08', status: TaskStatus.blocked), today, 10),
        isTrue,
      );
      expect(
        isLater(task('x', date: '2026-12-08', status: TaskStatus.done), today, 10),
        isFalse,
      );
      expect(isLater(task('x'), today, 10), isFalse);
    });
  });

  group('formatTaskDate', () {
    TaskDateLabel? label(String? date, [String? time]) => formatTaskDate(
      date == null ? null : '${date}T00:00:00.000Z',
      time,
      today,
    );

    test('the table of the spec', () {
      expect(label(null), isNull);
      expect(label('2026-11-26'), const TaskDateLabel('вчера', DateTone.overdue));
      expect(
        label('2026-11-24'),
        const TaskDateLabel('3 дн. назад', DateTone.overdue),
      );
      expect(label(today), const TaskDateLabel('сегодня', DateTone.today));
      expect(
        label(today, '15:00'),
        const TaskDateLabel('сегодня · 15:00', DateTone.today),
      );
      expect(
        label('2026-11-28', '09:30'),
        const TaskDateLabel('завтра · 9:30', DateTone.soon),
      );
      expect(label('2026-11-29'), const TaskDateLabel('вс 29.11', DateTone.soon));
      expect(label('2026-12-03'), const TaskDateLabel('чт 3.12', DateTone.soon));
      expect(label('2027-02-25').toString(), contains('25 фев 2027'));
      expect(label('2026-12-25'), const TaskDateLabel('25 дек', DateTone.soon));
    });

    test('capitalized for the editor chip', () {
      expect(label('2026-11-28')!.capitalized, 'Завтра');
    });
  });

  group('days', () {
    test('addDays crosses months and years', () {
      expect(addDays('2026-11-30', 1), '2026-12-01');
      expect(addDays('2026-12-31', 1), '2027-01-01');
      expect(addDays('2026-03-01', -1), '2026-02-28');
    });

    test('nextMonday is always ahead', () {
      expect(nextMonday('2026-11-27'), '2026-11-30'); // Friday
      expect(nextMonday('2026-11-30'), '2026-12-07'); // Monday: a week on
      expect(nextMonday('2026-11-29'), '2026-11-30'); // Sunday
    });

    test('weekdayDate and shortDate', () {
      expect(weekdayDate('2026-11-27'), 'пт 27.11');
      expect(shortDate('2026-11-30'), '30.11');
      expect(formatClock('09:05'), '9:05');
    });
  });

  test('placeBoardTasks keeps scope and board order', () {
    Project project(String id, String scopeId) => Project(
      id: id,
      name: 'Name $id',
      scopeId: scopeId,
      archivedAt: null,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    );
    Scope scope(String id, String name, double position) => Scope(
      id: id,
      name: name,
      position: position,
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    );
    final board = <BoardProject>[
      BoardProject(
        project: project('a', 'home'),
        tasks: <Task>[task('a1', date: today, projectId: 'a')],
      ),
      BoardProject(
        project: project('b', 'work'),
        tasks: <Task>[task('b1', date: today, projectId: 'b')],
      ),
    ];
    final placedTasks = placeBoardTasks(
      board,
      scopes: <Scope>[scope('work', 'Работа', 1), scope('home', 'Дом', 2)],
    );
    final view = dayViewOf(placedTasks, today);
    expect(view.today.map((t) => t.id), <String>['b1', 'a1']);
    expect(view.today.first.scopeName, 'Работа');
    expect(view.today.first.projectName, 'Name b');
  });

  group('wire models', () {
    test('a placed task parses without isCurrent', () {
      final placedTask = PlacedTask.fromJson(<String, dynamic>{
        'id': 't',
        'projectId': 'p',
        'title': 'T',
        'description': null,
        'status': 'done',
        'position': 1.5,
        'remindAt': null,
        'doneAt': '2026-11-27T10:00:00.000Z',
        'createdAt': '2026-11-01T00:00:00.000Z',
        'updatedAt': '2026-11-01T00:00:00.000Z',
        'projectName': 'TaskRadar',
        'scopeId': 's',
        'scopeName': 'Работа',
      });
      expect(placedTask.task.isCurrent, isFalse);
      expect(placedTask.task.doneAt, '2026-11-27T10:00:00.000Z');
      expect(placedTask.projectName, 'TaskRadar');
    });

    test('a project carries its rhythm', () {
      final project = Project.fromJson(<String, dynamic>{
        'id': 'p',
        'name': 'P',
        'scopeId': 's',
        'archivedAt': null,
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'rhythmClosedPerWeek': 2,
        'rhythmMaxOpen': null,
        'rhythm': <String, dynamic>{
          'closedPerWeek': 2,
          'maxOpen': null,
          'closedAvg': 0.5,
          'open': 24,
          'lastClosedAt': null,
          'silentWeeks': 3,
          'signal': 'silence',
        },
      });
      expect(project.rhythm?.signal, RhythmSignal.silence);
      expect(project.rhythm?.closedAvg, 0.5);
      expect(Project.fromJson(project.toJson()), project);
    });

    test('settings and review status read leniently', () {
      expect(
        OwnerSettings.fromJson(const <String, dynamic>{}),
        const OwnerSettings(),
      );
      final status = ReviewStatus.fromJson(const <String, dynamic>{
        'due': true,
        'nextAt': '2026-11-23T06:00:00.000Z',
        'lastAt': null,
      });
      expect(status.due, isTrue);
    });
  });
}

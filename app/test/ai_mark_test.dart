import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/domain/ai_mark.dart';
import 'package:taskradar/models/inbox_item.dart';
import 'package:taskradar/models/task.dart';
import 'package:taskradar/models/task_status.dart';

Task _task({
  String title = 'Позвонить в сервис',
  String? description,
  String? aiSource,
  String? aiKind,
  Map<String, dynamic>? aiResult,
}) => Task(
  id: 't1',
  projectId: 'p1',
  title: title,
  description: description,
  status: TaskStatus.pending,
  position: 1,
  remindAt: null,
  createdAt: '2026-10-14T00:00:00Z',
  updatedAt: '2026-10-14T00:00:00Z',
  isCurrent: false,
  aiSource: aiSource,
  aiKind: aiKind,
  aiResult: aiResult,
);

void main() {
  group('taskAiMark', () {
    test('no mark for a task AI never touched', () {
      expect(taskAiMark(_task()).shown, isFalse);
    });

    test('as AI left it while the fields match the snapshot', () {
      final mark = taskAiMark(
        _task(
          aiSource: 'ну позвонить в сервис',
          aiKind: 'task',
          aiResult: <String, dynamic>{
            'title': 'Позвонить в сервис',
            'description': null,
          },
        ),
      );
      expect(mark.state, AiMarkState.asAi);
      expect(mark.source, 'ну позвонить в сервис');
    });

    test('edited after AI once a field differs', () {
      final mark = taskAiMark(
        _task(
          description: 'Спросить про колодки',
          aiSource: 'исходник',
          aiKind: 'task',
          aiResult: <String, dynamic>{
            'title': 'Позвонить в сервис',
            'description': null,
          },
        ),
      );
      expect(mark.state, AiMarkState.editedAfter);
    });
  });

  test('inboxAiMark compares the text', () {
    final item = InboxItem(
      id: 'i1',
      text: 'Купить корм',
      createdAt: '',
      updatedAt: '',
      aiSource: 'ну купить корм',
      aiKind: 'sandbox',
      aiResult: <String, dynamic>{'text': 'Купить корм коту'},
    );
    expect(inboxAiMark(item).state, AiMarkState.editedAfter);
  });

  group('taskSourceFields', () {
    test('note: only the description comes back', () {
      final fields = taskSourceFields(
        _task(aiSource: 'ну это самое колодки', aiKind: 'note'),
      );
      expect(fields.title, 'Позвонить в сервис');
      expect(fields.description, 'ну это самое колодки');
    });

    test('task_tidy: the first line is the title', () {
      final fields = taskSourceFields(
        _task(
          aiSource: 'позвонить ну в сервис\nи колодки',
          aiKind: 'task_tidy',
        ),
      );
      expect(fields.title, 'позвонить ну в сервис');
      expect(fields.description, 'и колодки');
    });

    test('task: a short dictation is the title whole', () {
      final fields = taskSourceFields(
        _task(aiSource: 'ну позвонить в сервис', aiKind: 'task'),
      );
      expect(fields.title, 'ну позвонить в сервис');
      expect(fields.description, isNull);
    });
  });

  group('splitSourceText', () {
    test('a long text gives its first sentence to the title', () {
      final text = 'Позвонить в сервис насчёт машины. ${'Подробности ' * 15}';
      final parts = splitSourceText(text);
      expect(parts.title, 'Позвонить в сервис насчёт машины');
      expect(parts.description, startsWith('Подробности'));
    });

    test('with no sentence end, cuts at a word with an ellipsis', () {
      final parts = splitSourceText('слово ' * 40);
      expect(parts.title, endsWith('…'));
      expect(parts.title.length, lessThanOrEqualTo(121));
      expect(parts.description, isNotNull);
    });
  });
}

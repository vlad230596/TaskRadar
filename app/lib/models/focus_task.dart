import 'package:freezed_annotation/freezed_annotation.dart';

import 'task_status.dart';

part 'focus_task.freezed.dart';
part 'focus_task.g.dart';

/// Одна задача набора «в работе», как её отдаёт `GET /focus` (F11/F13).
///
/// ## Почему это отдельная модель, а не [Task]
///
/// Два отличия от обычной строки задачи, и оба — не мелочь:
///
/// 1. **Нет `isCurrent`.** «Текущая» — свойство списка задач *одного проекта*
///    («первая `pending` по позиции»), а набор собран из разных проектов, и
///    сервер честно не присылает этого ключа (`backend/src/routes/focus.ts`).
///    `Task.fromJson` требует его — разбор строки набора им просто упал бы, а
///    подставленный `false` был бы выдумкой про чужой список.
/// 2. **Есть `project`** — id и имя, вложенные сервером. Экран работы подписывает
///    именем проекта каждую задачу, и в этом весь смысл набора из пятнадцати
///    проектов; брать имя из закешированной доски значило бы ошибаться ровно
///    тогда, когда кеш устарел.
///
/// Плюс `focusedAt` не nullable: `GET /focus` фильтрует по `focusedAt != null`,
/// так что в этой модели он всегда есть — и именно по нему сервер упорядочивает
/// набор (по возрастанию). Клиент порядок **не пересчитывает**: он показывает
/// список в том виде, в каком тот пришёл, — то же правило, что и для
/// `Task.position`.
///
/// Временные метки остаются ISO-строками — как в [Task] и по той же причине.
@freezed
abstract class FocusTask with _$FocusTask {
  const factory FocusTask({
    required String id,
    required String projectId,
    required String title,
    required String? description,
    required TaskStatus status,
    required double position,
    required String? remindAt,
    required String createdAt,
    required String updatedAt,

    /// Когда задачу взяли в работу. Порядок набора — по нему, по возрастанию.
    required String focusedAt,

    /// Проект задачи: только id и имя — больше сервер здесь и не присылает.
    required FocusProject project,
  }) = _FocusTask;

  factory FocusTask.fromJson(Map<String, dynamic> json) =>
      _$FocusTaskFromJson(json);
}

/// Проект внутри строки набора: id и имя, ничего больше.
///
/// Отдельный тип, а не `Project`: у настоящего проекта есть `scopeId`,
/// `archivedAt` и обе даты, и ни одного из этих полей в ответе `/focus` нет.
/// Модель, требующая того, чего на проводе не бывает, — это разбор, который
/// падает на первом же честном ответе сервера.
@freezed
abstract class FocusProject with _$FocusProject {
  const factory FocusProject({
    required String id,
    required String name,
  }) = _FocusProject;

  factory FocusProject.fromJson(Map<String, dynamic> json) =>
      _$FocusProjectFromJson(json);
}

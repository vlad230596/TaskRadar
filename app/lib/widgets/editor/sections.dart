import 'package:flutter/material.dart';

import '../../models/task.dart';

/// The places in the task editor where the checklist (WP5), the pictures
/// (WP6) and the place (WP7) plug in (task-editor spec, section 11).
///
/// Everything here renders nothing today: the data layer for those three
/// (WP2) is not in yet. The editor already calls every function below at the
/// spot the spec's "Раскладка full" draws it, so a package that lands only
/// fills in its own function and its own [EditorExtras] fields -- the editor
/// screen (`screens/task_editor_screen.dart`) does not need to change.
///
/// ## The order on screen (full height)
///
/// ```
/// header · title card · AttributeBar([reminder, ...EditorSlots.chips, category])
/// ОПИСАНИЕ + link cards
/// EditorSlots.checklist      ← WP5, «СПИСОК · 2/5»
/// EditorSlots.attachments    ← WP6, «КАРТИНКИ»
/// EditorSlots.location       ← WP7, «МЕСТО»
/// status segment · «Взять в работу» · «Жизнь задачи» (existing task)
/// ```
///
/// Each section is wrapped by the editor in an `AnimatedSize` (200 ms), so a
/// section appearing when its chip's «+» is pressed animates in by itself.
/// A section must render `SizedBox.shrink()` while it is empty and closed
/// (the spec: "секции не рисуются пустыми").
@immutable
class EditorSectionScope {
  const EditorSectionScope({
    required this.projectId,
    required this.task,
    required this.extras,
    required this.expanded,
  });

  /// The project the task is in (or, for a new one, the one it will be
  /// created in -- it follows the header chip and a `#проект` token).
  final String projectId;

  /// The task as the list has it now; null for a task not created yet.
  final Task? task;

  /// The editor-held state of the extras, see [EditorExtras].
  final EditorExtras extras;

  /// False in the compact quick-add sheet: sections stay hidden there, only
  /// their chips show (tapping one expands the sheet).
  final bool expanded;

  bool get isNew => task == null;
}

/// What the editor holds for the extras between opening and "Добавить" /
/// "Сохранить". A [ChangeNotifier]: the editor rebuilds and re-checks
/// "unsaved changes" whenever it notifies.
///
/// WP5 adds `List<ChecklistItem>? checklist` (+ `bool checklistOpen`), WP6
/// `List<PendingAttachment> pending` (a new task's pictures before create),
/// WP7 `TaskLocation? location`. Each also extends [isDirty], [clear] and
/// [createArgs].
class EditorExtras extends ChangeNotifier {
  /// Something here differs from the saved task (a new task: anything set at
  /// all). Feeds the "Выйти без сохранения?" guard and the visibility of
  /// "Сохранить".
  bool get isDirty => false;

  /// "Добавить и ещё": back to empty, keeping nothing.
  void clear() {}

  /// Extra named arguments for `ProjectTasks.create` once WP2 adds them
  /// (`checklist`, `location`). Empty until then; the editor does not pass
  /// them anywhere yet -- WP5/WP7 wire this into `_createIn` in the editor
  /// when the parameters exist.
  Map<String, Object?> get createArgs => const <String, Object?>{};

  /// Called after "Сохранить" of an existing task, with the row the save was
  /// made against: write the extras' text edits (checklist item texts) the
  /// same way the editor writes the title. Discrete actions (a checkbox, a
  /// picture added) are written at once by the sections themselves.
  Future<void> saveExisting(Task task) async {}

  /// Called after "Добавить" with where the new task went, so pending
  /// pictures can be queued against it (WP6:
  /// `AttachmentQueue.add('local:outbox:KEY' or the id)`). [projectId] is the
  /// project the task was created in.
  Future<void> afterCreate({required String projectId}) async {}
}

/// The slots themselves.
abstract final class EditorSlots {
  /// Chips for the attribute row, between the reminder and the category:
  /// «📍 + Место» (WP7), «☑ + Список» (WP5), «🖼 + Фото» (WP6). Hidden until
  /// those land. [onOpen] expands a compact sheet to full height -- a chip
  /// tapped in quick-add should show the section it opens.
  static List<Widget> chips(
    EditorSectionScope scope, {
    required VoidCallback onOpen,
  }) => const <Widget>[];

  /// WP5: `ChecklistSection(items, onChanged, onToggle, autofocusNew)`.
  static Widget checklist(EditorSectionScope scope) => const SizedBox.shrink();

  /// WP6: `AttachmentStrip(taskIdOrLocal, attachments, pending, onAdd,
  /// onDelete)`.
  static Widget attachments(EditorSectionScope scope) =>
      const SizedBox.shrink();

  /// WP7: `LocationTile(value, onChanged)`.
  static Widget location(EditorSectionScope scope) => const SizedBox.shrink();
}

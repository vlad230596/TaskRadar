import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/checklist_item.dart';
import '../../models/task.dart';
import '../../models/task_location.dart';
import '../../providers/project_providers.dart';
import 'attribute_bar.dart';
import 'checklist_section.dart';
import 'editor_theme.dart';
import 'location_picker.dart';
import 'place_tile.dart';

/// The places in the task editor where the checklist (WP5), the pictures
/// (WP6) and the place (WP7) plug in (task-editor spec, section 11).
///
/// The *data* already flows: [EditorExtras] holds the checklist and the
/// place, and the editor (`screens/task_editor_screen.dart`) sends them with
/// "Добавить" (`ProjectTasks.create(checklist:, location:)`) and with
/// "Сохранить" (`ProjectTasks.edit(checklist:, location:)`). What renders
/// nothing yet are the *widgets*: the functions of [EditorSlots] below. A
/// package that lands fills in its own function -- the editor calls each of
/// them already, at the spot the spec's "Раскладка full" draws it -- and the
/// editor screen does not need to change.
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
/// A section renders `SizedBox.shrink()` while it is empty and closed (the
/// spec: "секции не рисуются пустыми") -- [EditorExtras.checklistOpen] /
/// [EditorExtras.locationOpen] say whether its chip asked for it.
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
  /// their chips show (tapping one should call `onOpen` to expand the sheet).
  final bool expanded;

  bool get isNew => task == null;
}

/// What the editor holds for the extras between opening and "Добавить" /
/// "Сохранить". A [ChangeNotifier]: the editor rebuilds and re-checks
/// "unsaved changes" whenever it notifies.
///
/// - [checklist] (WP5): the items as edited. On an existing task the
///   *text* of items waits for "Сохранить", like the title; a tick is an
///   action and is written at once by the section itself
///   (`ProjectTasks.toggleChecklistItem`), after which it calls
///   [adoptSaved] with the row's new list so the tick is not "unsaved".
/// - [location] (WP7): the place, or null.
/// - Pictures (WP6) are not held here: before "Добавить" they are the
///   section's own pending list, queued in [afterCreate] against the new
///   task's id ([WriteOutcome.taskId]); on an existing task they upload at
///   once.
class EditorExtras extends ChangeNotifier {
  List<ChecklistItem>? _checklist;
  List<ChecklistItem>? _savedChecklist;
  TaskLocation? _location;
  TaskLocation? _savedLocation;

  /// The checklist section was asked for (its chip) while still empty.
  bool checklistOpen = false;

  /// The place section was asked for while still empty.
  bool locationOpen = false;

  /// Hooks a section may set to run after "Добавить" -- WP6 queues its
  /// pending pictures here. [projectId] is the project the task went to.
  final List<Future<void> Function(String projectId, WriteOutcome outcome)>
  createHooks = <Future<void> Function(String projectId, WriteOutcome)>[];

  List<ChecklistItem>? get checklist => _checklist;
  set checklist(List<ChecklistItem>? value) {
    _checklist = (value == null || value.isEmpty) ? null : value;
    notifyListeners();
  }

  TaskLocation? get location => _location;
  set location(TaskLocation? value) {
    _location = value;
    notifyListeners();
  }

  void openChecklist() {
    checklistOpen = true;
    notifyListeners();
  }

  void openLocation() {
    locationOpen = true;
    notifyListeners();
  }

  /// The list as it is sent: trimmed, blank items dropped; null when empty.
  List<ChecklistItem>? get checklistForSave {
    final items = ChecklistSection.forSave(_checklist ?? const []);
    return items.isEmpty ? null : items;
  }

  /// Text, order or membership changed. Ticks do not count: on an existing
  /// task a tick is written at once by the section.
  bool get checklistChanged =>
      ChecklistSection.differsInContent(_checklist ?? const [], _savedChecklist);
  bool get locationChanged => _location != _savedLocation;

  /// Something here differs from the saved task (a new task: anything set at
  /// all). Feeds the "Выйти без сохранения?" guard and "Сохранить".
  bool get isDirty => checklistChanged || locationChanged;

  /// An existing task opened: its values are the saved ones. Not notifying:
  /// called while the editor builds.
  void loadFrom(Task task) {
    _checklist = _savedChecklist = task.checklist;
    _location = _savedLocation = task.location;
    checklistOpen = false;
    locationOpen = false;
  }

  /// The row now holds these (a tick written at once, a save landed).
  void adoptSaved(Task task) {
    _savedChecklist = task.checklist;
    _savedLocation = task.location;
    notifyListeners();
  }

  /// "Добавить и ещё": back to empty.
  void clear() {
    _checklist = _savedChecklist = null;
    _location = _savedLocation = null;
    checklistOpen = false;
    locationOpen = false;
    notifyListeners();
  }

  /// Called after "Добавить" with where the new task went.
  Future<void> afterCreate({
    required String projectId,
    required WriteOutcome outcome,
  }) async {
    for (final hook in createHooks) {
      await hook(projectId, outcome);
    }
  }
}

/// The slots themselves -- the one place WP5–7 add their widgets.
abstract final class EditorSlots {
  /// Chips for the attribute row, between the reminder and the category:
  /// «📍 + Место» (WP7), «☑ + Список» (WP5), «🖼 + Фото» (WP6) -- an
  /// `AttributeChip` each (`attribute_bar.dart`). Hidden until those land.
  /// [onOpen] expands a compact sheet to full height: a chip tapped in
  /// quick-add should show the section it opens.
  static List<Widget> chips(
    EditorSectionScope scope, {
    required VoidCallback onOpen,
  }) => <Widget>[
    // WP7: «📍 Место». Tapping goes straight to the map; the section below
    // then shows the place with its status.
    Builder(
      builder: (context) {
        final extras = scope.extras;
        final place = extras.location;
        final label = place?.label?.trim() ?? '';
        return AttributeChip(
          icon: Icons.place_outlined,
          label: label.isEmpty ? 'Место' : label,
          filled: place != null,
          tooltip: place == null ? 'Напомнить по месту' : 'Изменить место',
          onTap: () async {
            onOpen();
            final picked = await pickLocation(context, initial: place);
            if (picked != null) extras.location = picked;
          },
          onClear: place == null ? null : () => extras.location = null,
          clearTooltip: 'Убрать место',
        );
      },
    ),
    if (scope.extras.checklist == null && !scope.extras.checklistOpen)
      AttributeChip(
        icon: Icons.checklist_rounded,
        label: 'Список',
        tooltip: 'Добавить чек-лист',
        onTap: () {
          scope.extras.checklist = ChecklistSection.withNewItem(
            scope.extras.checklist ?? const [],
          );
          scope.extras.openChecklist();
          onOpen();
        },
      ),
  ];

  /// WP5: `ChecklistSection(items: scope.extras.checklist ?? [], onChanged:
  /// (items) => scope.extras.checklist = items, onToggle: …)` when
  /// `checklist != null || checklistOpen`.
  static Widget checklist(EditorSectionScope scope) =>
      (!scope.expanded ||
          (scope.extras.checklist == null && !scope.extras.checklistOpen))
      ? const SizedBox.shrink()
      : _ChecklistSlot(scope: scope);

  /// WP6: `AttachmentStrip(taskIdOrLocal, attachments: scope.task?.attachments,
  /// pending, onAdd, onDelete)`; for a new task, register the upload of the
  /// pending pictures in `scope.extras.createHooks`.
  static Widget attachments(EditorSectionScope scope) =>
      const SizedBox.shrink();

  /// WP7: `LocationTile(value: scope.extras.location, onChanged: (v) =>
  /// scope.extras.location = v)` when `location != null || locationOpen`.
  static Widget location(EditorSectionScope scope) {
    final extras = scope.extras;
    if (!scope.expanded) return const SizedBox.shrink();
    if (extras.location == null && !extras.locationOpen) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const EditorSectionLabel('Место'),
          const SizedBox(height: 8),
          PlaceTile(
            value: extras.location,
            taskId: scope.task?.id,
            onChanged: (value) {
              if (value == null) extras.locationOpen = false;
              extras.location = value;
            },
          ),
        ],
      ),
    );
  }
}

/// WP5 in its slot: the section edits [EditorExtras.checklist]; on an
/// existing task a tick is written at once.
class _ChecklistSlot extends ConsumerWidget {
  const _ChecklistSlot({required this.scope});

  final EditorSectionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = scope.task;
    return ChecklistSection(
      items: scope.extras.checklist ?? const [],
      onChanged: (items) => scope.extras.checklist = items,
      onToggle: task == null
          ? null
          : (id) => ref
                .read(projectTasksProvider(scope.projectId).notifier)
                .toggleChecklistItem(task, id),
    );
  }
}

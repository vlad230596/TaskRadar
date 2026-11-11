import 'dart:math' as math;

import 'package:freezed_annotation/freezed_annotation.dart';

part 'checklist_item.freezed.dart';
part 'checklist_item.g.dart';

/// One line of a task's checklist (`Task.checklist`,
/// `design/task-editor-spec.md` §6 and §10).
///
/// The list travels whole -- `PATCH /tasks/:id` with every item, checked
/// against `expected` as one value -- so an item has no route and no server
/// id of its own: [id] is made here ([newId]), 8..40 characters, and only has
/// to be stable for the list's lifetime (the reorder handle, the toggle).
@freezed
abstract class ChecklistItem with _$ChecklistItem {
  const factory ChecklistItem({
    required String id,

    /// 1..500 characters on the server.
    required String text,
    @Default(false) bool done,
  }) = _ChecklistItem;

  const ChecklistItem._();

  factory ChecklistItem.fromJson(Map<String, dynamic> json) =>
      _$ChecklistItemFromJson(json);

  /// A fresh item with a new [id].
  factory ChecklistItem.create(String text, {bool done = false}) =>
      ChecklistItem(id: newId(), text: text, done: done);

  /// A fresh client id: 12 base-36 characters from a secure source, inside
  /// the server's 8..40.
  static String newId() {
    const alphabet = '0123456789abcdefghijklmnopqrstuvwxyz';
    return List<String>.generate(
      12,
      (_) => alphabet[_random.nextInt(alphabet.length)],
    ).join();
  }

  /// "2/5": done of all, for the row badge and the section header.
  static String progressOf(List<ChecklistItem> items) =>
      '${items.where((item) => item.done).length}/${items.length}';
}

final math.Random _random = math.Random.secure();

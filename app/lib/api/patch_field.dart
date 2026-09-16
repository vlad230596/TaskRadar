import 'package:flutter/foundation.dart';

/// One field of a PATCH body, which has **three** states and not two.
///
/// ## The trap this type exists to make impossible
///
/// `backend/src/schemas.ts` declares two task fields as
/// `z.string().nullable().optional()`:
///
/// ```ts
/// description: z.string().nullable().optional(),
/// remindAt: z.coerce.date().nullable().optional(),
/// ```
///
/// and `backend/src/routes/tasks.ts` then copies them across with
/// `if (body.x !== undefined) data.x = body.x`. So the server distinguishes
/// three inputs per field, not two:
///
/// | body | meaning |
/// |---|---|
/// | key absent | leave the stored value alone |
/// | `"text"` | store this |
/// | `null` | **clear the stored value** |
///
/// In Dart, "absent" and "null" collapse the moment a field is typed `String?`
/// and written into a map: the natural
/// `body['description'] = task.description` sends `null` for every task that
/// happens to have no description *right now*, and the natural
/// `updateTask(id, status: done)` would send `description: null` alongside it
/// and silently wipe a description the user never touched. That bug leaves no
/// trace: the request succeeds, the UI shows what it optimistically expected,
/// and the text is gone.
///
/// A sum type makes the third state impossible to reach by accident -- there is
/// no way to write "clear it" that looks like "leave it alone", because
/// [PatchField.clear] has to be typed out on purpose.
///
/// Fields the server declares as `optional()` but **not** `nullable()` (a task's
/// `title`, `status`; a note's `title`, `content`) genuinely have only two
/// states, and those stay plain nullable parameters where `null` means "not
/// provided". Using this type for them would suggest a "clear" the server would
/// reject with a 400.
@immutable
sealed class PatchField<T extends Object> {
  const PatchField();

  /// Do not send this field at all.
  const factory PatchField.keep() = PatchKeep<T>;

  /// Send this value.
  const factory PatchField.to(T value) = PatchSet<T>;

  /// Send an explicit `null`, i.e. ask the server to clear the field.
  const factory PatchField.clear() = PatchClear<T>;

  /// `value ?? clear` -- for the callers that hold a nullable value and really
  /// do mean "store this, or wipe it if I have nothing".
  ///
  /// Deliberately *not* the default behaviour of [PatchField.to]: the whole
  /// point of this type is that turning a `null` into a wipe is a decision
  /// someone had to write down.
  factory PatchField.toOrClear(T? value) =>
      value == null ? PatchField<T>.clear() : PatchField<T>.to(value);

  /// Adds (or does not add) [key] to [body].
  void writeTo(Map<String, dynamic> body, String key);

  /// Whether this patch would change the request at all.
  bool get isKeep => this is PatchKeep<T>;
}

final class PatchKeep<T extends Object> extends PatchField<T> {
  const PatchKeep();

  @override
  void writeTo(Map<String, dynamic> body, String key) {
    // Nothing. This is the entire reason the type exists.
  }

  @override
  String toString() => 'PatchField<$T>.keep()';
}

final class PatchSet<T extends Object> extends PatchField<T> {
  const PatchSet(this.value);

  final T value;

  @override
  void writeTo(Map<String, dynamic> body, String key) {
    body[key] = value;
  }

  @override
  String toString() => 'PatchField<$T>.to($value)';
}

final class PatchClear<T extends Object> extends PatchField<T> {
  const PatchClear();

  @override
  void writeTo(Map<String, dynamic> body, String key) {
    body[key] = null;
  }

  @override
  String toString() => 'PatchField<$T>.clear()';
}

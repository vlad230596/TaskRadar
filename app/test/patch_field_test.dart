import 'package:flutter_test/flutter_test.dart';
import 'package:taskradar/api/patch_field.dart';

/// The difference between "do not touch this field" and "erase this field".
///
/// It is one word in a JSON body and it is the difference between an edit and a
/// data loss: `PATCH /tasks/:id` with `description: null` wipes the description,
/// and a client that sends that key on every status change wipes it on every
/// status change -- successfully, silently, with a 200 and an optimistic UI that
/// shows exactly what the user expected. See the class comment on [PatchField].
void main() {
  group('the three states', () {
    test('keep adds nothing to the body', () {
      final body = <String, dynamic>{};
      const PatchField<String>.keep().writeTo(body, 'description');

      // Not "contains a null" -- *absent*. `routes/tasks.ts` branches on
      // `!== undefined`, so an absent key is the only way to say "leave it".
      expect(body, isEmpty);
      expect(body.containsKey('description'), isFalse);
    });

    test('to writes the value', () {
      final body = <String, dynamic>{};
      const PatchField<String>.to('жду кабель').writeTo(body, 'description');

      expect(body, <String, dynamic>{'description': 'жду кабель'});
    });

    test('clear writes an explicit null', () {
      final body = <String, dynamic>{};
      const PatchField<String>.clear().writeTo(body, 'description');

      expect(body.containsKey('description'), isTrue);
      expect(body['description'], isNull);
    });
  });

  group('toOrClear', () {
    test('a value becomes a set', () {
      final body = <String, dynamic>{};
      PatchField<String>.toOrClear('текст').writeTo(body, 'description');

      expect(body, <String, dynamic>{'description': 'текст'});
    });

    test('null becomes a clear, not a keep', () {
      final body = <String, dynamic>{};
      PatchField<String>.toOrClear(null).writeTo(body, 'description');

      // This is the one conversion in the app that turns a Dart null into a
      // wipe, and it only happens where a caller asked for it by name.
      expect(body.containsKey('description'), isTrue);
      expect(body['description'], isNull);
    });
  });

  test('isKeep distinguishes the no-op from the other two', () {
    expect(const PatchField<String>.keep().isKeep, isTrue);
    expect(const PatchField<String>.to('x').isKeep, isFalse);
    expect(const PatchField<String>.clear().isKeep, isFalse);
  });

  test('several fields compose into one body', () {
    final body = <String, dynamic>{'status': 'pending'};
    const PatchField<String>.keep().writeTo(body, 'description');
    const PatchField<String>.clear().writeTo(body, 'remindAt');

    // The exact shape a "back to pending" status change sends: the status, the
    // reminder cleared because it only means something while blocked, and the
    // description untouched.
    expect(body, <String, dynamic>{'status': 'pending', 'remindAt': null});
  });
}

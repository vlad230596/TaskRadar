/// A write was asked of a list that has never been loaded.
///
/// Before the offline QA pass, the writers in `providers/` answered this case
/// with a bare `return` -- and `runMutation` took the normal completion for
/// success: no rollback, no message, and on the task screen the typed draft
/// popped away into nothing. A write that did not happen must fail like one,
/// so the writers now throw the provider's own error (usually "no network")
/// or, when there is none, this.
class NotLoadedException implements Exception {
  const NotLoadedException();

  @override
  String toString() => 'Данные ещё не загружены — обновите экран.';
}

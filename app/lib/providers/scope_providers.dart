import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/board_project.dart';
import '../models/scope.dart';
import 'board_providers.dart';
import 'dependencies.dart';

part 'scope_providers.g.dart';

/// Scopes (F7): the list of spaces, which one the board is showing, and the
/// filter that turns the second into the first.
///
/// ## The one decision this file is built around
///
/// **The board is fetched whole and filtered here, on the client.** The server
/// can filter it (`GET /board?scopeId=`) and this deliberately does not ask it
/// to, for three reasons, in order of how badly each one bites:
///
/// 1. **Reminders.** The local alarm queue is armed from the board
///    ([boardReminderBridge]). A server-filtered board would arm alarms for the
///    scope currently on screen and silently drop every other scope's -- so
///    switching to "Работа" in the morning would quietly disarm the reminder
///    about the cable for the dacha. The one feature the native client exists
///    for would fail in a way nobody notices until a date passes.
/// 2. **Switching scopes must be instant**, including with no signal. A whole
///    board is a few dozen rows; it is already in memory and already in the
///    snapshot.
/// 3. **One snapshot.** A per-scope cache would need a file per scope and a
///    rule for what to show while the fresh one for the newly selected scope is
///    still loading.
///
/// The cost is one wire format carrying projects the screen will not draw,
/// which at 10-15 projects is nothing.
///
/// ## Why the selection is stored as an id and resolved against the list
///
/// The stored value is a string from a previous run, and the scope it names can
/// be gone -- deleted on another device, or this database restored from a
/// backup. Every read therefore resolves it ([activeScope]) and falls back to
/// "all spaces" rather than trusting it, which makes "the selected scope was
/// deleted" an ordinary state instead of an empty board with no explanation.
///
/// ## "Все пространства" is the default
///
/// The board opens on every scope at once, grouped under the scope names
/// ([groupProjectsByScope]). A single scope turned out to be the wrong default:
/// the morning question is "what is waiting anywhere", and a board that shows
/// one part of life hides the others behind a switcher nobody remembers to
/// flip. Choosing one scope is still a remembered preference; "all" is simply
/// what nothing chosen means, and what [allScopesSelection] records when it is
/// chosen explicitly.

/// `GET /scopes`, in server (position) order.
///
/// `keepAlive`, like the board: the switcher is on the app's home screen and
/// the list is read by everything that creates or moves a project, so letting
/// it dispose between screens would mean re-fetching it on every navigation.
///
/// Framework retries are off for the same reason as on the board -- see
/// [noAutomaticRetry].
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class Scopes extends _$Scopes {
  @override
  Future<List<Scope>> build() {
    return ref.read(scopeApiProvider).fetchScopes();
  }

  /// Re-reads the list. Used by pull-to-refresh on the scopes screen and after
  /// a write that the client did not splice.
  Future<void> refresh() async {
    // `invalidateSelf` + await, exactly as `Board.refresh` does it: Riverpod
    // keeps the previous value visible while the rebuild is in flight, so the
    // switcher does not blank out, and a failure is left in the provider's
    // error state rather than thrown at whoever pulled to refresh.
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      // Reported by the widget watching this provider, not here.
    }
  }

  /// `POST /scopes`, appended at the end by the server.
  ///
  /// Not optimistic, unlike the task and project writes: a scope is created
  /// from a dialog a few times a year, its `position` is the server's to
  /// choose, and inventing one locally would mean guessing where the row goes
  /// while the answer is one round trip away.
  Future<Scope> create(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'a scope needs a name');
    }

    final scope = await ref.read(scopeApiProvider).createScope(name: trimmed);
    state = AsyncValue<List<Scope>>.data(<Scope>[...?state.value, scope]);
    return scope;
  }

  /// `PATCH /scopes/:id`. Optimistic, because the name is a string the user
  /// just typed and it is on screen in the switcher while they type it.
  Future<void> rename(Scope scope, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(name, 'name', 'a scope needs a name');
    }
    if (trimmed == scope.name) return;

    final previous = state.value ?? const <Scope>[];
    _publish(
      previous
          .map((s) => s.id == scope.id ? s.copyWith(name: trimmed) : s)
          .toList(),
    );

    try {
      final saved = await ref
          .read(scopeApiProvider)
          .renameScope(scope.id, name: trimmed);
      _publish(
        (state.value ?? previous)
            .map((s) => s.id == saved.id ? saved : s)
            .toList(),
      );
    } catch (error) {
      _publish(previous);
      rethrow;
    }
  }

  /// `PATCH /scopes/:id/position`, by naming the **neighbours in the new
  /// order**.
  ///
  /// The index arithmetic is `ReorderableListView`'s convention, ported exactly
  /// as the task list does it: `newIndex` counts positions in the list *before*
  /// the row is removed, so moving downwards needs the decrement. Getting this
  /// wrong is a one-off error that only shows up when dragging downwards, which
  /// is why it is written once and tested.
  Future<void> move(int oldIndex, int newIndex) async {
    final previous = state.value ?? const <Scope>[];
    if (oldIndex < 0 || oldIndex >= previous.length) return;

    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (target == oldIndex) return;

    final reordered = <Scope>[...previous];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(target, moved);
    _publish(reordered);

    // Neighbours are read from the list the user just made, by id -- never by
    // position. A position computed here would be stale the moment the server
    // decides it has to rebalance (see ScopeApi.moveScope).
    final before = target > 0 ? reordered[target - 1] : null;
    final after = target + 1 < reordered.length ? reordered[target + 1] : null;

    try {
      await ref
          .read(scopeApiProvider)
          .moveScope(
            moved.id,
            beforeScopeId: before?.id,
            afterScopeId: after?.id,
          );
      // The server answers with the moved row only, and its new `position` can
      // be the product of a rebalance that renumbered every other row too. So
      // the list is re-read rather than patched: it is five rows, and the
      // alternative is holding positions that quietly disagree with the server.
      await refresh();
    } catch (error) {
      _publish(previous);
      rethrow;
    }
  }

  /// `DELETE /scopes/:id`. The server answers 409 when the scope still holds
  /// projects (archived ones included) or is the last one left; the caller
  /// turns that into a message.
  Future<void> delete(Scope scope) async {
    final previous = state.value ?? const <Scope>[];
    await ref.read(scopeApiProvider).deleteScope(scope.id);
    _publish(previous.where((s) => s.id != scope.id).toList());

    // The board does not change -- a deletable scope held no projects -- but
    // the *selection* might have been pointing at it. Nothing to do here:
    // [activeScope] resolves against this list on every read and falls back to
    // the first scope, so the switcher corrects itself.
  }

  void _publish(List<Scope> scopes) {
    state = AsyncValue<List<Scope>>.data(List<Scope>.unmodifiable(scopes));
  }
}

/// What [SelectedScopeId] stores for "Все пространства".
///
/// A value no scope id can be (ids are cuids), so it can never resolve to a
/// real scope by accident. Resolving it goes through the same "not a known id"
/// branch as a deleted scope, which is exactly the right answer for both.
const String allScopesSelection = '*';

/// Which scope the board is showing, as stored on disk (F7).
///
/// The raw id, resolved by [activeScope]. Null means "nothing was ever chosen",
/// which is the ordinary state on a fresh install and reads as "all spaces" --
/// as does [allScopesSelection].
@Riverpod(keepAlive: true)
class SelectedScopeId extends _$SelectedScopeId {
  @override
  Future<String?> build() {
    return ref.read(settingsStoreProvider).readSelectedScopeId();
  }

  /// "Все пространства", remembered like any other choice.
  Future<void> selectAll() => select(allScopesSelection);

  /// Remembers the choice, showing it immediately.
  ///
  /// The write is awaited but its failure is **not** propagated as a state
  /// change: a preference that could not be persisted must not make the board
  /// jump back to another scope under the user's finger. The worst case is that
  /// the choice is forgotten by tomorrow, which is a smaller lie than the
  /// screen changing by itself.
  Future<void> select(String scopeId) async {
    state = AsyncValue<String?>.data(scopeId);
    try {
      await ref.read(settingsStoreProvider).writeSelectedScopeId(scopeId);
    } catch (error) {
      // Deliberately swallowed; see above.
    }
  }
}

/// The one scope the board is narrowed to, or **null for "all spaces"**.
///
/// Null covers three states that all mean "show everything": nothing was
/// chosen (the default), "Все пространства" was chosen, or the stored id no
/// longer names a scope. It is also the answer while the list is loading, when
/// "all of them" is the honest thing to draw. Only a stored id that names a
/// scope that exists narrows the board.
///
/// Anything that needs *a* scope rather than a filter -- creating a project --
/// passes this through as-is: null there means "let the server choose", and
/// the server's default is the first scope in position order, the same one the
/// grouped board lists first.
@Riverpod(keepAlive: true)
Scope? activeScope(Ref ref) {
  final scopes = ref.watch(scopesProvider).value;
  if (scopes == null || scopes.isEmpty) return null;

  final storedId = ref.watch(selectedScopeIdProvider).value;
  if (storedId == null || storedId == allScopesSelection) return null;
  for (final scope in scopes) {
    if (scope.id == storedId) return scope;
  }
  return null;
}

/// True when the switcher is worth drawing at all.
///
/// One scope is what every existing installation has after the migration, and a
/// switcher with a single option is furniture: it costs a row of screen on the
/// home screen to offer a choice that does not exist. So the whole feature
/// stays invisible until a second scope is created -- which is also what makes
/// F7 free for someone who never wanted it.
@Riverpod(keepAlive: true)
bool hasMultipleScopes(Ref ref) {
  final scopes = ref.watch(scopesProvider).value;
  return scopes != null && scopes.length > 1;
}

/// The board rows that belong to [scope].
///
/// A free function rather than a provider so the same rule serves the board and
/// the archive, and so it can be tested without a container. Null [scope] is
/// "all spaces" (see [activeScope]) and shows everything -- which is also the
/// honest answer during the frame before the scope list lands.
List<BoardProject> projectsInScope(List<BoardProject> projects, Scope? scope) {
  if (scope == null) return projects;
  return projects
      .where((entry) => entry.project.scopeId == scope.id)
      .toList(growable: false);
}

/// One heading of the "all spaces" board: a scope and its projects.
///
/// [scope] is null only for the trailing group of projects whose scope is not
/// in the list -- a scope created on another device a moment ago, before the
/// scope list here was re-read. They are drawn under no heading rather than
/// dropped: a project that vanished from the board would be the worse lie.
typedef ScopeGroup = ({Scope? scope, List<BoardProject> projects});

/// The board's projects grouped by scope, in scope (position) order, each group
/// in the board's own order. Scopes with no projects get no group -- a heading
/// over nothing is noise on the one screen that has to be read at a glance.
List<ScopeGroup> groupProjectsByScope(
  List<BoardProject> projects,
  List<Scope> scopes,
) {
  final byScope = <String, List<BoardProject>>{};
  for (final entry in projects) {
    byScope
        .putIfAbsent(entry.project.scopeId, () => <BoardProject>[])
        .add(entry);
  }

  final groups = <ScopeGroup>[];
  for (final scope in scopes) {
    final rows = byScope.remove(scope.id);
    if (rows != null) groups.add((scope: scope, projects: rows));
  }
  final orphans = byScope.values.expand((rows) => rows).toList();
  if (orphans.isNotEmpty) {
    // Back in board order: the map above interleaved them by scope id.
    orphans.sort((a, b) => projects.indexOf(a) - projects.indexOf(b));
    groups.add((scope: null, projects: orphans));
  }
  return groups;
}

/// How many **active** projects sit in one scope, or null while the board has
/// not loaded.
///
/// Read from the board that is already in memory rather than from a count
/// endpoint that does not exist: the client holds every project anyway (see the
/// note at the top of this file), so this is a filter over data already
/// fetched. Null rather than 0 while the board is unknown -- "no projects" and
/// "we do not know yet" must not look the same next to a delete button.
@riverpod
int? projectCountInScope(Ref ref, String scopeId) {
  final view = ref.watch(boardViewProvider);
  if (view is! BoardReady) return null;
  return view.projects.where((e) => e.project.scopeId == scopeId).length;
}

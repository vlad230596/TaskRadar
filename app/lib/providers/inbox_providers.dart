import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/inbox_item.dart';
import '../models/task.dart';
import 'board_providers.dart';
import 'capture_queue_providers.dart';
import 'dependencies.dart';

part 'inbox_providers.g.dart';

/// The sandbox (F8): the pile of lines the server holds, and what can happen to
/// one.
///
/// ## Where capture went (F8.1)
///
/// It is not here any more. Writing a line down is `CaptureQueue.capture` in
/// `capture_queue_providers.dart`: it goes to a file on the device first and
/// reaches the server afterwards, because the sandbox has to work with no
/// network -- "надо не забыть" arrives in a lift. This provider holds the lines
/// the server has acknowledged; the screen shows both, and the queued ones
/// carry an "unsent" mark.
///
/// That also retired the long note F8 left here about capture being the app's
/// one non-optimistic write. The reasoning was right for the code as it stood
/// (a row that appears and evaporates breaks the sandbox's only promise) and
/// wrong the moment a queue existed: with one, the line is on disk before it is
/// on screen, so showing it immediately promises nothing that cannot be kept.
///
/// ## What still requires the network, and why that is not inconsistent
///
/// Editing, discarding and filing all go straight to the server here. The
/// exception F8.1 carved out is about the *shape of the data*, not about the
/// sandbox being special: a captured line has no order, no state another device
/// can change, and a lifetime of hours, so two devices merging is set union.
/// Filing lands a task at a position in a list somebody else may have reordered
/// since -- the conflict resolution this product still defers.
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class Inbox extends _$Inbox {
  @override
  Future<List<InboxItem>> build() {
    return ref.read(inboxApiProvider).fetchInbox();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    try {
      await future;
    } catch (error) {
      // Reported by whoever is watching this provider.
    }
  }

  /// Takes rows that are already on the server into the pile, without a round
  /// trip.
  ///
  /// Called by the capture queue when a flush succeeds: those rows came from
  /// `POST /inbox` in exactly the shape `GET /inbox` would have sent them, so
  /// re-fetching the list to learn what this client already has in its hand
  /// would be a request spent on nothing.
  ///
  /// Two guards, both for real cases:
  ///
  /// - nothing happens unless the pile has actually loaded. Splicing into an
  ///   absent list would turn "not loaded yet" into "these three lines are
  ///   everything there is", and the board badge would report it as fact;
  /// - an id already present is skipped, because a flush can re-send a line
  ///   whose first attempt did reach the server (that is what the idempotency
  ///   key is for) and get back a row this list already holds.
  void adoptAll(List<InboxItem> items) {
    final current = state.value;
    if (current == null || items.isEmpty) return;

    final known = current.map((row) => row.id).toSet();
    final added = <InboxItem>[
      for (final row in items)
        if (known.add(row.id)) row,
    ];
    if (added.isEmpty) return;

    _publish(<InboxItem>[...current, ...added]);
  }

  /// `PATCH /inbox/:id`.
  Future<void> edit(InboxItem item, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(text, 'text', 'an inbox item needs text');
    }
    if (trimmed == item.text) return;

    final saved = await ref
        .read(inboxApiProvider)
        .editItem(item.id, text: trimmed);
    _publish(
      (state.value ?? const <InboxItem>[])
          .map((row) => row.id == saved.id ? saved : row)
          .toList(),
    );
  }

  /// `DELETE /inbox/:id`.
  Future<void> discard(InboxItem item) async {
    await ref.read(inboxApiProvider).deleteItem(item.id);
    _publish(
      (state.value ?? const <InboxItem>[])
          .where((row) => row.id != item.id)
          .toList(),
    );
  }

  /// `POST /inbox/:id/file` -- the line becomes a task in [projectId].
  ///
  /// The board is **invalidated** rather than spliced, and this is the one
  /// place in the app where that is not laziness: the response is a single raw
  /// task row with no `isCurrent`, and `Board.applyProjectTasks` wants the
  /// project's whole settled list (that is what makes the current-task
  /// highlight and the counters right). Re-reading `GET /board` is one request
  /// for an action performed a handful of times a day, and it also re-arms the
  /// reminder queue for free -- the filed task carries no date yet, but the
  /// board it lands on is the one the alarms are built from.
  Future<Task> file(InboxItem item, {required String projectId}) async {
    final task = await ref
        .read(inboxApiProvider)
        .fileItem(item.id, projectId: projectId);

    _publish(
      (state.value ?? const <InboxItem>[])
          .where((row) => row.id != item.id)
          .toList(),
    );
    ref.invalidate(boardProvider);
    return task;
  }

  void _publish(List<InboxItem> items) {
    state = AsyncValue<List<InboxItem>>.data(List<InboxItem>.unmodifiable(items));
  }
}

/// How many lines are waiting, or null while there is nothing honest to say.
///
/// Counts both halves of the sandbox: what the server holds and what is still
/// queued on this device (F8.1). A line captured in the lift is in the pile
/// from the user's point of view the moment it is typed, and a badge that only
/// caught up once the phone found a signal would be telling them their sandbox
/// is emptier than it is.
///
/// Null rather than 0 while the server half is unknown *and* nothing is queued:
/// the board draws this as a badge, and one that says "0" and then changes to
/// "3" is a small lie told every cold start. With something queued there is a
/// real number to show, so it shows it.
@Riverpod(keepAlive: true)
int? inboxCount(Ref ref) {
  final filed = ref.watch(inboxProvider).value?.length;
  final pending = ref.watch(pendingCapturesProvider).length;
  if (filed == null) return pending == 0 ? null : pending;
  return filed + pending;
}

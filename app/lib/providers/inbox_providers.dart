import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../models/inbox_item.dart';
import '../models/task.dart';
import 'board_providers.dart';
import 'dependencies.dart';

part 'inbox_providers.g.dart';

/// The sandbox (F8): the pile, and the four things that can happen to a line in
/// it.
///
/// ## Why the writes here are not optimistic
///
/// Every other write in this app shows its result immediately and rolls back on
/// failure (`project_providers.dart` explains why). Capture is the exception,
/// and for a reason specific to what it is for: **a captured line that quietly
/// disappears is the failure this feature exists to prevent.** An optimistic
/// row is a promise the client cannot keep without a queue, and there is no
/// queue -- `../../../flutter-migration-plan.md` still defers offline editing.
/// So capture waits for the server and only then shows the line, and a failure
/// is a message with the text still in the field rather than a row that appears
/// and then evaporates.
///
/// That is also the honest limit of F8, worth knowing before relying on it:
/// **capture needs the network.** The scenario it is built for -- writing
/// something down while walking -- is exactly the one where the phone may have
/// no signal. If that turns out to matter in practice, an offline capture queue
/// is the natural first exception to the no-offline-writes rule, precisely
/// because an inbox item has no ordering and no conflicts: two devices can only
/// ever add lines.
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

  /// `POST /inbox`. Appended at the end, which is where the server's
  /// oldest-first order puts a new line.
  Future<InboxItem> capture(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(text, 'text', 'an inbox item needs text');
    }

    final item = await ref.read(inboxApiProvider).capture(text: trimmed);
    _publish(<InboxItem>[...?state.value, item]);
    return item;
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

/// How many lines are waiting, or null while the pile has not loaded.
///
/// Null rather than 0 on purpose: the board draws this as a badge, and a badge
/// that says nothing while the request is in flight is right, whereas one that
/// says "0" and then changes to "3" is a small lie told every cold start.
@Riverpod(keepAlive: true)
int? inboxCount(Ref ref) => ref.watch(inboxProvider).value?.length;

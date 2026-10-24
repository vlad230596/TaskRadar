import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_error_message.dart';
import '../api/api_exception.dart';
import '../domain/outbox_overlay.dart';
import '../models/task.dart';
import '../storage/capture_queue_store.dart' show PendingCapture;
import '../storage/outbox_store.dart';
import 'board_providers.dart';
import 'dependencies.dart';
import 'project_providers.dart';

part 'outbox_providers.g.dart';

/// Task writes made with no network, and the last week of what became of
/// them (the "Офлайн" view of the history mode).
///
/// ## What goes in, and when
///
/// Only what failed for want of a network: `ProjectTasks` tries the request
/// first, as it always has, and hands the write here when the answer is a
/// [NetworkException]. Unlike the capture queue (which takes every line, see
/// `CaptureQueue`), a task write online has a reconcile to do -- `isCurrent`,
/// positions -- and routing every edit through a file would make the common
/// case slower to buy nothing.
///
/// ## What "gentle" means here
///
/// An edit carries the values it was made against. If the server's task has
/// moved on since (edited on the laptop meanwhile), the server refuses it with
/// a 409, nothing is overwritten, and the entry waits in the history as
/// "пропущено" with both values -- the user can apply theirs on purpose, copy
/// it, or leave the server's. A create is idempotent by its key, so a replay
/// after a lost answer cannot make a twin.
@Riverpod(keepAlive: true, retry: noAutomaticRetry)
class Outbox extends _$Outbox {
  /// The tail of the chain of flushes -- see `CaptureQueue._flushing` for why
  /// they are chained rather than skipped or run in parallel.
  Future<void>? _flushing;

  /// Rebuilds the marks once a green "отправлено" has been seen long enough.
  Timer? _fade;

  /// How long a just-sent row keeps its green check.
  static const Duration sentMarkFor = Duration(seconds: 3);

  @override
  Future<List<OutboxEntry>> build() async {
    ref.onDispose(() => _fade?.cancel());
    return _prune(await ref.read(outboxStoreProvider).read());
  }

  OutboxStore get _store => ref.read(outboxStoreProvider);

  /// Puts a create on the outbox. Returns once it is on disk; throws only if
  /// it is not -- then the task exists nowhere and the caller must say so.
  Future<OutboxEntry> queueCreate({
    required String projectId,
    required Map<String, Object?> body,
  }) {
    return _append(
      OutboxEntry(
        key: PendingCapture.newKey(),
        kind: OutboxKind.createTask,
        projectId: projectId,
        title: body['title']! as String,
        body: body,
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Puts an edit of [base] on the outbox. [body] is the `PATCH` body;
  /// [checked] are the fields whose values in [base] the server must still
  /// hold for the edit to apply -- by default every field the edit changes.
  ///
  /// [base] is the row as the user saw it, including any edit still waiting
  /// in front of this one: the second edit of an offline afternoon is made
  /// against the first, and if the first is skipped, so is the second -- it
  /// was never made against what the server has.
  Future<OutboxEntry> queueEdit({
    required Task base,
    required Map<String, Object?> body,
    Set<String>? checked,
  }) {
    final values = taskWireValues(base);
    final fields = checked ?? body.keys.toSet();
    return _append(
      OutboxEntry(
        key: PendingCapture.newKey(),
        kind: OutboxKind.editTask,
        projectId: base.projectId,
        taskId: base.id,
        title: base.title,
        body: body,
        expected: <String, Object?>{
          for (final field in outboxTaskFields)
            if (fields.contains(field)) field: values[field],
        },
        createdAt: DateTime.now(),
      ),
    );
  }

  /// A refused entry, back to waiting.
  Future<void> retry(OutboxEntry entry) =>
      _replace(entry.key, (row) => row.copyWith(state: OutboxState.waiting));

  /// A refused entry, thrown away.
  Future<void> discard(OutboxEntry entry) async {
    final next = (await future)
        .where((row) => row.key != entry.key)
        .toList(growable: false);
    await _store.write(next);
    _publish(next);
  }

  /// A skipped edit, left as the server has it.
  Future<void> keepServer(OutboxEntry entry) => _replace(
    entry.key,
    (row) =>
        row.copyWith(state: OutboxState.resolved, settledAt: DateTime.now()),
  );

  /// A skipped edit, sent again on purpose over the server's value: the same
  /// body, now expected to land on what the server had when it refused.
  Future<void> applyMine(OutboxEntry entry) => _replace(entry.key, (row) {
    final server = row.serverTask;
    return OutboxEntry(
      key: row.key,
      kind: row.kind,
      projectId: row.projectId,
      taskId: row.taskId,
      title: row.title,
      body: row.body,
      expected: server == null
          ? row.expected
          : <String, Object?>{
              for (final field in row.expected.keys)
                field: jsonWireValues(server)[field],
            },
      createdAt: row.createdAt,
    );
  });

  /// Sends what is waiting, oldest first. Never throws. Called from the same
  /// moments as the capture queue's flush (`CaptureFlushScope`).
  Future<void> flush() {
    final running = _flushing;
    final next = running == null ? _flush() : running.then((_) => _flush());
    _flushing = next;
    next.whenComplete(() {
      if (identical(_flushing, next)) _flushing = null;
    });
    return next;
  }

  Future<void> _flush() async {
    final snapshot = await future;
    if (!snapshot.any((entry) => entry.isWaiting)) return;

    final api = ref.read(projectApiProvider);
    final settled = <String, OutboxEntry>{};
    final touched = <String>{};

    for (final entry in snapshot) {
      if (!entry.isWaiting) continue;
      try {
        final task = switch (entry.kind) {
          OutboxKind.createTask => await api.createTask(
            projectId: entry.projectId,
            title: entry.body['title']! as String,
            description: entry.body['description'] as String?,
            categoryId: entry.body['categoryId'] as String?,
            remindAt: entry.body['remindAt'] as String?,
            remindTime: entry.body['remindTime'] as String?,
            dictationParseId: entry.body['dictationParseId'] as String?,
            createKey: entry.key,
          ),
          OutboxKind.editTask => await api.replayTaskPatch(
            entry.taskId!,
            entry.body,
            expected: entry.expected,
          ),
        };
        settled[entry.key] = entry.copyWith(
          state: OutboxState.sent,
          settledAt: DateTime.now(),
          taskId: task.id,
        );
        touched.add(entry.projectId);
      } on NetworkException {
        // Still no network: the rest would fail the same way.
        break;
      } on UnauthorizedException {
        // The session is gone; the entries wait on disk for the next one.
        break;
      } on ApiException catch (error) {
        final body = error.body;
        if (error.statusCode == 409 &&
            body is Map &&
            body['error'] == 'conflict') {
          settled[entry.key] = entry.copyWith(
            state: OutboxState.skipped,
            settledAt: DateTime.now(),
            conflictFields: List<String>.from(
              (body['fields'] as List?) ?? const <String>[],
            ),
            serverTask: body['task'] is Map
                ? Map<String, Object?>.from(body['task'] as Map)
                : null,
          );
          touched.add(entry.projectId);
          continue;
        }
        // The server answered and said no. Kept, marked, and not holding the
        // entries behind it hostage -- the capture queue's rule.
        debugPrint('Outbox ${entry.key} refused: $error');
        settled[entry.key] = entry.copyWith(
          state: OutboxState.refused,
          settledAt: DateTime.now(),
          message: describeApiError(error),
        );
      }
    }

    if (settled.isEmpty) return;

    // The lists the entries landed in, re-read once per project *before* the
    // entries stop waiting: the other order would show the list without the
    // overlay and without the server's row for one frame -- an offline task
    // blinking out of existence on the way to being saved.
    for (final projectId in touched) {
      await _adoptFreshTasks(projectId);
    }

    // Reconciled against the outbox as it is now, not as this pass found it:
    // an edit can be queued while a request is in flight.
    final live = <OutboxEntry>[
      for (final row in await future) settled[row.key] ?? row,
    ];
    try {
      await _store.write(live);
    } catch (error) {
      // The writes *are* on the server. The file still has them as waiting;
      // the next pass sends them again, which the create key and `expected`
      // (a field that already holds the value is not a conflict) both absorb.
      debugPrint('Could not record the sent outbox entries: $error');
    }
    _publish(live);

    _fade?.cancel();
    _fade = Timer(sentMarkFor, () {
      final value = state.value;
      if (value != null) _publish(value);
    });
  }

  Future<void> _adoptFreshTasks(String projectId) async {
    try {
      final rows = await ref.read(projectApiProvider).fetchTasks(projectId);
      if (!ref.mounted) return;
      ref.read(boardProvider.notifier).applyProjectTasks(projectId, rows);
      final provider = projectTasksProvider(projectId);
      if (ref.exists(provider)) ref.read(provider.notifier).adopt(rows);
    } catch (error) {
      // The lists catch up on their own next read; the entries are sent.
      debugPrint('Could not re-read $projectId after the outbox: $error');
    }
  }

  Future<OutboxEntry> _append(OutboxEntry entry) async {
    final next = <OutboxEntry>[...await future, entry];
    await _store.write(next);
    _publish(next);
    return entry;
  }

  Future<void> _replace(
    String key,
    OutboxEntry Function(OutboxEntry row) change,
  ) async {
    final next = <OutboxEntry>[
      for (final row in await future) row.key == key ? change(row) : row,
    ];
    await _store.write(next);
    _publish(next);
    if (next.any((row) => row.key == key && row.isWaiting)) {
      unawaited(flush());
    }
  }

  void _publish(List<OutboxEntry> entries) {
    if (!ref.mounted) return;
    state = AsyncData(List<OutboxEntry>.unmodifiable(entries));
  }

  /// Drops history older than [OutboxStore.keepHistory]. Never an entry that
  /// is waiting or waits for a decision: those are not history yet.
  static List<OutboxEntry> _prune(List<OutboxEntry> entries) {
    final cutoff = DateTime.now().subtract(OutboxStore.keepHistory);
    return List<OutboxEntry>.unmodifiable(
      entries.where(
        (entry) =>
            entry.isWaiting ||
            entry.needsDecision ||
            (entry.settledAt ?? entry.createdAt).isAfter(cutoff),
      ),
    );
  }
}

/// Everything in the outbox, or nothing while the file loads.
@Riverpod(keepAlive: true)
List<OutboxEntry> outboxEntries(Ref ref) =>
    ref.watch(outboxProvider).value ?? const <OutboxEntry>[];

/// How many entries the history mode's badge counts: waiting, and waiting
/// for a decision.
@Riverpod(keepAlive: true)
({int waiting, int decisions}) outboxCounts(Ref ref) {
  final entries = ref.watch(outboxEntriesProvider);
  return (
    waiting: entries.where((entry) => entry.isWaiting).length,
    decisions: entries.where((entry) => entry.needsDecision).length,
  );
}

/// The mark a task row carries.
enum OutboxMark {
  /// "не отправлено": a create or an edit of this row is waiting.
  waiting,

  /// "отправлено", green, for [Outbox.sentMarkFor] after it went.
  sent,
}

/// The marks of one project's rows, by task id (an unsent create's by its
/// `localTaskId`).
@riverpod
Map<String, OutboxMark> outboxMarks(Ref ref, String projectId) {
  final now = DateTime.now();
  final marks = <String, OutboxMark>{};
  for (final entry in ref.watch(outboxEntriesProvider)) {
    if (entry.projectId != projectId) continue;
    switch (entry.state) {
      case OutboxState.waiting:
        final id = entry.kind == OutboxKind.createTask
            ? entry.localTaskId
            : entry.taskId;
        if (id != null) marks[id] = OutboxMark.waiting;
      case OutboxState.sent:
        final id = entry.taskId;
        final at = entry.settledAt;
        if (id != null &&
            at != null &&
            now.difference(at) < Outbox.sentMarkFor &&
            marks[id] != OutboxMark.waiting) {
          marks[id] = OutboxMark.sent;
        }
      case OutboxState.skipped || OutboxState.refused || OutboxState.resolved:
        break;
    }
  }
  return marks;
}

/// Whether the history mode shows its «Офлайн» view (the outbox) instead of
/// its charts. Kept above the screen so the header's switch and the body read
/// one answer.
@Riverpod(keepAlive: true)
class HistoryShowsOutbox extends _$HistoryShowsOutbox {
  @override
  bool build() => false;

  void show(bool value) => state = value;
}

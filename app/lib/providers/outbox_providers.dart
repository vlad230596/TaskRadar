import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../api/api_error_message.dart';
import '../api/api_exception.dart';
import '../api/attachment_api.dart';
import '../api/task_wire.dart';
import '../domain/outbox_overlay.dart';
import '../models/task.dart';
import '../models/task_status.dart';
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
  ///
  /// [key] is the `createKey`; a create that was already tried online passes
  /// the key it was tried with, so a request whose answer was lost is not
  /// made twice.
  Future<OutboxEntry> queueCreate({
    required String projectId,
    required Map<String, Object?> body,
    String? key,
  }) {
    return _append(
      OutboxEntry(
        key: key ?? PendingCapture.newKey(),
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

  /// Puts a move of [base] into [targetProjectId] on the outbox.
  ///
  /// [base] is the row as the user saw it -- edits still waiting in front of
  /// this one included -- and is kept whole in [OutboxEntry.row], because the
  /// target's list has never had the task and has to draw it from something.
  /// No `expected`: a move overwrites no field the user typed, and the server
  /// answers a replay of a move that already landed with the task unchanged.
  Future<OutboxEntry> queueMove({
    required Task base,
    required String targetProjectId,
  }) {
    return _append(
      OutboxEntry(
        key: PendingCapture.newKey(),
        kind: OutboxKind.moveTask,
        projectId: base.projectId,
        taskId: base.id,
        title: base.title,
        body: <String, Object?>{'projectId': targetProjectId},
        row: base.toJson(),
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Puts a picture for [taskIdOrLocal] on the outbox: the task's id, or the
  /// `local:outbox:<createKey>` of its create still in the outbox.
  ///
  /// [localPath] is the copy already made in `OutboxFileStore` under [key]
  /// (which is also the `uploadKey`). [projectId] and [title] are the task's,
  /// for the history line and the overlay; for a local id they are taken
  /// from its create. Does not send -- the caller flushes, so the order is
  /// always the outbox's.
  Future<OutboxEntry> queueUpload({
    required String key,
    required String taskIdOrLocal,
    required String localPath,
    required String mime,
    String? projectId,
    String? title,
  }) async {
    final create = _createOf(await future, taskIdOrLocal);
    return _append(
      OutboxEntry(
        key: key,
        kind: OutboxKind.uploadAttachment,
        projectId: create?.projectId ?? projectId ?? '',
        taskId: taskIdOrLocal,
        title: create?.title ?? title ?? '',
        body: <String, Object?>{
          'uploadKey': key,
          'mime': mime,
          'localPath': localPath,
        },
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Puts the removal of [attachmentId] from [task] on the outbox. Does not
  /// send, like [queueUpload].
  Future<OutboxEntry> queueDeleteAttachment({
    required Task task,
    required String attachmentId,
    bool waited = false,
  }) {
    return _append(
      OutboxEntry(
        key: PendingCapture.newKey(),
        kind: OutboxKind.deleteAttachment,
        projectId: task.projectId,
        taskId: task.id,
        title: task.title,
        body: <String, Object?>{'attachmentId': attachmentId},
        createdAt: DateTime.now(),
        waited: waited,
      ),
    );
  }

  /// The create of a `local:outbox:<key>` id, if it is in the outbox.
  static OutboxEntry? _createOf(List<OutboxEntry> entries, String taskId) {
    const prefix = 'local:outbox:';
    if (!taskId.startsWith(prefix)) return null;
    final key = taskId.substring(prefix.length);
    for (final entry in entries) {
      if (entry.kind == OutboxKind.createTask && entry.key == key) return entry;
    }
    return null;
  }

  /// A refused entry, back to waiting.
  Future<void> retry(OutboxEntry entry) =>
      _replace(entry.key, (row) => row.copyWith(state: OutboxState.waiting));

  /// A refused entry, thrown away -- and a picture's local copy with it.
  /// Also takes a picture still waiting («Убрать» on its thumbnail).
  Future<void> discard(OutboxEntry entry) async {
    await _serial(() async {
      final next = (await future)
          .where((row) => row.key != entry.key)
          .toList(growable: false);
      await _store.write(next);
      _publish(next);
    });
    final path = entry.localPath;
    if (path != null) await ref.read(outboxFileStoreProvider).delete(path);
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

    /// Pictures sent on the first try, which leave the outbox instead of
    /// becoming history (see [OutboxEntry.waited]).
    final dropped = <String>{};

    /// Local copies to delete once the entries that name them are written.
    final sentFiles = <String>[];

    /// Whether the pass stopped for want of a network (or a session).
    var stalled = false;

    for (final entry in snapshot) {
      if (!entry.isWaiting) continue;
      try {
        final String? taskId;
        switch (entry.kind) {
          case OutboxKind.createTask:
            final body = entry.body;
            final status = body['status'] as String?;
            taskId = (await api.createTask(
              projectId: entry.projectId,
              title: body['title']! as String,
              description: body['description'] as String?,
              categoryId: body['categoryId'] as String?,
              status: status == null ? null : TaskStatus.values.byName(status),
              remindAt: body['remindAt'] as String?,
              remindTime: body['remindTime'] as String?,
              checklist: TaskWire.checklistFrom(body[TaskWire.checklistKey]),
              location: TaskWire.locationFrom(body[TaskWire.locationKey]),
              dictationParseId: body['dictationParseId'] as String?,
              createKey: entry.key,
            )).id;
          case OutboxKind.editTask:
            taskId = (await api.replayTaskPatch(
              entry.taskId!,
              entry.body,
              expected: entry.expected,
            )).id;
          case OutboxKind.moveTask:
            taskId = (await api.moveTaskToProject(
              entry.taskId!,
              entry.targetProjectId!,
            )).id;
          case OutboxKind.uploadAttachment:
            final target = _uploadTarget(entry, snapshot, settled);
            switch (target) {
              case _UploadWaits():
                // Its task's create has not gone yet (refused, skipped):
                // the picture waits with it, and holds nothing else up.
                continue;
              case _UploadOrphaned(:final message):
                settled[entry.key] = entry.copyWith(
                  state: OutboxState.refused,
                  settledAt: DateTime.now(),
                  message: message,
                );
                continue;
              case _UploadTo(:final id):
                final sent = await _upload(entry, id);
                if (sent == null) {
                  settled[entry.key] = entry.copyWith(
                    state: OutboxState.refused,
                    settledAt: DateTime.now(),
                    message: 'Файл картинки потерян на устройстве',
                  );
                  continue;
                }
            }
            taskId = target.taskId;
            final path = entry.localPath;
            if (path != null) sentFiles.add(path);
            if (!entry.waited) dropped.add(entry.key);
          case OutboxKind.deleteAttachment:
            try {
              await ref.read(attachmentApiProvider).delete(entry.attachmentId!);
            } on ApiException catch (error) {
              // Gone already: what the delete wanted.
              if (error.statusCode != 404) rethrow;
            }
            taskId = entry.taskId;
            if (!entry.waited) dropped.add(entry.key);
        }
        settled[entry.key] = entry.copyWith(
          state: OutboxState.sent,
          settledAt: DateTime.now(),
          taskId: taskId,
        );
        if (entry.projectId.isNotEmpty) {
          touched
            ..add(entry.projectId)
            ..add(entry.landsInProjectId);
        }
      } on NetworkException {
        // Still no network: the rest would fail the same way.
        stalled = true;
        break;
      } on UnauthorizedException {
        // The session is gone; the entries wait on disk for the next one.
        stalled = true;
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

    _clearProgress();

    // Pictures that are now waiting for a network are offline history: they
    // stay in the «Офлайн» view once sent, like any other offline write.
    if (stalled) {
      for (final entry in snapshot) {
        if (entry.isAttachment &&
            entry.isWaiting &&
            !entry.waited &&
            !settled.containsKey(entry.key)) {
          settled[entry.key] = entry.copyWith(waited: true);
        }
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
    // Under [_serial], so a picture thrown away or an edit queued meanwhile
    // is neither lost nor brought back by this write.
    await _serial(() async {
      final live = <OutboxEntry>[
        for (final row in await future)
          if (!dropped.contains(row.key)) settled[row.key] ?? row,
      ];
      try {
        await _store.write(live);
      } catch (error) {
        // The writes *are* on the server. The file still has them as
        // waiting; the next pass sends them again, which the create key,
        // the upload key and `expected` (a field that already holds the
        // value is not a conflict) all absorb.
        debugPrint('Could not record the sent outbox entries: $error');
      }
      _publish(live);
    });

    final files = ref.read(outboxFileStoreProvider);
    for (final path in sentFiles) {
      await files.delete(path);
    }

    _fade?.cancel();
    _fade = Timer(sentMarkFor, () {
      final value = state.value;
      if (value != null) _publish(value);
    });
  }

  /// Where an upload goes: its task's id, or -- for a picture of a task
  /// created offline -- the id that create got, from this pass ([settled])
  /// or an earlier one.
  static _UploadTarget _uploadTarget(
    OutboxEntry entry,
    List<OutboxEntry> snapshot,
    Map<String, OutboxEntry> settled,
  ) {
    final taskId = entry.taskId;
    if (taskId == null || taskId.isEmpty) {
      return const _UploadOrphaned('Картинка без задачи');
    }
    const prefix = 'local:outbox:';
    if (!taskId.startsWith(prefix)) return _UploadTo(taskId);

    final key = taskId.substring(prefix.length);
    OutboxEntry? create;
    for (final row in snapshot) {
      if (row.kind == OutboxKind.createTask && row.key == key) {
        create = settled[row.key] ?? row;
        break;
      }
    }
    if (create == null) {
      // The create was thrown away: the task never existed on the server.
      return const _UploadOrphaned('Задача не была создана');
    }
    final created = create.taskId;
    if (create.state == OutboxState.sent && created != null) {
      return _UploadTo(created);
    }
    return const _UploadWaits();
  }

  /// Sends one picture's bytes, reporting progress. Null when the local copy
  /// is gone.
  Future<Object?> _upload(OutboxEntry entry, String taskId) async {
    final path = entry.localPath;
    final bytes = path == null
        ? null
        : await ref.read(outboxFileStoreProvider).read(path);
    if (bytes == null) return null;

    final progress = ref.read(uploadProgressProvider.notifier);
    progress.report(entry.key, 0);
    final saved = await ref
        .read(attachmentApiProvider)
        .upload(
          taskId,
          uploadKey: entry.key,
          bytes: bytes,
          mime: entry.mime ?? sniffImageMime(bytes) ?? 'image/jpeg',
          onSendProgress: (sent, total) {
            if (total > 0) progress.report(entry.key, sent / total);
          },
        );
    return saved;
  }

  void _clearProgress() {
    if (!ref.mounted) return;
    ref.read(uploadProgressProvider.notifier).clear();
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

  Future<OutboxEntry> _append(OutboxEntry entry) => _serial(() async {
    final next = <OutboxEntry>[...await future, entry];
    await _store.write(next);
    _publish(next);
    return entry;
  });

  Future<void> _replace(
    String key,
    OutboxEntry Function(OutboxEntry row) change,
  ) async {
    final next = await _serial(() async {
      final next = <OutboxEntry>[
        for (final row in await future) row.key == key ? change(row) : row,
      ];
      await _store.write(next);
      _publish(next);
      return next;
    });
    if (next.any((row) => row.key == key && row.isWaiting)) {
      unawaited(flush());
    }
  }

  /// The tail of the read-modify-write steps on the list.
  Future<void> _changing = Future<void>.value();

  /// Runs one read-modify-write of the list after the one before it.
  ///
  /// Each step reads the list, writes the file and publishes, with awaits in
  /// between; two of them interleaved -- a flush settling while a picture is
  /// thrown away, say -- would let the later publish undo the earlier one,
  /// and an upload already sent (its copy deleted) would come back as
  /// waiting with no file to send.
  Future<T> _serial<T>(Future<T> Function() step) {
    final run = _changing.then((_) => step());
    _changing = run.then<void>((_) {}, onError: (Object _) {});
    return run;
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
  final entries = ref.watch(outboxEntriesProvider);
  for (final entry in entries) {
    // A moved row is marked where it is drawn: in the project it went to.
    if (entry.landsInProjectId != projectId) continue;
    switch (entry.state) {
      case OutboxState.waiting:
        final id = switch (entry.kind) {
          OutboxKind.createTask => entry.localTaskId,
          OutboxKind.uploadAttachment => resolvedTaskId(entry, entries),
          _ => entry.taskId,
        };
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

/// How far each picture being uploaded has got, 0..1, by upload key. Empty
/// between flushes -- a picture not in here is waiting (the clock) or done.
@Riverpod(keepAlive: true)
class UploadProgress extends _$UploadProgress {
  @override
  Map<String, double> build() => const <String, double>{};

  void report(String uploadKey, double fraction) {
    final value = fraction.clamp(0.0, 1.0);
    if (state[uploadKey] == value) return;
    state = Map<String, double>.unmodifiable(<String, double>{
      ...state,
      uploadKey: value,
    });
  }

  void clear() {
    if (state.isNotEmpty) state = const <String, double>{};
  }
}

/// Where an upload goes: see `Outbox._uploadTarget`.
sealed class _UploadTarget {
  const _UploadTarget();

  String? get taskId => null;
}

class _UploadTo extends _UploadTarget {
  const _UploadTo(this.id);

  final String id;

  @override
  String get taskId => id;
}

class _UploadWaits extends _UploadTarget {
  const _UploadWaits();
}

class _UploadOrphaned extends _UploadTarget {
  const _UploadOrphaned(this.message);

  final String message;
}

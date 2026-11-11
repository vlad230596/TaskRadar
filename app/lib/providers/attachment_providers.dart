import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/attachment_api.dart';
import '../api/link_preview_api.dart';
import '../domain/outbox_overlay.dart';
import '../models/task.dart';
import '../storage/capture_queue_store.dart' show PendingCapture;
import '../storage/outbox_store.dart';
import 'board_providers.dart';
import 'dependencies.dart';
import 'outbox_providers.dart';

/// A task's pictures on their way up and down (`design/task-editor-spec.md`
/// §6, §10).
///
/// ## Everything goes through the outbox
///
/// Unlike a task edit, which is tried online first and queued only when that
/// fails, a picture is *always* put on the outbox and then sent by its flush.
/// Two reasons. A picture of a task created a moment ago offline has to wait
/// for that create -- and only the outbox knows the order. And a 10 MB upload
/// is long enough for the network to go mid-way, so the local copy has to
/// exist before the first byte is sent anyway. A picture that goes on the
/// first try then simply leaves the outbox (`OutboxEntry.waited`), so the
/// «Офлайн» history shows only what actually waited.
class AttachmentQueue {
  AttachmentQueue(this._ref);

  final Ref _ref;

  Outbox get _outbox => _ref.read(outboxProvider.notifier);

  /// Queues [file] as a picture of [taskIdOrLocal] -- a task's id, or the
  /// `local:outbox:<createKey>` of a create still in the outbox (what
  /// `ProjectTasks.create` answers as `WriteOutcome.taskId`) -- and starts
  /// sending it.
  ///
  /// The bytes are copied first, so [file] may be a temporary one. The type
  /// is read from the bytes; anything but PNG, JPEG or WebP is refused here
  /// with an [UnsupportedAttachment] rather than by the server later.
  /// Compressing is the caller's (`attachments/compress.dart`).
  ///
  /// [projectId] and [title] label the history line; they are looked up
  /// (the outbox's create, the board) when not given. Throws when the copy
  /// could not be written -- then nothing was queued.
  Future<PendingAttachment> add(
    String taskIdOrLocal,
    XFile file, {
    String? projectId,
    String? title,
  }) async {
    final bytes = await file.readAsBytes();
    final mime = sniffImageMime(bytes);
    if (mime == null) throw UnsupportedAttachment(file.name);

    final key = PendingCapture.newKey();
    final path = await _ref
        .read(outboxFileStoreProvider)
        .put(key, bytes, extensionForMime(mime));

    final known = _findTask(taskIdOrLocal);
    final OutboxEntry entry;
    try {
      entry = await _outbox.queueUpload(
        key: key,
        taskIdOrLocal: taskIdOrLocal,
        localPath: path,
        mime: mime,
        projectId: projectId ?? known?.projectId,
        title: title ?? known?.title,
      );
    } catch (_) {
      await _ref.read(outboxFileStoreProvider).delete(path);
      rethrow;
    }
    unawaited(_outbox.flush());
    return PendingAttachment(
      entry: entry,
      state: PendingAttachmentState.waiting,
    );
  }

  /// [add] for each of [files], in order.
  Future<List<PendingAttachment>> addAll(
    String taskIdOrLocal,
    List<XFile> files, {
    String? projectId,
    String? title,
  }) async => <PendingAttachment>[
    for (final file in files)
      await add(taskIdOrLocal, file, projectId: projectId, title: title),
  ];

  /// Removes picture [attachmentId] of [task]: the server's (queued as a
  /// delete and drawn gone at once), or one still waiting to go up
  /// (`local:upload:<key>` -- just taken off the outbox, never sent).
  Future<void> remove(Task task, String attachmentId) async {
    if (attachmentId.startsWith(OutboxEntry.pendingUploadPrefix)) {
      final key = attachmentId.substring(
        OutboxEntry.pendingUploadPrefix.length,
      );
      for (final entry in await _ref.read(outboxProvider.future)) {
        if (entry.key == key) return _outbox.discard(entry);
      }
      return;
    }
    await _outbox.queueDeleteAttachment(
      task: task,
      attachmentId: attachmentId,
    );
    unawaited(_outbox.flush());
  }

  /// A refused picture, sent again («Повторить»).
  Future<void> retry(PendingAttachment pending) =>
      _outbox.retry(pending.entry);

  /// A waiting or refused picture, thrown away with its local copy
  /// («Убрать»).
  Future<void> discard(PendingAttachment pending) =>
      _outbox.discard(pending.entry);

  Task? _findTask(String taskId) {
    final view = _ref.read(boardViewProvider);
    if (view is! BoardReady) return null;
    for (final row in view.projects) {
      for (final task in row.tasks) {
        if (task.id == taskId) return task;
      }
    }
    return null;
  }
}

/// A file that is not a PNG, JPEG or WebP.
class UnsupportedAttachment implements Exception {
  const UnsupportedAttachment(this.name);

  final String name;

  String get message => 'Можно прикрепить только PNG, JPEG или WebP';

  @override
  String toString() => 'UnsupportedAttachment($name)';
}

final Provider<AttachmentQueue> attachmentQueueProvider =
    Provider<AttachmentQueue>(AttachmentQueue.new);

/// The pictures of a task still in the outbox (waiting, uploading, refused),
/// oldest first, by the task's id or its `local:outbox:<createKey>`.
final pendingAttachmentsProvider =
    Provider.family<List<PendingAttachment>, String>((ref, taskIdOrLocal) {
      final progress = ref.watch(uploadProgressProvider);
      return List<PendingAttachment>.unmodifiable(<PendingAttachment>[
        for (final pending in pendingAttachments(
          ref.watch(outboxEntriesProvider),
          taskIdOrLocal,
        ))
          pending.withProgress(progress[pending.uploadKey]),
      ]);
    });

/// How many pictures each task has in the outbox, by task id -- for the
/// row's badge, added to `task.attachments.length`.
final pendingAttachmentCountsProvider = Provider<Map<String, int>>(
  (ref) => pendingAttachmentCounts(ref.watch(outboxEntriesProvider)),
);

/// The bytes of a picture: `(attachmentId, thumb)`.
///
/// A server attachment is read from the disk cache, else fetched with the
/// Bearer token and cached -- forever, an attachment never changes. A
/// `local:upload:<key>` id (a [PendingAttachment.id]) is read from its
/// outbox copy, so the strip draws a picture the server has not seen yet the
/// same way as one it has.
///
/// Kept for two minutes after the last listener goes, so scrolling a strip
/// back and forth does not reload it.
final attachmentBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, (String, bool)>((ref, args) async {
      final (id, thumb) = args;
      _keepWarm(ref, const Duration(minutes: 2));

      if (id.startsWith(OutboxEntry.pendingUploadPrefix)) {
        final key = id.substring(OutboxEntry.pendingUploadPrefix.length);
        String? path;
        for (final entry in await ref.read(outboxProvider.future)) {
          if (entry.key == key) path = entry.localPath;
        }
        final bytes = path == null
            ? null
            : await ref.read(outboxFileStoreProvider).read(path);
        if (bytes == null) throw StateError('picture $id is gone');
        return bytes;
      }

      final cache = ref.read(attachmentCacheProvider);
      final cached = await cache.read(id, thumb: thumb);
      if (cached != null) return cached;

      final bytes = await ref
          .read(attachmentApiProvider)
          .fetchBytes(id, thumb: thumb);
      await cache.write(id, bytes, thumb: thumb);
      return bytes;
    }, retry: noAutomaticRetry);

/// What the server knows about a link (`GET /link-preview`), or null --
/// none, or the request failed: a preview is decoration, and a link card
/// without a title is still a link. Kept for the session.
final linkPreviewProvider = FutureProvider.family<LinkPreview?, String>((
  ref,
  url,
) async {
  try {
    return await ref.read(linkPreviewApiProvider).fetch(url);
  } catch (error) {
    debugPrint('No preview for $url: $error');
    return null;
  }
}, retry: noAutomaticRetry);

void _keepWarm(Ref ref, Duration duration) {
  final link = ref.keepAlive();
  Timer? timer;
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(duration, link.close);
  });
  ref.onResume(() => timer?.cancel());
  ref.onDispose(() => timer?.cancel());
}

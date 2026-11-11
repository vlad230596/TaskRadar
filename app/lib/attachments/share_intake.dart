import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_handler/share_handler.dart';

import '../models/task.dart';
import '../navigation/app_routes.dart';
import '../providers/attachment_providers.dart';
import '../providers/project_providers.dart';
import 'compress.dart';
import 'pick.dart' show maxAttachmentsPerTask;
import 'share_target_sheet.dart';

/// «Поделиться» from another app into TaskRadar (`design/task-editor-spec.md`
/// §6): a picture shared from the gallery, a screenshot's share button, a
/// browser. Android only -- the `SEND` / `SEND_MULTIPLE` `image/*` intent
/// filter is on `MainActivity` (WP0).
///
/// The flow: [ShareIntakeScope] hears the share, asks «В какую задачу?»
/// ([showShareTargetSheet]): a new task in a chosen project, or an existing
/// one. Then [deliverSharedPictures] compresses and queues the pictures and
/// the task opens.

/// What was shared into the app: the picture files. Behind an interface so
/// tests do not need the plugin.
abstract interface class ShareInbox {
  /// The pictures the app was *started* with, once; empty when none. Null
  /// when sharing is not available here (no plugin: a test, a platform
  /// without the intent filter) -- then [incoming] is not listened to
  /// either, because a missing event channel reports an error on listen.
  Future<List<XFile>?> initial();

  /// Pictures shared while the app is running.
  Stream<List<XFile>> get incoming;

  /// Forget the starting share, so a rebuild or a sign-in does not ask
  /// about it twice.
  Future<void> reset();
}

/// The pictures of [media]: attachments of the image type (anything else
/// shared -- text, a PDF -- is not ours to take).
List<XFile> sharedPictures(SharedMedia? media) => <XFile>[
  for (final attachment in media?.attachments ?? const <SharedAttachment?>[])
    if (attachment != null &&
        attachment.type == SharedAttachmentType.image &&
        attachment.path.isNotEmpty)
      XFile(attachment.path),
];

/// [ShareInbox] over `share_handler`.
class ShareHandlerInbox implements ShareInbox {
  ShareHandlerInbox([ShareHandlerPlatform? platform])
    : _platform = platform ?? ShareHandlerPlatform.instance;

  final ShareHandlerPlatform _platform;

  @override
  Future<List<XFile>?> initial() async {
    try {
      return sharedPictures(await _platform.getInitialSharedMedia());
    } catch (error) {
      debugPrint('Sharing into the app is unavailable: $error');
      return null;
    }
  }

  @override
  Stream<List<XFile>> get incoming => _platform.sharedMediaStream
      .map(sharedPictures)
      .where((files) => files.isNotEmpty);

  @override
  Future<void> reset() async {
    try {
      await _platform.resetInitialSharedMedia();
    } catch (error) {
      debugPrint('Initial share not reset: $error');
    }
  }
}

/// Where shares come from nowhere: Windows, the web.
class NoShareInbox implements ShareInbox {
  const NoShareInbox();

  @override
  Future<List<XFile>?> initial() async => null;

  @override
  Stream<List<XFile>> get incoming => const Stream<List<XFile>>.empty();

  @override
  Future<void> reset() async {}
}

final shareInboxProvider = Provider<ShareInbox>((ref) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return ShareHandlerInbox();
  }
  return const NoShareInbox();
});

/// The answer to «В какую задачу?».
sealed class ShareTarget {
  const ShareTarget();
}

/// A new task titled [title] in project [projectId].
class NewTaskTarget extends ShareTarget {
  const NewTaskTarget({required this.projectId, required this.title});

  final String projectId;
  final String title;
}

/// An existing [task].
class ExistingTaskTarget extends ShareTarget {
  const ExistingTaskTarget(this.task);

  final Task task;
}

/// Where the shared pictures went.
class ShareDelivery {
  const ShareDelivery({
    required this.projectId,
    required this.taskId,
    required this.added,
    this.dropped = 0,
    this.refused = 0,
  });

  final String projectId;

  /// The task's id, or `local:outbox:<key>` while its create is queued.
  final String taskId;

  final int added;

  /// Over [maxAttachmentsPerTask].
  final int dropped;

  /// Not a PNG, JPEG or WebP.
  final int refused;

  /// Whether the task exists on the server, so it can be opened.
  bool get isOpenable => !taskId.startsWith('local:');
}

/// Puts [files] into [target]: creates the task first for a [NewTaskTarget],
/// then compresses and queues each picture. A file that is not a picture is
/// counted in [ShareDelivery.refused], not thrown.
///
/// Throws when the task could not be created at all (empty title is guarded
/// by the sheet).
Future<ShareDelivery> deliverSharedPictures(
  WidgetRef ref,
  List<XFile> files,
  ShareTarget target,
) async {
  final String projectId;
  final String taskId;
  final String title;
  var room = maxAttachmentsPerTask;
  switch (target) {
    case NewTaskTarget():
      if (target.title.trim().isEmpty) {
        throw ArgumentError.value(target.title, 'title', 'is empty');
      }
      projectId = target.projectId;
      title = target.title.trim();
      final outcome = await ref
          .read(projectTasksProvider(projectId).notifier)
          .create(title);
      final id = outcome.taskId;
      if (id == null) throw StateError('The task was not created');
      taskId = id;
    case ExistingTaskTarget():
      final task = target.task;
      projectId = task.projectId;
      taskId = task.id;
      title = task.title;
      room -=
          task.attachments.length +
          (ref.read(pendingAttachmentCountsProvider)[task.id] ?? 0);
  }

  final kept = room <= 0
      ? const <XFile>[]
      : (files.length > room ? files.sublist(0, room) : files);
  final encoder = ref.read(imageEncoderProvider);
  final queue = ref.read(attachmentQueueProvider);
  var added = 0, refused = 0;
  for (final file in kept) {
    try {
      await queue.add(
        taskId,
        await compressForUpload(file, encoder),
        projectId: projectId,
        title: title,
      );
      added++;
    } on UnsupportedAttachment {
      refused++;
    }
  }
  return ShareDelivery(
    projectId: projectId,
    taskId: taskId,
    added: added,
    dropped: files.length - kept.length,
    refused: refused,
  );
}

/// Opens a task after a share. Defaults to [AppRoutes.openTask]; the editor
/// may be swapped in here once it has its own route.
typedef ShareTaskOpener =
    Future<void> Function(
      BuildContext context, {
      required String projectId,
      required String taskId,
    });

/// Listens for pictures shared into the app and runs the «В какую задачу?»
/// flow. Sits inside the signed-in half (`app.dart`), next to
/// `NotificationLinkScope`, for the same reasons: a navigator exists, and
/// the board -- which the sheet lists projects and tasks from -- has a
/// session. A share made while signed out waits in the launch intent.
class ShareIntakeScope extends ConsumerStatefulWidget {
  const ShareIntakeScope({
    required this.child,
    this.openTask = AppRoutes.openTask,
    super.key,
  });

  final Widget child;
  final ShareTaskOpener openTask;

  @override
  ConsumerState<ShareIntakeScope> createState() => _ShareIntakeScopeState();
}

class _ShareIntakeScopeState extends ConsumerState<ShareIntakeScope> {
  StreamSubscription<List<XFile>>? _subscription;

  /// Shares that came while the sheet for an earlier one was up.
  final List<List<XFile>> _waiting = <List<XFile>>[];
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    final inbox = ref.read(shareInboxProvider);
    unawaited(() async {
      final files = await inbox.initial();
      if (files == null || !mounted) return;
      _subscription = inbox.incoming.listen(_offer);
      if (files.isEmpty) return;
      await inbox.reset();
      _offer(files);
    }());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  void _offer(List<XFile> files) {
    if (files.isEmpty) return;
    _waiting.add(files);
    if (!_asking) unawaited(_drain());
  }

  Future<void> _drain() async {
    _asking = true;
    try {
      while (_waiting.isNotEmpty && mounted) {
        await _ask(_waiting.removeAt(0));
      }
    } finally {
      _asking = false;
    }
  }

  Future<void> _ask(List<XFile> files) async {
    final target = await showShareTargetSheet(context, files);
    if (target == null || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final delivery = await deliverSharedPictures(ref, files, target);
      if (!mounted) return;
      final note = shareDeliveryMessage(delivery);
      if (note != null) {
        messenger?.showSnackBar(SnackBar(content: Text(note)));
      }
      if (delivery.isOpenable && delivery.added > 0) {
        await widget.openTask(
          context,
          projectId: delivery.projectId,
          taskId: delivery.taskId,
        );
      }
    } catch (error) {
      debugPrint('Shared pictures not delivered: $error');
      messenger?.showSnackBar(
        const SnackBar(content: Text('Не получилось добавить картинку')),
      );
    }
  }
}

/// The sentence after a share, or null when there is nothing to say beyond
/// the task opening.
String? shareDeliveryMessage(ShareDelivery delivery) {
  final parts = <String>[
    if (!delivery.isOpenable && delivery.added > 0)
      'Задача и картинки уйдут, когда будет сеть',
    if (delivery.dropped > 0)
      'Не больше $maxAttachmentsPerTask картинок у задачи — '
          'лишние не добавлены (${delivery.dropped})',
    if (delivery.refused > 0)
      'Можно прикрепить только PNG, JPEG или WebP — '
          'не добавлено: ${delivery.refused}',
  ];
  return parts.isEmpty ? null : parts.join('. ');
}

import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../attachments/compress.dart';
import '../../attachments/pick.dart';
import '../../domain/outbox_overlay.dart' show PendingAttachment;
import '../../providers/attachment_providers.dart';
import '../../providers/project_providers.dart' show WriteOutcome;
import 'attachment_strip.dart';
import 'attribute_bar.dart';
import 'sections.dart';

/// The pictures of a task the editor is creating: picked before «Добавить»,
/// held on the device only, queued against the new task's id by the create
/// hook this registers on [EditorExtras.createHooks].
///
/// Kept beside the editor's [EditorExtras] (one per editor) rather than in
/// it, so the extras class stays the editor's.
class PictureDrafts extends ChangeNotifier {
  PictureDrafts._();

  static final Expando<PictureDrafts> _byExtras = Expando<PictureDrafts>(
    'PictureDrafts',
  );

  /// The drafts of [extras]' editor; they go to [queue] when the task is
  /// created. The queue itself is held, not a `ref`: the widget that first
  /// asked may be gone by «Добавить» (the chip of a compact sheet).
  static PictureDrafts of(EditorExtras extras, AttachmentQueue queue) {
    final existing = _byExtras[extras];
    if (existing != null) return existing;
    final drafts = PictureDrafts._();
    _byExtras[extras] = drafts;
    extras.createHooks.add((projectId, outcome) async {
      if (drafts.isEmpty) return;
      await drafts.queueFor(projectId, outcome, queue);
    });
    return drafts;
  }

  final List<XFile> _files = <XFile>[];

  List<XFile> get files => List<XFile>.unmodifiable(_files);
  bool get isEmpty => _files.isEmpty;

  void addAll(List<XFile> files) {
    if (files.isEmpty) return;
    _files.addAll(files);
    notifyListeners();
  }

  void remove(XFile file) {
    if (_files.remove(file)) notifyListeners();
  }

  /// After «Добавить»: every draft goes to the outbox against
  /// [WriteOutcome.taskId], and the list empties (for «Добавить и ещё»).
  /// A file that turns out not to be a picture is skipped.
  @visibleForTesting
  Future<void> queueFor(
    String projectId,
    WriteOutcome outcome,
    AttachmentQueue queue,
  ) async {
    final taskId = outcome.taskId;
    final files = List<XFile>.of(_files);
    _files.clear();
    notifyListeners();
    if (taskId == null) return;
    for (final file in files) {
      try {
        await queue.add(taskId, file, projectId: projectId);
      } on UnsupportedAttachment catch (error) {
        debugPrint('Draft picture skipped: $error');
      }
    }
  }
}

/// Where pictures added in the editor go -- the strip's «+», the chip, a
/// paste ([PictureClipboardPaste], `pictureContentInsertion`): the outbox
/// for an existing task, the [PictureDrafts] for a new one. The files must
/// already be compressed (every source in `lib/attachments/` does that).
Future<void> Function(List<XFile>) editorPictureAdder(
  WidgetRef ref,
  EditorSectionScope scope,
) {
  return (files) async {
    final task = scope.task;
    if (task == null) {
      _drafts(ref, scope).addAll(files);
      return;
    }
    await ref
        .read(attachmentQueueProvider)
        .addAll(task.id, files, projectId: task.projectId, title: task.title);
  };
}

PictureDrafts _drafts(WidgetRef ref, EditorSectionScope scope) =>
    PictureDrafts.of(scope.extras, ref.read(attachmentQueueProvider));

/// `EditorSlots.attachments`: «КАРТИНКИ» with the strip, when the task has
/// pictures (sent, in the outbox, or drafts); nothing otherwise, and
/// nothing in the compact sheet.
class AttachmentsSection extends ConsumerWidget {
  const AttachmentsSection({required this.scope, super.key});

  final EditorSectionScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = _drafts(ref, scope);
    final task = scope.task;
    final pending = task == null
        ? const <PendingAttachment>[]
        : ref.watch(pendingAttachmentsProvider(task.id));
    return ListenableBuilder(
      listenable: drafts,
      builder: (context, _) {
        final attachments = task?.attachments ?? const [];
        if (!scope.expanded ||
            (attachments.isEmpty && pending.isEmpty && drafts.isEmpty)) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(top: 18),
          child: AttachmentStrip(
            taskIdOrLocal: task?.id ?? 'new:${scope.projectId}',
            attachments: attachments,
            pending: pending,
            drafts: drafts.files,
            onAdd: editorPictureAdder(ref, scope),
            onDelete: (id) {
              if (task == null) return;
              unawaited(ref.read(attachmentQueueProvider).remove(task, id));
            },
            onRemoveDraft: drafts.remove,
          ),
        );
      },
    );
  }
}

/// «🖼 + Фото» in the attribute row, «🖼 3» once there are pictures: opens
/// the picker straight away (and expands a compact sheet).
class AttachmentChip extends ConsumerStatefulWidget {
  const AttachmentChip({required this.scope, required this.onOpen, super.key});

  final EditorSectionScope scope;
  final VoidCallback onOpen;

  @override
  ConsumerState<AttachmentChip> createState() => _AttachmentChipState();
}

class _AttachmentChipState extends ConsumerState<AttachmentChip> {
  bool _picking = false;

  Future<void> _pick(int current) async {
    if (_picking) return;
    _picking = true;
    widget.onOpen();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final picked = await pickPictures(
        ref.read(pictureSourceProvider),
        ref.read(imageEncoderProvider),
        current: current,
      );
      if (!picked.isEmpty) {
        await editorPictureAdder(ref, widget.scope)(picked.files);
      }
      final note = droppedPicturesMessage(picked.dropped);
      if (note != null) messenger?.showSnackBar(SnackBar(content: Text(note)));
    } on UnsupportedAttachment catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      debugPrint('Pictures not added: $error');
      messenger?.showSnackBar(
        const SnackBar(content: Text('Не получилось добавить картинку')),
      );
    } finally {
      _picking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final drafts = _drafts(ref, widget.scope);
    final task = widget.scope.task;
    final saved = task == null
        ? 0
        : task.attachments.length +
              ref.watch(pendingAttachmentsProvider(task.id)).length;
    return ListenableBuilder(
      listenable: drafts,
      builder: (context, _) {
        final count = saved + drafts.files.length;
        return AttributeChip(
          key: const ValueKey<String>('chip-pictures'),
          icon: count == 0
              ? Icons.add_photo_alternate_outlined
              : Icons.image_outlined,
          label: count == 0 ? '+ Фото' : 'Фото · $count',
          filled: count > 0,
          tooltip: 'Добавить картинку',
          onTap: () => _pick(count),
        );
      },
    );
  }
}

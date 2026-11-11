import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../attachments/compress.dart';
import '../../attachments/pick.dart';
import '../../domain/outbox_overlay.dart';
import '../../models/task_attachment.dart';
import '../../providers/attachment_providers.dart';
import '../../screens/attachment_viewer_screen.dart';
import '../../theme/tokens.dart';
import '../ai_tidy.dart' show TidyLabel;
import '../attachment_image.dart';

/// The editor's «КАРТИНКИ» section (`design/task-editor-spec.md` §6): a row
/// of 96x96 thumbnails, the «+» tile last.
///
/// Three kinds of picture, drawn alike ([AttachmentPicture]):
///
/// - [attachments], the server's: tap opens the viewer, long press offers
///   «Удалить»;
/// - [pending], in the outbox: a progress ring while going up, a clock while
///   waiting, a red dot when refused (tap: «Повторить» / «Убрать»);
/// - [drafts], picked for a task not created yet (the editor holds them until
///   «Добавить», then queues them with `AttachmentQueue.addAll`).
///
/// Deleting is undoable: the picture disappears at once with «Вернуть» in a
/// snack bar, and only when that goes is it really deleted -- [onDelete] for
/// a server picture, [onRemoveDraft] for a draft, `AttachmentQueue.discard`
/// for one in the outbox (never sent, nothing to tell the server).
/// Leaving the screen meanwhile deletes it then.
class AttachmentStrip extends ConsumerStatefulWidget {
  const AttachmentStrip({
    required this.taskIdOrLocal,
    required this.attachments,
    required this.pending,
    required this.onAdd,
    required this.onDelete,
    this.drafts = const <XFile>[],
    this.onRemoveDraft,
    this.enabled = true,
    this.showLabel = true,
    super.key,
  });

  /// The task's id, its `local:outbox:<createKey>`, or anything stable for a
  /// task not created yet -- keys the widgets, nothing is sent with it.
  final String taskIdOrLocal;

  final List<TaskAttachment> attachments;

  /// `ref.watch(pendingAttachmentsProvider(taskIdOrLocal))`.
  final List<PendingAttachment> pending;

  /// Pictures chosen with «+», already compressed. An existing task queues
  /// them (`attachmentQueueProvider.addAll(id, files)`); a new one keeps
  /// them as [drafts].
  final Future<void> Function(List<XFile>) onAdd;

  /// A server picture's id, deleted for good (after the undo window):
  /// `AttachmentQueue.remove(task, id)`.
  final ValueChanged<String> onDelete;

  final List<XFile> drafts;

  /// A draft, removed for good. Null: drafts cannot be removed.
  final ValueChanged<XFile>? onRemoveDraft;

  /// False: no «+», no deleting (a done task, a read-only view).
  final bool enabled;

  /// Draws «КАРТИНКИ · n» above the row.
  final bool showLabel;

  static const double tileSize = 96;

  @override
  ConsumerState<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends ConsumerState<AttachmentStrip> {
  /// Deleted, waiting out the undo: by id.
  final Map<String, AttachmentPicture> _hidden = <String, AttachmentPicture>{};
  bool _picking = false;

  @override
  void dispose() {
    // The snack bar may outlive the strip; what it was holding goes now.
    for (final picture in _hidden.values.toList()) {
      _commit(picture);
    }
    super.dispose();
  }

  List<AttachmentPicture> get _pictures => <AttachmentPicture>[
    for (final p in attachmentPictures(
      attachments: widget.attachments,
      pending: widget.pending,
      drafts: widget.drafts,
    ))
      if (!_hidden.containsKey(p.id)) p,
  ];

  void _commit(AttachmentPicture picture) {
    if (_hidden.remove(picture.id) == null) return;
    final file = picture.file;
    final pending = picture.pending;
    if (file != null) {
      widget.onRemoveDraft?.call(file);
    } else if (pending != null) {
      unawaited(ref.read(attachmentQueueProvider).discard(pending));
    } else {
      widget.onDelete(picture.id);
    }
  }

  void _delete(AttachmentPicture picture) {
    setState(() => _hidden[picture.id] = picture);
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      _commit(picture);
      return;
    }
    messenger.hideCurrentSnackBar();
    final controller = messenger.showSnackBar(
      SnackBar(
        content: const Text('Картинка удалена'),
        duration: const Duration(seconds: 4),
        // An action makes a snack bar persist by default; this one must
        // time out, which is what deletes the picture.
        persist: false,
        action: SnackBarAction(
          label: 'Вернуть',
          onPressed: () {
            if (!mounted) return;
            setState(() => _hidden.remove(picture.id));
          },
        ),
      ),
    );
    unawaited(
      controller.closed.then((reason) {
        if (reason == SnackBarClosedReason.action) return;
        if (!_hidden.containsKey(picture.id)) return;
        if (mounted) {
          setState(() => _commit(picture));
        } else {
          _commit(picture);
        }
      }),
    );
  }

  Future<void> _add() async {
    if (_picking) return;
    setState(() => _picking = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final picked = await pickPictures(
        ref.read(pictureSourceProvider),
        ref.read(imageEncoderProvider),
        current: _pictures.length,
      );
      if (!picked.isEmpty) await widget.onAdd(picked.files);
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
      if (mounted) setState(() => _picking = false);
    }
  }

  void _open(List<AttachmentPicture> pictures, AttachmentPicture picture) {
    unawaited(
      AttachmentViewerScreen.open(
        context,
        pictures: pictures,
        initialIndex: pictures.indexOf(picture),
        onDelete: widget.enabled ? _delete : null,
      ),
    );
  }

  Future<void> _tap(
    List<AttachmentPicture> pictures,
    AttachmentPicture picture,
  ) async {
    final pending = picture.pending;
    if (pending == null || pending.state != PendingAttachmentState.refused) {
      _open(pictures, picture);
      return;
    }
    final choice = await showModalBottomSheet<_RefusedChoice>(
      context: context,
      backgroundColor: AppColors.voiceBackground,
      builder: (context) => _RefusedSheet(message: pending.message),
    );
    if (!mounted || choice == null) return;
    final queue = ref.read(attachmentQueueProvider);
    switch (choice) {
      case _RefusedChoice.retry:
        await queue.retry(pending);
      case _RefusedChoice.discard:
        await queue.discard(pending);
      case _RefusedChoice.open:
        _open(pictures, picture);
    }
  }

  Future<void> _longPress(
    List<AttachmentPicture> pictures,
    AttachmentPicture picture,
  ) async {
    final delete = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.voiceBackground,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _SheetAction(
              icon: Icons.open_in_full,
              label: 'Открыть',
              onTap: () => Navigator.of(context).pop(false),
            ),
            if (widget.enabled)
              _SheetAction(
                key: const ValueKey<String>('strip-delete'),
                icon: Icons.delete_outline,
                label: 'Удалить',
                onTap: () => Navigator.of(context).pop(true),
              ),
          ],
        ),
      ),
    );
    if (!mounted || delete == null) return;
    if (delete) {
      _delete(picture);
    } else {
      _open(pictures, picture);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pictures = _pictures;
    final canAdd = widget.enabled && pictures.length < maxAttachmentsPerTask;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.showLabel)
          TidyLabel(
            pictures.isEmpty ? 'КАРТИНКИ' : 'КАРТИНКИ · ${pictures.length}',
          ),
        SizedBox(
          height: AttachmentStrip.tileSize,
          child: ListView(
            key: PageStorageKey<String>('strip-${widget.taskIdOrLocal}'),
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (final picture in pictures)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: AttachmentTile(
                    key: ValueKey<String>('strip-tile-${picture.id}'),
                    picture: picture,
                    onTap: () => _tap(pictures, picture),
                    onLongPress: () => _longPress(pictures, picture),
                  ),
                ),
              if (canAdd) _AddTile(busy: _picking, onTap: _add),
            ],
          ),
        ),
      ],
    );
  }
}

/// One 96x96 thumbnail with its state on top.
class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    required this.picture,
    this.onTap,
    this.onLongPress,
    super.key,
  });

  final AttachmentPicture picture;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final pending = picture.pending;
    final refused = pending?.state == PendingAttachmentState.refused;
    final progress = pending?.progress;
    final String label;
    if (refused) {
      label = 'Картинка не отправлена';
    } else if (progress != null) {
      label = 'Картинка отправляется';
    } else if (pending != null) {
      label = 'Картинка ждёт отправки';
    } else {
      label = 'Картинка';
    }
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox.square(
          dimension: AttachmentStrip.tileSize,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Radii.row),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                AttachmentImage.of(picture),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.row),
                    border: Border.all(color: AppColors.voiceLine),
                  ),
                ),
                if (progress != null) ...<Widget>[
                  const ColoredBox(color: Color(0x66000000)),
                  Center(
                    child: SizedBox.square(
                      dimension: 34,
                      child: CircularProgressIndicator(
                        key: const ValueKey<String>('strip-progress'),
                        value: progress <= 0 ? null : progress,
                        strokeWidth: 3,
                        color: AppColors.voiceInk,
                        backgroundColor: const Color(0x55FFFFFF),
                      ),
                    ),
                  ),
                ] else if (pending != null && !refused)
                  const Positioned(
                    right: 6,
                    bottom: 6,
                    child: _Badge(
                      key: ValueKey<String>('strip-waiting'),
                      child: Icon(
                        Icons.schedule,
                        size: 14,
                        color: AppColors.voiceInk,
                      ),
                    ),
                  ),
                if (refused)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: Container(
                      key: const ValueKey<String>('strip-refused'),
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.alarm,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.voiceInk, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: Color(0xCC14183C),
        shape: BoxShape.circle,
      ),
      child: child,
    );
  }
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Добавить картинку',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.row),
          side: const BorderSide(color: AppColors.voiceLine, width: 1.5),
        ),
        child: InkWell(
          key: const ValueKey<String>('strip-add'),
          borderRadius: BorderRadius.circular(Radii.row),
          onTap: busy ? null : onTap,
          child: SizedBox.square(
            dimension: AttachmentStrip.tileSize,
            child: Center(
              child: busy
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppColors.voiceBright,
                      ),
                    )
                  : const Icon(
                      Icons.add_photo_alternate_outlined,
                      color: AppColors.voiceBright,
                      size: 30,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _RefusedChoice { retry, discard, open }

class _RefusedSheet extends StatelessWidget {
  const _RefusedSheet({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.gutter,
              18,
              Insets.gutter,
              6,
            ),
            child: Text(
              message == null || message!.isEmpty
                  ? 'Картинку не приняли'
                  : 'Картинку не приняли: $message',
              style: const TextStyle(color: AppColors.voiceInk, fontSize: 16),
            ),
          ),
          _SheetAction(
            key: const ValueKey<String>('strip-retry'),
            icon: Icons.refresh,
            label: 'Повторить',
            onTap: () => Navigator.of(context).pop(_RefusedChoice.retry),
          ),
          _SheetAction(
            key: const ValueKey<String>('strip-discard'),
            icon: Icons.close,
            label: 'Убрать',
            onTap: () => Navigator.of(context).pop(_RefusedChoice.discard),
          ),
          _SheetAction(
            icon: Icons.open_in_full,
            label: 'Посмотреть',
            onTap: () => Navigator.of(context).pop(_RefusedChoice.open),
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: Targets.row),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.gutter),
          child: Row(
            children: <Widget>[
              Icon(icon, color: AppColors.voiceBright),
              const SizedBox(width: 14),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.voiceInk,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

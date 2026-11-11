import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/outbox_overlay.dart'
    show PendingAttachment, PendingAttachmentState;
import '../models/task_attachment.dart';
import '../providers/attachment_providers.dart';
import '../storage/outbox_store.dart' show OutboxEntry;
import '../theme/tokens.dart';

/// One picture of a task as the strip and the viewer see it -- whichever of
/// three lives it is in:
///
/// - [attachment]: the server has it (`Task.attachments`);
/// - [pending]: in the outbox, waiting / going up / refused;
/// - [file]: picked for a task not created yet; only the editor holds it.
@immutable
class AttachmentPicture {
  AttachmentPicture.server(TaskAttachment this.attachment)
    : id = attachment.id,
      pending = null,
      file = null;

  AttachmentPicture.pending(PendingAttachment this.pending)
    : id = pending.id,
      attachment = null,
      file = null;

  /// [id] must be unique among the drafts of the strip; `draft:<n>` is the
  /// convention.
  const AttachmentPicture.draft(XFile this.file, {required this.id})
    : attachment = null,
      pending = null;

  final String id;
  final TaskAttachment? attachment;
  final PendingAttachment? pending;
  final XFile? file;

  bool get isDraft => file != null;
  bool get isPending => pending != null;
  bool get isRefused => pending?.state == PendingAttachmentState.refused;

  @override
  bool operator ==(Object other) =>
      other is AttachmentPicture &&
      other.id == id &&
      other.pending == pending &&
      other.attachment == attachment &&
      identical(other.file, file);

  @override
  int get hashCode => Object.hash(id, pending, attachment, file);
}

/// The pictures of a task in the strip's order: the server's, then the
/// outbox's, then the drafts.
List<AttachmentPicture> attachmentPictures({
  List<TaskAttachment> attachments = const <TaskAttachment>[],
  List<PendingAttachment> pending = const <PendingAttachment>[],
  List<XFile> drafts = const <XFile>[],
}) => <AttachmentPicture>[
  for (final a in attachments) AttachmentPicture.server(a),
  for (final p in pending) AttachmentPicture.pending(p),
  for (final file in drafts)
    AttachmentPicture.draft(file, id: 'draft:${identityHashCode(file)}'),
];

/// Draws a picture of a task: by its id through `attachmentBytesProvider`
/// (the disk cache, then `GET /attachments/:id[/thumb]` -- or the outbox's
/// local copy for a `local:upload:<key>`), or straight from a local [XFile].
///
/// [thumb] asks the server for its 512 px thumbnail, and decodes local
/// copies at thumbnail size -- a strip of 96 px squares must not decode
/// 3000 px screenshots at full size.
class AttachmentImage extends ConsumerStatefulWidget {
  const AttachmentImage({
    required String this.id,
    this.thumb = true,
    this.fit = BoxFit.cover,
    super.key,
  }) : file = null;

  const AttachmentImage.file(
    XFile this.file, {
    this.thumb = true,
    this.fit = BoxFit.cover,
    super.key,
  }) : id = null;

  /// Whichever [AttachmentImage] draws [picture].
  factory AttachmentImage.of(
    AttachmentPicture picture, {
    bool thumb = true,
    BoxFit fit = BoxFit.cover,
    Key? key,
  }) {
    final file = picture.file;
    return file != null
        ? AttachmentImage.file(file, thumb: thumb, fit: fit, key: key)
        : AttachmentImage(id: picture.id, thumb: thumb, fit: fit, key: key);
  }

  final String? id;
  final XFile? file;
  final bool thumb;
  final BoxFit fit;

  /// The width local copies are decoded at for [thumb].
  static const int thumbDecodeWidth = 360;

  @override
  ConsumerState<AttachmentImage> createState() => _AttachmentImageState();
}

class _AttachmentImageState extends ConsumerState<AttachmentImage> {
  Future<Uint8List>? _fileBytes;

  @override
  void initState() {
    super.initState();
    _readFile();
  }

  @override
  void didUpdateWidget(AttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.file, widget.file)) _readFile();
  }

  void _readFile() {
    final file = widget.file;
    _fileBytes = file?.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.id;
    if (id == null) {
      return FutureBuilder<Uint8List>(
        future: _fileBytes,
        builder: (context, snapshot) =>
            _draw(snapshot.data, failed: snapshot.hasError, localCopy: true),
      );
    }
    // A local copy has no thumbnail; one key for it, whatever is asked.
    final local = id.startsWith(OutboxEntry.pendingUploadPrefix);
    final bytes = ref.watch(
      attachmentBytesProvider((id, local ? false : widget.thumb)),
    );
    return _draw(bytes.value, failed: bytes.hasError, localCopy: local);
  }

  Widget _draw(
    Uint8List? bytes, {
    required bool failed,
    required bool localCopy,
  }) {
    if (bytes == null) {
      return ColoredBox(
        color: AppColors.voiceWell,
        child: Center(
          child: failed
              ? const Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.voiceMuted,
                  semanticLabel: 'Картинка не загрузилась',
                )
              : const SizedBox.shrink(),
        ),
      );
    }
    return Image.memory(
      bytes,
      fit: widget.fit,
      gaplessPlayback: true,
      cacheWidth: widget.thumb && localCopy
          ? AttachmentImage.thumbDecodeWidth
          : null,
      errorBuilder: (_, _, _) => const ColoredBox(
        color: AppColors.voiceWell,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.voiceMuted),
        ),
      ),
    );
  }
}

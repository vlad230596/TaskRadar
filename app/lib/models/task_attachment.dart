import 'package:freezed_annotation/freezed_annotation.dart';

part 'task_attachment.freezed.dart';
part 'task_attachment.g.dart';

/// A picture attached to a task, as every task response carries it
/// (`attachments: [{ id, mime, width, height, sizeBytes, createdAt }]`,
/// `design/task-editor-spec.md` §10).
///
/// Metadata only: the bytes are behind `GET /attachments/:id` and
/// `/attachments/:id/thumb` with the Bearer token, and are read through
/// `attachmentBytesProvider` (`providers/attachment_providers.dart`), which
/// keeps a copy on disk -- an attachment never changes, so its id is a
/// perfect cache key.
@freezed
abstract class TaskAttachment with _$TaskAttachment {
  const factory TaskAttachment({
    required String id,

    /// `image/png`, `image/jpeg` or `image/webp`.
    required String mime,
    @Default(0) int width,
    @Default(0) int height,
    @Default(0) int sizeBytes,
    required String createdAt,
  }) = _TaskAttachment;

  factory TaskAttachment.fromJson(Map<String, dynamic> json) =>
      _$TaskAttachmentFromJson(json);
}

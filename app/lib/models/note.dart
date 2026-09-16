import 'package:freezed_annotation/freezed_annotation.dart';

part 'note.freezed.dart';
part 'note.g.dart';

/// A markdown note attached to a project (`GET /projects/:projectId/notes`).
///
/// Port of the `Note` interface in `frontend/src/lib/types.ts`. Not used until
/// F3; it lives here now so the whole `types.ts` surface is ported in one pass
/// rather than one interface per iteration.
///
/// `content` is raw markdown source and is never empty-able server-side -- it is
/// a required string, not nullable, so an "empty" note is `""`.
@freezed
abstract class Note with _$Note {
  const factory Note({
    required String id,
    required String projectId,
    required String title,
    required String content,
    required String createdAt,
    required String updatedAt,
  }) = _Note;

  factory Note.fromJson(Map<String, dynamic> json) => _$NoteFromJson(json);
}

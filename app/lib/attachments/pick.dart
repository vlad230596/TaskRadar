import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'compress.dart';

/// How many pictures one task may have (the server's 409 above that,
/// `design/task-editor-spec.md` §12.4).
const int maxAttachmentsPerTask = 30;

/// Where pictures are picked from: the gallery's multi-pick on Android, the
/// file dialog on Windows (image_picker_windows over file_selector), the
/// browser's file input on the web. Behind an interface so tests do not need
/// the plugin.
abstract interface class PictureSource {
  /// The pictures chosen, at most [limit] when given; empty when the user
  /// backed out.
  Future<List<XFile>> pickImages({int? limit});
}

/// [PictureSource] over `image_picker`.
class ImagePickerSource implements PictureSource {
  ImagePickerSource([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<List<XFile>> pickImages({int? limit}) async {
    if (limit != null && limit <= 0) return const <XFile>[];
    // image_picker refuses a limit below 2; one is picked as one.
    if (limit == 1) {
      final one = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );
      return one == null ? const <XFile>[] : <XFile>[one];
    }
    return _picker.pickMultiImage(limit: limit, requestFullMetadata: false);
  }
}

final pictureSourceProvider = Provider<PictureSource>(
  (ref) => ImagePickerSource(),
);

/// What [pickPictures] got: the files, ready to upload, and how many more
/// the user chose than the task had room for.
class PickedPictures {
  const PickedPictures(this.files, {this.dropped = 0});

  final List<XFile> files;
  final int dropped;

  bool get isEmpty => files.isEmpty;
}

/// Opens the picker for a task that already has [current] pictures, and
/// compresses what was chosen. Never more than [maxAttachmentsPerTask] in
/// all: the rest are [PickedPictures.dropped].
Future<PickedPictures> pickPictures(
  PictureSource source,
  ImageEncoder? encoder, {
  required int current,
}) async {
  final room = maxAttachmentsPerTask - current;
  if (room <= 0) return const PickedPictures(<XFile>[]);
  final picked = await source.pickImages(limit: room);
  final kept = picked.length > room ? picked.sublist(0, room) : picked;
  return PickedPictures(
    await compressAllForUpload(kept, encoder),
    dropped: picked.length - kept.length,
  );
}

/// The sentence for pictures over the limit, or null.
String? droppedPicturesMessage(int dropped) => dropped <= 0
    ? null
    : 'Не больше $maxAttachmentsPerTask картинок у задачи — '
          'лишние не добавлены ($dropped)';

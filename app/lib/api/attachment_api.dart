import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/task_attachment.dart';
import 'api_client.dart';
import 'task_wire.dart';

/// A task's pictures (`design/task-editor-spec.md` §10, "Вложения").
///
/// Only metadata rides on the task rows; the bytes are fetched here, with the
/// Bearer token like every other call -- the files are not public, Caddy never
/// serves them directly.
class AttachmentApi {
  const AttachmentApi(this._client);

  final ApiClient _client;

  /// `POST /tasks/:taskId/attachments`, multipart: `uploadKey`, then `file`.
  ///
  /// The field goes before the file on the wire (dio writes fields first),
  /// so the server can answer a replay -- same key -> 200 and the same
  /// attachment -- without storing the bytes twice.
  ///
  /// There is no route listing a task's pictures: every task response
  /// carries `attachments`.
  ///
  /// 201 or 200 with the attachment. 413 too big / over quota, 415 not a
  /// PNG/JPEG/WebP (judged by the bytes, not by [mime]), 409 the task already
  /// has 30, 404 the task is gone.
  Future<TaskAttachment> upload(
    String taskId, {
    required String uploadKey,
    required Uint8List bytes,
    required String mime,
    String? filename,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final form = FormData.fromMap(<String, dynamic>{
      'uploadKey': uploadKey,
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename ?? '$uploadKey.${extensionForMime(mime)}',
        contentType: DioMediaType.parse(mime),
      ),
    });
    final json = await _client.postForm<Map<String, dynamic>>(
      '/tasks/$taskId/attachments',
      form,
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
    return TaskWire.attachmentFrom(json);
  }

  /// `GET /attachments/:id` (the picture as uploaded, after the server's
  /// re-encode) or, with [thumb], `GET /attachments/:id/thumb` (WebP, long
  /// side 512).
  Future<Uint8List> fetchBytes(String attachmentId, {bool thumb = false}) =>
      _client.getBytes(
        thumb
            ? '/attachments/$attachmentId/thumb'
            : '/attachments/$attachmentId',
      );

  /// `DELETE /attachments/:id`. 204; a 404 means it is already gone, and the
  /// caller decides whether that is fine (the outbox says yes).
  Future<void> delete(String attachmentId) =>
      _client.delete<dynamic>('/attachments/$attachmentId');
}

/// The three types the server accepts, by their first bytes -- the same test
/// the server makes, so a file is labelled what it will be judged as.
/// Null for anything else.
String? sniffImageMime(Uint8List bytes) {
  bool startsWith(List<int> magic, [int offset = 0]) {
    if (bytes.length < offset + magic.length) return false;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[offset + i] != magic[i]) return false;
    }
    return true;
  }

  if (startsWith(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (startsWith(const <int>[0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const <int>[0x52, 0x49, 0x46, 0x46]) && // RIFF
      startsWith(const <int>[0x57, 0x45, 0x42, 0x50], 8)) {
    // ....WEBP
    return 'image/webp';
  }
  return null;
}

/// `png` / `jpg` / `webp` for a file name; `bin` for anything else.
String extensionForMime(String mime) => switch (mime) {
  'image/png' => 'png',
  'image/jpeg' => 'jpg',
  'image/webp' => 'webp',
  _ => 'bin',
};

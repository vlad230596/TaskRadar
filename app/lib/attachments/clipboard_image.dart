import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';

import '../api/attachment_api.dart' show extensionForMime, sniffImageMime;
import 'compress.dart';

/// A picture pasted into the editor (`design/task-editor-spec.md` §6).
///
/// Two ways in, one per kind of keyboard:
///
/// - **Android**: the soft keyboard (Gboard's clipboard strip, a screenshot
///   suggestion) inserts content into the focused text field. The editor
///   passes [pictureContentInsertion] to its `TextField`s'
///   `contentInsertionConfiguration`.
/// - **Windows and the web**: Ctrl+V. [PictureClipboardPaste] wraps the
///   editor and, when the clipboard holds a picture, takes the paste;
///   otherwise the text field below pastes text as usual.

/// The image MIME types the keyboard may offer us -- the three the server
/// takes.
const List<String> pictureMimeTypes = <String>[
  'image/png',
  'image/jpeg',
  'image/webp',
];

/// Reads a picture off the system clipboard. Behind an interface so tests
/// do not need the plugin.
abstract interface class ClipboardImageReader {
  /// The clipboard's picture as PNG/JPEG/WebP bytes, or null when there is
  /// none (text, nothing, or the platform cannot say).
  Future<Uint8List?> readImage();
}

/// [ClipboardImageReader] over `pasteboard`: the bitmap on the clipboard
/// (a screenshot, "Copy image" in a browser) and, on desktop, a picture
/// *file* copied in Explorer.
class PasteboardImageReader implements ClipboardImageReader {
  const PasteboardImageReader();

  @override
  Future<Uint8List?> readImage() async {
    try {
      final image = await Pasteboard.image;
      if (image != null && image.isNotEmpty) return image;
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
        return null;
      }
      for (final path in await Pasteboard.files()) {
        final lower = path.toLowerCase();
        final isPicture = <String>[
          '.png',
          '.jpg',
          '.jpeg',
          '.webp',
        ].any(lower.endsWith);
        if (!isPicture) continue;
        final bytes = await XFile(path).readAsBytes();
        if (sniffImageMime(bytes) != null) return bytes;
      }
    } catch (error) {
      debugPrint('Clipboard picture not read: $error');
    }
    return null;
  }
}

final clipboardImageReaderProvider = Provider<ClipboardImageReader>(
  (ref) => const PasteboardImageReader(),
);

/// Whether Ctrl+V is watched for pictures here: desktop and the web. On
/// Android the keyboard delivers pictures itself.
bool get pastesPicturesWithKeys =>
    kIsWeb ||
    switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.linux ||
      TargetPlatform.macOS => true,
      _ => false,
    };

/// [bytes] as a file to upload, named by its type; null when they are not
/// a PNG, JPEG or WebP.
XFile? pastedPicture(Uint8List bytes, {String stem = 'paste'}) {
  final mime = sniffImageMime(bytes);
  if (mime == null) return null;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final name = '$stem-$stamp.${extensionForMime(mime)}';
  // `path` too: on io `XFile.name` is read from the path, not `name`.
  return XFile.fromData(
    bytes,
    path: name,
    name: name,
    mimeType: mime,
    length: bytes.length,
  );
}

/// The picture the keyboard inserted, or null when it brought none we take
/// (a GIF, or a URI without bytes).
XFile? keyboardPicture(KeyboardInsertedContent content) {
  final data = content.data;
  if (data == null || data.isEmpty) return null;
  return pastedPicture(data, stem: 'keyboard');
}

/// For a text field's `contentInsertionConfiguration`: a picture from the
/// keyboard is compressed and handed to [onAdd] (the strip's own `onAdd`).
/// Text the keyboard commits is unaffected.
ContentInsertionConfiguration pictureContentInsertion(
  WidgetRef ref,
  Future<void> Function(List<XFile>) onAdd,
) {
  return ContentInsertionConfiguration(
    allowedMimeTypes: pictureMimeTypes,
    onContentInserted: (content) {
      final file = keyboardPicture(content);
      if (file == null) return;
      final encoder = ref.read(imageEncoderProvider);
      unawaited(() async {
        await onAdd(<XFile>[await compressForUpload(file, encoder)]);
      }());
    },
  );
}

/// Takes Ctrl+V (Cmd+V on a Mac) when the clipboard holds a picture: it is
/// compressed and handed to [onAdd]. When it does not, the paste goes on to
/// whatever text field has focus, unchanged.
///
/// Works through `Action.overridable`: `EditableText` lets an ancestor
/// [Actions] take its [PasteTextIntent], and hands the override its own
/// action to fall back to.
class PictureClipboardPaste extends ConsumerWidget {
  const PictureClipboardPaste({
    required this.onAdd,
    required this.child,
    this.enabled,
    super.key,
  });

  final Future<void> Function(List<XFile>) onAdd;
  final Widget child;

  /// Null: [pastesPicturesWithKeys].
  final bool? enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(enabled ?? pastesPicturesWithKeys)) return child;
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyV, control: true):
            PasteTextIntent(SelectionChangedCause.keyboard),
        SingleActivator(LogicalKeyboardKey.keyV, meta: true): PasteTextIntent(
          SelectionChangedCause.keyboard,
        ),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          PasteTextIntent: PastePictureAction(
            read: () => ref.read(clipboardImageReaderProvider).readImage(),
            onPicture: (file) async {
              final encoder = ref.read(imageEncoderProvider);
              await onAdd(<XFile>[await compressForUpload(file, encoder)]);
            },
          ),
        },
        child: child,
      ),
    );
  }
}

/// The paste override behind [PictureClipboardPaste].
class PastePictureAction extends ContextAction<PasteTextIntent> {
  PastePictureAction({required this.read, required this.onPicture});

  final Future<Uint8List?> Function() read;
  final Future<void> Function(XFile) onPicture;

  /// The last paste's work, for tests.
  @visibleForTesting
  Future<void>? pending;

  @override
  bool consumesKey(PasteTextIntent intent) => true;

  @override
  Object? invoke(PasteTextIntent intent, [BuildContext? context]) {
    final fallback = callingAction;
    pending = () async {
      final bytes = await read();
      final file = bytes == null ? null : pastedPicture(bytes);
      if (file != null) {
        await onPicture(file);
      } else if (fallback != null && fallback.isActionEnabled) {
        fallback.invoke(intent);
      }
    }();
    return null;
  }
}

/// Puts a picture *on* the clipboard -- the viewer's «Скопировать». (A
/// system share sheet would need `share_plus`, which the app does not have;
/// copying works everywhere and pastes into any messenger.)
abstract interface class ClipboardImageWriter {
  /// Whether the picture is on the clipboard now.
  Future<bool> writeImage(Uint8List bytes);
}

/// [ClipboardImageWriter] over `pasteboard`: the bitmap on Android and the
/// web; on Windows, where the plugin cannot write a bitmap, the picture as
/// a file (pastes into Explorer, Telegram, Word...).
class PasteboardImageWriter implements ClipboardImageWriter {
  const PasteboardImageWriter();

  @override
  Future<bool> writeImage(Uint8List bytes) async {
    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
        final mime = sniffImageMime(bytes) ?? 'image/png';
        final dir = await getTemporaryDirectory();
        final stamp = DateTime.now().millisecondsSinceEpoch;
        final path = '${dir.path}\\taskradar-$stamp.${extensionForMime(mime)}';
        await XFile.fromData(bytes).saveTo(path);
        return Pasteboard.writeFiles(<String>[path]);
      }
      await Pasteboard.writeImage(bytes);
      return true;
    } catch (error) {
      debugPrint('Picture not copied: $error');
      return false;
    }
  }
}

final clipboardImageWriterProvider = Provider<ClipboardImageWriter>(
  (ref) => const PasteboardImageWriter(),
);

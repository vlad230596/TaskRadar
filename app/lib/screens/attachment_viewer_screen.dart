import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../attachments/clipboard_image.dart';
import '../domain/outbox_overlay.dart' show PendingAttachmentState;
import '../providers/attachment_providers.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/attachment_image.dart';

/// A task's pictures, full screen (`design/task-editor-spec.md` §6):
/// swipe between them, pinch or double-tap to zoom, «Скопировать» and
/// «Удалить».
///
/// Deleting asks first, then hands the picture to [onDelete] (the strip,
/// which offers the undo) and drops it from the pages here; the last one
/// closes the screen.
class AttachmentViewerScreen extends ConsumerStatefulWidget {
  const AttachmentViewerScreen({
    required this.pictures,
    this.initialIndex = 0,
    this.onDelete,
    super.key,
  });

  final List<AttachmentPicture> pictures;
  final int initialIndex;

  /// Null: no «Удалить» (a task that cannot be changed).
  final ValueChanged<AttachmentPicture>? onDelete;

  /// Pushes the viewer.
  static Future<void> open(
    BuildContext context, {
    required List<AttachmentPicture> pictures,
    int initialIndex = 0,
    ValueChanged<AttachmentPicture>? onDelete,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => AttachmentViewerScreen(
          pictures: pictures,
          initialIndex: initialIndex,
          onDelete: onDelete,
        ),
      ),
    );
  }

  @override
  ConsumerState<AttachmentViewerScreen> createState() =>
      _AttachmentViewerScreenState();
}

class _AttachmentViewerScreenState
    extends ConsumerState<AttachmentViewerScreen> {
  late List<AttachmentPicture> _pictures = List.of(widget.pictures);
  late int _index = widget.initialIndex.clamp(0, _pictures.length - 1);
  late final PageController _pages = PageController(initialPage: _index);
  bool _zoomed = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  AttachmentPicture get _current => _pictures[_index];

  Future<Uint8List> _bytesOf(AttachmentPicture picture) {
    final file = picture.file;
    if (file != null) return file.readAsBytes();
    return ref.read(attachmentBytesProvider((picture.id, false)).future);
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    var done = false;
    try {
      final bytes = await _bytesOf(_current);
      done = await ref.read(clipboardImageWriterProvider).writeImage(bytes);
    } catch (error) {
      debugPrint('Picture not read for copying: $error');
    }
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          done ? 'Картинка скопирована' : 'Не получилось скопировать',
        ),
      ),
    );
  }

  Future<void> _delete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить картинку?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          TextButton(
            key: const ValueKey<String>('viewer-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    final gone = _current;
    onDelete(gone);
    if (_pictures.length == 1) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _pictures = List.of(_pictures)..removeAt(_index);
      if (_index >= _pictures.length) _index = _pictures.length - 1;
      _zoomed = false;
    });
    _pages.jumpToPage(_index);
  }

  @override
  Widget build(BuildContext context) {
    final count = _pictures.length;
    final status = _statusOf(_current);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: AppColors.voiceBackground,
        appBar: AppBar(
          backgroundColor: AppColors.voiceBackground,
          foregroundColor: AppColors.voiceInk,
          surfaceTintColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Text(
            count > 1 ? '${_index + 1} из $count' : 'Картинка',
            style: AppText.screenTight.copyWith(color: AppColors.voiceInk),
          ),
          actions: <Widget>[
            IconButton(
              key: const ValueKey<String>('viewer-copy'),
              icon: const Icon(Icons.copy_outlined),
              tooltip: 'Скопировать',
              onPressed: _copy,
            ),
            if (widget.onDelete != null)
              IconButton(
                key: const ValueKey<String>('viewer-delete'),
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Удалить',
                onPressed: _delete,
              ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: _pages,
                physics: _zoomed
                    ? const NeverScrollableScrollPhysics()
                    : const PageScrollPhysics(),
                itemCount: count,
                onPageChanged: (i) => setState(() {
                  _index = i;
                  _zoomed = false;
                }),
                itemBuilder: (_, i) => _ZoomablePage(
                  key: ValueKey<String>('viewer-page-${_pictures[i].id}'),
                  picture: _pictures[i],
                  onZoomChanged: (zoomed) {
                    if (i == _index && zoomed != _zoomed) {
                      setState(() => _zoomed = zoomed);
                    }
                  },
                ),
              ),
            ),
            if (status != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.gutter,
                    8,
                    Insets.gutter,
                    12,
                  ),
                  child: Text(
                    status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.voiceMuted,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String? _statusOf(AttachmentPicture picture) {
    if (picture.isDraft) return 'Уйдёт вместе с задачей';
    final pending = picture.pending;
    if (pending == null) return null;
    if (pending.state == PendingAttachmentState.refused) {
      return 'Не отправлена: ${pending.message ?? 'сервер отказал'}';
    }
    final progress = pending.progress;
    if (progress != null) return 'Отправляется · ${(progress * 100).round()}%';
    return 'Ждёт отправки';
  }
}

/// One page: the picture in an [InteractiveViewer]; double tap zooms in to
/// 2.5x at the tap and back out.
class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({
    required this.picture,
    required this.onZoomChanged,
    super.key,
  });

  final AttachmentPicture picture;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _transform = TransformationController();
  TapDownDetails? _doubleTap;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) {
      _zoomed = zoomed;
      widget.onZoomChanged(zoomed);
    }
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _toggleZoom() {
    if (_zoomed) {
      _transform.value = Matrix4.identity();
      return;
    }
    final at = _doubleTap?.localPosition ?? Offset.zero;
    const scale = 2.5;
    _transform.value = Matrix4.identity()
      ..translateByDouble(-at.dx * (scale - 1), -at.dy * (scale - 1), 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: (details) => _doubleTap = details,
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        child: SizedBox.expand(
          child: AttachmentImage.of(
            widget.picture,
            thumb: false,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}

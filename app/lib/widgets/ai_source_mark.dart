import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/ai_mark.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The "правил AI" mark: a small pill next to text that AI processed, and the
/// sheet behind it with the words as they were before the first processing.
///
/// Nothing at all for text AI never touched -- the mark is there to be
/// noticed when it matters, not to label every row "not AI".
///
/// [onRevert] puts the source back. Each screen decides what that means: the
/// task and note screens put it into the draft (saved with "Сохранить", like
/// any other edit), the sandbox writes it at once. Null hides the button.
class AiSourceMark extends StatelessWidget {
  const AiSourceMark({required this.mark, this.onRevert, super.key});

  final AiMark mark;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    if (!mark.shown) return const SizedBox.shrink();
    final edited = mark.state == AiMarkState.editedAfter;
    return Tooltip(
      message: edited ? 'Обработано AI, потом изменено' : 'Обработано AI',
      child: Material(
        color: AppColors.indigoFill,
        shape: const StadiumBorder(),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showAiSource(context, mark: mark, onRevert: onRevert),
          child: SizedBox(
            height: 30,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: AppColors.indigoInk,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    edited ? 'AI · изменено' : 'AI',
                    style: AppText.chip.copyWith(
                      fontSize: 12.5,
                      color: AppColors.indigoInk,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The sheet: the source, what state the text is in, copy, and put it back.
Future<void> showAiSource(
  BuildContext context, {
  required AiMark mark,
  VoidCallback? onRevert,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _AiSourceSheet(
      mark: mark,
      onRevert: onRevert == null
          ? null
          : () {
              Navigator.of(sheetContext).pop();
              onRevert();
            },
    ),
  );
}

class _AiSourceSheet extends StatelessWidget {
  const _AiSourceSheet({required this.mark, required this.onRevert});

  final AiMark mark;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    final source = mark.source ?? '';
    final edited = mark.state == AiMarkState.editedAfter;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.gutter,
            0,
            Insets.gutter,
            16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text('Как было до AI', style: AppText.screenTight),
              const SizedBox(height: 4),
              Text(
                edited
                    ? 'Текст обработан AI, а потом изменён вручную.'
                    : 'Текст сейчас такой, каким его оставил AI.',
                style: AppText.caption,
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.lineFaint,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      source,
                      style: AppText.body.copyWith(fontSize: 14, height: 1.45),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Скопировать'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: source));
                      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                        const SnackBar(content: Text('Исходник скопирован')),
                      );
                    },
                  ),
                  const Spacer(),
                  if (onRevert != null)
                    FilledButton.icon(
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Вернуть исходник'),
                      onPressed: onRevert,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

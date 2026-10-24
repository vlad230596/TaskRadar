import 'package:flutter/material.dart';

import '../domain/ai_mark.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// The "правил AI" mark: a small pill next to text that AI processed.
///
/// Nothing at all for text AI never touched, or put back to its source -- the
/// mark is there to be noticed when it matters, not to label every row "not
/// AI".
///
/// [onOpen] opens the AI screen on the saved answer and its source
/// (`ai_tidy.dart`): the one place to compare them, keep the source ("Как
/// надиктовано") or run the model again. There used to be a sheet here with
/// its own "Вернуть исходник"; see `domain/ai_mark.dart` for why it went.
class AiSourceMark extends StatelessWidget {
  const AiSourceMark({required this.mark, required this.onOpen, super.key});

  final AiMark mark;
  final VoidCallback onOpen;

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
          onTap: onOpen,
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

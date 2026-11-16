import 'package:flutter/material.dart';

/// Text that shows as many *whole* lines as the height it was given holds, up
/// to [maxLines], and ellipsizes the last of them.
///
/// ## Why not `Text(maxLines: 2)` in an `Expanded`
///
/// Because `maxLines` is a promise about the text, not about the box. A tile of
/// fixed height hands its middle `Expanded` whatever is left after the badge,
/// the name and the footer; at a large system font that is a line and a half,
/// and `Text` then lays out its two lines anyway and lets the box clip the
/// second one through the middle of its letters -- the "Посмотреть, почему не
/// работа…" with its lower half missing on the owner's phone. Here the line
/// count is worked out from the height first, so a line that does not fit is
/// not drawn at all and the one before it carries the "…".
///
/// Lays the text out once more than a plain [Text] does; it is meant for a
/// few lines on a card, not for long passages.
class FitLinesText extends StatelessWidget {
  const FitLinesText(
    this.data, {
    required this.style,
    this.maxLines = 2,
    super.key,
  });

  final String data;
  final TextStyle style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var lines = maxLines;
        if (constraints.maxHeight.isFinite) {
          final painter = TextPainter(
            text: TextSpan(
              text: data,
              style: DefaultTextStyle.of(context).style.merge(style),
            ),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            maxLines: maxLines,
            ellipsis: '…',
          );
          while (lines > 0) {
            painter
              ..maxLines = lines
              ..layout(maxWidth: constraints.maxWidth);
            if (painter.height <= constraints.maxHeight + 0.5) break;
            lines--;
          }
          painter.dispose();
        }
        if (lines == 0) return const SizedBox.shrink();
        return Text(
          data,
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
      },
    );
  }
}

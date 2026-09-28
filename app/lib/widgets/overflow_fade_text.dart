import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Text clipped to [maxLines] that *says* when it was clipped.
///
/// ## Why not an ellipsis
///
/// An ellipsis at the end of line three is two pixels of grey at the far end of
/// a row, and a task title that happens to end mid-thought reads the same way.
/// People did not notice that there was more. Here the last visible line fades
/// out, and a small "ещё 2 строки" sits under it -- a count rather than a bare
/// "ещё", so a title missing one word and a title missing a paragraph look
/// different before anyone taps.
///
/// Tapping is left to the caller: in a task row the whole row already opens the
/// full text, and a second tap target inside it would only fight the first.
///
/// The measurement is a [TextPainter] laid out without a line limit at the
/// width the parent offers, with the same style, scaler and direction the
/// [Text] below will use -- so "is there more" is answered by the same layout
/// that draws the text, not by a character count.
class OverflowFadeText extends StatelessWidget {
  const OverflowFadeText(this.text, {this.style, this.maxLines = 3, super.key});

  final String text;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final body = Text(
          text,
          style: style,
          maxLines: maxLines,
          overflow: TextOverflow.clip,
        );

        // Unbounded width (a Row without Expanded) cannot overflow by lines;
        // measuring against infinity would say "one line" and be wrong for the
        // same reason.
        if (!constraints.hasBoundedWidth) return body;

        final hidden = _lineCount(context, constraints.maxWidth) - maxLines;
        if (hidden <= 0) return body;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ShaderMask(
              blendMode: BlendMode.dstIn,
              // Fades across roughly the last line only: the lines above it are
              // the part worth reading at a glance and stay at full ink.
              shaderCallback: (bounds) => LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const <Color>[Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                stops: <double>[1 - 0.75 / maxLines, 1],
              ).createShader(bounds),
              child: body,
            ),
            const SizedBox(height: 2),
            Text(
              'ещё $hidden ${linesWord(hidden)}',
              maxLines: 1,
              style: AppText.caption.copyWith(color: AppColors.indigoLink),
            ),
          ],
        );
      },
    );
  }

  int _lineCount(BuildContext context, double width) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
    )..layout(maxWidth: width);
    final lines = painter.computeLineMetrics().length;
    painter.dispose();
    return lines;
  }
}

/// A fade from transparent to [colour]: "the text goes on under here", laid
/// over the bottom edge of something that scrolls or is cut -- the sandbox's
/// open field, a closed sandbox line. Ignores touches, so it never steals a tap
/// meant for the text under it.
///
/// The painted cousin of [OverflowFadeText]'s mask: that one fades the text
/// itself and needs to know nothing about what is behind it; this one covers
/// the text with the colour of the card, which is what works over a
/// `TextField`, whose text cannot be masked from outside.
class FadeInto extends StatelessWidget {
  const FadeInto({required this.colour, this.height = 22, super.key});

  final Color colour;
  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colour.withValues(alpha: 0), colour],
          ),
        ),
      ),
    );
  }
}

/// "строка", "строки" or "строк" for [count]: Russian needs three forms.
String linesWord(int count) {
  final lastTwo = count % 100;
  final last = count % 10;
  if (lastTwo >= 11 && lastTwo <= 14) return 'строк';
  if (last == 1) return 'строка';
  if (last >= 2 && last <= 4) return 'строки';
  return 'строк';
}

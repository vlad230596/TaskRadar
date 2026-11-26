import 'package:flutter/material.dart';

/// The icons of «Сегодня», history and the review
/// (`design/today-history-spec.md` §2): 24x24 strokes, 1.9-2 wide, no fill,
/// painted from their SVG paths like the goal icons.
enum TodayGlyph {
  calendar,
  lock,
  unlock,
  next,
  reopen,
  stack,
  later,
  rhythm,
  review,
  clock,
}

class TodayIcon extends StatelessWidget {
  const TodayIcon(
    this.glyph, {
    this.size = 16,
    required this.color,
    this.stroke = 2,
    this.semanticLabel,
    super.key,
  });

  final TodayGlyph glyph;
  final double size;
  final Color color;
  final double stroke;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final box = SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _TodayPainter(glyph, color, stroke)),
    );
    final label = semanticLabel;
    return label == null
        ? ExcludeSemantics(child: box)
        : Semantics(label: label, child: box);
  }
}

class _TodayPainter extends CustomPainter {
  const _TodayPainter(this.glyph, this.color, this.stroke);

  final TodayGlyph glyph;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(_path(glyph), line);
  }

  static Path _path(TodayGlyph glyph) {
    switch (glyph) {
      case TodayGlyph.calendar:
        return Path()
          ..addRRect(
            RRect.fromLTRBR(3.5, 5, 20.5, 20.5, const Radius.circular(3)),
          )
          ..moveTo(3.5, 10)
          ..lineTo(20.5, 10)
          ..moveTo(8, 3)
          ..lineTo(8, 7)
          ..moveTo(16, 3)
          ..lineTo(16, 7);
      case TodayGlyph.lock:
        return Path()
          ..addRRect(
            RRect.fromLTRBR(5, 10.5, 19, 20.5, const Radius.circular(2.5)),
          )
          ..moveTo(8, 10.5)
          ..lineTo(8, 8)
          ..arcToPoint(const Offset(16, 8), radius: const Radius.circular(4))
          ..lineTo(16, 10.5);
      case TodayGlyph.unlock:
        return Path()
          ..addRRect(
            RRect.fromLTRBR(5, 10.5, 19, 20.5, const Radius.circular(2.5)),
          )
          ..moveTo(8, 10.5)
          ..lineTo(8, 8)
          ..arcToPoint(
            const Offset(15.6, 6.2),
            radius: const Radius.circular(4),
          );
      case TodayGlyph.next:
        return Path()
          ..moveTo(5, 5)
          ..lineTo(5, 10)
          ..arcToPoint(
            const Offset(9, 14),
            radius: const Radius.circular(4),
            clockwise: false,
          )
          ..lineTo(19, 14)
          ..moveTo(15, 10)
          ..lineTo(19, 14)
          ..lineTo(15, 18);
      case TodayGlyph.reopen:
        return Path()
          ..moveTo(9, 14)
          ..lineTo(4, 9)
          ..lineTo(9, 4)
          ..moveTo(4, 9)
          ..lineTo(14.5, 9)
          ..arcToPoint(
            const Offset(14.5, 20),
            radius: const Radius.circular(5.5),
          )
          ..lineTo(11, 20);
      case TodayGlyph.stack:
        return Path()
          ..moveTo(4, 13)
          ..lineTo(9, 13)
          ..lineTo(10.5, 15.5)
          ..lineTo(13.5, 15.5)
          ..lineTo(15, 13)
          ..lineTo(20, 13)
          ..moveTo(5.5, 6)
          ..lineTo(18.5, 6)
          ..lineTo(20, 13)
          ..lineTo(20, 18.5)
          ..lineTo(4, 18.5)
          ..lineTo(4, 13)
          ..close();
      case TodayGlyph.later:
        return Path()
          ..moveTo(7, 3)
          ..lineTo(17, 3)
          ..moveTo(7, 21)
          ..lineTo(17, 21)
          ..moveTo(8, 3)
          ..lineTo(8, 5)
          ..arcToPoint(
            const Offset(9.6, 8.2),
            radius: const Radius.circular(4),
            clockwise: false,
          )
          ..lineTo(12, 10)
          ..lineTo(14.4, 8.2)
          ..arcToPoint(
            const Offset(16, 5),
            radius: const Radius.circular(4),
            clockwise: false,
          )
          ..lineTo(16, 3)
          ..moveTo(8, 21)
          ..lineTo(8, 19)
          ..arcToPoint(
            const Offset(9.6, 15.8),
            radius: const Radius.circular(4),
          )
          ..lineTo(12, 14)
          ..lineTo(14.4, 15.8)
          ..arcToPoint(const Offset(16, 19), radius: const Radius.circular(4))
          ..lineTo(16, 21);
      case TodayGlyph.rhythm:
        return Path()
          ..moveTo(3, 12)
          ..lineTo(7, 12)
          ..lineTo(9.5, 6)
          ..lineTo(14.5, 18)
          ..lineTo(17, 12)
          ..lineTo(21, 12);
      case TodayGlyph.review:
        return Path()
          ..moveTo(4, 12)
          ..arcToPoint(
            const Offset(6.4, 6.3),
            radius: const Radius.circular(8),
            largeArc: true,
            clockwise: false,
          )
          ..moveTo(4, 4)
          ..lineTo(4, 9)
          ..lineTo(9, 9)
          ..moveTo(12, 8)
          ..lineTo(12, 12)
          ..lineTo(15, 14);
      case TodayGlyph.clock:
        return Path()
          ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 8.5))
          ..moveTo(12, 7.5)
          ..lineTo(12, 12)
          ..lineTo(15, 14);
    }
  }

  @override
  bool shouldRepaint(_TodayPainter old) =>
      old.glyph != glyph || old.color != color || old.stroke != stroke;
}

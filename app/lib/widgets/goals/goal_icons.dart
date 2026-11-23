import 'package:flutter/material.dart';

/// The three icons goals and ideas brought (`design/goals-ideas-spec.md`,
/// «Значки»), drawn from their 24x24 SVG paths. Painted rather than taken from
/// Material: the crown is the one filled glyph of the interface, which is how
/// it still reads at 13 px, and Material has no bench at all.

enum _Glyph { crown, bulb, bench }

/// The crown: filled, with its base line.
class CrownIcon extends StatelessWidget {
  const CrownIcon({this.size = 16, required this.color, super.key});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => _GlyphBox(
    glyph: _Glyph.crown,
    size: size,
    color: color,
    stroke: 2,
  );
}

/// The idea's bulb (stroke 1.9).
class BulbIcon extends StatelessWidget {
  const BulbIcon({this.size = 18, required this.color, super.key});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      _GlyphBox(glyph: _Glyph.bulb, size: size, color: color, stroke: 1.9);
}

/// The bench (stroke 1.9).
class BenchIcon extends StatelessWidget {
  const BenchIcon({this.size = 16, required this.color, super.key});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      _GlyphBox(glyph: _Glyph.bench, size: size, color: color, stroke: 1.9);
}

class _GlyphBox extends StatelessWidget {
  const _GlyphBox({
    required this.glyph,
    required this.size,
    required this.color,
    required this.stroke,
  });

  final _Glyph glyph;
  final double size;
  final Color color;
  final double stroke;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _GlyphPainter(glyph, color, stroke)),
  );
}

class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color, this.stroke);

  final _Glyph glyph;
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
    switch (glyph) {
      case _Glyph.crown:
        final body = Path()
          ..moveTo(3, 8.5)
          ..lineTo(7.6, 12.1)
          ..lineTo(12, 5)
          ..lineTo(16.4, 12.1)
          ..lineTo(21, 8.5)
          ..lineTo(19.2, 18)
          ..lineTo(4.8, 18)
          ..close();
        canvas
          ..drawPath(body, Paint()..color = color)
          ..drawLine(const Offset(5, 20.6), const Offset(19, 20.6), line);
      case _Glyph.bulb:
        final bulb = Path()
          ..moveTo(9, 18)
          ..lineTo(15, 18)
          ..moveTo(10, 21)
          ..lineTo(14, 21)
          ..moveTo(12, 3)
          ..arcToPoint(
            const Offset(8.4, 13.8),
            radius: const Radius.circular(6),
            clockwise: false,
          )
          ..cubicTo(9, 14.3, 9.4, 15, 9.4, 15.8)
          ..lineTo(9.4, 16)
          ..lineTo(14.6, 16)
          ..lineTo(14.6, 15.8)
          ..cubicTo(14.6, 15, 15, 14.3, 15.6, 13.8)
          ..arcToPoint(
            const Offset(12, 3),
            radius: const Radius.circular(6),
            clockwise: false,
          )
          ..close();
        canvas.drawPath(bulb, line);
      case _Glyph.bench:
        final bench = Path()
          ..moveTo(4, 10)
          ..lineTo(20, 10)
          ..moveTo(4, 14)
          ..lineTo(20, 14)
          ..moveTo(6, 14)
          ..lineTo(6, 19)
          ..moveTo(18, 14)
          ..lineTo(18, 19)
          ..moveTo(6, 10)
          ..lineTo(6, 7)
          ..moveTo(18, 10)
          ..lineTo(18, 7);
        canvas.drawPath(bench, line);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.stroke != stroke;
}

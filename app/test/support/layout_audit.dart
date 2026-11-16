import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Проверка вёрстки «ничего не вылезает за свои границы».
///
/// ## Зачем она, если Flutter и так ругается на переполнение
///
/// Ругается не на всё. `RenderFlex overflowed` ловится (и [captureLayoutErrors]
/// его собирает), а вот две вещи, которые владелец увидел на телефоне, — нет:
///
/// - **текст, обрезанный по высоте посреди строки.** `Text(maxLines: 2)` в
///   ячейке, где места на полторы строки, молча клипуется: многоточие стоит в
///   конце второй строки, а её нижняя половина срезана соседом. Ни ошибки, ни
///   предупреждения — только [_auditParagraph] это видит, разложив тот же текст
///   заново и сравнив нужную высоту с отведённой;
/// - **то, что нарисовано поверх соседа или за краем карточки.** В релизной
///   сборке переполненный ряд не рисует жёлто-чёрную полосу, а просто рисует
///   точки дальше, поверх подписи и за скруглённым краем. Поэтому каждая
///   «карточка» (ближайший непрозрачный [Material]) проверяется отдельно:
///   текст и фигуры внутри неё лежат внутри её прямоугольника и не наезжают
///   друг на друга.
///
/// ## Что считается листом
///
/// [RenderParagraph] (текст и значки — [Icon] тоже рисуется абзацем) и
/// бездетный [RenderDecoratedBox] — точки, полоски, кружки. Фигуры между собой
/// не сравниваются: полоска прогресса поверх дорожки — так и задумано; а вот
/// текст поверх точки — нет.
///
/// Граница карточки сбрасывается на каждом вьюпорте: содержимое прокрутки не
/// обязано помещаться в карточку, внутри которой прокрутка стоит.
List<String> auditLayout() {
  final problems = <String>[];
  final cards = <_Card>[];
  final root = WidgetsBinding.instance.rootElement;
  if (root == null) return problems;
  _walk(root, null, cards, problems);

  for (final card in cards) {
    final bounds = card.rect.inflate(_tolerance);
    for (final leaf in card.leaves) {
      final r = leaf.rect;
      if (r.isEmpty) continue;
      if (!_contains(bounds, r)) {
        problems.add(
          'outside its card: ${leaf.describe()} at ${_fmt(r)}, '
          'card ${_fmt(card.rect)} (${card.label})',
        );
      }
    }
    for (var i = 0; i < card.leaves.length; i++) {
      for (var j = i + 1; j < card.leaves.length; j++) {
        final a = card.leaves[i];
        final b = card.leaves[j];
        if (!a.isText && !b.isText) continue;
        final overlap = a.rect
            .deflate(_tolerance)
            .intersect(b.rect.deflate(_tolerance));
        if (overlap.width > 0 && overlap.height > 0) {
          problems.add(
            'overlap in card (${card.label}): ${a.describe()} '
            '${_fmt(a.rect)} and ${b.describe()} ${_fmt(b.rect)}',
          );
        }
      }
    }
  }
  return problems;
}

/// Runs [body] with [FlutterError.onError] collecting instead of failing, and
/// returns the first lines of every error reported meanwhile.
///
/// Collected rather than left to the test binding: the binding fails the test
/// on the first one and says nothing about the rest, and a layout matrix wants
/// all of them in one message.
Future<List<String>> captureLayoutErrors(Future<void> Function() body) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final lines = details.toString().split('\n');
    errors.add(
      lines.where((line) => line.trim().isNotEmpty).take(6).join('\n'),
    );
  };
  try {
    await body();
  } finally {
    FlutterError.onError = previous;
  }
  return errors;
}

const double _tolerance = 1;

class _Card {
  _Card(this.box, this.label);

  final RenderBox box;
  final String label;
  final List<_Leaf> leaves = <_Leaf>[];

  Rect get rect => _globalRect(box);
}

class _Leaf {
  _Leaf(this.box, this.rect, {required this.isText, required this.label});

  final RenderBox box;
  final Rect rect;
  final bool isText;
  final String label;

  String describe() => isText ? 'text "$label"' : 'shape $label';
}

void _walk(
  Element element,
  _Card? card,
  List<_Card> cards,
  List<String> problems,
) {
  final widget = element.widget;
  if (widget is Offstage && widget.offstage) return;

  var current = card;

  if (widget is Material && widget.type != MaterialType.transparency) {
    final box = element.renderObject;
    if (box is RenderBox && box.hasSize && !box.size.isEmpty) {
      current = _Card(box, _label(element));
      cards.add(current);
    }
  }

  if (element is RenderObjectElement) {
    final ro = element.renderObject;
    if (ro is RenderBox && !ro.hasSize) return;
    if (ro is RenderOpacity && ro.opacity == 0) return;
    if (ro is RenderAnimatedOpacity && ro.opacity.value == 0) return;
    if (ro is RenderAbstractViewport) current = null;
    // Only the shown child of an IndexedStack is painted; the others are
    // kept alive, laid out, and invisible (the shell keeps every mode so).
    if (ro is RenderIndexedStack) {
      var i = 0;
      element.visitChildren((child) {
        if (i++ == ro.index) _walk(child, current, cards, problems);
      });
      return;
    }

    if (ro is RenderParagraph) {
      if (ro.size.isEmpty) return;
      _auditParagraph(ro, problems);
      current?.leaves.add(
        _Leaf(
          ro,
          _globalRect(ro),
          isText: true,
          label: _short(ro.text.toPlainText()),
        ),
      );
      // A WidgetSpan's children are laid out by the paragraph; they are part
      // of it, not neighbours to compare it with.
      return;
    }
    if (ro is RenderDecoratedBox && ro.child == null && !ro.size.isEmpty) {
      current?.leaves.add(
        _Leaf(
          ro,
          _globalRect(ro),
          isText: false,
          label: '${_fmtSize(ro.size)} ${_creator(element)}',
        ),
      );
    }
  }

  element.visitChildren((child) => _walk(child, current, cards, problems));
}

/// Lays [p]'s text out again, exactly as [RenderParagraph] does, and reports
/// it when the box it got is smaller than the text it has to show.
void _auditParagraph(RenderParagraph p, List<String> problems) {
  var hasPlaceholder = false;
  p.text.visitChildren((span) {
    if (span is PlaceholderSpan) hasPlaceholder = true;
    return !hasPlaceholder;
  });
  if (hasPlaceholder) return;

  final painter = TextPainter(
    text: p.text,
    textAlign: p.textAlign,
    textDirection: p.textDirection,
    textScaler: p.textScaler,
    maxLines: p.maxLines,
    ellipsis: p.overflow == TextOverflow.ellipsis ? '…' : null,
    locale: p.locale,
    strutStyle: p.strutStyle,
    textWidthBasis: p.textWidthBasis,
    textHeightBehavior: p.textHeightBehavior,
  );
  try {
    final widthMatters = p.softWrap || p.overflow == TextOverflow.ellipsis;
    painter.layout(maxWidth: widthMatters ? p.size.width : double.infinity);
    final text = _short(p.text.toPlainText());
    if (painter.height > p.size.height + 0.5) {
      problems.add(
        'text clipped vertically: "$text" needs '
        '${painter.height.toStringAsFixed(1)} px, has '
        '${p.size.height.toStringAsFixed(1)} px',
      );
    }
    final cutsSideways =
        p.overflow == TextOverflow.clip || p.overflow == TextOverflow.visible;
    if (cutsSideways && painter.width > p.size.width + 0.5) {
      problems.add(
        'text cut sideways: "$text" needs '
        '${painter.width.toStringAsFixed(1)} px, has '
        '${p.size.width.toStringAsFixed(1)} px',
      );
    }
  } finally {
    painter.dispose();
  }
}

Rect _globalRect(RenderBox box) {
  final rect = MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
  // A zero scale (a collapsed transition) gives NaNs: nothing is drawn.
  return rect.isFinite ? rect : Rect.zero;
}

bool _contains(Rect outer, Rect inner) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;

/// The first text inside a card, which is what a human calls it.
String _label(Element element) {
  String? text;
  void visit(Element e) {
    if (text != null) return;
    final ro = e is RenderObjectElement ? e.renderObject : null;
    if (ro is RenderParagraph) {
      final plain = ro.text.toPlainText().trim();
      if (plain.isNotEmpty && plain.codeUnitAt(0) < 0xE000) {
        text = _short(plain);
        return;
      }
    }
    e.visitChildren(visit);
  }

  element.visitChildren(visit);
  return text ?? _creator(element);
}

String _creator(Element element) {
  final chain = <String>[element.widget.runtimeType.toString()];
  element.visitAncestorElements((ancestor) {
    if (chain.length >= 4) return false;
    chain.add(ancestor.widget.runtimeType.toString());
    return true;
  });
  return '(${chain.join(' ← ')})';
}

String _short(String text) {
  final flat = text.replaceAll('\n', ' ');
  // Icons are private-use glyphs; name them by code point.
  if (flat.length == 1 && flat.codeUnitAt(0) >= 0xE000) {
    return 'icon U+${flat.codeUnitAt(0).toRadixString(16)}';
  }
  return flat.length <= 40 ? flat : '${flat.substring(0, 39)}…';
}

String _fmt(Rect r) =>
    '[${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} '
    '${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}]';

String _fmtSize(Size s) =>
    '${s.width.toStringAsFixed(0)}x${s.height.toStringAsFixed(0)}';

/// Walks every tall vertical scrollable on screen from top to bottom,
/// [auditLayout]-ing each stop, so content below the fold is checked too.
Future<List<String>> auditWhileScrolling(WidgetTester tester) async {
  final problems = <String>{...auditLayout()};
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;

  final states = tester
      .stateList<ScrollableState>(find.byType(Scrollable))
      .where(
        (s) =>
            s.position.axis == Axis.vertical &&
            s.position.hasViewportDimension &&
            s.position.viewportDimension >= screen.height * 0.4,
      )
      .toList();

  for (final state in states) {
    final position = state.position;
    if (!position.hasContentDimensions) continue;
    final start = position.pixels;
    final step = math.max(position.viewportDimension * 0.8, 100.0);
    var guard = 0;
    while (position.pixels < position.maxScrollExtent && guard++ < 30) {
      position.jumpTo(
        math.min(position.pixels + step, position.maxScrollExtent),
      );
      await tester.pump();
      problems.addAll(auditLayout());
    }
    position.jumpTo(start);
    await tester.pump();
  }
  return problems.toList();
}

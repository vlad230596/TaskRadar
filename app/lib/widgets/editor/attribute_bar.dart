import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'editor_theme.dart';

/// The row of attribute chips under the title (task-editor spec, section 3):
/// scrolls sideways, 36 px chips with a 44 px target.
///
/// The editor decides which chips are in it -- reminder, category, and the
/// ones WP5–7 add through `sections.dart` ([EditorSlots.chips]).
class AttributeBar extends StatelessWidget {
  const AttributeBar({required this.chips, super.key});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    // A handful of chips: all built, not lazily -- a chip scrolled out of
    // view is still the same control.
    return SizedBox(
      height: Targets.minimum,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            for (final chip in chips) ...<Widget>[
              if (chip != chips.first) const SizedBox(width: 8),
              chip,
            ],
          ],
        ),
      ),
    );
  }
}

/// One chip of the [AttributeBar].
///
/// Empty: outlined in the line colour, «+ Напомнить». Set: filled with the
/// well colour, the value, and a `×` when [onClear] is given.
///
/// When [flash] changes to a new non-null value the chip "comes alive":
/// a short 1.0 → 1.08 → 1.0 pulse with a brighter fill, 180 ms -- typing
/// «завтра в 10» is answered by the reminder chip, not by a dialog.
class AttributeChip extends StatefulWidget {
  const AttributeChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
    this.onClear,
    this.clearTooltip,
    this.tooltip,
    this.flash,
    this.alarm = false,
    this.aiMark = false,
    this.note,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final String? clearTooltip;
  final String? tooltip;

  /// A counter or a value that changes each time the text set this chip.
  final Object? flash;

  /// Painted in the alarm colour: a reminder already gone by.
  final bool alarm;

  /// The value came from AI (a dictation's reminder): a small sparkle.
  final bool aiMark;

  /// A short word after the value, e.g. «уже прошло».
  final String? note;

  static const double height = 36;

  @override
  State<AttributeChip> createState() => _AttributeChipState();
}

class _AttributeChipState extends State<AttributeChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  );

  @override
  void didUpdateWidget(AttributeChip old) {
    super.didUpdateWidget(old);
    if (widget.flash != null && widget.flash != old.flash) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filled = widget.filled;
    final ink = widget.alarm
        ? EditorColors.past
        : filled
        ? EditorColors.ink
        : EditorColors.bright;
    final onClear = widget.onClear;

    final body = AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        // Up and back down: a triangle over the 180 ms.
        final t = _pulse.value;
        final lift = t < 0.5 ? t * 2 : (1 - t) * 2;
        return Transform.scale(
          scale: 1 + 0.08 * (_pulse.isAnimating ? lift : 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Color.lerp(
                filled ? EditorColors.well : Colors.transparent,
                EditorColors.focus,
                _pulse.isAnimating ? lift * 0.6 : 0,
              ),
              border: Border.all(
                color: filled ? EditorColors.well : EditorColors.line,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(AttributeChip.height / 2),
            ),
            child: child,
          ),
        );
      },
      child: SizedBox(
        height: AttributeChip.height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              child: InkWell(
                borderRadius: BorderRadius.circular(AttributeChip.height / 2),
                onTap: widget.onTap,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 12,
                    right: onClear == null ? 14 : 4,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(widget.icon, size: 17, color: ink),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: EditorText.chip.copyWith(color: ink),
                        ),
                      ),
                      if (widget.note case final note?) ...<Widget>[
                        const SizedBox(width: 6),
                        Text(
                          note,
                          style: EditorText.note.copyWith(color: ink),
                        ),
                      ],
                      if (widget.aiMark) ...<Widget>[
                        const SizedBox(width: 5),
                        const Icon(
                          Icons.auto_awesome,
                          size: 13,
                          color: EditorColors.focus,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            if (onClear != null)
              Tooltip(
                message: widget.clearTooltip ?? 'Убрать',
                child: InkResponse(
                  radius: 20,
                  onTap: onClear,
                  child: const SizedBox(
                    width: 32,
                    height: AttributeChip.height,
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: EditorColors.muted,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    final tooltip = widget.tooltip;
    final hit = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Material(type: MaterialType.transparency, child: body),
    );
    return tooltip == null ? hit : Tooltip(message: tooltip, child: hit);
  }
}

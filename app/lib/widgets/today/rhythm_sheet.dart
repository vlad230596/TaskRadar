import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error_message.dart';
import '../../models/project.dart';
import '../../providers/today_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'today_icons.dart';

/// «Ритм…» (`design/today-history-spec.md` §6.2): the project's norm «≥ N
/// closed a week» and ceiling «≤ M open», both optional. Light from the
/// project menu; [dark] on the review's step 4.
///
/// Answers the saved project, or null when nothing was saved.
Future<Project?> showRhythmSheet(
  BuildContext context, {
  required Project project,
  bool dark = false,
}) {
  return showModalBottomSheet<Project>(
    context: context,
    isScrollControlled: true,
    backgroundColor: dark ? AppColors.voiceBackground : AppColors.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => RhythmSheet(project: project, dark: dark),
  );
}

/// The text of a rhythm signal on the plan and in the review: «тишина 3 нед»,
/// «перебор 24/20»; null without one.
String? rhythmSignalText(ProjectRhythm? rhythm) {
  if (rhythm == null) return null;
  switch (rhythm.signal) {
    case RhythmSignal.silence:
      return rhythm.silentWeeks <= 0
          ? 'тишина'
          : 'тишина ${rhythm.silentWeeks} нед';
    case RhythmSignal.overflow:
      return 'перебор ${rhythm.open}/${rhythm.maxOpen ?? '—'}';
    case null:
      return null;
  }
}

/// «0,5» -- a Russian decimal, at most one digit after the comma.
String formatAverage(double value) {
  final rounded = (value * 10).round() / 10;
  final text = rounded == rounded.roundToDouble()
      ? rounded.toInt().toString()
      : rounded.toStringAsFixed(1);
  return text.replaceAll('.', ',');
}

class RhythmSheet extends ConsumerStatefulWidget {
  const RhythmSheet({required this.project, this.dark = false, super.key});

  final Project project;
  final bool dark;

  @override
  ConsumerState<RhythmSheet> createState() => _RhythmSheetState();
}

class _RhythmSheetState extends ConsumerState<RhythmSheet> {
  late int? _closed = widget.project.rhythmClosedPerWeek;
  late int? _maxOpen = widget.project.rhythmMaxOpen;
  bool _saving = false;

  bool get _changed =>
      _closed != widget.project.rhythmClosedPerWeek ||
      _maxOpen != widget.project.rhythmMaxOpen;

  ProjectRhythm? get _rhythm => widget.project.rhythm;

  Future<void> _save() async {
    setState(() => _saving = true);
    final container = ProviderScope.containerOf(context, listen: false);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final saved = await saveRhythm(
        container,
        widget.project.id,
        closedPerWeek: _closed,
        maxOpen: _maxOpen,
      );
      if (navigator.mounted) navigator.pop(saved);
    } catch (error) {
      if (mounted) setState(() => _saving = false);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('Не удалось сохранить ритм. ${describeApiError(error)}'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = widget.dark;
    final ink = dark ? AppColors.voiceInk : AppColors.ink;
    final muted = dark ? AppColors.voiceMuted : AppColors.muted;
    final open = _rhythm?.open;
    final openDefault = open == null ? 20 : ((open + 4) ~/ 5) * 5;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: dark ? AppColors.voiceLine : AppColors.lineStrong,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                TodayIcon(TodayGlyph.rhythm, size: 18, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ритм проекта',
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: ink,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close, color: muted),
                ),
              ],
            ),
            Text(
              'Тихая метка в планировании, если проект затих или разросся. '
              'Без пушей — решаете на пересмотре.',
              style: TextStyle(
                fontFamily: AppFonts.text,
                fontWeight: FontWeight.w500,
                fontSize: 13.5,
                height: 1.35,
                color: muted,
              ),
            ),
            const SizedBox(height: 16),
            _RhythmRow(
              key: const ValueKey<String>('rhythm-closed'),
              dark: dark,
              title: 'Закрывать в неделю, не меньше',
              caption: _rhythm == null
                  ? null
                  : 'сейчас ${formatAverage(_rhythm!.closedAvg)} в неделю '
                        '(за 2 нед)',
              value: _closed,
              min: 1,
              max: 50,
              fallback: 2,
              onChanged: (value) => setState(() => _closed = value),
            ),
            const SizedBox(height: 10),
            _RhythmRow(
              key: const ValueKey<String>('rhythm-open'),
              dark: dark,
              title: 'Открытых, не больше',
              caption: open == null ? null : 'сейчас открыто $open',
              value: _maxOpen,
              min: 1,
              max: 500,
              fallback: openDefault.clamp(1, 500),
              onChanged: (value) => setState(() => _maxOpen = value),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _changed && !_saving ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: dark ? AppColors.card : AppColors.ink,
                  foregroundColor: dark
                      ? AppColors.voiceBackground
                      : AppColors.onInk,
                  disabledBackgroundColor: dark
                      ? AppColors.voiceWell
                      : AppColors.lineFaint,
                  disabledForegroundColor: muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: AppText.action.copyWith(fontSize: 16),
                ),
                child: const Text('Сохранить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RhythmRow extends StatelessWidget {
  const _RhythmRow({
    required this.dark,
    required this.title,
    required this.caption,
    required this.value,
    required this.min,
    required this.max,
    required this.fallback,
    required this.onChanged,
    super.key,
  });

  final bool dark;
  final String title;
  final String? caption;
  final int? value;
  final int min;
  final int max;
  final int fallback;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final ink = dark ? AppColors.voiceInk : AppColors.ink;
    final muted = dark ? AppColors.voiceMuted : AppColors.muted;
    final line = dark ? AppColors.voiceLine : AppColors.line;
    final value = this.value;
    final caption = this.caption;

    Widget square(IconData icon, String tip, int? next) => SizedBox(
      width: 40,
      height: 40,
      child: OutlinedButton(
        onPressed: next == null ? null : () => onChanged(next),
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: ink,
          side: BorderSide(color: line),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Icon(icon, size: 18, semanticLabel: tip),
      ),
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: dark ? AppColors.goalRaised : AppColors.card,
        border: dark ? null : Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppFonts.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                    color: ink,
                  ),
                ),
                if (caption != null) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    caption,
                    style: TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w500,
                      fontSize: 12.5,
                      color: muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (value == null)
            SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: () => onChanged(fallback),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ink,
                  side: BorderSide(
                    color: dark ? AppColors.voiceLine : AppColors.lineStrong,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: AppText.action.copyWith(fontSize: 13.5),
                ),
                child: const Text('Задать'),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                square(Icons.remove, 'меньше', value > min ? value - 1 : null),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$value',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppFonts.display,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      color: ink,
                    ),
                  ),
                ),
                square(Icons.add, 'больше', value < max ? value + 1 : null),
                IconButton(
                  tooltip: 'Убрать',
                  onPressed: () => onChanged(null),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 44),
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.close, size: 18, color: muted),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Opens the sheet for [project] and swallows nothing: used by the menu.
void openRhythmSheet(BuildContext context, Project project) =>
    unawaited(showRhythmSheet(context, project: project));

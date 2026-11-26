import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/api_error_message.dart';
import '../../domain/reminders.dart';
import '../../domain/today_view.dart';
import '../../navigation/app_routes.dart';
import '../../providers/today_providers.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../dictate_into.dart';
import '../ime_text_controller.dart';
import 'date_sheet.dart';
import 'today_icons.dart';

/// «Следом…» (`design/today-history-spec.md` §8): after «сделано», a short
/// dark sheet that makes the continuation -- in the same project, with a
/// date. Also on a row of «Сделано» and on step 1 of the review.

/// A follow-up that was made: what the screens that offered it remember.
@immutable
class FollowUp {
  const FollowUp({required this.title, required this.date});

  final String title;

  /// `YYYY-MM-DD`.
  final String date;
}

/// «через 3 дня» and the rest: how many days from today.
const List<({String label, int days})> kFollowUpQuick =
    <({String label, int days})>[
      (label: 'через 3 дня', days: 3),
      (label: 'через неделю', days: 7),
      (label: 'через 2 недели', days: 14),
    ];

/// Opens the sheet and, on «Создать», creates the task (through the outbox,
/// so it works offline) and says so. Answers what was created, or null.
Future<FollowUp?> showNextSheet(
  BuildContext context, {
  required String projectId,
  required String projectName,
  required String afterTitle,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final today = container.read(todayKeyProvider);
  final made = await showModalBottomSheet<FollowUp>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.voiceBackground,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => NextSheet(
      projectName: projectName,
      afterTitle: afterTitle,
      today: today,
    ),
  );
  if (made == null) return null;
  try {
    await createFollowUp(
      container,
      projectId: projectId,
      title: made.title,
      date: made.date,
    );
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Следом: ${made.title} · ${weekdayDate(made.date)}'),
        ),
      );
    return made;
  } catch (error) {
    messenger
      ?..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text('Не удалось создать. ${describeApiError(error)}'),
        ),
      );
    return null;
  }
}

class NextSheet extends StatefulWidget {
  const NextSheet({
    required this.projectName,
    required this.afterTitle,
    required this.today,
    super.key,
  });

  final String projectName;
  final String afterTitle;
  final String today;

  @override
  State<NextSheet> createState() => _NextSheetState();
}

class _NextSheetState extends State<NextSheet> {
  final TextEditingController _title = ImeTextController();

  /// Selected quick choice (index into [kFollowUpQuick]), or -1 for a picked
  /// date. «через неделю» by default: the task is made with a date.
  int _quick = 1;
  String? _picked;

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  String get _date => _quick >= 0
      ? addDays(widget.today, kFollowUpQuick[_quick].days)
      : _picked!;

  Future<void> _pickDate() async {
    final choice = await showTaskDateSheet(
      context,
      current: _picked,
      today: widget.today,
    );
    final value = choice?.value;
    if (value == null || !mounted) return;
    setState(() {
      _quick = -1;
      _picked = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title = _title.text.trim();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  const TodayIcon(
                    TodayGlyph.next,
                    size: 18,
                    color: AppColors.voiceBright,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Следом',
                      style: TextStyle(
                        fontFamily: AppFonts.display,
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                        color: AppColors.voiceInk,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: AppColors.voiceMuted),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Container(
                    height: 28,
                    constraints: const BoxConstraints(maxWidth: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.railActive,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      widget.projectName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.voiceBright,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'после: ${widget.afterTitle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppColors.voiceMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                constraints: const BoxConstraints(minHeight: 96),
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 4),
                decoration: BoxDecoration(
                  color: AppColors.voiceWell,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: _title,
                      autofocus: true,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      cursorColor: AppColors.voiceBright,
                      style: const TextStyle(
                        fontFamily: AppFonts.text,
                        fontWeight: FontWeight.w500,
                        fontSize: 19,
                        color: Color(0xFFFFFFFF),
                      ),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        filled: false,
                        hintText: 'что дальше по: ${widget.afterTitle}',
                        hintMaxLines: 2,
                        hintStyle: const TextStyle(
                          fontFamily: AppFonts.text,
                          fontWeight: FontWeight.w500,
                          fontSize: 19,
                          color: AppColors.reviewSkipped,
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: DictateInto(controller: _title, label: 'Следом'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    for (var i = 0; i < kFollowUpQuick.length; i++) ...<Widget>[
                      _WhenPill(
                        label: kFollowUpQuick[i].label,
                        selected: _quick == i,
                        onTap: () => setState(() => _quick = i),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _WhenPill(
                      label: _quick < 0 && _picked != null
                          ? weekdayDate(_picked!)
                          : 'Дата…',
                      selected: _quick < 0,
                      onTap: _pickDate,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                weekdayDate(_date),
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                  color: AppColors.voiceMuted,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 64,
                child: FilledButton(
                  onPressed: title.isEmpty
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(FollowUp(title: title, date: _date)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.card,
                    foregroundColor: AppColors.voiceBackground,
                    disabledBackgroundColor: AppColors.voiceWell,
                    disabledForegroundColor: AppColors.voiceMuted,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: AppFonts.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  child: const Text('Создать'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WhenPill extends StatelessWidget {
  const _WhenPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.card : Colors.transparent,
      shape: StadiumBorder(
        side: selected
            ? BorderSide.none
            : const BorderSide(color: AppColors.voiceLine),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: selected
                  ? AppColors.voiceBackground
                  : AppColors.voiceBright,
            ),
          ),
        ),
      ),
    );
  }
}

/// «Сделано: <задача> · Следом… · Отменить» (§8.1): six seconds, a new one
/// replaces it. [undo] puts the task back; «Следом…» opens [showNextSheet]
/// over whatever screen is on top.
void showDoneSnackBar(
  ScaffoldMessengerState messenger, {
  required String title,
  required String projectId,
  required String projectName,
  required Future<void> Function() undo,
}) {
  void hide() => messenger.hideCurrentSnackBar();
  final wide = MediaQuery.maybeSizeOf(messenger.context)?.width ?? 0;
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        persist: false,
        backgroundColor: AppColors.snackBackground,
        width: wide >= 720 ? 480 : null,
        padding: const EdgeInsets.only(left: 16, right: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                'Сделано: $title',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w500,
                  fontSize: 14.5,
                  color: Color(0xFFFFFFFF),
                ),
              ),
            ),
            // The snackbar's own context is under the Navigator (the
            // Scaffold draws it), so the sheet opens from it -- before the
            // snackbar goes, which the pushed route does not depend on.
            Builder(
              builder: (snackContext) => TextButton.icon(
              key: const ValueKey<String>('snack-next'),
              onPressed: () {
                final context =
                    appNavigatorKey.currentContext ?? snackContext;
                unawaited(
                  showNextSheet(
                    context,
                    projectId: projectId,
                    projectName: projectName,
                    afterTitle: title,
                  ),
                );
                hide();
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.snackAction,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
              icon: const TodayIcon(
                TodayGlyph.next,
                size: 16,
                color: AppColors.snackAction,
              ),
              label: const Text('Следом…'),
            ),
            ),
            TextButton(
              onPressed: () {
                hide();
                unawaited(() async {
                  try {
                    await undo();
                  } catch (error) {
                    if (!messenger.mounted) return;
                    messenger
                      ..clearSnackBars()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            'Не удалось отменить. ${describeApiError(error)}',
                          ),
                        ),
                      );
                  }
                }());
              },
              style: TextButton.styleFrom(
                foregroundColor: AppColors.snackActionSoft,
                minimumSize: const Size(0, 44),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: const TextStyle(
                  fontFamily: AppFonts.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
              child: const Text('Отменить'),
            ),
          ],
        ),
      ),
    );
}

/// The date label of a row: the calendar icon and the label in its tone.
class TaskDateMeta extends StatelessWidget {
  const TaskDateMeta({
    required this.label,
    this.lead,
    this.leadColor,
    this.icon = true,
    super.key,
  });

  final TaskDateLabel label;

  /// Words before the label: «следующая», «ждёт 2 д · проверить».
  final String? lead;
  final Color? leadColor;
  final bool icon;

  static Color toneColor(DateTone tone) => switch (tone) {
    DateTone.overdue => AppColors.dateOverdue,
    DateTone.today => AppColors.dateToday,
    DateTone.soon => AppColors.dateSoon,
  };

  @override
  Widget build(BuildContext context) {
    final colour = toneColor(label.tone);
    final lead = this.lead;
    return Row(
      children: <Widget>[
        if (icon) ...<Widget>[
          TodayIcon(
            TodayGlyph.calendar,
            size: 13,
            color: leadColor ?? colour,
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text.rich(
            TextSpan(
              children: <InlineSpan>[
                if (lead != null)
                  TextSpan(
                    text: '$lead · ',
                    style: TextStyle(color: leadColor ?? colour),
                  ),
                TextSpan(
                  text: label.text,
                  style: TextStyle(
                    color: colour,
                    fontWeight: label.tone == DateTone.today
                        ? FontWeight.w700
                        : FontWeight.w600,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.dateLabel,
          ),
        ),
      ],
    );
  }
}

/// Today's date label of [remindAt] as a row shows it, from the day block's
/// clock.
TaskDateLabel? watchTaskDate(
  WidgetRef ref,
  String? remindAt,
  String? remindTime,
) => formatTaskDate(remindAt, remindTime, ref.watch(todayKeyProvider));

/// The local calendar day of now, for code without a ref.
String todayNow() => localTodayCalendarDate();

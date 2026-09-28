import 'dart:async';

import 'package:flutter/material.dart';

import '../api/dictation_api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Where one "Разобрать" is, from the phone's side (F14): the stages of
/// [DictationApi.parseStream], each with the moment it arrived.
///
/// ## Why the moments and not just the stage
///
/// The card says how long every step took and how long ago the server was last
/// heard from. Both are differences between these timestamps and "now", worked
/// out at paint time by [steps] and [signal] -- so a test can ask what the card
/// says at any moment without a clock, and a card that ticks is a card that
/// repaints, not one that keeps counters.
class TidyProgress {
  TidyProgress(this.startedAt);

  /// When "Разобрать" was pressed.
  final DateTime startedAt;

  DateTime? sentAt;
  DateTime? acceptedAt;
  DateTime? modelStartedAt;
  DateTime? modelDoneAt;
  DateTime? validatedAt;

  /// The last time anything came from the server -- an event or a byte.
  DateTime? lastSignalAt;

  /// The model's name, once the server has said which one it asked.
  String? model;

  /// What went wrong, said on the card; null while it has not.
  String? failure;
  DateTime? failedAt;

  bool get failed => failure != null;

  /// Records [progress], which arrived [at].
  void record(ParseProgress progress, DateTime at) {
    if (progress is! ParseSent) lastSignalAt = at;
    switch (progress) {
      case ParseSent():
        sentAt ??= at;
      case ParseAccepted():
        sentAt ??= at;
        acceptedAt ??= at;
      case ParseModelStarted(:final model):
        this.model = model.isEmpty ? null : model;
        modelStartedAt ??= at;
      case ParseModelDone():
        modelDoneAt ??= at;
      case ParseValidated():
        validatedAt ??= at;
      case ParseAlive():
      case ParseDone():
        break;
    }
  }

  void fail(String message, DateTime at) {
    failure = message;
    failedAt = at;
  }

  /// The four steps as they stand at [now]. After a failure time stops at the
  /// moment of it: the step that was running is the one that failed, and the
  /// seconds it shows are how long it ran.
  List<TidyStep> steps(DateTime now) {
    final at = failedAt ?? now;
    final sent = sentAt;
    final accepted = acceptedAt;
    final thinkingFrom = modelStartedAt ?? accepted;
    final modelDone = modelDoneAt;
    final validated = validatedAt;

    final raw = <(String, DateTime?, DateTime?, bool)>[
      // (label, started, finished, live seconds while running)
      ('Запрос отправлен', startedAt, sent, false),
      (
        model == null ? 'Сервер принял' : 'Сервер принял · $model',
        sent ?? startedAt,
        accepted,
        false,
      ),
      ('Модель думает', thinkingFrom, modelDone, true),
      ('Проверяю ответ', modelDone, validated, false),
    ];

    final result = <TidyStep>[];
    var running = false;
    for (final (label, started, finished, live) in raw) {
      if (finished != null && started != null) {
        result.add(
          TidyStep(
            label,
            TidyStepState.done,
            formatStepTime(finished.difference(started)),
          ),
        );
      } else if (!running && started != null) {
        running = true;
        result.add(
          TidyStep(
            label,
            failed ? TidyStepState.failed : TidyStepState.active,
            live ? '${at.difference(started).inSeconds} с' : null,
          ),
        );
      } else {
        result.add(TidyStep(label, TidyStepState.pending, null));
      }
    }
    return result;
  }

  /// The line under the steps: whether the server is still there.
  String signal(DateTime now) {
    final last = lastSignalAt;
    if (last == null) return 'жду ответа сервера';
    final seconds = now.difference(last).inSeconds;
    if (seconds >= 10) return 'сигнала нет уже $seconds с';
    return 'связь есть · последний сигнал $seconds с назад';
  }
}

enum TidyStepState { pending, active, done, failed }

class TidyStep {
  const TidyStep(this.label, this.state, this.time);

  final String label;
  final TidyStepState state;

  /// How long it took (done), or has been running (the model, while it
  /// thinks); null when there is nothing to say.
  final String? time;

  @override
  bool operator ==(Object other) =>
      other is TidyStep &&
      other.label == label &&
      other.state == state &&
      other.time == time;

  @override
  int get hashCode => Object.hash(label, state, time);

  @override
  String toString() => 'TidyStep($label, ${state.name}, $time)';
}

/// `0,2 с` under ten seconds, where the tenth is the information; `12 с`
/// above, where it is noise.
String formatStepTime(Duration duration) {
  final ms = duration.inMilliseconds < 0 ? 0 : duration.inMilliseconds;
  if (ms < 10000) {
    final tenths = (ms / 100).round();
    return '${tenths ~/ 10},${tenths % 10} с';
  }
  return '${(ms / 1000).round()} с';
}

/// The card on the dictation screen while "Разобрать" runs, and after it
/// failed: the steps, the signal line, and "Отменить" / "Повторить".
class TidyProgressCard extends StatefulWidget {
  const TidyProgressCard({
    required this.progress,
    required this.onCancel,
    required this.onRetry,
    this.now = DateTime.now,
    super.key,
  });

  final TidyProgress progress;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final DateTime Function() now;

  @override
  State<TidyProgressCard> createState() => _TidyProgressCardState();
}

class _TidyProgressCardState extends State<TidyProgressCard> {
  /// Repaints once a second, for the live seconds and the signal line.
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final now = widget.now();
    final failure = progress.failure;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.voiceLine),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final step in progress.steps(now)) ...<Widget>[
            _StepRow(step: step),
            const SizedBox(height: 12),
          ],
          Text(
            failure ?? progress.signal(now),
            style: failure == null
                ? const TextStyle(fontSize: 12, color: AppColors.voiceMuted)
                : const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                    color: AppColors.voiceRecordingSoft,
                  ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: <Widget>[
              if (failure != null)
                _CardButton(
                  label: 'Повторить',
                  onPressed: widget.onRetry,
                  primary: true,
                ),
              _CardButton(label: 'Отменить', onPressed: widget.onCancel),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.step});

  final TidyStep step;

  @override
  Widget build(BuildContext context) {
    final Widget icon = switch (step.state) {
      TidyStepState.done => const Icon(
        Icons.check,
        size: 18,
        color: AppColors.voiceLevelHigh,
      ),
      TidyStepState.active => const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: AppColors.voiceLevelHigh,
        ),
      ),
      TidyStepState.failed => const Icon(
        Icons.close,
        size: 18,
        color: AppColors.voiceRecordingSoft,
      ),
      TidyStepState.pending => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.voiceLine, width: 2),
        ),
      ),
    };
    final current =
        step.state == TidyStepState.active ||
        step.state == TidyStepState.failed;
    final time = step.time;

    return Row(
      children: <Widget>[
        SizedBox(width: 18, height: 18, child: Center(child: icon)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            step.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: current ? FontWeight.w600 : FontWeight.w400,
              fontSize: 14,
              color: step.state == TidyStepState.pending
                  ? AppColors.voiceMuted
                  : AppColors.voiceInk,
            ),
          ),
        ),
        if (time != null)
          Text(
            time,
            style: TextStyle(
              fontSize: 12,
              color: current ? AppColors.voiceBright : AppColors.voiceMuted,
            ),
          ),
      ],
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        backgroundColor: primary ? AppColors.voiceLine : Colors.transparent,
        foregroundColor: AppColors.voiceInk,
        side: const BorderSide(color: AppColors.voiceLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: AppText.voiceNote.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
